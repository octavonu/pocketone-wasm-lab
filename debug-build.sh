#!/usr/bin/env bash
# Rebuilds only bin/pocketone, without optimizations (-N -l), so a debugger shows every variable and line. It uses
# build/pocketone from ./setup.sh and leaves pb_data/, pb_hooks/ and the modules as they are. ./setup.sh builds the normal
# binary again.
#
#   ./debug-build.sh   then ./start.sh, and attach from VS Code ("Attach to lab (start.sh)")
set -euo pipefail
cd "$(dirname "$0")"
[[ -f build/pocketone/go.mod ]] || { echo "run ./setup.sh first" >&2; exit 1; }
export CGO_ENABLED=0 GOTOOLCHAIN=auto
(cd build/pocketone && go build -gcflags "all=-N -l" \
  -ldflags "-X ganigeorgiev.com/pocketbase/pocketbase.Version=wasm-lab" -o ../../bin/pocketone .)
echo "bin/pocketone (debug build): restart ./start.sh"
