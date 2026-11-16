#!/usr/bin/env bash
# Puts plugins in the lab instance's plugin folder, pb_wasm/, the way a copy, `pocketone deploy` or an SFTP
# upload does: <name>.wasm, and <name>.json when the plugin has a plugin.json. Each call reads the plugin's files as
# they are then, so the next call gets the new version: no restart. The module is copied under a hidden name and
# renamed into place, as an upload should, so no call reads it half written.
#
#   ./plugin.sh list
#   ./plugin.sh install <name> [as]   copy plugins/<name> (built by ./setup.sh) in, as <as> if given
#   ./plugin.sh remove <name>
set -euo pipefail
cd "$(dirname "$0")"
U=http://127.0.0.1:8090
DIR=pb_wasm
mkdir -p "$DIR"

running() { curl -s -o /dev/null "$U/api/health"; }
plugins() { # what the running lab says about its plugins (JSON)
  local t
  t=$(curl -sf -X POST "$U/api/collections/_superusers/auth-with-password" -H 'Content-Type: application/json' \
    -d '{"identity":"admin@example.com","password":"password"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
  curl -sf "$U/api/lab/wasm" -H "Authorization: $t"
}
case "${1:-list}" in
  list)
    if running; then
      plugins | python3 -c '
import sys,json
items=json.load(sys.stdin)
print("no plugins" if not items else "\n".join("%-20s %s" % (p["name"], ("on" if p["running"] else "error") + (": " + p["error"] if p.get("error") else "")) for p in items))'
    else
      ls "$DIR"
    fi ;;
  install)
    name="${2:?name}" as="${3:-$2}"
    [[ -f "plugins/$name/plugin.wasm" ]] || { echo "no plugins/$name (built by ./setup.sh)" >&2; exit 1; }
    if [[ -f "plugins/$name/plugin.json" ]]; then cp "plugins/$name/plugin.json" "$DIR/$as.json"; else rm -f "$DIR/$as.json"; fi
    cp "plugins/$name/plugin.wasm" "$DIR/.$as.wasm.part" && mv "$DIR/.$as.wasm.part" "$DIR/$as.wasm"
    echo "$as: copied to $DIR; the next call runs it" ;;
  remove)
    name="${2:?name}"
    [[ -f "$DIR/$name.wasm" ]] || { echo "no plugin $name in $DIR" >&2; exit 1; }
    rm -f "$DIR/$name.wasm" "$DIR/$name.json"
    echo "removed $name; the next call finds no such plugin" ;;
  *) echo "usage: $0 list | install <name> [as] | remove <name>" >&2; exit 1 ;;
esac
