// Command summary is the summary module built as a reactor (a library), for bench's stateful variant (D): wazero
// instantiates it once and calls its exported functions many times, so its memory, and calls, live between calls.
//
//	alloc(size) -> ptr           a buffer of size bytes in the module's memory, for the input
//	run(ptr, len) -> ptr<<32|len  {"title","body"} in, {"text","words","calls"} out
//
// Build: GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o ../../reactors/summary-go.wasm .
package main

import (
	"encoding/json"
	"strings"
	"unsafe"
)

func main() {} // required, never run in a reactor

var (
	in, out []byte // kept in globals: the GC doesn't free them while the host uses their addresses
	calls   int    // the state: survives between calls because the instance does
)

//go:wasmexport alloc
func alloc(size uint32) uint32 {
	in = make([]byte, size)
	return ptr(in)
}

//go:wasmexport run
func run(p, n uint32) uint64 {
	calls++
	var post struct {
		Title string `json:"title"`
		Body  string `json:"body"`
	}
	var res any
	if err := json.Unmarshal(in[:n], &post); err != nil {
		res = map[string]string{"code": "bad_input", "message": err.Error()}
	} else {
		words := strings.Fields(post.Body)
		short := strings.Join(words[:min(len(words), 12)], " ")
		if len(words) > 12 {
			short += " …"
		}
		text := short
		if post.Title != "" {
			text = post.Title + ": " + short
		}
		res = map[string]any{"text": text, "words": len(words), "calls": calls}
	}
	out, _ = json.Marshal(res)
	return uint64(ptr(out))<<32 | uint64(len(out))
}

func ptr(b []byte) uint32 {
	if len(b) == 0 {
		return 0
	}
	return uint32(uintptr(unsafe.Pointer(&b[0])))
}
