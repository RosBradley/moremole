// Command moremole-view-go shows what a command printed, after it finished,
// on a screen of its own: the menu records the command's terminal output
// with script(1), and this program replays the recording and lets the user
// scroll it like the main menu. With --file it also offers that file (Clean's
// list of files) on F.
//
//	moremole-view-go --title TITLE --rows N --cols N [--file PATH] RECORDING
//
// --print writes the replayed lines instead, for checking a recording.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// readFileLines reads the file offered on F; a missing or unreadable file
// leaves the key out.
func readFileLines(path string) ([]string, bool) {
	f, err := os.Open(path)
	if err != nil {
		return nil, false
	}
	defer func() { _ = f.Close() }()
	var lines []string
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	return lines, scanner.Err() == nil
}

func replay(r io.Reader, cols, rows int) ([]string, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	term := newTerminal(cols, rows)
	term.write(stripBanners(data))
	return term.Lines(), nil
}

func run(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("moremole-view-go", flag.ContinueOnError)
	flags.SetOutput(stderr)
	title := flags.String("title", "Results", "title shown at the top")
	rows := flags.Int("rows", 24, "terminal rows the command ran in")
	cols := flags.Int("cols", 80, "terminal columns the command ran in")
	file := flags.String("file", "", "a file to offer on F")
	printOnly := flags.Bool("print", false, "print the replayed lines instead of showing them")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if flags.NArg() != 1 {
		_, _ = fmt.Fprintln(stderr, "Usage: moremole-view-go --title TITLE --rows N --cols N [--file PATH] RECORDING")
		return 2
	}
	f, err := os.Open(flags.Arg(0))
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	output, err := replay(f, *cols, *rows)
	_ = f.Close()
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	if *printOnly {
		for _, line := range output {
			_, _ = fmt.Fprintln(stdout, line)
		}
		return 0
	}
	filePath := *file
	fileLines, ok := readFileLines(filePath)
	if !ok {
		filePath = ""
	}
	m := newModel(strings.TrimSpace(*title), output, filePath, fileLines, *cols, *rows)
	if _, err := show(m); err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

// show runs the screen until the user leaves it; tests pass their own input
// and output.
func show(m model, opts ...tea.ProgramOption) (model, error) {
	final, err := tea.NewProgram(m, append([]tea.ProgramOption{tea.WithAltScreen()}, opts...)...).Run()
	if done, ok := final.(model); ok {
		m = done
	}
	return m, err
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
