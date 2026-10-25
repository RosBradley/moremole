// Command moremole-models-go looks at Ollama models for moremole's AI models
// screens. bin/moremole-models.sh shows the lists and runs `ollama pull` and
// `ollama rm`; this program only looks.
//
//	moremole-models-go status          Ollama's app, command, service and the Mac's memory
//	moremole-models-go list [--check]  installed models; --check asks the registry about each
//	moremole-models-go library         the models on ollama.com/library
//	moremole-models-go size NAME...    download size of each model, from the registry
//
// status prints key=value lines. The others print one row per item, fields
// separated by the ASCII unit separator (0x1f) so empty fields survive a
// shell read:
//
//	list:     model  name  size  modified  status  loaded
//	library:  model  name  capabilities  pulls  updated  installed  description
//	size:     size   name  bytes
//	notice:   notice key   text
//
// status in list is update, current, local (the registry has no such model:
// made on this Mac or removed upstream) or unknown (could not check); it is
// empty without --check. loaded is 1 for a model in memory now. Times are
// Unix seconds; sizes are bytes, 0 when unknown.
package main

import (
	"fmt"
	"io"
	"os"
	"strings"
)

const fieldSeparator = "\x1f"

// row joins fields for the shell script, keeping each on one line.
func row(fields ...string) string {
	for i, f := range fields {
		fields[i] = strings.Map(func(c rune) rune {
			if c == '\t' || c == '\n' || c == '\r' || c == 0x1f {
				return ' '
			}
			return c
		}, f)
	}
	return strings.Join(fields, fieldSeparator)
}

func notice(key, text string) string { return row("notice", key, text) }

func usage(w io.Writer) {
	_, _ = fmt.Fprintln(w, "Usage: moremole-models-go status|list [--check]|library|size NAME...")
}

func main() {
	if len(os.Args) < 2 {
		usage(os.Stderr)
		os.Exit(2)
	}
	var lines []string
	switch os.Args[1] {
	case "status":
		lines = statusLines(findOllama(), newService().running(), memoryBytes())
	case "list":
		check := len(os.Args) > 2 && os.Args[2] == "--check"
		lines = listLines(newService(), check, fetchManifest)
	case "library":
		lines = libraryLines(fetchLibrary, newService())
	case "size":
		lines = sizeLines(os.Args[2:], fetchManifest)
	case "-h", "--help":
		usage(os.Stdout)
		return
	default:
		usage(os.Stderr)
		os.Exit(2)
	}
	for _, l := range lines {
		fmt.Println(l)
	}
}
