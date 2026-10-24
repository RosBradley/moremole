package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

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
	// 12 rows: a title, 10 lines and the keys.
	if m.offset[outputPage] != 90 {
		t.Fatalf("starts at %d, want the last page (90)", m.offset[outputPage])
	}
	view := ansi.Strip(m.View())
	rows := strings.Split(view, "\n")
	if len(rows) != 12 || !strings.HasPrefix(rows[0], "Clean · Preview") || !strings.HasSuffix(rows[0], "91-100 of 100") {
		t.Fatalf("view rows %d, title %q", len(rows), rows[0])
	}
	if rows[1] != "line 91" || rows[10] != "line 100" {
		t.Errorf("body %q .. %q", rows[1], rows[10])
	}
	m = press(m, "up", "up", "pgup")
	if m.offset[outputPage] != 78 {
		t.Errorf("after up, up, pgup: %d", m.offset[outputPage])
	}
	m = press(m, "home", "up")
	if m.offset[outputPage] != 0 {
		t.Errorf("home then up: %d", m.offset[outputPage])
	}
	m = press(m, "end", "down", "pgdown")
	if m.offset[outputPage] != 90 {
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

func TestFooterDropsHintsBeforeTheBackKey(t *testing.T) {
	m := newModel("Clean", numbered(3), "/tmp/x", []string{"x"}, 120, 12)
	if f := m.footer(120); !strings.Contains(f, "Home End") || !strings.Contains(f, "PgUp PgDn") {
		t.Errorf("wide footer %q", f)
	}
	f := m.footer(50)
	if strings.Contains(f, "Home End") || !strings.Contains(f, "F File list") || !strings.Contains(f, "Q Back to menu") {
		t.Errorf("narrow footer %q", f)
	}
}

func TestRunReplaysARecordingFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "log")
	if err := os.WriteFile(path, []byte("Hello\r\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr strings.Builder
	if code := run([]string{"--rows", "5"}, &stdout, &stderr); code != 2 || !strings.Contains(stderr.String(), "Usage") {
		t.Errorf("no recording: %d %q", code, stderr.String())
	}
	if code := run([]string{filepath.Join(dir, "missing")}, &stdout, &stderr); code != 1 {
		t.Errorf("missing recording: %d", code)
	}
	if code := run([]string{"--print", path}, &stdout, &stderr); code != 0 || stdout.String() != "Hello\n" {
		t.Errorf("--print: %d %q", code, stdout.String())
	}
	if _, ok := readFileLines(""); ok {
		t.Error("an empty --file was offered")
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
	if final.page != outputPage || final.offset[outputPage] != 88 {
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
	if got := next.(model).offset[outputPage]; got != 87 {
		t.Errorf("kkk scrolled to %d, want 87", got)
	}
	if _, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("kq")}); cmd == nil {
		t.Error("a q among other keys did not leave")
	}
}
