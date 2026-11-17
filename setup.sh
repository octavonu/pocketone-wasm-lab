#!/usr/bin/env bash
# Builds the WASM lab from scratch: PocketOne (its examples/pocketone, the stock binary) with ext/wasm in the standard
# set, the modules (WASI programs: summary in Go, Rust and Zig, edifact-orders-go,
# crypto, edifact-orders-rust, order-xml, devil, evil, memhog and waflows, and three that must be refused: phone,
# library and fat_evil), and a fresh instance here (pb_data/, pb_hooks/<name>.pb.wasm) with the lab collections and a
# superuser. Everything stays in this folder.
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

step "2. modules -> modules/"
rm -rf modules
build_go() { # name, source folder, [build tags], [library]
  mkdir -p "modules/$1"
  local args=(-tags="${3:-}")
  [[ -n "${4:-}" ]] && args+=(-buildmode=c-shared)
  (cd "$2" && GOOS=wasip1 GOARCH=wasm go build "${args[@]}" -o "$LAB/modules/$1/module.wasm" .)
  echo "modules/$1 ($(du -h "modules/$1/module.wasm" | cut -f1))"
}
build_go summary "$WASM/example/summary"
build_go edifact-orders-go src/edifact
build_go crypto "$WASM/example/crypto"
build_go fat_evil "$WASM/testdata/evil"                  # evil in Go, ~11 MB: over MaxModulesMB, refused when it loads
build_go phone "$WASM/testdata/imports" extism             # an Extism plugin: refused when it loads
build_go library "$WASM/example/summary" "" c-shared       # summary built as a library, the usual mistake: refused
# The Rust and Zig modules come built: ext/wasm keeps its examples built beside their sources
# (example/<folder>/<name>.pb.wasm; its tests check they're what the sources build), and this lab keeps evil's
# (src/evil/evil.pb.wasm). So the lab needs only Go. BUILD_WASM=1 ./setup.sh builds them from source instead (Rust
# with the wasm32-wasip1 target, Zig 0.14).
take() { # name, .wasm file
  mkdir -p "modules/$1"
  cp "$2" "modules/$1/module.wasm"
  echo "modules/$1 ($(du -h "modules/$1/module.wasm" | cut -f1))"
}
build_rust() { # name, crate folder, the crate's .wasm name. Paths remapped as ext/wasm's tests do: the module holds
  # none of this machine's, and comes out the same as the one kept
  local sysroot commit
  sysroot="$(rustc --print sysroot)" commit="$(rustc -vV | sed -n 's/^commit-hash: //p')"
  (cd "$2" && CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=$sysroot/lib/rustlib/src/rust=/rustc/$commit"$'\x1f'"--remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}/registry/src=/cargo" \
    cargo build -q --release --locked --target wasm32-wasip1)
  take "$1" "$2/target/wasm32-wasip1/release/$3.wasm"
}
E="$WASM/example"
if [[ "${BUILD_WASM:-}" == 1 ]]; then
  command -v cargo >/dev/null || { echo "BUILD_WASM=1 needs Rust (and: rustup target add wasm32-wasip1)" >&2; exit 1; }
  ZIG="$(command -v zig || ls "$HOME"/.local/zig-*/zig 2>/dev/null | tail -1 || true)"
  [[ -n "$ZIG" ]] || { echo "BUILD_WASM=1 needs Zig 0.14" >&2; exit 1; }
  build_rust summary-rust "$E/summary-rust" summary
  build_rust edifact-orders-rust "$E/edifact-orders-rust" orders
  build_rust order-xml "$E/order-xml" order-xml
  build_rust devil "$E/devil" devil
  build_rust evil src/evil evil
  build_rust memhog "$E/memhog" memhog
  build_rust waflows "$E/waflows" waflows
  (cd "$E/summary-zig" && "$ZIG" build -Doptimize=ReleaseSmall)
  take summary-zig "$E/summary-zig/zig-out/bin/summary.wasm"
else
  take summary-rust "$E/summary-rust/summary.pb.wasm"
  take edifact-orders-rust "$E/edifact-orders-rust/edifact-orders-rust.pb.wasm"   # EDIFACT ORDERS -> order JSON (edifact-rs)
  take order-xml "$E/order-xml/order-xml.pb.wasm"       # XML order -> the same JSON (roxmltree)
  take devil "$E/devil/devil.pb.wasm"                   # tries files, env, a command, attacker.example: all refused
  take evil src/evil/evil.pb.wasm                       # tries files, env, args, TCP, HTTP, a port: all refused
  take memhog "$E/memhog/memhog.pb.wasm"                # asks for more memory than MaxCallMemoryMB allows
  take waflows "$E/waflows/waflows.pb.wasm"             # what pb_hooks lacks for WhatsApp Flows: RSA-OAEP, AES-GCM
  take summary-zig "$E/summary-zig/summary.pb.wasm"
fi

head -c 1000 modules/summary/module.wasm > extras/broken.wasm   # not valid WebAssembly: refused when it loads

step "3. a fresh instance (summary and edifact-orders-go in pb_hooks/)"
./reset.sh

