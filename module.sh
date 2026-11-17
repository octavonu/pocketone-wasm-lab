#!/usr/bin/env bash
# Puts modules in the lab instance's module folder, pb_hooks/, the way a copy, `pocketone deploy` or an SFTP upload
# does: <name>.pb.wasm, beside the JS hooks. The module says what it is itself (<name> --describe). Each call reads
# the module's file as it is then; the change in pb_hooks/ also restarts the app, as a .pb.js change does. The module
# is copied under a hidden name and renamed into place, as an upload should, so no call reads it half written.
#
#   ./module.sh list
#   ./module.sh install <name> [as]   copy modules/<name> (built by ./setup.sh) in, as <as> if given
#   ./module.sh remove <name>
set -euo pipefail
cd "$(dirname "$0")"
U=http://127.0.0.1:8090
DIR=pb_hooks
mkdir -p "$DIR"

running() { curl -s -o /dev/null "$U/api/health"; }
modules() { # what the running lab says about its modules (JSON)
  local t
  t=$(curl -sf -X POST "$U/api/collections/_superusers/auth-with-password" -H 'Content-Type: application/json' \
    -d '{"identity":"admin@example.com","password":"password"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
  curl -sf "$U/api/lab/wasm" -H "Authorization: $t"
}
case "${1:-list}" in
  list)
    if running; then
      modules | python3 -c '
import sys,json
items=json.load(sys.stdin)
print("no modules" if not items else "\n".join("%-20s %s" % (p["name"], ("on" if p["running"] else "error") + (": " + p["error"] if p.get("error") else "")) for p in items))'
    else
      ls "$DIR" | grep '\.pb\.wasm$' || echo "no modules"
    fi ;;
  install)
    name="${2:?name}" as="${3:-$2}"
    [[ -f "modules/$name/module.wasm" ]] || { echo "no modules/$name (built by ./setup.sh)" >&2; exit 1; }
    cp "modules/$name/module.wasm" "$DIR/.$as.pb.wasm.part" && mv "$DIR/.$as.pb.wasm.part" "$DIR/$as.pb.wasm"
    echo "$as: copied to $DIR/$as.pb.wasm; the next call runs it" ;;
  remove)
    name="${2:?name}"
    [[ -f "$DIR/$name.pb.wasm" ]] || { echo "no module $name in $DIR" >&2; exit 1; }
    rm -f "$DIR/$name.pb.wasm"
    echo "removed $name; the next call finds no such module" ;;
  *) echo "usage: $0 list | install <name> [as] | remove <name>" >&2; exit 1 ;;
esac
