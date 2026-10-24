package main

import (
	"slices"
	"strings"

	"github.com/charmbracelet/x/ansi"
)

// The command screen keeps everything that does not scroll at the top: the
// title, the command's summary, the keys and a divider. The output scrolls
// below them.

// spinnerFrames match Mole's own spinner (lib/core/ui.sh, cmd/analyze).
var spinnerFrames = []string{"⠖", "⠲", "⠴", "⠦"}

// liveKeys is the key row while the command runs.
const liveKeys = "Keys go to the command  |  Ctrl-C Stop"

// topRows returns the rows above the output: the title with a note on the
// right, the summary rows, the key row and a divider.
func topRows(title, note string, summary []string, keys string, width int) []string {
	rows := []string{header(title, note, width)}
	for _, s := range summary {
		rows = append(rows, ansi.Truncate(s, width, "…"))
	}
	rows = append(rows,
		grayStyle+ansi.Truncate(keys, width, "…")+resetStyle,
		grayStyle+strings.Repeat("─", width)+resetStyle)
	return rows
}

// header is the title row: the title, and a gray note on the right.
func header(title, note string, width int) string {
	room := width - ansi.StringWidth(note) - 1
	title = ansi.Truncate(title, max(1, room), "…")
	row := titleStyle + title + resetStyle
	if note != "" {
		gap := max(1, width-ansi.StringWidth(title)-ansi.StringWidth(note))
		row += strings.Repeat(" ", gap) + grayStyle + note + resetStyle
	}
	return row
}

// placeholder is the summary while the command runs: its labels, with the
// spinner where the numbers will go.
func placeholder(labels []string, spin string) []string {
	if len(labels) == 0 {
		return nil
	}
	parts := make([]string, len(labels))
	for i, label := range labels {
		parts[i] = label + ": " + grayStyle + spin + resetStyle
	}
	return []string{strings.Join(parts, " | ")}
}

// splitSummary takes the command's closing summary out of its output. Mole
// prints every summary as a block between two rows of "=" (print_summary_block
// in lib/core/log.sh); the last such block is the summary.
func splitSummary(lines []string) (rest, summary []string) {
	end := -1
	for i, line := range slices.Backward(lines) {
		if isRule(line) {
			end = i
			break
		}
	}
	start := -1
	for i := end - 1; i >= 0; i-- {
		if isRule(lines[i]) {
			start = i
			break
		}
	}
	if start < 0 {
		return lines, nil
	}
	for _, l := range lines[start+1 : end] {
		if strings.TrimSpace(ansi.Strip(l)) != "" {
			summary = append(summary, l)
		}
	}
	rest = trimBlankEnd(append([]string(nil), lines[:start]...))
	rest = append(rest, lines[end+1:]...)
	return trimBlankEnd(rest), summary
}

func isRule(line string) bool {
	s := strings.TrimSpace(ansi.Strip(line))
	return len(s) >= 10 && strings.Trim(s, "=") == ""
}
