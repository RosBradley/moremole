//go:build darwin || linux

package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/charmbracelet/x/ansi"
	"golang.org/x/sys/unix"
)

// pane runs a command on a terminal of its own and shows that terminal's
// screen between a fixed title row and a fixed key row, so the command's
// output scrolls inside the frame while the frame stays put. Keys go to the
// command, so its prompts, passwords and pick lists work as usual.
type pane struct {
	title string
	note  string
	in    *os.File  // the user's keyboard
	out   io.Writer // the user's screen
	size  func() (cols, rows int, ok bool)
	term  *terminal
	prev  []string // rows last drawn, to redraw only what changed
}

// redrawEvery caps redraws while output streams in.
const redrawEvery = 33 * time.Millisecond

// settleAfterExit is how long output may keep arriving after the command
// exits, from children it left running, before the pane stops reading.
const settleAfterExit = 200 * time.Millisecond

func terminalSize(f *os.File) (cols, rows int, ok bool) {
	ws, err := unix.IoctlGetWinsize(int(f.Fd()), unix.TIOCGWINSZ)
	if err != nil || ws.Col == 0 || ws.Row == 0 {
		return 0, 0, false
	}
	return int(ws.Col), int(ws.Row), true
}

func isTerminal(f *os.File) bool {
	_, err := unix.IoctlGetTermios(int(f.Fd()), getTermios)
	return err == nil
}

// makeRaw passes every key through unchanged, as cfmakeraw does.
func makeRaw(t *unix.Termios) {
	t.Iflag &^= unix.IGNBRK | unix.BRKINT | unix.PARMRK | unix.ISTRIP | unix.INLCR | unix.IGNCR | unix.ICRNL | unix.IXON
	t.Oflag &^= unix.OPOST
	t.Lflag &^= unix.ECHO | unix.ECHONL | unix.ICANON | unix.ISIG | unix.IEXTEN
	t.Cflag &^= unix.CSIZE | unix.PARENB
	t.Cflag |= unix.CS8
	t.Cc[unix.VMIN] = 1
	t.Cc[unix.VTIME] = 0
}

func setSize(master *os.File, cols, rows int) {
	_ = unix.IoctlSetWinsize(int(master.Fd()), unix.TIOCSWINSZ, &unix.Winsize{Col: uint16(cols), Row: uint16(rows)})
}

// paneRows leaves a row for the title and one for the keys.
func paneRows(rows int) int { return max(1, rows-2) }

// run starts argv in the pane and returns its output once it exits, with
// its exit status (-1 when a signal stopped it). errCannotRun means nothing
// was started, so the caller can run the command another way.
func (p *pane) run(argv []string) ([]string, int, error) {
	cols, rows, ok := p.size()
	if !ok {
		return nil, 0, fmt.Errorf("%w: no terminal size", errCannotRun)
	}
	p.term = newTerminal(cols, paneRows(rows))
	if p.note != "" {
		p.term.write([]byte(grayStyle + p.note + resetStyle + "\r\n\r\n"))
	}

	master, slave, err := openPTY()
	if err != nil {
		return nil, 0, fmt.Errorf("%w: %v", errCannotRun, err)
	}
	defer func() { _ = master.Close() }()
	inFd := int(p.in.Fd())
	if orig, err := unix.IoctlGetTermios(inFd, getTermios); err == nil {
		// The command's terminal starts with the user's own settings.
		_ = unix.IoctlSetTermios(int(slave.Fd()), setTermios, orig)
		raw := *orig
		makeRaw(&raw)
		if err := unix.IoctlSetTermios(inFd, setTermios, &raw); err == nil {
			defer func() { _ = unix.IoctlSetTermios(inFd, setTermios, orig) }()
		}
	}
	setSize(master, cols, paneRows(rows))

	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = slave, slave, slave
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true}
	if err := cmd.Start(); err != nil {
		_ = slave.Close()
		return nil, 0, fmt.Errorf("%w: %v", errCannotRun, err)
	}
	_ = slave.Close()

	_, _ = io.WriteString(p.out, "\x1b[?1049h\x1b[2J")
	p.draw()

	output := make(chan []byte, 64)
	go func() {
		buf := make([]byte, 32*1024)
		for {
			n, err := master.Read(buf)
			if n > 0 {
				output <- append([]byte(nil), buf[:n]...)
			}
			if err != nil {
				close(output)
				return
			}
		}
	}()
	stopInput := make(chan struct{})
	inputDone := make(chan struct{})
	go forwardInput(inFd, master, stopInput, inputDone)
	exited := make(chan int, 1)
	go func() {
		err := cmd.Wait()
		code := 0
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			code = exitErr.ExitCode()
		} else if err != nil {
			code = 1
		}
		exited <- code
	}()
	winch := make(chan os.Signal, 1)
	signal.Notify(winch, syscall.SIGWINCH)
	defer signal.Stop(winch)
	tick := time.NewTicker(redrawEvery)
	defer tick.Stop()

	code, done, dirty := 0, false, false
	var settle <-chan time.Time
loop:
	for {
		select {
		case data, open := <-output:
			if !open {
				output = nil
				if done {
					break loop
				}
				continue
			}
			p.term.write(data)
			dirty = true
			if done {
				settle = time.After(settleAfterExit)
			}
		case code = <-exited:
			done = true
			if output == nil {
				break loop
			}
			settle = time.After(settleAfterExit)
		case <-settle:
			break loop
		case <-winch:
			if c, r, ok := p.size(); ok {
				p.term.Resize(c, paneRows(r))
				setSize(master, c, paneRows(r))
				p.prev = nil
				dirty = true
			}
		case <-tick.C:
			if dirty {
				p.draw()
				dirty = false
			}
		}
	}
	close(stopInput)
	<-inputDone
	p.draw()
	return p.term.Lines(), code, nil
}

// forwardInput passes keys to the command until stop closes. It waits with
// select, which works on terminals on macOS too, so it never sits in a read
// that would swallow the first key meant for the results screen.
func forwardInput(fd int, to io.Writer, stop <-chan struct{}, done chan<- struct{}) {
	defer close(done)
	buf := make([]byte, 1024)
	for {
		select {
		case <-stop:
			return
		default:
		}
		var set unix.FdSet
		set.Set(fd)
		timeout := unix.NsecToTimeval((50 * time.Millisecond).Nanoseconds())
		n, err := unix.Select(fd+1, &set, nil, nil, &timeout)
		if err == unix.EINTR {
			continue
		}
		if err != nil {
			return
		}
		if n == 0 || !set.IsSet(fd) {
			continue
		}
		k, err := unix.Read(fd, buf)
		if k > 0 {
			if _, werr := to.Write(buf[:k]); werr != nil {
				return
			}
		}
		if err == unix.EINTR || err == unix.EAGAIN {
			continue
		}
		if err != nil || k == 0 {
			return
		}
	}
}

// draw shows the frame: the title, the command's screen, and the keys.
func (p *pane) draw() {
	cols := p.term.width
	frame := make([]string, 0, p.term.height+2)
	frame = append(frame, header(p.title, "running", cols))
	frame = append(frame, p.term.Screen()...)
	frame = append(frame, grayStyle+ansi.Truncate("Keys go to the command  |  Ctrl-C Stop", cols, "…")+resetStyle)
	var sb strings.Builder
	sb.WriteString("\x1b[?25l")
	for i, line := range frame {
		if i < len(p.prev) && p.prev[i] == line {
			continue
		}
		fmt.Fprintf(&sb, "\x1b[%d;1H\x1b[0m%s\x1b[0m\x1b[K", i+1, ansi.Truncate(line, cols, ""))
	}
	p.prev = frame
	if row, col, visible := p.term.Cursor(); visible {
		fmt.Fprintf(&sb, "\x1b[%d;%dH\x1b[?25h", row+2, col+1)
	}
	_, _ = io.WriteString(p.out, sb.String())
}

// leaveScreen goes back to the screen the menu was on.
func leaveScreen(out io.Writer) {
	_, _ = io.WriteString(out, "\x1b[0m\x1b[?25h\x1b[?1049l")
}
