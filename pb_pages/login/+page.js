// Superuser sign-in for the /wasm page (a cookie session through the auth plugin).
module.exports = {
  post(ctx) {
    const { email, password } = ctx.req.body()
    try {
      ctx.session.signInWithPassword(email, password, { collection: '_superusers' })
    } catch (e) {
      return ctx.res.redirect('/login', { flash: { error: 'Wrong email or password.' } })
    }
    return ctx.res.redirect('/wasm')
  },
}
