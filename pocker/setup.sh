#!/usr/bin/env bash
# The WASM lab under pocker: one pocketone process hosting three instances, each a normal app folder in pb_root/<id>
# with its own pb_data/, pb_hooks/ (the JS hooks and the plugins, <name>.pb.wasm) and pb_pages/, routed by hostname. It uses the lab's binary and plugins
# (../setup.sh builds them, with ext/wasm in the standard set every pocker instance gets) and its hooks, pages and
# migrations (collections, admin@example.com / password).
#
#   alpha.localhost  summary (Rust), edifact-orders-go; its own wasm settings: timeout 10s, maxCallMemoryMB 64
#   beta.localhost   summary (Go), crypto, memhog; the defaults
#   gamma.localhost  wasm turned off (enabled: false): no $wasm at all
#
#   ./setup.sh   (again: a fresh pb_root/), then ./start.sh
set -euo pipefail
cd "$(dirname "$0")"
LAB="$(cd .. && pwd)"
PORT=8092
[[ -x "$LAB/bin/pocketone" && -d "$LAB/plugins/summary" ]] || { echo "run ../setup.sh first" >&2; exit 1; }
if curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
  echo "127.0.0.1:$PORT is in use: stop the pocker lab first (Ctrl+C where start.sh runs)" >&2
  exit 1
fi

cat > pocketone.yaml <<YAML
# The pocker lab: many instances in one process (pocker), routed by hostname. *.localhost resolves to 127.0.0.1.
server: { http: "127.0.0.1:$PORT" }
multisite: {}
instances: { file: ./instances.yaml }
pocker: { root: ./pb_root }
YAML

cat > instances.yaml <<'YAML'
# Edits apply without restarting the host (checked every 2 s); a change to an instance's extensions restarts just
# that instance on its next request.
instances:
  - id: alpha
    hosts: [alpha.localhost]
    extensions: { wasm: { timeout: 10s, maxCallMemoryMB: 64 } }
  - id: beta
    hosts: [beta.localhost]
  - id: gamma
    hosts: [gamma.localhost]
    extensions: { wasm: { enabled: false } }
YAML

rm -rf pb_root
install() { # instance, plugin, [as]
  cp "$LAB/plugins/$2/plugin.wasm" "pb_root/$1/pb_hooks/${3:-$2}.pb.wasm"
}
for id in alpha beta gamma; do
  mkdir -p "pb_root/$id"
  cp -R "$LAB/pb_hooks" "$LAB/pb_pages" "$LAB/pb_migrations" "pb_root/$id/"
  rm -f "pb_root/$id"/pb_hooks/*.pb.wasm   # the single-app lab's plugins; each instance gets its own below
  sed -i '' "s/127.0.0.1:8090/$id.localhost:$PORT/g" "pb_root/$id/pb_hooks/main.pb.js"
done
install alpha summary-rust summary
install alpha edifact-orders-go
install beta summary
install beta crypto
install beta memhog
install gamma summary-rust summary
echo "pb_root/: alpha, beta, gamma. ./start.sh, then http://alpha.localhost:$PORT/wasm  (admin@example.com / password)"
