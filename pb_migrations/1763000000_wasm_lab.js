/// <reference path="../pb_data/types.d.ts" />
// The WASM lab's one collection: posts, whose summary pb_hooks/main.pb.js fills in with the summary plugin.
migrate((app) => {
  app.save(new Collection({
    type: "base", name: "posts",
    listRule: "", viewRule: "",
    fields: [
      { name: "title", type: "text" },
      { name: "body", type: "text", max: 100000 },
      { name: "summary", type: "text", max: 1000 }, // set by pb_hooks from the plugin's output
      { name: "words", type: "number" },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
  }))
}, (app) => {
  app.delete(app.findCollectionByNameOrId("posts"))
})
