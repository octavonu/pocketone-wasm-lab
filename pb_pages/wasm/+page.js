/// <reference path="../../pb_data/types.d.ts" />
// The /wasm page: the plugins in pb_hooks/, how each plugin is doing, the limits every call runs within, and each module's
// size (the calls running at once share MaxModulesMB of modules). Nothing to change here: a plugin is a file
// (pb_hooks/<name>.pb.wasm, which says what it is when run as `<name> --describe`), shipped with the app's code (a copy, `pocketone deploy`, SFTP); each
// call reads it as it is then.
//
// Each example in a plugin's manifest shows three ways to run it: from pb_hooks, locally with the wazero CLI, and what
// it should give.
module.exports = {
  load(ctx) {
    ctx.data.limits = $wasm.limits()
    ctx.data.plugins = rustFirst($wasm.plugins()).map((p) => ({
      ...p,
      sizeText: p.size ? size(p.size) : "",
      examples: (p.examples || []).map((ex) => ({
        ...ex,
        hook: ex.function === "run"
          ? `await $wasm.run.async(${JSON.stringify(p.name)}, ${JSON.stringify(ex.input)})`
          : `await $wasm.call.async(${JSON.stringify(p.name)}, ${JSON.stringify(ex.function)}, ${JSON.stringify(ex.input)})`,
        // a string goes to stdin as it is, anything else as JSON (as $wasm.run.async does)
        local: `printf '%s' ${shellQuote(typeof ex.input === "string" ? ex.input : JSON.stringify(ex.input))}` +
          ` | wazero run ${p.name}.pb.wasm ${ex.function}`,
        // the start of the input, on one line, for the collapsed example's title
        preview: shorten((typeof ex.input === "string" ? ex.input : JSON.stringify(ex.input)).replace(/\s+/g, " ")),
        want: ex.output === undefined ? "" : typeof ex.output === "string" ? ex.output : JSON.stringify(ex.output, null, 2),
      })),
    }))
  },
}

// rustFirst puts edifact-orders-rust just before edifact-orders-go: the same message, side by side.
function rustFirst(plugins) {
  const i = plugins.findIndex((p) => p.name === "edifact-orders-rust")
  const j = plugins.findIndex((p) => p.name === "edifact-orders-go")
  if (i < 0 || j < 0 || i < j) return plugins
  const list = plugins.slice()
  const [rust] = list.splice(i, 1)
  list.splice(j, 0, rust)
  return list
}

// size is n bytes for people: "95 KB", "4.3 MB".
function size(n) {
  return n < 1 << 20 ? `${Math.ceil(n / 1024)} KB` : `${(n / (1 << 20)).toFixed(1)} MB`
}

// shorten keeps the first 60 characters of s.
function shorten(s) {
  return s.length > 60 ? s.slice(0, 60) + "…" : s
}

// shellQuote quotes s for a POSIX shell: inside '...', each ' becomes '\'' (EDIFACT is full of them).
function shellQuote(s) {
  return "'" + s.replaceAll("'", "'\\''") + "'"
}
