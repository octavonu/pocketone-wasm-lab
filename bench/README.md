# bench

How much a compilation cache would save for `ext/wasm`. The same module, `summary`, built in Go, Rust and Zig, called
three ways with wazero's compiler:

- **cold:** compile the `.wasm` to native code, then call it. This is what `ext/wasm` does today, on every call.
- **disk:** load the native code from wazero's on-disk cache (`NewCompilationCacheWithDir`), then call it.
- **RAM:** call a module that's already compiled in memory.

Every call runs in a fresh instance, the way `ext/wasm` runs one, and checks the module's answer.

Then a fourth, **stateful (D)**: the same `summary` built as a reactor (a library with exported functions, sources in
`reactor/`), instantiated once and kept; every call goes into that same instance, so its memory survives between
calls. Each answer carries a counter of calls, which must go 1, 2, 3... `./build-reactors.sh` rebuilds them.

## Run

```
go run github.com/octavonu/pocketone-wasm-lab/bench@latest
```

`-n 10` changes the rounds per measurement (default 5; the median is shown). The disk cache goes to a temporary
folder, removed at the end. The modules are embedded, so nothing else is needed.

## Output

```
darwin/amd64, 16 CPUs, go1.27.4, wazero v1.12.0, median of 5

module             .wasm      native      cold      disk       RAM
summary-go       4.32 MB    17.24 MB    1.91 s   79.0 ms    4.3 ms
summary-rust     0.09 MB     0.35 MB   65.3 ms    3.2 ms    271 µs
summary-zig      0.05 MB     0.18 MB   47.8 ms    2.2 ms    562 µs

cold = compile + call, disk = load native code from disk + call, RAM = call only

stateful (D): one instance kept, 100 calls into it

module             .wasm     start      call   memory held   counter
summary-go       4.27 MB    4.8 ms     60 µs       3.50 MB    1..100
summary-rust     0.09 MB    167 µs      2 µs       1.06 MB    1..100

start = instantiate once (the language runtime starts), call = one call into the kept instance,
memory held = the instance's memory, kept between calls; compiling is the same as cold above
```

`native` is the size of the native code wazero wrote to disk; a compiled module takes about as much RAM. In D,
`memory held` comes on top of that, for every instance kept.

## License

MIT, like the rest of this repository.
