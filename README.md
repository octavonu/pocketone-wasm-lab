# PocketOne WASM lab

**Bring your own WASM (BYOW).** A hands-on lab for [`ext/wasm`](https://github.com/octavonu/pocketone/tree/ext-wasm/ext/wasm),
the PocketOne extension that lets pb_hooks call your own code compiled to WebAssembly, where `$os.cmd` and `$os.exec`
aren't allowed. A plugin is a closed box: JSON (or text) in, JSON out. It can't reach the database, files, network,
environment or processes; the hook gives it what it needs and decides what to do with the result.

The lab builds PocketOne's stock binary with `ext/wasm` added, about fifteen plugins in Go, Rust and Zig (some made to
be refused), and an instance laid out like one on PocketHost. Then you try it in the browser and with `curl` ([Try it](#try-it)).
[`pocker/`](pocker/README.md) runs the same lab as three instances in one
process, as PocketHost does.

## Run it

You need only Go 1.27 (or `GOTOOLCHAIN=auto`): the Rust and Zig plugins come built (`ext/wasm` keeps its examples
built beside their sources, and its tests check they're what the sources build; this lab keeps `src/evil`'s).
`BUILD_WASM=1 ./setup.sh` builds them from source instead, with Rust (`rustup target add wasm32-wasip1`) and Zig 0.14.
The [wazero CLI](https://wazero.io) is handy for running a plugin by hand.

```sh
./setup.sh     # once, ~2 min: builds everything and makes a fresh instance
./start.sh     # serves it on http://127.0.0.1:8090; Ctrl+C stops it
```

`setup.sh` clones PocketOne with `ext/wasm` (the `ext-wasm` branch of a fork, until it's in PocketOne) into
`build/pocketone-src`. To use a checkout you already have: `POCKETONE=~/src/pocketone ./setup.sh`.

- **Plugins page:** http://127.0.0.1:8090/wasm: the plugins in `pb_hooks/`, the limits every call runs within, and each
  plugin's functions, examples and module size.
- **Try a plugin:** http://127.0.0.1:8090/wasm/edifact-orders-go (any name): input on the left (JSON, text or a file,
  and the examples from the plugin's manifest, `<name> --describe`); output, error, compile and run times and what the plugin wrote to
  stderr on the right; below, the same call from pb_hooks and with the wazero CLI. Ctrl+Enter runs it.
- **Dashboard:** http://127.0.0.1:8090/_/

Login for all three: `admin@example.com` / `password` (also a plain user, `user@example.com` / `password`). These are
local test accounts, made by a migration.

## Try it

With the lab running (`./start.sh`), in another terminal in this folder. Each step is short; together they answer
what you'd ask about a feature like this.

**A hook calls a plugin.** In the dashboard, create a `posts` record with a title and a few words in `body`. It's
saved with `summary` and `words` already filled: the hook called the `summary` plugin before the save
([pb_hooks/main.pb.js](pb_hooks/main.pb.js)). Remove the plugin (`./plugin.sh remove summary`) and create another:
it's saved anyway, with `(no summary: not_found)`, because the hook caught the `WasmError`. Put it back with
`./plugin.sh install summary-rust summary`.

**Is it safe?** `./plugin.sh install devil`, then open `/wasm/devil` and run both examples, then your own input,
like `{"steal": "pb_hooks/main.pb.js"}`. It tries to read the app's database and `/etc/passwd`, list folders, write
a file, read the environment, run `sh -c id` and send to `attacker.example`. Every line says `refused`, and the
verdict is `nothing got out of the box`. The same with the wazero CLI (`echo '{}' | wazero run
plugins/devil/plugin.wasm run`): the box comes from WASI, not from PocketOne.

**What does it cost?** `./plugin.sh install memhog`, then on `/wasm/memhog`:
- `{"mb": 8}` works;
- `{"mb": 64}` fails as `crashed`, with "memory allocation of 1048576 bytes failed … (each call may allocate up to
  32 MB: MaxCallMemoryMB)", and its log shows how far it got;
- `probe` says `got 30 MB`: the limit, seen from inside;
- then create a post: everything else works, since only that call failed.

**Why not in JS?** Two things pb_hooks can't do well:
- `./plugin.sh install waflows`, then run the three examples on `/wasm/waflows`: the RSA-OAEP and AES-GCM steps of a
  WhatsApp Flows endpoint, each marked ✓ against the expected output. Change one letter of `data` in the first one:
  `cannot_decrypt`.
- `./plugin.sh install edifact-orders-rust` and `./plugin.sh install order-xml`, then post an order in either format
  to the lab's route, which picks the plugin:

  ```sh
  T=$(curl -s -X POST http://127.0.0.1:8090/api/collections/_superusers/auth-with-password \
    -H 'Content-Type: application/json' -d '{"identity":"admin@example.com","password":"password"}' \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
  curl -s -X POST http://127.0.0.1:8090/api/lab/order -H "Authorization: $T" --data-binary @extras/order.edi
  curl -s -X POST http://127.0.0.1:8090/api/lab/order -H "Authorization: $T" --data-binary @extras/order.xml
  ```

  Both give the same order (`PO-4711`, two lines). On `/wasm/edifact-orders-rust`, example 2 reads a full ORDERS
  message: parties, addresses, prices, allowances, and a warning for the wrong segment count in its UNT.

**Deploy a plugin.** A plugin is one file, beside the JS hooks. Copy it in the way an upload should, under a hidden
name first, then renamed:

```sh
cp plugins/crypto/plugin.wasm pb_hooks/.crypto.pb.wasm.part && mv pb_hooks/.crypto.pb.wasm.part pb_hooks/crypto.pb.wasm
```

The change in `pb_hooks/` restarts the app, as a `.pb.js` change does; then `/wasm` shows `crypto`, with the
description, functions and examples it gives itself (`wazero run pb_hooks/crypto.pb.wasm --describe`), and
`/wasm/crypto` runs it. Rename it to `crypto.pb.wasm.off` and it's gone.

**Go or Rust?** `./bulk.sh 300` creates 300 posts at once, each summarized by the Rust plugin: a few seconds, all
with a summary. Then `./plugin.sh install summary` (the Go build) and `./bulk.sh 20`: each call compiles a 4.3 MB
module for over a second, only 2 fit in `MaxModulesMB` at once, and the calls that wait longer than 5 s fail as
`busy`, so some posts get no summary. `/wasm` shows why: the limits, and each module's size. Put Rust back with
`./plugin.sh install summary-rust summary`.

## The model

A plugin is an ordinary program built for WASI (`wasip1`): it reads its input on **stdin**, writes the result on
**stdout**, and exits non-zero when it fails, with the error on stderr (ideally JSON: `{"code", "message",
"retryable"}`). The function asked for is its first argument (`os.Args[1]` in Go). The same shape as a program run
with `$os.exec`, without access to anything.

It's called from **pb_hooks** only: `$wasm.run(name, input)`, `$wasm.call(name, function, input)`, and the `.async`
twins (`await $wasm.run.async(...)`), which run the plugin off the app's JS VM so the app serves other requests
meanwhile. A string goes to stdin as it is (EDIFACT, CSV, XML), anything else as JSON. See
[pb_hooks/main.pb.js](pb_hooks/main.pb.js).

A plugin is **one file** beside the JS hooks: `pb_hooks/<name>.pb.wasm`. It says what it is itself: run as
`<name> --describe`, it prints its manifest (description, version, functions (default `run`), language, repository
and examples), as JSON on stdout; the examples here keep it as `plugin.json` beside the source and build it in. A
plugin that doesn't answer `--describe` gets the defaults; one whose manifest is wrong still runs, and `/wasm` shows
the error. It gets there like the rest of the code: a copy, `pocketone deploy`, SFTP, and the change restarts the app,
as a `.pb.js` change does. Like `node script.js`, every call reads the plugin's file as it is then, and nothing stays
in memory between calls. To turn a plugin off, remove or rename it. One that can't load (a broken module, a
half-written upload) can't be called, and `/wasm` says why. A function the plugin doesn't have is for the plugin to
refuse: by convention it fails with `no_such_function`.

## Scripts

| Script | What it does |
|---|---|
| `setup.sh` | Builds PocketOne (`examples/pocketone`, copied to `build/pocketone` with `wasm.New` in the standard set) as `bin/pocketone`, the plugins into `plugins/` (Go built, Rust and Zig copied as kept built; `BUILD_WASM=1` builds those too), then runs `reset.sh`. |
| `reset.sh` | A fresh instance: an empty `pb_data/` with the `posts` and `messages` collections and the two logins, and only `summary` (the Rust build) and `edifact-orders-go` in `pb_hooks/`. Doesn't rebuild. |
| `start.sh` | Serves the instance in the foreground. Changes in `pb_hooks/` and `pb_pages/` show at once. |
| `plugin.sh` | Copies plugins into `pb_hooks/` (`<name>.pb.wasm`), as a deploy would: `list`, `install <name> [as]` (from `plugins/<name>`), `remove <name>`. |
| `bulk.sh [N]` | Creates N posts at once (default 1000); each gets its summary from a plugin before it's saved. |
| `debug-build.sh` | Rebuilds only `bin/pocketone` without optimizations, for a debugger (`.vscode/launch.json`). |

## What's where

The folder is the instance, laid out like one on PocketHost: `pb_data/`, `pb_hooks/`, `pb_migrations/` and
`pb_pages/` side by side. The rest belongs to the lab.

```
pb_data/          the instance's data (reset.sh makes it again)
pb_hooks/         main.pb.js: a summary on every new post, EDIFACT parsed on every new message, and the lab's
                  routes: /api/lab/call, /api/lab/wasm, /api/lab/order, /api/lab/summarize ($http.send); and the
                  instance's plugins, <name>.pb.wasm
pb_migrations/    the posts and messages collections, the two logins
pb_pages/         /wasm (the plugins in pb_hooks/) and /wasm/<name> (try a plugin); /login, /logout

src/              two lab plugins: edifact (Go), evil (Rust, kept built: evil.pb.wasm). The others are ext/wasm's
                  examples, in PocketOne
plugins/          the plugins (setup.sh)
extras/           files for the scenarios: order.edi, order.xml, broken.wasm (setup.sh)
pocker/           the same lab under pocker: three instances in one process
bin/, build/      the built binary, and the copy of PocketOne's examples/pocketone it's built from
```

## The plugins

| Plugin | Language | Size | What it does |
|---|---|---|---|
| `summary` | Go | ~4.3 MB | `{title, body}` → `{text, words}`; without a body, the error `empty_body` |
| `summary-rust` | Rust | ~96 KB | the same; `reset.sh` installs it as `summary` |
| `summary-zig` | Zig | ~56 KB | the same |
| `edifact-orders-go` | Go | ~4.3 MB | an EDIFACT message (raw text) → segments, elements, components |
| `crypto` | Go | ~4.7 MB | `encrypt` / `decrypt`, AES-256-GCM; the key comes with the input |
| `edifact-orders-rust` | Rust | ~144 KB | an EDIFACT ORDERS message → the whole order: interchange, parties with addresses and contacts, lines with codes, prices and allowances; UNT/UNZ checked ([edifact-rs](https://crates.io/crates/edifact-rs)) |
| `order-xml` | Rust | ~136 KB | an XML order → the same order JSON ([roxmltree](https://crates.io/crates/roxmltree)) |
| `waflows` | Rust | ~270 KB | what pb_hooks lacks for WhatsApp Flows: `rsa-decrypt` (RSA-OAEP), `gcm-open` / `gcm-seal` (AES-GCM with the given key and IV); JSON and base64 stay in the hook |
| `devil` | Rust | ~124 KB | tries, in plain sight, what a plugin may not do: files, environment, a command (like `$os.cmd`), sending to `attacker.example`; all refused, with the reason |
| `evil` | Rust | ~120 KB | tries files, environment, arguments, TCP, HTTP, listening on a port; reports what it got (nothing) |
| `memhog` | Rust | ~92 KB | asks for more memory than a call may have (`MaxCallMemoryMB`): `run` allocates the MB you ask for, `probe` says how much it got before the refusal |
| `fat_evil` | Go | ~11 MB | `evil` in Go: over `MaxModulesMB` (10 MB), so refused when it loads |
| `phone` | Go | ~4.3 MB | an Extism plugin: refused when it loads |
| `library` | Go | ~4.3 MB | `summary` built as a library (`-buildmode=c-shared`), the usual mistake: refused when it loads |

Every call compiles its plugin and keeps nothing: memory is used only while a call runs. Measured with `summary` on a
laptop:

| | Go | Rust | Zig |
|---|---|---|---|
| One call, compiling included | ~1.7 s | ~40 ms | ~23 ms |
| Compiled code, while the call runs | ~20–30 MB | ~2–5 MB | ~2.5 MB |
| The program's memory, while it runs | 3.6 MB | 1.1 MB | 1.2 MB |
| Between calls (only the `.wasm` file) | 4.4 MB | 95 KB | 55 KB |

So the calls running at once are bounded by count and by module size: at most `MaxConcurrent` (8) calls, whose
`.wasm` sizes add up to at most `MaxModulesMB` (10 MB). With the defaults, 2 Go calls run at once, or 8 Rust or Zig
ones. Go where speed doesn't matter (a nightly job, an import); Rust or Zig on a hook that runs on every save.

A new plugin in Go: `GOOS=wasip1 GOARCH=wasm go build -o plugin.wasm .` from a `main` that reads stdin. In Rust:
`cargo build --release --target wasm32-wasip1`. In Zig: target `wasm32-wasi`, with a smaller stack
(`stack_size = 1 << 20`; the default 16 MB is taken on every call).

Default limits: 32 MB of memory and 5 s per call, at most 8 calls and 10 MB of modules at once (10 MB is also the
largest module that loads), input and output up to 4 MB each.

## License

MIT ([LICENSE](LICENSE)).
