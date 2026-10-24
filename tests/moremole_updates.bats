#!/usr/bin/env bats
# shellcheck disable=SC2016  # inner bash scripts expand their own arguments
# MoreMole: Software updates (bin/moremole-updates.sh). A fake helper stands
# in for moremole-updates-go, and fake brew, mas and open record what would
# have run; nothing touches the real Homebrew, App Store or macOS.

load helpers/common

setup_file() {
	mole_test_setup_home moremole-updates
}

teardown_file() {
	mole_test_teardown_home
}

setup() {
	if [[ "$HOME" != "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
		printf 'FATAL: HOME is not a test temp dir: %s\n' "$HOME" >&2
		return 1
	fi
	export TERM="xterm-256color"
	export MO_DEBUG=0
	rm -rf "$HOME/Library/Logs/mole" # SAFE: test-owned HOME under tests/tmp-*
	ROWS_DIR="$BATS_TEST_TMPDIR/rows"
	CALLS="$BATS_TEST_TMPDIR/calls"
	mkdir -p "$ROWS_DIR"
	: > "$CALLS"
	export ROWS_DIR CALLS

	cat > "$BATS_TEST_TMPDIR/helper" << 'EOF'
#!/bin/bash
[[ -f "$ROWS_DIR/$1" ]] && cat "$ROWS_DIR/$1"
exit 0
EOF
	chmod +x "$BATS_TEST_TMPDIR/helper"
	mole_test_fake_command brew 'printf "brew %s\n" "$*" >> "$CALLS"; [[ "$*" != *broken* ]]'
	mole_test_fake_command mas 'printf "mas %s\n" "$*" >> "$CALLS"'
	mole_test_fake_command open 'printf "open %s\n" "$*" >> "$CALLS"'
}

# Append a helper row: kind id name installed available selected note.
row() {
	local file="$ROWS_DIR/$1"
	shift
	local IFS=$'\x1f'
	printf '%s\n' "$*" >> "$file"
}

updates_env() {
	env HOME="$HOME" PATH="$PATH" MOLE_TEST_MODE=1 \
		MOREMOLE_TEST_UPDATES_HELPER="$BATS_TEST_TMPDIR/helper" \
		MOREMOLE_TEST_OPEN="$BATS_TEST_TMPDIR/fake-bin/open" "$@"
}

full_scan_rows() {
	row brew notice homebrew-stale "" "" "" 0 "Couldn't refresh Homebrew's version list."
	# The helper sorts each source by name; the script groups by kind.
	row brew app google-chrome "Google Chrome" 124.0 125.0 0 "updates itself"
	row brew app visual-studio-code "Visual Studio Code" 1.88.0 1.89.0 1 ""
	row brew tool git git 2.44.0 2.45.0 0 ""
	row store store 497799835 Xcode 15.0 15.1 1 ""
	row takeover takeover firefox Firefox 129.0 130.0 0 "replaces your copy"
	row macos macos-settings "macOS Sequoia 15.1-24B83" "macOS Sequoia 15.1" "" 15.1 0 "needs a restart, opens Settings"
	row macos macos "Safari18.1-18.1" Safari "" 18.1 0 ""
}

@test "a dry run lists every source in order with its defaults and installs nothing" {
	full_scan_rows
	run updates_env /bin/bash -c 'source "$1"; main --dry-run' bash "$PROJECT_ROOT/bin/moremole-updates.sh"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"DRY RUN"*"Couldn't refresh Homebrew's version list."*"7 updates available"* ]] || return 1
	# Homebrew apps, then apps to move to Homebrew, App Store, tools and macOS.
	[[ "$output" == *"Google Chrome"*"Visual Studio Code"*"Firefox"*"Xcode"*"git"*"Safari"*"macOS Sequoia"* ]] || return 1
	[[ "$output" == *"● Visual Studio Code"*"1.88.0 → 1.89.0"*"Homebrew"* ]] || return 1
	[[ "$output" == *"○ Google Chrome"*"Homebrew (updates itself)"* ]] || return 1
	[[ "$output" == *"○ Firefox"*"Move to Homebrew (replaces your copy)"* ]] || return 1
	[[ "$output" == *"● Xcode"*"App Store"* ]] || return 1
	[[ "$output" == *"○ git"*"Command-line tool"* ]] || return 1
	[[ "$output" == *"○ macOS Sequoia 15.1"*"macOS (needs a restart, opens Settings)"* ]] || return 1
	[ ! -s "$CALLS" ]
}

@test "without a terminal the list is shown and nothing is installed" {
	full_scan_rows
	run updates_env /bin/bash -c 'source "$1"; main < /dev/null' bash "$PROJECT_ROOT/bin/moremole-updates.sh"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" != *"DRY RUN"* ]] || return 1
	[[ "$output" == *"7 updates available"*"Run moremole updates in a terminal to choose updates."* ]] || return 1
	[ ! -s "$CALLS" ]
}

@test "nothing to update says so, and a missing helper says how to build it" {
	run updates_env /bin/bash -c 'source "$1"; main --dry-run' bash "$PROJECT_ROOT/bin/moremole-updates.sh"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Everything is up to date"* ]] || return 1

	run updates_env MOREMOLE_TEST_UPDATES_HELPER="$BATS_TEST_TMPDIR/missing" \
		/bin/bash -c 'source "$1"; main --dry-run' bash "$PROJECT_ROOT/bin/moremole-updates.sh"
	[ "$status" -eq 1 ] || { echo "$output"; return 1; }
	[[ "$output" == *"make build"* ]] || return 1

	run updates_env /bin/bash -c 'source "$1"; main --bogus' bash "$PROJECT_ROOT/bin/moremole-updates.sh"
	[ "$status" -eq 1 ]
}

@test "helper rows keep empty fields and notices stay out of the update list" {
	row brew notice mas-missing "" "" "" 0 "App Store apps need mas."
	row brew macos "Label-1" "Safari" "" 18.1 0 ""
	run updates_env /bin/bash -c '
		source "$1"
		load_update_rows < "$ROWS_DIR/brew"
		printf "count=%s notices=%s\n" "${#U_KIND[@]}" "${NOTICE_KEYS[*]}"
		printf "[%s][%s][%s][%s][%s][%s][%s]\n" "${U_KIND[0]}" "${U_ID[0]}" "${U_NAME[0]}" "${U_FROM[0]}" "${U_TO[0]}" "${U_SEL[0]}" "${U_NOTE[0]}"
		printf "version=%s\n" "$(version_text 0)"
	' bash "$PROJECT_ROOT/bin/moremole-updates.sh"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"count=1 notices=mas-missing"* ]] || return 1
	[[ "$output" == *"[macos][Label-1][Safari][][18.1][0][]"* ]] || return 1
	[[ "$output" == *"version=18.1"* ]]
}

@test "the pick list starts with the default selections in list order" {
	full_scan_rows
	printf 'ENTER\n' > "$BATS_TEST_TMPDIR/keys"
	run updates_env COLUMNS=60 KEYS_FILE="$BATS_TEST_TMPDIR/keys" KEY_STATE="$BATS_TEST_TMPDIR/key-state" /bin/bash -c '
		source "$1"
		enter_alt_screen() { :; }
		leave_alt_screen() { :; }
		stty() { :; }
		tput() { if [[ "$1" == cols ]]; then echo 60; else echo 20; fi; }
		drain_pending_input() { :; }
		read_key() {
			local index key
			index=$(cat "$KEY_STATE" 2>/dev/null || echo 0)
			index=$((index + 1))
			printf "%s\n" "$index" > "$KEY_STATE"
			key=$(sed -n "${index}p" "$KEYS_FILE")
			printf "%s\n" "${key:-QUIT}"
		}
		for source in brew store takeover macos; do
			load_update_rows < "$ROWS_DIR/$source"
		done
		order_update_rows
		select_updates || exit 1
		printf "RESULT=%s\n" "$MOLE_SELECTION_RESULT"
		printf "first=%s last=%s\n" "${U_NAME[0]}" "${U_NAME[6]}"
		measure_columns
		for ((i = 0; i < ${#U_KIND[@]}; i++)); do
			w=$(text_width "$(update_row_text "$i")")
			((w <= 56)) || { echo "row $i is $w cells wide"; exit 1; }
		done
	' bash "$PROJECT_ROOT/bin/moremole-updates.sh"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	# Visual Studio Code (1) and Xcode (3) start selected; the rest do not.
	[[ "$output" == *"RESULT=1,3"* ]] || return 1
	[[ "$output" == *"first=Google Chrome last=macOS Sequoia 15.1"* ]]
}

@test "the confirm screen warns about what each kind of update does" {
	full_scan_rows
	run updates_env /bin/bash -c '
		source "$1"
		for source in brew store takeover macos; do
			load_update_rows < "$ROWS_DIR/$source"
		done
		order_update_rows
		printf "\n" | confirm_updates 1 2 3 5 6 && echo CONFIRMED
		printf "x" | confirm_updates 1 || echo CANCELLED
	' bash "$PROJECT_ROOT/bin/moremole-updates.sh"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Apps being updated may quit"* ]] || return 1
	[[ "$output" == *"Apps moved to Homebrew are replaced by Homebrew's copy"* ]] || return 1
	[[ "$output" == *"App Store updates may ask for your password"* ]] || return 1
	[[ "$output" == *"macOS updates ask for your password"* ]] || return 1
	[[ "$output" == *"Updates that restart the Mac open Software Update"* ]] || return 1
	[[ "$output" == *"Install 5 updates"*"CONFIRMED"* ]] || return 1
	[[ "$output" == *"CANCELLED"* ]]
}

@test "installing runs each source's own command, logs each one and opens Software Update once" {
	row scan app visual-studio-code "Visual Studio Code" 1.88.0 1.89.0 1 ""
	row scan app broken "Broken App" 1.0 2.0 1 ""
	row scan tool git git 2.44.0 2.45.0 0 ""
	row scan takeover firefox Firefox 129.0 130.0 0 ""
	row scan store 497799835 Xcode 15.0 15.1 1 ""
	row scan macos "Safari18.1-18.1" Safari "" 18.1 0 ""
	row scan macos-settings "macOS Sequoia 15.1-24B83" "macOS Sequoia 15.1" "" 15.1 0 ""
	row scan macos-settings "Some Firmware-1.0" "Some Firmware" "" 1.0 0 ""
	run updates_env /bin/bash -c '
		source "$1"
		load_update_rows < "$ROWS_DIR/scan"
		install_updates 0 1 2 3 4 5 6 7
		show_updates_summary
		printf "updated=%s failed=%s\n" "$total_updated" "$total_failed"
	' bash "$PROJECT_ROOT/bin/moremole-updates.sh"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" != *"UNSTUBBED"* ]] || return 1
	[[ "$output" == *"updated=4 failed=2"* ]] || return 1
	[[ "$output" == *"Some updates did not install"*"Updated"*"4"* ]] || return 1
	[[ "$output" == *"Not updated: Broken App: brew reported an error"* ]] || return 1
	[[ "$output" == *"Not updated: Safari: needs your password"* ]] || return 1
	[[ "$output" == *"Opened Software Update for: macOS Sequoia 15.1, Some Firmware"* ]] || return 1

	local calls
	calls=$(cat "$CALLS")
	[ "$calls" = "brew upgrade --cask --greedy visual-studio-code
brew upgrade --cask --greedy broken
brew upgrade --formula git
brew install --cask --force firefox
mas upgrade 497799835
open x-apple.systempreferences:com.apple.Software-Update-Settings.extension" ] || { echo "$calls"; return 1; }

	local log="$HOME/Library/Logs/mole/operations.log"
	grep -q "REBUILT Visual Studio Code (updated to 1.89.0, Homebrew)" "$log" || return 1
	grep -q "REBUILT Firefox (updated to 130.0, Move to Homebrew)" "$log" || return 1
	grep -q "FAILED Broken App (brew reported an error)" "$log" || return 1
	grep -q "FAILED Safari (needs your password)" "$log" || return 1
	grep -q "SKIPPED Some Firmware (opened Software Update in System Settings)" "$log" || return 1
	[ "$(grep -c "REBUILT" "$log")" -eq 4 ]
}

@test "updates is a command with help, completion and a menu row" {
	run "$PROJECT_ROOT/mole" updates --help
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Usage: moremole updates"*"--dry-run"* ]] || return 1

	run /bin/bash -c 'source "$1/lib/core/commands.sh"; printf "%s\n" "${MOLE_COMMANDS[@]}"' bash "$PROJECT_ROOT"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *$'slim:Remove Intel code from universal apps\nupdates:Update apps, tools and macOS\n'* ]] || return 1

	run "$PROJECT_ROOT/mole" --help
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"slim"*"updates"*"Update apps, tools and macOS"* ]]
}
