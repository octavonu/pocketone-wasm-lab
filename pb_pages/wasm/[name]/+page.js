/// <reference path="../../../pb_data/types.d.ts" />
// Try one module from the browser: /wasm/<name>. The page sends what's typed on the left to /api/lab/try/<name> in
// pb_hooks, which calls the module with $wasm.inspect.async (pages run synchronously, calls are async), and shows on
// the right what came back: the output, the error, what the module wrote to stderr, and how long compiling and
// running took. Superusers only (../+middleware.js, and the route checks too).
module.exports = {
  load(ctx) {
    const mod = $wasm.modules().find((p) => p.name === ctx.params.name)
    if (!mod) ctx.res.status(404)
    ctx.data.module = mod || null
    ctx.data.limits = $wasm.limits()
    ctx.data.sizeText = mod && mod.size ? size(mod.size) : ""
  },
}

// size is n bytes for people: "95 KB", "4.3 MB".
function size(n) {
  return n < 1 << 20 ? `${Math.ceil(n / 1024)} KB` : `${(n / (1 << 20)).toFixed(1)} MB`
}
