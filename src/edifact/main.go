// Command edifact is a lab plugin: an EDIFACT message (raw text on stdin, as the hook got it) parsed into JSON.
//
//	stdin:  UNA:+.? 'UNB+UNOA:2+SENDER+RECEIVER+261114:1200+1'UNH+1+ORDERS:D:96A:UN'...
//	stdout: {"type": "ORDERS", "count": 7, "segments": [{"tag": "UNB", "elements": [["UNOA", "2"], ["SENDER"], ...]}, ...]}
//
// Elements are split on +, components on :, segments on ', with ? as the release character; an UNA segment
// changes them. Build: GOOS=wasip1 GOARCH=wasm go build -o edifact.wasm .
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
)

type segment struct {
	Tag      string     `json:"tag"`
	Elements [][]string `json:"elements"`
}

func main() {
	in, _ := io.ReadAll(os.Stdin)
	text := strings.TrimSpace(string(in))
	if text == "" {
		fail("empty", "no EDIFACT message in the input")
	}
	comp, elem, release, term := byte(':'), byte('+'), byte('?'), byte('\'')
	if strings.HasPrefix(text, "UNA") {
		if len(text) < 9 {
			fail("bad_una", "the UNA segment is cut short")
		}
		comp, elem, release, term = text[3], text[4], text[6], text[8]
		text = text[9:]
	}

	var segs []segment
	var cur []string   // the components of the element being read
	var els [][]string // the elements of the segment being read
	var b strings.Builder
	endComponent := func() { cur = append(cur, b.String()); b.Reset() }
	endElement := func() { endComponent(); els = append(els, cur); cur = nil }
	for i := 0; i < len(text); i++ {
		switch c := text[i]; {
		case c == release && i+1 < len(text):
			i++
			b.WriteByte(text[i])
		case c == comp:
			endComponent()
		case c == elem:
			endElement()
		case c == term:
			endElement()
			tag := strings.TrimSpace(els[0][0])
			segs = append(segs, segment{Tag: tag, Elements: els[1:]})
			els = nil
		case c == '\r' || c == '\n':
		default:
			b.WriteByte(c)
		}
	}
	if b.Len() > 0 || len(els) > 0 {
		fail("unterminated", fmt.Sprintf("the last segment doesn't end with the segment terminator %c", term))
	}

	typ := ""
	for _, s := range segs {
		if s.Tag == "UNH" && len(s.Elements) > 1 {
			typ = s.Elements[1][0]
			break
		}
	}
	if typ == "" {
		fail("no_message", "no UNH segment: not an EDIFACT message")
	}
	json.NewEncoder(os.Stdout).Encode(map[string]any{"type": typ, "count": len(segs), "segments": segs})
}

func fail(code, message string) {
	b, _ := json.Marshal(map[string]string{"code": code, "message": message})
	os.Stderr.Write(b)
	os.Exit(1)
}
