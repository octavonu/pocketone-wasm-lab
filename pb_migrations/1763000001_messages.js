/// <reference path="../pb_data/types.d.ts" />
// EDIFACT messages: pb_hooks/main.pb.js hands the raw text to the edifact-orders-go plugin and saves what it parsed.
migrate((app) => {
  app.save(new Collection({
    type: "base", name: "messages",
    fields: [
      { name: "raw", type: "text", max: 100000 },  // the message as received
      { name: "type", type: "text" },               // set by pb_hooks: ORDERS, INVOIC, ...
      { name: "segments", type: "number" },
      { name: "parsed", type: "json", maxSize: 2000000 },
      { name: "error", type: "text", max: 1000 },   // why it couldn't be parsed
      { name: "created", type: "autodate", onCreate: true },
    ],
  }))
}, (app) => {
  app.delete(app.findCollectionByNameOrId("messages"))
})
