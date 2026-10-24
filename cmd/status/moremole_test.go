package main

import (
	"strings"
	"testing"

	"github.com/charmbracelet/lipgloss"
)

// moremoleSnapshot is a 16-core Apple-silicon Mac with one internal disk.
func moremoleSnapshot() MetricsSnapshot {
	perCore := make([]float64, 16)
	for i := range perCore {
		perCore[i] = float64(i * 6)
	}
	return MetricsSnapshot{
		CPU: CPUStatus{Usage: 8.1, PerCore: perCore, Load1: 1.66, Load5: 2.6, Load15: 2.76,
			CoreCount: 16, LogicalCPU: 16, PCoreCount: 12, ECoreCount: 4},
		GPU:    []GPUStatus{{Name: "Apple M4 Max", Usage: 17, CoreCount: 40}},
		Memory: MemoryStatus{Used: 54 << 30, Total: 128 << 30, UsedPercent: 42.8},
		Disks: []DiskStatus{{Mount: "/", Used: 1100 << 30, Total: 1800 << 30, UsedPercent: 61.1},
			{Mount: "/Volumes/X", Used: 18 << 30, Total: 19 << 30, UsedPercent: 97.5, External: true}},
	}
}

func withCardWidth(t *testing.T, width int) {
	t.Helper()
	saved := statusCardWidth
	statusCardWidth = width
	t.Cleanup(func() { statusCardWidth = saved })
}

func withGPUCardPlatform(t *testing.T, platform string) {
	t.Helper()
	saved := gpuCardPlatform
	gpuCardPlatform = platform
	t.Cleanup(func() { gpuCardPlatform = saved })
}

func TestStatusBarWidthFillsTheCard(t *testing.T) {
	withCardWidth(t, 0)
	if got := statusBarWidth(); got != classicBarWidth {
		t.Fatalf("no card width: bar = %d, want the classic %d", got, classicBarWidth)
	}
	for _, tc := range []struct{ card, want int }{
		{30, classicBarWidth}, // never narrower than before
		{76, 76 - barLabelRoom - barValueRoom},
		{400, maxBarWidth},
	} {
		statusCardWidth = tc.card
		if got := statusBarWidth(); got != tc.want {
			t.Errorf("card %d: bar = %d, want %d", tc.card, got, tc.want)
		}
	}
	statusCardWidth = 76
	if got := lipgloss.Width(diskProgressBar(50)); got != 76-barLabelRoom-diskValueRoom {
		t.Errorf("disk bar = %d cells, want %d", got, 76-barLabelRoom-diskValueRoom)
	}
	if got := lipgloss.Width(classicProgressBar(50)); got != classicBarWidth {
		t.Errorf("process bar = %d cells, want the classic %d", got, classicBarWidth)
	}
	if statusValueRoom != barValueRoom {
		t.Errorf("diskProgressBar left statusValueRoom at %d", statusValueRoom)
	}
}

// Wider bars must never push a line past its card, where it would wrap. From
// 47 columns a disk line fits a classic bar; narrower cards keep Mole's own
// behaviour.
func TestStretchedCardLinesFitTheirCard(t *testing.T) {
	withGPUCardPlatform(t, "darwin")
	for _, width := range []int{47, 60, 76, 120} {
		withCardWidth(t, width)
		for _, card := range buildCards(moremoleSnapshot(), width, 0, true) {
			for _, line := range card.lines {
				if got := lipgloss.Width(line); got > width {
					t.Errorf("card width %d: %s line is %d wide: %q", width, card.title, got, line)
				}
			}
		}
	}
}

func TestStatusShowsAllCoresAndAGPUCard(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	withGPUCardPlatform(t, "darwin")
	cores := loadCPUCores()
	if cores != 0 {
		t.Fatalf("default cpu cores = %d, want 0 (all)", cores)
	}
	cards := buildCards(moremoleSnapshot(), 76, cores, true)
	var cpu, gpu string
	for _, card := range cards {
		switch card.title {
		case "CPU":
			cpu = strings.Join(card.lines, "\n")
		case "GPU":
			gpu = stripANSI(strings.Join(card.lines, "\n"))
		}
	}
	if got := strings.Count(cpu, "Core"); got != 16 {
		t.Errorf("CPU card lists %d cores, want all 16", got)
	}
	if !strings.Contains(gpu, "17.0%") || !strings.Contains(gpu, "Apple M4 Max · 40 cores") {
		t.Errorf("GPU card = %q", gpu)
	}
}

func TestGPUCardWhenUsageIsUnknownOrMissing(t *testing.T) {
	withGPUCardPlatform(t, "darwin")
	card, ok := renderGPUCard([]GPUStatus{{Name: "Apple M4", Usage: -1, CoreCount: 10}})
	if !ok || !strings.Contains(stripANSI(strings.Join(card.lines, "\n")), "not available") {
		t.Errorf("unknown usage: ok=%v lines=%q", ok, card.lines)
	}
	if _, ok := renderGPUCard(nil); ok {
		t.Error("no GPU: card shown")
	}
	if _, ok := renderGPUCard([]GPUStatus{{Usage: -1}}); ok {
		t.Error("nothing known about the GPU: card shown")
	}
	withGPUCardPlatform(t, "linux")
	if _, ok := renderGPUCard([]GPUStatus{{Name: "x", Usage: 5, CoreCount: 4}}); ok {
		t.Error("card shown off macOS")
	}
}

func TestParseIORegGPUUtilization(t *testing.T) {
	out := `+-o AGXAcceleratorG16X  <class AGXAcceleratorG16X>
    {
      "PerformanceStatistics" = {"In use system memory"=1234,"Device Utilization %"=23,"Renderer Utilization %"=21}
    }`
	if got := parseIORegGPUUtilization(out); got != 23 {
		t.Errorf("got %v, want 23", got)
	}
	if got := parseIORegGPUUtilization(`"Renderer Utilization %"=21`); got != -1 {
		t.Errorf("missing key: got %v, want -1", got)
	}
	if got := parseIORegGPUUtilization(`"Device Utilization %"=140`); got != 100 {
		t.Errorf("out of range: got %v, want 100", got)
	}
}
