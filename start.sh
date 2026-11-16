#!/usr/bin/env bash
# Runs the lab instance in the foreground; Ctrl+C stops it. This folder is the instance, laid out like one on
# PocketHost: pb_data/, pb_hooks/, pb_migrations/, pb_pages/ and pb_wasm/ side by side, each found beside pb_data.
# Hook and page edits show up at once (hooks reload); plugins in pb_wasm/ load as they change. Extra flags go to
# `pocketone serve`.
set -euo pipefail
cd "$(dirname "$0")"
[[ -x bin/pocketone && -d pb_data ]] || { echo "run ./setup.sh first" >&2; exit 1; }
echo "wasm:      http://127.0.0.1:8090/wasm"
echo "dashboard: http://127.0.0.1:8090/_/   (admin@example.com / password for both; app user user@example.com / password)"
exec bin/pocketone serve --dir pb_data --http 127.0.0.1:8090 "$@"
