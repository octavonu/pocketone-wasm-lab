/// <reference path="../pb_data/types.d.ts" />
// The lab's hooks: the only place plugins are called from. A plugin is a WASI program in pb_wasm/ (<name>.wasm): what a
// hook gives it is its stdin (a string as it is, anything else as JSON), what it writes to stdout comes back (parsed
// if it's JSON). The hook decides what to save.
//
// The app has one JS VM: a sync $wasm.run holds it while the plugin runs, so the app's other requests wait. The hooks
// below that can meet a slow plugin (Go compiles for over a second each call) are async and await $wasm.run.async,
// so the app serves other requests meanwhile; /api/lab/order calls fast Rust plugins and stays sync.
onBootstrap((e) => {
  e.app.logger().info("lab hooks loaded")
  e.next();
})
//
// A new post gets its summary before it's saved. Without the plugin (removed, broken) the post is saved anyway.
onRecordCreate(async (e) => {
  try {
    const out = await $wasm.run.async("summary", { title: e.record.get("title"), body: e.record.get("body") })
    e.record.set("summary", out.text)
    e.record.set("words", out.words)
  } catch (err) {
    // err.name === "WasmError"; err.code, err.message, err.retryable, err.plugin
    e.app.logger().warn("no summary", "code", err.code, "message", err.message)
    e.record.set("summary", "(no summary: " + err.code + ")")
  }
  return e.next()
}, "posts")

// An EDIFACT message is parsed when it's saved: the raw text goes to the plugin as it is (a string is the plugin's
// stdin, byte for byte), the parsed segments come back as JSON. A message that doesn't parse is saved with the reason.
onRecordCreate(async (e) => {
  try {
    const out = await $wasm.run.async("edifact-orders-go", e.record.get("raw"))
    e.record.set("type", out.type)
    e.record.set("segments", out.count)
    e.record.set("parsed", out.segments)
  } catch (err) {
    e.record.set("error", err.code + ": " + err.message)
  }
  return e.next()
}, "messages")

// An order, EDIFACT ORDERS or XML, read into one order JSON: the hook looks at the format and picks the plugin
// (edifact-orders-rust or order-xml, both Rust); the plugins only read. Install them first: ./plugin.sh install edifact-orders-rust, order-xml.
//   curl -X POST http://127.0.0.1:8090/api/lab/order --data-binary @extras/order.edi -H "Authorization: <token>"
routerAdd("POST", "/api/lab/order", (e) => {
  const raw = toString(e.request.body)
  const plugin = raw.trimStart().startsWith("<") ? "order-xml" : "edifact-orders-rust"
  try {
    return e.json(200, { plugin: plugin, order: $wasm.run(plugin, raw) })
  } catch (err) {
    return e.json(400, { plugin: plugin, error: { code: err.code, message: err.message } })
  }
}, $apis.requireSuperuserAuth())

// A plugin never reaches the network: the hook calls the outside API and hands the result in.
//   http://127.0.0.1:8090/api/lab/summarize?url=https://example.com   (signed in as a superuser)
routerAdd("GET", "/api/lab/summarize", async (e) => {
  const url = e.request.url.query().get("url")
  const res = $http.send({ url: url, timeout: 10 })
  const text = toString(res.body)
    .replace(/<(style|script)[^>]*>[\s\S]*?<\/\1>/gi, " ") // not text
    .replace(/<[^>]*>/g, " ")
  return e.json(200, await $wasm.run.async("summary", { title: url, body: text }))
}, $apis.requireSuperuserAuth())

// Runs any plugin function with the query's input, to try plugins out (superusers only). The input is JSON; with
// raw=1 it's sent as the text it is.
//   /api/lab/call?plugin=evil&fn=run&input={"target":"127.0.0.1:8090"}
//   /api/lab/call?plugin=edifact&raw=1&input=UNH+1+ORDERS:D:96A:UN'
routerAdd("GET", "/api/lab/call", async (e) => {
  const q = e.request.url.query()
  const input = q.get("raw") ? q.get("input") : q.get("input") ? JSON.parse(q.get("input")) : {}
  try {
    return e.json(200, { output: await $wasm.call.async(q.get("plugin"), q.get("fn") || "run", input) })
  } catch (err) {
    return e.json(200, { error: { name: err.name, code: err.code, message: err.message, retryable: err.retryable } })
  }
}, $apis.requireSuperuserAuth())

// The plugins in pb_wasm/ and how each is doing (plugin.sh list), superusers only.
routerAdd("GET", "/api/lab/wasm", (e) => e.json(200, $wasm.plugins()), $apis.requireSuperuserAuth())
