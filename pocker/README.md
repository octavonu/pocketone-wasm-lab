# The lab under pocker

One `pocketone` process hosting three instances, routed by hostname, the way PocketHost runs them. Each is a normal
app folder in `pb_root/<id>/` (`pb_data/`, `pb_hooks/` with its plugins, `pb_pages/`). It uses the lab's binary and
plugins (`../setup.sh` builds them, with `ext/wasm` in the standard set every pocker instance gets) and its hooks,
pages and migrations.

| Instance | Plugins in `pb_hooks/` | `extensions.wasm` settings |
|---|---|---|
| `alpha.localhost` | `summary` (Rust), `edifact-orders-go` | `timeout: 10s`, `maxCallMemoryMB: 64` |
| `beta.localhost` | `summary` (Go), `crypto`, `memhog` | the defaults |
| `gamma.localhost` | `summary` (Rust) | `enabled: false`: no `$wasm` |

```sh
./setup.sh      # once (again: a fresh pb_root/)
./start.sh      # Ctrl+C stops it
```

Then http://alpha.localhost:8092/wasm (and `beta`, `gamma`), `admin@example.com` / `password` on each.
`*.localhost` resolves to `127.0.0.1`. Port 8092, so it runs beside the single-app lab (8090).

- `pocketone.yaml`: `multisite`, `pocker: { root: ./pb_root }`, `instances: { file: ./instances.yaml }`.
- `instances.yaml`: the three instances. Edits apply without restarting the process (it's read every 2 s); a change
  to an instance's `extensions` restarts only that instance, on its next request.
- A plugin goes in as in the single-app lab: one file, `pb_root/<id>/pb_hooks/<name>.pb.wasm` (a copy, `pocketone
  deploy`, SFTP). The change restarts only that instance, gracefully; every call reads the file as it is then.
- Logs: each instance's dashboard (Logs); `console.*` and starts in `pb_root/<id>/logs/exec.log`; the host's in the
  terminal running `start.sh`.

## Try it

A token for an instance, and a call through the lab's route:

```sh
tok() { curl -s -X POST http://$1.localhost:8092/api/collections/_superusers/auth-with-password \
  -H 'Content-Type: application/json' -d '{"identity":"admin@example.com","password":"password"}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])'; }
call() { curl -s -G http://$1.localhost:8092/api/lab/call -H "Authorization: $(tok $1)" \
  --data-urlencode plugin=$2 --data-urlencode fn=${3:-run} --data-urlencode "input=${4:-}"; echo; }
```

**Each instance has its own plugins.** `/wasm` on `alpha` and on `beta` list different plugins.
`call alpha crypto encrypt '{"key":"x","text":"y"}'` is `not_found`: `crypto` is only on beta, and one instance can't
call another's plugins, though they share the process.

**Its own settings.** On `/wasm`, alpha shows 64 MB and 10 s per call, beta 32 MB and 5 s. Copy `memhog` into alpha
too (`cp ../plugins/memhog/plugin.wasm pb_root/alpha/pb_hooks/memhog.pb.wasm`): `call alpha memhog run '{"mb":48}'` works, `call beta memhog run '{"mb":48}'` fails as `crashed`.

**Turned off.** On gamma there's no `$wasm`: a new post is saved with `(no summary: undefined)`, and `/wasm` says
WASM is off, though its `pb_hooks/` has a plugin. Set `enabled: true` for it in `instances.yaml`: gamma restarts on its
next request (only gamma, the log says so) and runs its plugin.

**Limits per instance.** Load beta with many posts at once (the Go `summary` compiles for over a second, so some fail
as `busy`) while you create posts on alpha: alpha's calls don't wait for beta's.

**A restart doesn't cut a call short.** Start a slow call on beta (`call beta summary run '{"title":"a","body":"b c"}'`)
and, within a second, edit `pb_root/beta/pb_hooks/main.pb.js`: the call finishes, then the new hooks take over.

**Deploy.** From a project folder whose `pb_hooks/` holds a new plugin (`<name>.pb.wasm`):
`P1_TOKEN=$(tok beta) ../bin/pocketone deploy http://beta.localhost:8092`. Beta restarts gracefully (the calls
running finish first) and the new plugin answers on beta; alpha and gamma don't notice.
