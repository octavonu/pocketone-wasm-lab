#!/usr/bin/env bash
# Rebuilds bench's reactor modules (variant D) from reactor/: Go needs 1.24+, Rust the wasm32-wasip1 target.
set -euo pipefail
cd "$(dirname "$0")"
(cd reactor/go && GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o ../../reactors/summary-go.wasm .)
(cd reactor/rust && cargo build -q --release --target wasm32-wasip1)
cp reactor/rust/target/wasm32-wasip1/release/summary_reactor.wasm reactors/summary-rust.wasm
ls -l reactors
