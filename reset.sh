#!/usr/bin/env bash
# A fresh lab instance: an empty pb_data/ (from pb_migrations/: the posts and messages collections, and the logins of
# every PocketOne example, superuser admin@example.com and user user@example.com, both with password "password") and
# only the summary and edifact-orders-go plugins in pb_hooks/. Keeps the built binary and plugins (./setup.sh rebuilds those).
set -euo pipefail
cd "$(dirname "$0")"
[[ -x bin/pocketone && -d plugins/summary ]] || { echo "run ./setup.sh first" >&2; exit 1; }
if curl -s -o /dev/null http://127.0.0.1:8090/; then
  echo "127.0.0.1:8090 is in use: stop the lab first (Ctrl+C where start.sh runs)" >&2
  exit 1
fi
rm -rf pb_data pb_wasm run   # pb_wasm/: the folder plugins had before 2026-11-16
rm -f pb_hooks/*.pb.wasm pb_hooks/.*.pb.wasm.part
bin/pocketone migrate up --dir pb_data >/dev/null   # the collections and the logins, from pb_migrations/

# the plugins: files in pb_hooks/, as a copy or a deploy puts them (they load when the lab starts). summary runs on
# every post, so it's the Rust build (~40 ms a call; Go's compiles for ~1.7 s each call); Go when there's no Rust.
if [[ -d plugins/summary-rust ]]; then ./plugin.sh install summary-rust summary >/dev/null; else ./plugin.sh install summary >/dev/null; fi
./plugin.sh install edifact-orders-go >/dev/null
echo "fresh instance (pb_data/, pb_hooks/: summary (Rust), edifact-orders-go). ./start.sh, then http://127.0.0.1:8090/wasm  (admin@example.com / password)"
