package main

import (
	"reflect"
	"strings"
	"testing"

	"github.com/charmbracelet/x/ansi"
)

func plain(t *testing.T, cols, rows int, data string) []string {
	t.Helper()
	term := newTerminal(cols, rows)
	term.write([]byte(data))
	var out []string
	for _, l := range term.Lines() {
		out = append(out, ansi.Strip(l))
	}
	return out
}

func TestReplayKeepsTextAndCollapsesSpinnerFrames(t *testing.T) {
	data := "Clean Your Mac\r\n\r\n" +
		"\r\x1b[2K| Scanning caches...\r\x1b[2K/ Scanning caches...\r\x1b[2K- Scanning caches...\r\x1b[2K" +
		"\x1b[0;32m✓\x1b[0m User caches \x1b[0;32m1.2GB\x1b[0m\r\n" +
		"Summary\r\n\r\n\r\n"
	got := plain(t, 40, 10, data)
	want := []string{"Clean Your Mac", "", "✓ User caches 1.2GB", "Summary"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %q\nwant %q", got, want)
	}
}

func TestReplayKeepsColors(t *testing.T) {
	term := newTerminal(40, 5)
	term.write([]byte("\x1b[1;35mTitle\x1b[0m plain \x1b[38;5;244mgray\x1b[0m\r\n"))
	got := term.Lines()[0]
	want := "\x1b[0m\x1b[1;35mTitle\x1b[0m plain \x1b[0m\x1b[38;5;244mgray\x1b[0m"
	if got != want {
		t.Errorf("got %q\nwant %q", got, want)
	}
}

func TestReplayKeepsHistoryAboveTheScreen(t *testing.T) {
	var sb strings.Builder
	for i := 1; i <= 12; i++ {
		sb.WriteString("line ")
		sb.WriteString(string(rune('a' + i - 1)))
		sb.WriteString("\r\n")
	}
	got := plain(t, 20, 4, sb.String())
	if len(got) != 12 || got[0] != "line a" || got[11] != "line l" {
		t.Errorf("history lost: %q", got)
	}
}

func TestReplayDropsAlternateScreenAndRedrawnFrames(t *testing.T) {
	// A pick list drawn on the alternate screen leaves nothing behind.
	data := "Before\r\n\x1b[?1049h\x1b[H\x1b[2JPick list frame 1\x1b[H\x1b[2JPick list frame 2\x1b[?1049lAfter\r\n"
	if got := plain(t, 30, 6, data); !reflect.DeepEqual(got, []string{"Before", "After"}) {
		t.Errorf("alternate screen: %q", got)
	}
	// A list redrawn in place on the main screen shows its last frame once.
	data = "\x1b[H\x1b[2J> one\r\n  two\r\n\x1b[H\x1b[J  one\r\n> two\r\nDone\r\n"
	if got := plain(t, 30, 6, data); !reflect.DeepEqual(got, []string{"  one", "> two", "Done"}) {
		t.Errorf("redrawn frames: %q", got)
	}
}

func TestReplayCursorMovesRewriteEarlierLines(t *testing.T) {
	data := "Downloading 10%\r\nfile.zip\r\n\x1b[2A\x1b[2KDownloading 100%\r\n\x1b[1B\x1b[GDone\r\n"
	if got := plain(t, 30, 6, data); !reflect.DeepEqual(got, []string{"Downloading 100%", "file.zip", "Done"}) {
		t.Errorf("got %q", got)
	}
}

func TestReplayWrapsLongLinesAndWideCharacters(t *testing.T) {
	if got := plain(t, 5, 4, "abcdefg\r\n"); !reflect.DeepEqual(got, []string{"abcde", "fg"}) {
		t.Errorf("wrap: %q", got)
	}
	if got := plain(t, 5, 4, "ab中文x\r\n"); !reflect.DeepEqual(got, []string{"ab中", "文x"}) {
		t.Errorf("wide: %q", got)
	}
}

func TestReplayDropsScriptBanners(t *testing.T) {
	// util-linux writes a long header ending in a bare newline, even with -q.
	data := "Script started on 2026-10-24 10:00:00+00:00 [COMMAND=\"bash -c 'source bin/moremole-updates.sh; main'\" <not executed on terminal>]\n" +
		"Hello\r\n\r\n\nScript done on 2026-10-24 10:00:01+00:00 [COMMAND_EXIT_CODE=\"0\"]\n"
	if got := plain(t, 60, 5, string(stripBanners([]byte(data)))); !reflect.DeepEqual(got, []string{"Hello"}) {
		t.Errorf("got %q", got)
	}
	// Text that merely mentions a banner stays.
	data = "echo Script done on Friday\r\nScript done on Friday\r\nmore\r\n"
	if got := string(stripBanners([]byte(data))); got != data {
		t.Errorf("stripped command output: %q", got)
	}
}

func TestReplayIgnoresTitlesLinksAndUnknownSequences(t *testing.T) {
	data := "\x1b]0;window title\x07\x1b]8;;file:///Users/me\x1b\\~/Library\x1b]8;;\x1b\\ \x1b[?25l\x1b[?2004hok\x1b(B\x1b=\r\n"
	if got := plain(t, 40, 5, data); !reflect.DeepEqual(got, []string{"~/Library ok"}) {
		t.Errorf("got %q", got)
	}
}
