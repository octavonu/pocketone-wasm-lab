#!/usr/bin/env bash
# Runs the pocker lab in the foreground (Ctrl+C stops it): the lab's binary (../bin), with pocketone.yaml here
# (multisite, pocker).
set -euo pipefail
cd "$(dirname "$0")"
[[ -f pocketone.yaml && -d pb_root ]] || { echo "run ./setup.sh first" >&2; exit 1; }
for id in alpha beta gamma; do echo "$id: http://$id.localhost:8092/wasm"; done
echo "(admin@example.com / password on each)"
exec ../bin/pocketone serve --config pocketone.yaml "$@"
