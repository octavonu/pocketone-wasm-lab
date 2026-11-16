/// <reference path="../../../pb_data/types.d.ts" />
// Try one plugin from the browser: /wasm/<name>. The page sends what's typed on the left to the plugin, through
// $wasm.inspect (as a hook would call it), and shows on the right what came back: the output, the error, what the
// plugin wrote to stderr, and how long compiling and running took. Superusers only (../+middleware.js).
module.exports = {
  load(ctx) {
    const plugin = $wasm.plugins().find((p) => p.name === ctx.params.name)
    if (!plugin) ctx.res.status(404)
    ctx.data.plugin = plugin || null
    ctx.data.limits = $wasm.limits()
    ctx.data.sizeText = plugin && plugin.size ? size(plugin.size) : ""
  },

  // POST {function, input, mode: "text" | "json"} -> what $wasm.inspect returned, as JSON
  post(ctx) {
    // the session cookie is SameSite=Lax, so another site's POST doesn't carry it; this checks the origin as well
    if (ctx.req.header("Origin") !== ctx.req.url.origin) {
      return ctx.res.json(403, { error: { code: "forbidden", message: "not from this page" } })
    }
    const p = ctx.data.plugin
    if (!p || !p.running) {
      return ctx.res.json(404, { error: { code: "not_loaded", message: "the plugin isn't running" } })
    }
    const body = ctx.req.body()
    let input = String(body.input ?? "")
    if (body.mode === "json") {
      try {
        input = JSON.parse(input)
      } catch (e) {
        return ctx.res.json(400, { error: { code: "bad_json", message: "the input isn't JSON: " + e.message } })
      }
    }
    return ctx.res.json(200, $wasm.inspect(p.name, String(body.function || "run"), input))
  },
}

// size is n bytes for people: "95 KB", "4.3 MB".
function size(n) {
  return n < 1 << 20 ? `${Math.ceil(n / 1024)} KB` : `${(n / (1 << 20)).toFixed(1)} MB`
}
