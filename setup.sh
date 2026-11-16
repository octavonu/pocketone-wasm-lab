#!/usr/bin/env bash
# Builds the WASM lab from scratch: PocketOne (its examples/pocketone, the stock binary) with ext/wasm in the standard
# set, the plugins (WASI programs: summary in Go, Rust and Zig when their toolchains are there, edifact-orders-go,
# crypto, edifact-orders-rust, order-xml, devil, evil, memhog and waflows, and three that must be refused: phone,
# library and fat_evil), and a fresh instance here (pb_data/, pb_wasm/) with the lab collections and a superuser.
# Everything stays in this folder.
#
#   ./setup.sh                              PocketOne with ext/wasm cloned into build/pocketone-src
#   POCKETONE=~/src/pocketone ./setup.sh    or a checkout you have, with ext/wasm in it
#
# then ./start.sh
set -euo pipefail
cd "$(dirname "$0")"
LAB="$PWD"
# PocketOne with ext/wasm: until ext/wasm is in PocketOne itself, the ext-wasm branch of a fork
REPO="${POCKETONE_REPO:-https://github.com/octavonu/pocketone.git}" BRANCH="${POCKETONE_BRANCH:-ext-wasm}"
PO="${POCKETONE:-$LAB/build/pocketone-src}"
WASM="$PO/ext/wasm"
export CGO_ENABLED=0 GOTOOLCHAIN=auto

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

if curl -s -o /dev/null http://127.0.0.1:8090/; then
  echo "127.0.0.1:8090 is in use: stop the lab first (Ctrl+C where start.sh runs)" >&2
  exit 1
fi

step "1. PocketOne + ext/wasm"
if [[ ! -d "$WASM" ]]; then
  [[ -n "${POCKETONE:-}" ]] && { echo "$PO has no ext/wasm" >&2; exit 1; }
  rm -rf "$PO" && git clone --quiet --depth 1 --branch "$BRANCH" "$REPO" "$PO"
fi
# PocketOne's stock binary (examples/pocketone), copied to build/pocketone with ext/wasm added to the standard
# set, in both places that build one: main.go (a single app, as here) and multi.go (every pocker instance). That
# gives pb_hooks $wasm, and pb_data/types.d.ts its types. The checkout itself is left as it is.
rm -rf build/pocketone && mkdir -p build && cp -R "$PO/examples/pocketone" build/pocketone
python3 - "$PO/examples/pocketone" build/pocketone <<'PY'
import json, os, re, subprocess, sys
src, dst = sys.argv[1], sys.argv[2]
imp = '\t"github.com/pockethost/pocketone/ext/mailtrap"\n'
for name, pattern, line in [
    ("main.go", r"(\tset := standard\.New\(\)\n)", "\tset.Add(wasm.New(wasm.Config{})) // $wasm in pb_hooks\n"),
    ("multi.go", r"(\tset := standard\.New\(\)\n)", "\tset.Add(wasm.New(wasm.Config{})) // $wasm in every instance's pb_hooks\n"),
]:
    code = open(f"{dst}/{name}").read()
    code, n = re.subn(pattern, lambda m: m.group(1) + line, code, 1)
    if n != 1 or imp not in code:
        sys.exit(f"examples/pocketone/{name} changed: can't find where to add wasm.New")
    code = code.replace(imp, imp + '\t"github.com/pockethost/pocketone/ext/wasm"\n', 1)
    open(f"{dst}/{name}", "w").write(code)
mod = json.loads(subprocess.check_output(["go", "mod", "edit", "-json"], cwd=dst))
edits = [f"-replace={r['Old']['Path']}={os.path.normpath(os.path.join(src, r['New']['Path']))}"
         for r in mod.get("Replace") or [] if r["New"]["Path"].startswith(".")]
edits.append(f"-replace=github.com/pockethost/pocketone/ext/wasm={os.path.normpath(os.path.join(src, '../../ext/wasm'))}")
subprocess.check_call(["go", "mod", "edit", *edits], cwd=dst)
PY
(cd build/pocketone && go mod tidy && go build -ldflags "-X ganigeorgiev.com/pocketbase/pocketbase.Version=wasm-lab" -o "$LAB/bin/pocketone" .)
echo "bin/pocketone"

step "2. plugins -> plugins/"
rm -rf plugins
build_go() { # name, source folder, [build tags], [library]
  mkdir -p "plugins/$1"
  local args=(-tags="${3:-}")
  [[ -n "${4:-}" ]] && args+=(-buildmode=c-shared)
  (cd "$2" && GOOS=wasip1 GOARCH=wasm go build "${args[@]}" -o "$LAB/plugins/$1/plugin.wasm" .)
  [[ -f "$2/plugin.json" ]] && cp "$2/plugin.json" "plugins/$1/"
  echo "plugins/$1 ($(du -h "plugins/$1/plugin.wasm" | cut -f1))"
}
build_go summary "$WASM/example/summary"
build_go edifact-orders-go src/edifact
build_go crypto "$WASM/example/crypto"
build_go fat_evil "$WASM/testdata/evil"                  # evil in Go, ~11 MB: over MaxModulesMB, refused when it loads
build_go phone "$WASM/testdata/imports" extism             # an Extism plugin: refused when it loads
build_go library "$WASM/example/summary" "" c-shared       # summary built as a library, the usual mistake: refused
rm -f plugins/library/plugin.json
build_rust() { # name, crate folder, the crate's .wasm name
  (cd "$2" && cargo build -q --release --target wasm32-wasip1)
  mkdir -p "plugins/$1"
  cp "$2/target/wasm32-wasip1/release/$3.wasm" "plugins/$1/plugin.wasm"
  cp "$2/plugin.json" "plugins/$1/"
  echo "plugins/$1 ($(du -h "plugins/$1/plugin.wasm" | cut -f1))"
}
if command -v cargo >/dev/null && rustup target list --installed 2>/dev/null | grep -q wasm32-wasip1; then
  build_rust summary-rust "$WASM/example/summary-rust" summary
  build_rust edifact-orders-rust "$WASM/example/edifact-orders-rust" orders           # EDIFACT ORDERS -> order JSON (edifact-rs)
  build_rust order-xml "$WASM/example/order-xml" order-xml   # XML order -> the same JSON (roxmltree)
  build_rust devil "$WASM/example/devil" devil               # tries files, env, a command, attacker.example: all refused
  build_rust evil src/evil evil                  # tries files, env, args, TCP, HTTP, a port: all refused
  build_rust memhog "$WASM/example/memhog" memhog            # asks for more memory than MaxCallMemoryMB allows
  build_rust waflows "$WASM/example/waflows" waflows         # what pb_hooks lacks for WhatsApp Flows: RSA-OAEP, AES-GCM
else echo "no cargo or no wasm32-wasip1 target (rustup target add wasm32-wasip1): skipping the Rust plugins"; fi
ZIG="$(command -v zig || ls "$HOME"/.local/zig-*/zig 2>/dev/null | tail -1 || true)"
if [[ -n "$ZIG" ]]; then
  (cd "$WASM/example/summary-zig" && "$ZIG" build -Doptimize=ReleaseSmall)
  mkdir -p plugins/summary-zig
  cp "$WASM/example/summary-zig/zig-out/bin/summary.wasm" plugins/summary-zig/plugin.wasm
  cp "$WASM/example/summary-zig/plugin.json" plugins/summary-zig/
  echo "plugins/summary-zig ($(du -h plugins/summary-zig/plugin.wasm | cut -f1))"
else echo "no zig: skipping summary-zig"; fi

head -c 1000 plugins/summary/plugin.wasm > extras/broken.wasm   # not valid WebAssembly: refused when it loads

step "3. a fresh instance (summary and edifact-orders-go in pb_wasm/)"
./reset.sh

