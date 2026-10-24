package main

// moremole: Status stretches its bars to fill the window and shows a GPU card.
// Kept in its own file so upstream Mole updates merge with few conflicts; the
// other files only call into it.

import (
	"context"
	"fmt"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
)

const (
	classicBarWidth = 16
	maxBarWidth     = 64
	// Room in front of a bar for its label, as in "Total  ".
	barLabelRoom = metricLabelWidth + 1
	// Room after a bar for its value, as in "  100.0% @ 99.9°C".
	barValueRoom = 17
	// Disk lines end with "  1.8T used, 677G free".
	diskValueRoom   = 24
	ioregGPUTimeout = 1 * time.Second
)

// gpuCardPlatform is the platform the GPU card is shown on; tests replace it.
var gpuCardPlatform = runtime.GOOS

// statusCardWidth is the width of the cards being drawn, set by View for each
// frame. 0 keeps the classic bar width, as in tests and before the first frame.
var statusCardWidth int

// statusValueRoom is the room the line being drawn needs after its bar.
var statusValueRoom = barValueRoom

// statusBarWidth is the bar width that fills the card while leaving room for
// the line's label and value.
func statusBarWidth() int {
	if statusCardWidth <= 0 {
		return classicBarWidth
	}
	return min(max(statusCardWidth-barLabelRoom-statusValueRoom, classicBarWidth), maxBarWidth)
}

// barOfWidth draws a bar total cells wide, filled to percent.
func barOfWidth(percent float64, total int) string {
	percent = min(max(percent, 0), 100)
	filled := int(percent / 100 * float64(total))
	return strings.Repeat("█", filled) + strings.Repeat("░", total-filled)
}

// diskProgressBar is progressBar for disk lines, whose value text is longer.
func diskProgressBar(percent float64) string {
	saved := statusValueRoom
	statusValueRoom = diskValueRoom
	defer func() { statusValueRoom = saved }()
	return progressBar(percent)
}

// classicProgressBar keeps the original width, for process rows whose names
// need the rest of the line.
func classicProgressBar(percent float64) string {
	return colorizePercent(percent, barOfWidth(percent, classicBarWidth))
}

// renderGPUCard shows total GPU usage and the GPU's core count and name.
// macOS reports usage for the GPU as a whole, not for each GPU core.
func renderGPUCard(gpus []GPUStatus) (cardData, bool) {
	if gpuCardPlatform != "darwin" || len(gpus) == 0 {
		return cardData{}, false
	}
	gpu := gpus[0]
	if gpu.CoreCount <= 0 && gpu.Usage < 0 {
		return cardData{}, false
	}

	var lines []string
	if gpu.Usage >= 0 {
		lines = append(lines, fmt.Sprintf("%-*s %s  %5.1f%%", metricLabelWidth, "Usage", progressBar(gpu.Usage), gpu.Usage))
	} else {
		lines = append(lines, fmt.Sprintf("%-*s %s", metricLabelWidth, "Usage", subtleStyle.Render("not available")))
	}
	var about []string
	if gpu.Name != "" {
		about = append(about, gpu.Name)
	}
	if gpu.CoreCount > 0 {
		about = append(about, fmt.Sprintf("%d cores", gpu.CoreCount))
	}
	if len(about) > 0 {
		lines = append(lines, fmt.Sprintf("%-*s %s", metricLabelWidth, "Chip", strings.Join(about, " · ")))
	}
	return cardData{icon: iconGPU, title: "GPU", lines: lines}, true
}

var gpuDeviceUtilizationRe = regexp.MustCompile(`"Device Utilization %"\s*=\s*(\d+(?:\.\d+)?)`)

// parseIORegGPUUtilization reads the GPU's "Device Utilization %" from ioreg
// output, or -1 when it is missing.
func parseIORegGPUUtilization(out string) float64 {
	matches := gpuDeviceUtilizationRe.FindStringSubmatch(out)
	if len(matches) < 2 {
		return -1
	}
	usage, err := strconv.ParseFloat(matches[1], 64)
	if err != nil {
		return -1
	}
	return min(max(usage, 0), 100)
}

// readIORegGPUUtilization asks the GPU driver for its utilization. Unlike
// powermetrics it needs no administrator rights. Returns -1 when unavailable.
func readIORegGPUUtilization() float64 {
	if runtime.GOOS != "darwin" || !commandExists("ioreg") {
		return -1
	}
	ctx, cancel := context.WithTimeout(context.Background(), ioregGPUTimeout)
	defer cancel()
	out, err := runCmd(ctx, "ioreg", "-r", "-d", "1", "-w", "0", "-c", "IOAccelerator")
	if err != nil {
		return -1
	}
	return parseIORegGPUUtilization(out)
}
