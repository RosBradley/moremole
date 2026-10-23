#!/usr/bin/env bats
# moremole: the full main menu, the user's own commands and update_mole.

load helpers/common

setup_file() {
	mole_test_setup_home "moremole-menu"
}

teardown_file() {
	mole_test_teardown_home
}

setup() {
	rm -rf "${HOME:?}/.config" # SAFE: test-owned mktemp HOME under tests/tmp-*
	mkdir -p "$HOME/.config/mole"
}

# Shared prelude: load the router without running it, at a fixed 24x80 size.
prelude() {
	cat << 'EOF'
set -euo pipefail
export MOLE_TEST_MODE=1 MOLE_SKIP_MAIN=1 NO_COLOR=1
source "$PROJECT_ROOT/mole"
_moremole_terminal_size() { echo "24 80"; }
MAIN_MENU_UPDATE_MESSAGE=""
EOF
}

@test "my commands join the editor row and skip malformed lines" {
	printf '# comment\nFlush DNS\tsudo dscacheutil -flushcache\n\nno tab here\n\techo no name\nSay hi\techo hi\n' > "$HOME/.config/mole/my_commands"
	run /bin/bash --noprofile --norc -c "$(prelude)"'
moremole_load_menu_items
moremole_show_menu_items 1 | tail -n 1
printf "count=%s\n" "${#MOREMOLE_MY_NAMES[@]}"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Edit my commands..."*"Flush DNS"*"Say hi"* ]] || return 1
	[[ "$output" == *"count=2"* ]] || return 1
	[[ "$output" != *"no tab here"* ]]
}

@test "arrow keys keep the column when the next row has one" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
moremole_load_menu_items
c=1
for key in RIGHT RIGHT RIGHT DOWN DOWN RIGHT DOWN LEFT LEFT UP TOP UP BOTTOM DOWN; do
    c=$(moremole_menu_move "$c" "$key")
    printf "%s " "$c"
done
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	# Row 1 holds items 1-3, Uninstall 4-5, Optimize 6-8, Analyze 9-10; the
	# editor is item 26 and the last item.
	[ "$output" = "2 3 3 5 7 8 10 9 9 6 1 1 26 26 " ]
}

@test "a long list scrolls to keep the selection visible" {
	for i in 1 2 3 4 5 6 7; do
		printf 'Cmd %s\techo %s\n' "$i" "$i" >> "$HOME/.config/mole/my_commands"
	done
	run /bin/bash --noprofile --norc -c "$(prelude)"'
moremole_load_menu_items
last=${#MOREMOLE_MENU_LABELS[@]}
printf "first:\n"; moremole_show_menu_items 1
printf "last:\n"; moremole_show_menu_items "$last"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	local first="${output%%last:*}" last="${output#*last:}"
	[[ "$first" == *"Clean"* && "$first" == *"more below"* ]] || return 1
	[[ "$first" != *"Cmd 7"* ]] || return 1
	[[ "$last" == *"Cmd 7"* && "$last" == *"more above"* ]] || return 1
	[[ "$last" != *"Protected caches"* ]]
}

@test "the editor adds and removes commands in the commands file" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
clear() { :; }
drain_pending_input() { :; }
moremole_edit_my_commands < <(printf "a\n  Say hi \necho hi\na\nList\nls -la\n\n")
cat "$MOREMOLE_MY_COMMANDS_FILE"
echo "---"
moremole_edit_my_commands < <(printf "r\n1\ny\nr\n9\n\n")
cat "$MOREMOLE_MY_COMMANDS_FILE"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	local added="${output%%---*}" removed="${output#*---}"
	[[ "$added" == *$'Say hi\techo hi\nList\tls -la'* ]] || return 1
	[[ "$removed" == *$'\nList\tls -la'* ]] || return 1
	[[ "$removed" == *"There is no command number 9."* ]] || return 1
	[[ "$removed" != *$'Say hi\techo hi'* ]]
}

@test "the editor keeps the file unchanged when a remove is not confirmed" {
	printf 'Say hi\techo hi\n' > "$HOME/.config/mole/my_commands"
	run /bin/bash --noprofile --norc -c "$(prelude)"'
clear() { :; }
drain_pending_input() { :; }
moremole_edit_my_commands < <(printf "r\n1\nn\na\n\n\n")
cat "$MOREMOLE_MY_COMMANDS_FILE"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Nothing removed."* ]] || return 1
	[[ "$output" == *"Nothing added: the name was empty."* ]] || return 1
	[[ "$output" == *$'Say hi\techo hi'* ]]
}

@test "menu items launch the right Mole script, preview flags and own commands" {
	printf 'Say hi\techo "hi there"\n' > "$HOME/.config/mole/my_commands"
	run /bin/bash --noprofile --norc -c "$(prelude)"'
clear() { :; }
drain_pending_input() { :; }
run_mole_command() { printf "RUN"; printf " [%s]" "$@"; printf "\n"; }
SHELL=/bin/sh
moremole_load_menu_items
moremole_menu_activate 1
moremole_menu_activate 2
moremole_menu_activate 22
moremole_menu_activate 27
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"RUN [$PROJECT_ROOT/bin/clean.sh]"* ]] || return 1
	[[ "$output" == *"RUN [$PROJECT_ROOT/bin/clean.sh] [--dry-run]"* ]] || return 1
	[[ "$output" == *"RUN [$PROJECT_ROOT/bin/touchid.sh] [enable] [--dry-run]"* ]] || return 1
	[[ "$output" == *'RUN [/bin/sh] [-c] [echo "hi there"]'* ]]
}

@test "update_mole runs the moremole sync script instead of installing Mole" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
SCRIPT_DIR="$HOME/fork"
mkdir -p "$SCRIPT_DIR/scripts"
git init -q "$SCRIPT_DIR"
printf "echo SYNC_RAN\n" > "$SCRIPT_DIR/scripts/moremole-sync.sh"
update_mole true false
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"--force and --nightly are not used"* ]] || return 1
	[[ "$output" == *"SYNC_RAN"* ]]
}

@test "update_mole keeps Mole's own updater outside a moremole git folder" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
SCRIPT_DIR="$HOME/not-a-repo"
mkdir -p "$SCRIPT_DIR/scripts"
printf "echo SYNC_RAN\n" > "$SCRIPT_DIR/scripts/moremole-sync.sh"
declare -f _moremole_official_update_mole | grep -q "UPDATE_LOCK_CONTROL" || exit 1
_moremole_official_update_mole() { echo "OFFICIAL_UPDATE $*"; }
update_mole true false
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"OFFICIAL_UPDATE true false"* ]] || return 1
	[[ "$output" != *"SYNC_RAN"* ]]
}
