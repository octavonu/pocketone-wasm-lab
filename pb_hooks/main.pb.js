/// <reference path="../pb_data/types.d.ts" />
// The lab's hooks: the only place modules are called from. A module is a WASI program beside them (<name>.pb.wasm): what a
// hook gives it is its stdin (a string as it is, anything else as JSON), what it writes to stdout comes back (parsed
// if it's JSON). The hook decides what to save.
//
// Calls are async only: the hooks are async and await $wasm.run.async / $wasm.call.async. The module runs off the
// app's one JS VM, so the app serves other requests meanwhile (a Go module compiles for over a second each call).
onBootstrap((e) => {
  e.app.logger().info("lab hooks loaded")
  e.next();
})
//
// A new post gets its summary before it's saved. Without the module (removed, broken) the post is saved anyway.
onRecordCreate(async (e) => {
  try {
    const out = await $wasm.run.async("summary", { title: e.record.get("title"), body: e.record.get("body") })
    e.record.set("summary", out.text)
    e.record.set("words", out.words)
  } catch (err) {
    // err.name === "WasmError"; err.code, err.message, err.retryable, err.module
    e.app.logger().warn("no summary", "code", err.code, "message", err.message)
    e.record.set("summary", "(no summary: " + err.code + ")")
  }
  return e.next()
}, "posts")

// An EDIFACT message is parsed when it's saved: the raw text goes to the module as it is (a string is the module's
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

// An order, EDIFACT ORDERS or XML, read into one order JSON: the hook looks at the format and picks the module
// (edifact-orders-rust or order-xml, both Rust); the modules only read. Install them first: ./module.sh install edifact-orders-rust, order-xml.
//   curl -X POST http://127.0.0.1:8090/api/lab/order --data-binary @extras/order.edi -H "Authorization: <token>"
routerAdd("POST", "/api/lab/order", async (e) => {
  const raw = toString(e.request.body)
  const mod = raw.trimStart().startsWith("<") ? "order-xml" : "edifact-orders-rust"
  try {
    return e.json(200, { module: mod, order: await $wasm.run.async(mod, raw) })
  } catch (err) {
    return e.json(400, { module: mod, error: { code: err.code, message: err.message } })
  }
}, $apis.requireSuperuserAuth())

// A module never reaches the network: the hook calls the outside API and hands the result in.
//   http://127.0.0.1:8090/api/lab/summarize?url=https://example.com   (signed in as a superuser)
routerAdd("GET", "/api/lab/summarize", async (e) => {
  const url = e.request.url.query().get("url")
  const res = $http.send({ url: url, timeout: 10 })
  const text = toString(res.body)
    .replace(/<(style|script)[^>]*>[\s\S]*?<\/\1>/gi, " ") // not text
    .replace(/<[^>]*>/g, " ")
  return e.json(200, await $wasm.run.async("summary", { title: url, body: text }))
}, $apis.requireSuperuserAuth())

// Runs any module function with the query's input, to try modules out (superusers only). The input is JSON; with
// raw=1 it's sent as the text it is.
//   /api/lab/call?module=evil&fn=run&input={"target":"127.0.0.1:8090"}
//   /api/lab/call?module=edifact&raw=1&input=UNH+1+ORDERS:D:96A:UN'
routerAdd("GET", "/api/lab/call", async (e) => {
  const q = e.request.url.query()
  const input = q.get("raw") ? q.get("input") : q.get("input") ? JSON.parse(q.get("input")) : {}
  try {
    return e.json(200, { output: await $wasm.call.async(q.get("module"), q.get("fn") || "run", input) })
  } catch (err) {
    return e.json(200, { error: { name: err.name, code: err.code, message: err.message, retryable: err.retryable } })
  }
}, $apis.requireSuperuserAuth())

// The modules in pb_hooks/ and how each is doing (module.sh list), superusers only.
routerAdd("GET", "/api/lab/wasm", (e) => e.json(200, $wasm.modules()), $apis.requireSuperuserAuth())

// The /wasm/<name> page's "Run" button: {function, input, mode: "text" | "json"} -> what $wasm.inspect.async gives
// (output, error, stderr, timings). Here and not in the page, since pages run synchronously and calls are async.
// Superusers only, signed in on the page (the pb_auth cookie) or with a token; and only from this site's pages.
routerAdd("POST", "/api/lab/try/{name}", async (e) => {
  if (!labSuperuser(e)) return e.json(403, { error: { code: "forbidden", message: "superusers only" } })
  const origin = e.request.header.get("Origin")
  if (origin && origin !== (e.request.tls ? "https://" : "http://") + e.request.host) {
    return e.json(403, { error: { code: "forbidden", message: "not from this site" } })
  }
  const name = e.request.pathValue("name")
  const p = $wasm.modules().find((p) => p.name === name)
  if (!p || !p.running) return e.json(404, { error: { code: "not_loaded", message: "the module isn't running" } })
  const body = e.requestInfo().body
  let input = String(body.input ?? "")
  if (body.mode === "json") {
    try {
      input = JSON.parse(input)
    } catch (err) {
      return e.json(400, { error: { code: "bad_json", message: "the input isn't JSON: " + err.message } })
    }
  }
  return e.json(200, await $wasm.inspect.async(name, String(body.function || "run"), input))
})

// labSuperuser: the request's superuser, from a token (Authorization) or the pages' pb_auth cookie ({token, record}).
function labSuperuser(e) {
  if (e.auth) return e.auth.isSuperuser()
  try {
    let v = e.request.cookie("pb_auth").value
    if (!v.startsWith("{")) v = decodeURIComponent(v)
    const rec = $app.findAuthRecordByToken(JSON.parse(v).token, "auth")
    return rec.isSuperuser()
  } catch (err) {
    return false
  }
}
