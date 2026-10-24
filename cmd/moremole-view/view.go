package main

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

// Colors match Mole's shell UI; NO_COLOR turns them off.
var (
	titleStyle = "\x1b[1;35m"
	grayStyle  = "\x1b[0;38;5;244m"
	resetStyle = "\x1b[0m"
)

func init() {
	if os.Getenv("NO_COLOR") != "" {
		titleStyle, grayStyle, resetStyle = "", "", ""
	}
}

type page int

const (
	outputPage page = iota
	filePage
)

// model shows the command's output and, on F, the file list it wrote.
type model struct {
	title     string
	output    []string
	filePath  string
	fileLines []string // as read; wrapped to the width when shown
	page      page
	offset    [2]int // first shown line on each page
	width     int
	height    int
}

func newModel(title string, output []string, filePath string, fileLines []string, width, height int) model {
	m := model{title: title, output: output, filePath: filePath, fileLines: fileLines, width: width, height: height}
	m.offset[outputPage] = m.maxOffset() // the summary is at the end
	return m
}

func (m model) Init() tea.Cmd { return nil }

// lines is what the current page shows, fitted to the width.
func (m model) lines() []string {
	if m.page == filePage {
		var out []string
		for _, l := range m.fileLines {
			l = strings.ReplaceAll(l, "\t", "    ")
			if l == "" {
				out = append(out, "")
				continue
			}
			out = append(out, strings.Split(ansi.Wrap(l, max(1, m.width), "/"), "\n")...)
		}
		return out
	}
	return m.output
}

// bodyHeight leaves a row for the title and one for the keys.
func (m model) bodyHeight() int { return max(1, m.height-2) }

func (m model) maxOffset() int { return max(0, len(m.lines())-m.bodyHeight()) }

func (m *model) scroll(delta int) {
	m.offset[m.page] = max(0, min(m.offset[m.page]+delta, m.maxOffset()))
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		atEnd := m.offset[m.page] >= m.maxOffset()
		m.width, m.height = msg.Width, msg.Height
		if atEnd && m.page == outputPage {
			m.offset[m.page] = m.maxOffset()
		}
		m.scroll(0)
		return m, nil
	case tea.KeyMsg:
		// Keys typed faster than they are read arrive together.
		if msg.Type == tea.KeyRunes && len(msg.Runes) > 1 {
			var cmd tea.Cmd
			var next tea.Model = m
			for _, r := range msg.Runes {
				next, cmd = next.(model).Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}})
				if cmd != nil {
					return next, cmd
				}
			}
			return next, nil
		}
		page := m.bodyHeight()
		switch msg.String() {
		case "up", "k":
			m.scroll(-1)
		case "down", "j":
			m.scroll(1)
		case "pgup", "b", "left":
			m.scroll(-page)
		case "pgdown", " ", "right":
			m.scroll(page)
		case "home", "g":
			m.offset[m.page] = 0
		case "end", "G":
			m.offset[m.page] = m.maxOffset()
		case "f", "F":
			if m.page == outputPage && m.filePath != "" {
				m.page = filePage
				m.scroll(0)
			}
		case "q", "Q", "esc", "enter":
			if m.page == filePage {
				m.page = outputPage
				return m, nil
			}
			return m, tea.Quit
		case "ctrl+c":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) View() string {
	width := max(1, m.width)
	lines := m.lines()
	body := m.bodyHeight()
	first := m.offset[m.page]
	last := min(len(lines), first+body)

	title := m.title
	if m.page == filePage {
		title = "File list: " + tildePath(m.filePath)
	}
	position := ""
	if len(lines) > body {
		position = fmt.Sprintf("%d-%d of %d", first+1, last, len(lines))
	}

	var sb strings.Builder
	sb.WriteString(header(title, position, width))
	sb.WriteString("\n")
	for i := first; i < first+body; i++ {
		if i < last {
			sb.WriteString(ansi.Truncate(lines[i], width, "…"))
		}
		sb.WriteString("\n")
	}
	sb.WriteString(grayStyle + m.footer(width) + resetStyle)
	return sb.String()
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

// footer lists the keys, dropping the less needed ones when space runs out.
func (m model) footer(width int) string {
	back := "Q Back to menu"
	if m.page == filePage {
		back = "Q Back to results"
	}
	keys := []string{"↑↓ Scroll", "PgUp PgDn Page", "Home End"}
	if m.page == outputPage && m.filePath != "" {
		keys = append(keys, "F File list")
	}
	keys = append(keys, back)
	optional := []string{"Home End", "PgUp PgDn Page"}
	for {
		line := strings.Join(keys, "  |  ")
		if ansi.StringWidth(line) <= width || len(optional) == 0 {
			return ansi.Truncate(line, width, "…")
		}
		drop := optional[0]
		optional = optional[1:]
		for i, k := range keys {
			if k == drop {
				keys = append(keys[:i], keys[i+1:]...)
				break
			}
		}
	}
}

func tildePath(path string) string {
	if home, err := os.UserHomeDir(); err == nil && home != "" && strings.HasPrefix(path, home+"/") {
		return "~" + strings.TrimPrefix(path, home)
	}
	return path
}
