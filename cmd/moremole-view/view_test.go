package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

func numbered(n int) []string {
	out := make([]string, n)
	for i := range out {
		out[i] = fmt.Sprintf("line %d", i+1)
	}
	return out
}

func press(m model, keys ...string) model {
	for _, k := range keys {
		var msg tea.KeyMsg
		switch k {
		case "up", "down", "pgup", "pgdown", "home", "end", "enter", "esc", "ctrl+c":
			msg = tea.KeyMsg{Type: map[string]tea.KeyType{
				"up": tea.KeyUp, "down": tea.KeyDown, "pgup": tea.KeyPgUp, "pgdown": tea.KeyPgDown,
				"home": tea.KeyHome, "end": tea.KeyEnd, "enter": tea.KeyEnter, "esc": tea.KeyEsc, "ctrl+c": tea.KeyCtrlC,
			}[k]}
		default:
			msg = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(k)}
		}
		next, _ := m.Update(msg)
		m = next.(model)
	}
	return m
}

func quits(m model, key string) bool {
	msg := tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(key)}
	if key == "enter" {
		msg = tea.KeyMsg{Type: tea.KeyEnter}
	}
	_, cmd := m.Update(msg)
	if cmd == nil {
		return false
	}
	_, ok := cmd().(tea.QuitMsg)
	return ok
}

func TestViewOpensAtTheEndAndScrolls(t *testing.T) {
	m := newModel("Clean · Preview", numbered(100), "", nil, 40, 12)
	// 12 rows: the title, the keys and a divider at the top, then 9 lines.
	if m.offset[outputPage] != 91 {
		t.Fatalf("starts at %d, want the last page (91)", m.offset[outputPage])
	}
	view := ansi.Strip(m.View())
	rows := strings.Split(view, "\n")
	if len(rows) != 12 || !strings.HasPrefix(rows[0], "Clean · Preview") || !strings.HasSuffix(rows[0], "92-100 of 100") {
		t.Fatalf("view rows %d, title %q", len(rows), rows[0])
	}
	if !strings.HasPrefix(rows[1], "↑↓ Scroll") || rows[2] != strings.Repeat("─", 40) {
		t.Errorf("keys %q, divider %q", rows[1], rows[2])
	}
	if rows[3] != "line 92" || rows[11] != "line 100" {
		t.Errorf("body %q .. %q", rows[3], rows[11])
	}
	m = press(m, "up", "up", "pgup")
	if m.offset[outputPage] != 80 {
		t.Errorf("after up, up, pgup: %d", m.offset[outputPage])
	}
	m = press(m, "home", "up")
	if m.offset[outputPage] != 0 {
		t.Errorf("home then up: %d", m.offset[outputPage])
	}
	m = press(m, "end", "down", "pgdown")
	if m.offset[outputPage] != 91 {
		t.Errorf("end, down, pgdown: %d", m.offset[outputPage])
	}
}

func TestViewShortOutputHasNoPosition(t *testing.T) {
	m := newModel("Touch ID", []string{"Touch ID is not configured"}, "", nil, 40, 12)
	view := ansi.Strip(m.View())
	if strings.Contains(view, " of ") || !strings.Contains(view, "Touch ID is not configured") {
		t.Errorf("view %q", view)
	}
	if strings.Contains(view, "File list") {
		t.Error("F offered without a file")
	}
}

func TestViewFileListOnF(t *testing.T) {
	long := "/Users/me/Library/Caches/" + strings.Repeat("a", 50) + "/file.cache"
	m := newModel("Clean · Preview", numbered(5), "/tmp/clean-list.txt", []string{"# Clean list", long}, 40, 12)
	if !strings.Contains(ansi.Strip(m.View()), "F File list") {
		t.Fatal("F not offered")
	}
	m = press(m, "F")
	if m.page != filePage {
		t.Fatal("F did not open the file list")
	}
	view := ansi.Strip(m.View())
	if !strings.HasPrefix(view, "File list: /tmp/clean-list.txt") || !strings.Contains(view, "Q Back to results") {
		t.Errorf("file view %q", view)
	}
	// The long path wraps instead of being cut.
	if !strings.Contains(strings.ReplaceAll(view, "\n", ""), long) {
		t.Errorf("path not shown whole: %q", view)
	}
	if quits(m, "q") {
		t.Fatal("Q on the file list left the screen")
	}
	m = press(m, "q")
	if m.page != outputPage {
		t.Fatal("Q on the file list did not go back to the results")
	}
	if !quits(m, "q") || !quits(m, "enter") {
		t.Error("Q or Enter on the results does not go back to the menu")
	}
}

func TestKeysDropHintsBeforeTheBackKey(t *testing.T) {
	m := newModel("Clean", numbered(3), "/tmp/x", []string{"x"}, 120, 12)
	if k := m.keys(120); !strings.Contains(k, "Home End") || !strings.Contains(k, "PgUp PgDn") {
		t.Errorf("wide keys %q", k)
	}
	k := m.keys(50)
	if strings.Contains(k, "Home End") || !strings.Contains(k, "F File list") || !strings.Contains(k, "Q Back to menu") {
		t.Errorf("narrow keys %q", k)
	}
}

func cleanPreviewOutput() []string {
	out := numbered(20)
	return append(out, "",
		strings.Repeat("=", 70),
		"\x1b[1;34mDry run complete - no changes made\x1b[0m",
		"Potential space: \x1b[0;33m611.0MB\x1b[0m | Items: 84 | Categories: 6",
		"Detailed file list: \x1b[0;38;5;244m/tmp/clean-list.txt\x1b[0m",
		"Use mo clean --whitelist to add protection rules",
		strings.Repeat("=", 70))
}

func TestSummaryIsPinnedAtTheTop(t *testing.T) {
	m := newModel("Clean · Preview", cleanPreviewOutput(), "/tmp/clean-list.txt", []string{"x"}, 80, 16)
	rows := strings.Split(ansi.Strip(m.View()), "\n")
	want := []string{
		"Dry run complete - no changes made",
		"Potential space: 611.0MB | Items: 84 | Categories: 6",
		"Detailed file list: /tmp/clean-list.txt  (F to view)",
		"Use mo clean --whitelist to add protection rules",
	}
	for i, w := range want {
		if rows[1+i] != w {
			t.Errorf("summary row %d = %q, want %q", i, rows[1+i], w)
		}
	}
	if !strings.HasPrefix(rows[5], "↑↓ Scroll") || !strings.HasPrefix(rows[6], "───") {
		t.Errorf("keys %q, divider %q", rows[5], rows[6])
	}
	// The summary is not repeated at the end of the output.
	body := strings.Join(rows[7:], "\n")
	if strings.Contains(body, "Potential space") || strings.Contains(body, "=====") || !strings.HasSuffix(body, "line 20") {
		t.Errorf("body %q", body)
	}
	// The file list shows no summary.
	m = press(m, "F")
	if strings.Contains(ansi.Strip(m.View()), "Potential space") {
		t.Error("the summary stayed on the file list")
	}
}

func TestSplitSummaryNeedsAWholeBlock(t *testing.T) {
	lines := []string{"a", strings.Repeat("=", 70), "b"}
	if rest, summary := splitSummary(lines); summary != nil || len(rest) != 3 {
		t.Errorf("one rule: %q %q", rest, summary)
	}
	lines = []string{"a", strings.Repeat("=", 70), "Done", strings.Repeat("=", 70), "after"}
	if rest, summary := splitSummary(lines); strings.Join(summary, ",") != "Done" || strings.Join(rest, ",") != "a,after" {
		t.Errorf("block: %q %q", rest, summary)
	}
	if rest, summary := splitSummary([]string{"=== a heading ==="}); summary != nil || len(rest) != 1 {
		t.Errorf("text with = signs: %q %q", rest, summary)
	}
}

func TestRunNeedsACommandAndATerminal(t *testing.T) {
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = r.Close(); _ = w.Close() }()
	var stderr strings.Builder
	if code := run([]string{"--title", "x"}, r, w, &stderr); code != 2 || !strings.Contains(stderr.String(), "Usage") {
		t.Errorf("no command: %d %q", code, stderr.String())
	}
	// Without a terminal the menu runs the command the plain way, told so by
	// the --unstarted file.
	unstarted := filepath.Join(t.TempDir(), "unstarted")
	if code := run([]string{"--unstarted", unstarted, "--", "true"}, r, w, &stderr); code != exitCannotRun {
		t.Errorf("no terminal: %d", code)
	}
	if _, err := os.Stat(unstarted); err != nil {
		t.Errorf("no --unstarted file: %v", err)
	}
	if _, ok := readFileLines(filepath.Join(t.TempDir(), "missing")); ok {
		t.Error("a missing file was read")
	}
}

func TestFileWrittenSinceTheRunStarted(t *testing.T) {
	path := filepath.Join(t.TempDir(), "clean-list.txt")
	if err := os.WriteFile(path, []byte("x\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-time.Hour)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	if fileWrittenSince(path, time.Now()) {
		t.Error("an hour-old list counts as this run's")
	}
	start := time.Now()
	if err := os.WriteFile(path, []byte("y\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if !fileWrittenSince(path, start) {
		t.Error("a list written during the run is not offered")
	}
}

// keystrokes hands the program one key per read, as a terminal does.
type keystrokes struct{ keys []string }

func (r *keystrokes) Read(p []byte) (int, error) {
	if len(r.keys) == 0 {
		return 0, io.EOF
	}
	n := copy(p, r.keys[0])
	r.keys = r.keys[1:]
	return n, nil
}

func TestShowRunsTheScreenUntilQ(t *testing.T) {
	m := newModel("Clean · Preview", numbered(100), "/tmp/clean-list.txt", []string{"# list"}, 40, 12)
	var out bytes.Buffer
	// Up twice, then F, Q (back to the results) and Q (back to the menu).
	keys := &keystrokes{keys: []string{"\x1b[A", "\x1b[A", "F", "q", "q"}}
	final, err := show(m, tea.WithInput(keys), tea.WithOutput(&out))
	if err != nil {
		t.Fatal(err)
	}
	if final.page != outputPage || final.offset[outputPage] != 89 {
		t.Errorf("ended on page %d at %d", final.page, final.offset[outputPage])
	}
	if !strings.Contains(ansi.Strip(out.String()), "Clean · Preview") {
		t.Error("the screen was never drawn")
	}

	// Ctrl-C leaves from the file list too.
	keys = &keystrokes{keys: []string{"F", "\x03"}}
	if final, err = show(m, tea.WithInput(keys), tea.WithOutput(&out)); err != nil || final.page != filePage {
		t.Errorf("Ctrl-C on the file list: page %d, %v", final.page, err)
	}
}

func TestKeysThatArriveTogetherEachCount(t *testing.T) {
	m := newModel("Clean", numbered(100), "", nil, 40, 12)
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("kkk")})
	if got := next.(model).offset[outputPage]; got != 88 {
		t.Errorf("kkk scrolled to %d, want 88", got)
	}
	if _, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("kq")}); cmd == nil {
		t.Error("a q among other keys did not leave")
	}
}
