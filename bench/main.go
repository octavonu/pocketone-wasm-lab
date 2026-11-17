// Command bench measures what a compilation cache would save for ext/wasm: the same module (summary, in Go, Rust and
// Zig) called three ways, with wazero's compiler.
//
//   - cold: compile the .wasm to native code, then call it (what ext/wasm does today on every call)
//   - disk: read the native code back from wazero's on-disk cache, then call it
//   - RAM:  call a module that's already compiled in memory
//
// Then the stateful variant (D): the same summary built as a reactor (reactor/, a library with exported functions),
// instantiated once and kept, with every call going into the same instance. Its counter of calls must go 1, 2, 3...
//
// Run it with:
//
//	go run github.com/octavonu/pocketone-wasm-lab/bench@latest
//
// Nothing is left behind: the disk cache goes to a temporary folder, removed at the end.
package main

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"slices"
	"strings"
	"time"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"
)

//go:embed modules/*.wasm
var modules embed.FS

//go:embed reactors/*.wasm
var reactors embed.FS

// statefulCalls is how many calls go into the kept instance of variant D.
const statefulCalls = 100

const (
	input = `{"title": "Hello", "body": "one two three"}`
	want  = `{"text":"Hello: one two three","words":3}`
)

func main() {
	rounds := flag.Int("n", 5, "rounds per measurement; the median is shown")
	flag.Parse()
	ctx := context.Background()

	tmp, err := os.MkdirTemp("", "wasm-bench-")
	check(err)
	defer os.RemoveAll(tmp)

	fmt.Printf("%s/%s, %d CPUs, %s, wazero %s, median of %d\n\n", runtime.GOOS, runtime.GOARCH, runtime.NumCPU(),
		runtime.Version(), wazeroVersion(), *rounds)
	fmt.Printf("%-14s %9s %11s %9s %9s %9s\n", "module", ".wasm", "native", "cold", "disk", "RAM")

	names, err := fs.Glob(modules, "modules/*.wasm")
	check(err)
	for _, path := range names {
		code, err := modules.ReadFile(path)
		check(err)
		name := strings.TrimSuffix(filepath.Base(path), ".wasm")
		dir := filepath.Join(tmp, name)

		var cold, disk, ram []time.Duration
		for i := 0; i < *rounds; i++ {
			check(os.RemoveAll(dir)) // empty cache: wazero must compile
			cold = append(cold, compileAndCall(ctx, code, dir))
		}
		for i := 0; i < *rounds; i++ {
			disk = append(disk, compileAndCall(ctx, code, dir)) // the native code is in dir now
		}
		ram = callInRAM(ctx, code, *rounds)

		fmt.Printf("%-14s %9s %11s %9s %9s %9s\n", name, mb(int64(len(code))), mb(dirSize(dir)),
			ms(median(cold)), ms(median(disk)), ms(median(ram)))
	}
	fmt.Println("\ncold = compile + call, disk = load native code from disk + call, RAM = call only")

	fmt.Printf("\nstateful (D): one instance kept, %d calls into it\n\n", statefulCalls)
	fmt.Printf("%-14s %9s %9s %9s %13s %9s\n", "module", ".wasm", "start", "call", "memory held", "counter")
	names, err = fs.Glob(reactors, "reactors/*.wasm")
	check(err)
	for _, path := range names {
		code, err := reactors.ReadFile(path)
		check(err)
		start, calls, mem := stateful(ctx, code)
		fmt.Printf("%-14s %9s %9s %9s %13s %9s\n", strings.TrimSuffix(filepath.Base(path), ".wasm"),
			mb(int64(len(code))), ms(start), ms(median(calls)), mb(int64(mem)), fmt.Sprintf("1..%d", statefulCalls))
	}
	fmt.Println("\nstart = instantiate once (the language runtime starts), call = one call into the kept instance,")
	fmt.Println("memory held = the instance's memory, kept between calls; compiling is the same as cold above")
}

// stateful instantiates a reactor once, then calls it statefulCalls times; each answer must count its call.
func stateful(ctx context.Context, code []byte) (start time.Duration, calls []time.Duration, mem uint32) {
	rt := newRuntime(ctx, nil)
	defer rt.Close(ctx)
	compiled, err := rt.CompileModule(ctx, code)
	check(err)

	t := time.Now()
	mod, err := rt.InstantiateModule(ctx, compiled, wazero.NewModuleConfig().WithName("").
		WithStartFunctions("_initialize")) // a reactor: initialize, then stay alive (no _start, no exit)
	check(err)
	start = time.Since(t)
	alloc, run := mod.ExportedFunction("alloc"), mod.ExportedFunction("run")
	if alloc == nil || run == nil {
		fail("reactor: alloc and run must be exported")
	}

	for i := 1; i <= statefulCalls; i++ {
		t := time.Now()
		r, err := alloc.Call(ctx, uint64(len(input)))
		check(err)
		if !mod.Memory().Write(uint32(r[0]), []byte(input)) { // the input goes into the instance's own memory
			fail("reactor: input out of memory range")
		}
		r, err = run.Call(ctx, r[0], uint64(len(input)))
		check(err)
		out, ok := mod.Memory().Read(uint32(r[0]>>32), uint32(r[0]))
		if !ok {
			fail("reactor: output out of memory range")
		}
		got := string(out) // copied out before the next call reuses the buffer
		calls = append(calls, time.Since(t))

		var res struct {
			Text  string `json:"text"`
			Words int    `json:"words"`
			Calls int    `json:"calls"`
		}
		check(json.Unmarshal([]byte(got), &res))
		if res.Text != "Hello: one two three" || res.Words != 3 || res.Calls != i {
			fail("reactor: call %d got %s", i, got)
		}
	}
	return start, calls, mod.Memory().Size()
}

// compileAndCall is one call in a fresh runtime with the disk cache in dir: compile (or load from dir), then call.
func compileAndCall(ctx context.Context, code []byte, dir string) time.Duration {
	cache, err := wazero.NewCompilationCacheWithDir(dir)
	check(err)
	defer cache.Close(ctx)
	rt := newRuntime(ctx, cache)
	defer rt.Close(ctx)

	start := time.Now()
	mod, err := rt.CompileModule(ctx, code)
	check(err)
	call(ctx, rt, mod)
	return time.Since(start)
}

// callInRAM compiles once, then times calls to the module already in memory.
func callInRAM(ctx context.Context, code []byte, rounds int) []time.Duration {
	rt := newRuntime(ctx, nil)
	defer rt.Close(ctx)
	mod, err := rt.CompileModule(ctx, code)
	check(err)
	call(ctx, rt, mod) // warm up
	var ds []time.Duration
	for i := 0; i < rounds; i++ {
		start := time.Now()
		call(ctx, rt, mod)
		ds = append(ds, time.Since(start))
	}
	return ds
}

func newRuntime(ctx context.Context, cache wazero.CompilationCache) wazero.Runtime {
	cfg := wazero.NewRuntimeConfigCompiler()
	if cache != nil {
		cfg = cfg.WithCompilationCache(cache)
	}
	rt := wazero.NewRuntimeWithConfig(ctx, cfg)
	wasi_snapshot_preview1.MustInstantiate(ctx, rt)
	return rt
}

// call runs the module once as `summary run`, input on stdin, in a fresh instance, as ext/wasm does.
func call(ctx context.Context, rt wazero.Runtime, mod wazero.CompiledModule) {
	var stdout, stderr bytes.Buffer
	inst, err := rt.InstantiateModule(ctx, mod, wazero.NewModuleConfig().WithName("").
		WithArgs("summary", "run").WithStdin(strings.NewReader(input)).WithStdout(&stdout).WithStderr(&stderr))
	if inst != nil {
		inst.Close(ctx)
	}
	if err != nil {
		fail("call: %v: %s", err, stderr.String())
	}
	if got := strings.TrimSpace(stdout.String()); got != want {
		fail("call: got %s, want %s", got, want)
	}
}

func dirSize(dir string) int64 {
	var n int64
	filepath.WalkDir(dir, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if info, err := d.Info(); err == nil {
				n += info.Size()
			}
		}
		return nil
	})
	return n
}

func wazeroVersion() string {
	if bi, ok := debug.ReadBuildInfo(); ok {
		for _, d := range bi.Deps {
			if d.Path == "github.com/tetratelabs/wazero" {
				return d.Version
			}
		}
	}
	return "?"
}

func median(ds []time.Duration) time.Duration {
	s := slices.Clone(ds)
	slices.Sort(s)
	return s[len(s)/2]
}

func ms(d time.Duration) string {
	if d >= time.Second {
		return fmt.Sprintf("%.2f s", d.Seconds())
	}
	if d < time.Millisecond {
		return fmt.Sprintf("%d µs", d.Microseconds())
	}
	return fmt.Sprintf("%.1f ms", float64(d.Microseconds())/1000)
}

func mb(n int64) string { return fmt.Sprintf("%.2f MB", float64(n)/(1<<20)) }

func check(err error) {
	if err != nil {
		fail("%v", err)
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "bench: "+format+"\n", args...)
	os.Exit(1)
}
