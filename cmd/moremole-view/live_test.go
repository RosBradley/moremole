//go:build darwin || linux

package main

import (
	"bytes"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/charmbracelet/x/ansi"
)

// lockedBuffer collects what the pane draws while it runs.
type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lockedBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

func runPane(t *testing.T, keys []string, argv ...string) ([]string, int, string) {
	t.Helper()
	if _, _, err := openPTY(); err != nil {
		t.Skipf("no pseudo-terminals here: %v", err)
	}
	in, typing, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = in.Close() }()
	go func() {
		for _, k := range keys {
			time.Sleep(300 * time.Millisecond)
			_, _ = typing.WriteString(k)
		}
		time.Sleep(300 * time.Millisecond)
		_ = typing.Close()
	}()
	var out lockedBuffer
	p := &pane{title: "Clean · Preview", note: "$ example", in: in, out: &out,
		size: func() (int, int, bool) { return 40, 8, true }}
	done := make(chan struct{})
	var lines []string
	var code int
	go func() {
		defer close(done)
		lines, code, err = p.run(argv)
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatalf("the pane did not finish; drawn so far: %q", ansi.Strip(out.String()))
	}
	if err != nil {
		t.Fatal(err)
	}
	for i := range lines {
		lines[i] = ansi.Strip(lines[i])
	}
	return lines, code, ansi.Strip(out.String())
}

func TestPaneShowsOutputInsideTheFrameAndPassesKeys(t *testing.T) {
	script := `for i in 1 2 3 4 5 6 7 8 9; do echo "line $i"; done; printf 'Name? '; read name; echo "hello $name"; exit 3`
	lines, code, drawn := runPane(t, []string{"Brad\r"}, "/bin/sh", "-c", script)
	if code != 3 {
		t.Errorf("exit status %d, want 3", code)
	}
	// Everything the command printed is kept, history included.
	got := strings.Join(lines, "\n")
	for _, want := range []string{"$ example", "line 1", "line 9", "Name? Brad", "hello Brad"} {
		if !strings.Contains(got, want) {
			t.Errorf("output lacks %q:\n%s", want, got)
		}
	}
	// The title row and the key row frame the command's screen.
	for _, want := range []string{"Clean · Preview", "Running", "Ctrl-C Stop", "hello Brad"} {
		if !strings.Contains(drawn, want) {
			t.Errorf("screen lacks %q: %q", want, drawn)
		}
	}
}

func TestPaneCtrlCStopsTheCommand(t *testing.T) {
	start := time.Now()
	_, code, _ := runPane(t, []string{"\x03"}, "/bin/sh", "-c", "echo started; sleep 30")
	if time.Since(start) > 5*time.Second {
		t.Fatal("Ctrl-C did not stop the command")
	}
	if code == 0 {
		t.Errorf("exit status 0 after Ctrl-C")
	}
}

func TestPaneKeepsTheSummaryAndKeysAtTheTop(t *testing.T) {
	p := &pane{title: "Clean · Preview", labels: []string{"Potential space", "Items", "Categories"}}
	if got := p.rowsFor(24); got != 24-4 {
		t.Fatalf("command rows %d, want 20 (title, summary, keys and divider above)", got)
	}
	top := p.top(70)
	want := []string{
		"Clean · Preview",
		"Potential space: ⠖ | Items: ⠖ | Categories: ⠖",
		liveKeys,
		strings.Repeat("─", 70),
	}
	for i, w := range want {
		if got := strings.TrimRight(ansi.Strip(top[i]), " "); !strings.HasPrefix(got, w) {
			t.Errorf("row %d = %q, want %q", i, got, w)
		}
	}
	if !strings.HasSuffix(ansi.Strip(top[0]), "⠖ Running") {
		t.Errorf("title row %q", ansi.Strip(top[0]))
	}
	// The spinner turns.
	p.ticks += spinEvery
	if got := ansi.Strip(p.top(70)[1]); !strings.Contains(got, "⠲") {
		t.Errorf("spinner did not turn: %q", got)
	}
	// Without labels there is no summary row.
	if got := (&pane{title: "History"}).rowsFor(24); got != 21 {
		t.Errorf("command rows without a summary: %d", got)
	}
}

func TestPaneDrawsOnlyRowsThatChanged(t *testing.T) {
	var out bytes.Buffer
	p := &pane{title: "T", out: &out, term: newTerminal(20, 4)}
	p.draw()
	first := out.Len()
	out.Reset()
	p.draw()
	if out.Len() >= first || strings.Contains(out.String(), "T") {
		t.Errorf("an unchanged frame was drawn again: %q", out.String())
	}
	p.term.write([]byte("new\r\n"))
	out.Reset()
	p.draw()
	// The command's first row sits under the title, the keys and the divider.
	if !strings.Contains(out.String(), "\x1b[4;1H") || !strings.Contains(out.String(), "new") {
		t.Errorf("the changed row was not drawn: %q", out.String())
	}
}
