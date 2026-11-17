// Only superusers: a module runs inside the app, so installing one is an admin decision. And only where ext/wasm is
// on: an instance with extensions.wasm.enabled: false (under pocker) has no $wasm at all.
module.exports = (ctx, next) => {
  if (!ctx.auth || !ctx.auth.isSuperuser()) return ctx.res.redirect('/login')
  if (typeof $wasm === 'undefined') {
    return ctx.res.html(503, '<!doctype html><title>WASM off</title><p>WASM is off for this app ' +
      '(<code>extensions.wasm.enabled: false</code>): no modules run here.</p>')
  }
  return next()
}
