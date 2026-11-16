/// <reference path="../pb_data/types.d.ts" />
// The lab's logins, the same as every PocketOne example's (ext/devusers): superuser admin@example.com and verified
// user user@example.com, both with password "password". Lab only: never deploy this migration to a real instance.
migrate((app) => {
  for (const [collection, email] of [["_superusers", "admin@example.com"], ["users", "user@example.com"]]) {
    const col = app.findCollectionByNameOrId(collection)
    let rec
    try {
      rec = app.findAuthRecordByEmail(col, email)
    } catch (_) {
      rec = new Record(col)
      rec.setEmail(email)
    }
    rec.setPassword("password")
    rec.setVerified(true)
    app.save(rec)
  }
})
