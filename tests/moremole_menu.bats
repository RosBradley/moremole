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

# Shared prelude: load the router without running it, at a fixed 40x120 size.
prelude() {
	cat << 'EOF'
set -euo pipefail
export MOLE_TEST_MODE=1 MOLE_SKIP_MAIN=1 NO_COLOR=1
source "$PROJECT_ROOT/mole"
_moremole_terminal_size() { echo "40 120"; }
MAIN_MENU_UPDATE_MESSAGE=""
EOF
}

@test "my commands get a section with one command per row and skip malformed lines" {
	printf '# comment\nFlush DNS\tsudo dscacheutil -flushcache\n\nno tab here\n\techo no name\nSay hi\techo hi\n' > "$HOME/.config/mole/my_commands"
	run /bin/bash --noprofile --norc -c "$(prelude)"'
moremole_load_menu_items
moremole_show_menu_items 1
printf "count=%s\n" "${#MOREMOLE_MY_NAMES[@]}"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Update MoreMole"$'\n'*"── My commands ──"$'\n'*"+ Add a command"$'\n'* ]] || return 1
	[[ "$output" == *"+ Add a command"$'\n'*"  Flush DNS"*"Edit"*"Remove"$'\n'*"  Say hi"*"Edit"*"Remove"$'\n'* ]] || return 1
	[[ "$output" == *"count=2"* ]] || return 1
	[[ "$output" != *"no tab here"* ]]
}

@test "the line under the menu describes the selected item" {
	printf 'Say hi\techo hi\n' > "$HOME/.config/mole/my_commands"
	run /bin/bash --noprofile --norc -c "$(prelude)"'
moremole_load_menu_items
moremole_show_menu_items 2 | tail -n 1
moremole_show_menu_items 27 | tail -n 1
moremole_show_menu_items 28 | tail -n 1
moremole_show_menu_items 30 | tail -n 1
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Show what Clean would remove, without removing anything"* ]] || return 1
	[[ "$output" == *"Add your own command to this menu"* ]] || return 1
	[[ "$output" == *"Runs: echo hi"* ]] || return 1
	[[ "$output" == *'Remove "Say hi" from the menu'* ]]
}

@test "arrow keys keep the column when the next row has one" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
moremole_load_menu_items
c=1
for key in RIGHT RIGHT RIGHT DOWN DOWN RIGHT DOWN LEFT LEFT UP TOP UP BOTTOM DOWN UP DOWN; do
    c=$(moremole_menu_move "$c" "$key")
    printf "%s " "$c"
done
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	# Row 1 holds items 1-3, Uninstall 4-5, Optimize 6-8, Analyze 9-10;
	# Update is 25, the section heading 26 is skipped, Add is 27.
	[ "$output" = "2 3 3 5 7 8 10 9 9 6 1 1 27 27 25 27 " ]
}

@test "a long list scrolls to keep the selection visible" {
	for i in 1 2 3 4 5 6 7; do
		printf 'Cmd %s\techo %s\n' "$i" "$i" >> "$HOME/.config/mole/my_commands"
	done
	run /bin/bash --noprofile --norc -c "$(prelude)"'
_moremole_terminal_size() { echo "24 80"; }
moremole_load_menu_items
last=${#MOREMOLE_MENU_LABELS[@]}
printf "first:\n"; moremole_show_menu_items 1
printf "last:\n"; moremole_show_menu_items "$last"
printf "lines=%s,%s\n" "$(moremole_show_menu_items 1 | wc -l)" "$(moremole_show_menu_items "$last" | wc -l)"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	local first="${output%%last:*}" last="${output#*last:}"
	# "more above" sits above the list and "more below" under it.
	[[ "$first" == *"Clean"*"more below"* ]] || return 1
	[[ "$first" != *"more above"* && "$first" != *"Cmd 7"* ]] || return 1
	[[ "$last" == *"more above"*"Cmd 7"* ]] || return 1
	local last_view="${last%%lines=*}"
	[[ "$last_view" != *"more below"* && "$last" != *"Protected caches"* ]] || return 1
	# Both hint rows are always there while scrolling, so the list keeps its place.
	[[ "$output" =~ lines=\ *([0-9]+),\ *([0-9]+) ]] || return 1
	[ "${BASH_REMATCH[1]}" -eq "${BASH_REMATCH[2]}" ]
}

# Items in the my-commands section: Add is 27, then each command's row holds
# the command, Edit and Remove (28-30 for the first, 31-33 for the second).

@test "Add appends a command, selects it and confirms" {
	printf '# my notes\nOne\techo 1' > "$HOME/.config/mole/my_commands"
	run /bin/bash --noprofile --norc -c "$(prelude)"'
clear() { :; }
drain_pending_input() { :; }
moremole_load_menu_items
moremole_menu_activate 27 < <(printf "  Say hi \necho hi\n")
echo "selected=$MOREMOLE_MENU_SELECTED"
moremole_show_menu_items "$MOREMOLE_MENU_SELECTED" | tail -n 1
echo "---"
cat "$MOREMOLE_MY_COMMANDS_FILE"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"selected=31"* ]] || return 1
	[[ "$output" == *'Added "Say hi".'* ]] || return 1
	[ "${output#*---}" = $'\n# my notes\nOne\techo 1\nSay hi\techo hi' ]
}

@test "Add with an empty name or command adds nothing" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
clear() { :; }
drain_pending_input() { :; }
moremole_load_menu_items
moremole_menu_activate 27 < <(printf "\n")
moremole_show_menu_items 27 | tail -n 1
moremole_menu_activate 27 < <(printf "Name\n\n")
moremole_show_menu_items 27 | tail -n 1
[[ ! -e "$MOREMOLE_MY_COMMANDS_FILE" ]] && echo "NO_FILE"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Nothing added."* ]] || return 1
	[[ "$output" == *"Nothing added: the command was empty."* ]] || return 1
	[[ "$output" == *"NO_FILE"* ]]
}

@test "Edit changes one line, keeps the rest and Enter keeps a value" {
	printf '# my notes\nOne\techo 1\nnot a command\nTwo\techo 2\n' > "$HOME/.config/mole/my_commands"
	run /bin/bash --noprofile --norc -c "$(prelude)"'
clear() { :; }
drain_pending_input() { :; }
moremole_load_menu_items
moremole_menu_activate 32 < <(printf "\necho two\n")
echo "selected=$MOREMOLE_MENU_SELECTED"
moremole_menu_activate 29 < <(printf "\n\n")
moremole_show_menu_items 28 | tail -n 1
echo "---"
cat "$MOREMOLE_MY_COMMANDS_FILE"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"selected=31"* ]] || return 1
	[[ "$output" == *"Nothing changed."* ]] || return 1
	[ "${output#*---}" = $'\n# my notes\nOne\techo 1\nnot a command\nTwo\techo two' ]
}

@test "Remove asks first, keeps hand-written lines and moves the selection" {
	printf '# my notes\nOne\techo 1\nnot a command\nTwo\techo 2\n' > "$HOME/.config/mole/my_commands"
	run /bin/bash --noprofile --norc -c "$(prelude)"'
clear() { :; }
drain_pending_input() { :; }
moremole_load_menu_items
moremole_menu_activate 30 < <(printf "n\n")
moremole_show_menu_items 30 | tail -n 1
moremole_menu_activate 30 < <(printf "y\n")
echo "selected=$MOREMOLE_MENU_SELECTED"
moremole_menu_activate 30 < <(printf "Y\n")
echo "selected=$MOREMOLE_MENU_SELECTED"
echo "---"
cat "$MOREMOLE_MY_COMMANDS_FILE"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Nothing removed."* ]] || return 1
	# Removing the first command selects the one that took its place; removing
	# the last selects Add.
	[[ "$output" == *"selected=28"*"selected=27"* ]] || return 1
	[ "${output#*---}" = $'\n# my notes\nnot a command' ]
}

@test "menu items launch the right Mole script, preview flags and own commands" {
	printf 'Say hi\techo "hi there"\n' > "$HOME/.config/mole/my_commands"
	run /bin/bash --noprofile --norc -c "$(prelude)"'
exec < /dev/null
clear() { :; }
drain_pending_input() { :; }
run_mole_command() { printf "RUN"; printf " [%s]" "$@"; printf "\n"; }
SHELL=/bin/sh
moremole_load_menu_items
moremole_menu_activate 1
moremole_menu_activate 2
moremole_menu_activate 22
moremole_menu_activate 28
echo "STILL_IN_MENU"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"STILL_IN_MENU"* ]] || return 1
	[[ "$output" == *"RUN [$PROJECT_ROOT/bin/clean.sh]"$'\n'* ]] || return 1
	[[ "$output" == *"RUN [$PROJECT_ROOT/bin/clean.sh] [--dry-run]"* ]] || return 1
	[[ "$output" == *"RUN [$PROJECT_ROOT/bin/touchid.sh] [enable] [--dry-run]"* ]] || return 1
	[[ "$output" == *'RUN [/bin/sh] [-c] [echo "hi there"]'* ]]
}

@test "commands return to the menu, after Enter unless they are full-screen" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
SCRIPT_DIR="$HOME/fake"
mkdir -p "$SCRIPT_DIR/bin"
for name in clean status; do
    printf "#!/bin/bash\necho RAN_%s\nexit 3\n" "$name" > "$SCRIPT_DIR/bin/$name.sh"
    chmod +x "$SCRIPT_DIR/bin/$name.sh"
done
show_main_menu() { echo "MENU_DRAWN"; }
hide_cursor() { :; }
show_cursor() { :; }
clear() { :; }
drain_pending_input() { :; }
keys=(ENTER DOWN DOWN DOWN DOWN ENTER QUIT)
read_key() {
    local n=0
    [[ -f "$HOME/key-count" ]] && n=$(cat "$HOME/key-count")
    echo $((n + 1)) > "$HOME/key-count"
    echo "${keys[n]}"
}
rm -f "$HOME/key-count"
interactive_main_menu < <(printf "\n")
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"RAN_clean"*"Press Enter or Q to return to the menu."*"MENU_DRAWN"*"RAN_status"*"MENU_DRAWN"* ]] || return 1
	# Status is full-screen, so it returns without asking for Enter.
	local after_status="${output#*RAN_status}"
	[[ "$after_status" != *"Press Enter"* ]]
}

@test "the banner says MoreMole and points to the moremole repository" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
show_brand_banner
echo "---"
_moremole_terminal_size() { echo "40 60"; }
show_brand_banner
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	local wide="${output%%---*}" narrow="${output#*---}"
	# The logo spells MoreMole: its last row ends in the "Mole" letters.
	[[ "$wide" == *'|_|  |_|\___/|_|  \___|_|  |_|\___/|_|\___|'* ]] || return 1
	[[ "$wide" != *"mole.fit"* ]] || return 1
	# Wide: the address and tagline sit beside the logo's last two rows.
	[[ "$wide" == *'__/  github.com/RosBradley/moremole'* ]] || return 1
	[[ "$wide" == *'\___|  Deep clean and optimize your Mac.'* ]] || return 1
	# Narrow: they move under the logo, each on its own line.
	[[ "$narrow" == *$'\ngithub.com/RosBradley/moremole\nDeep clean and optimize your Mac.'* ]]
}

@test "the version screen names MoreMole and credits Mole" {
	run env HOME="$HOME" "$PROJECT_ROOT/mole" --version
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	local expected
	expected="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$PROJECT_ROOT/mole")"
	[[ "$output" == *"MoreMole version $expected"* ]] || return 1
	[[ "$output" == *"Based on Mole by tw93: github.com/tw93/Mole"* ]] || return 1
	[[ "$output" == *"MoreMole: github.com/RosBradley/moremole"* ]] || return 1
	# Mole's own scripts read the number from the "Mole version" line.
	[ "$(printf '%s\n' "$output" | awk '/Mole version/ {print $NF; exit}')" = "$expected" ]
}

@test "the help screen names commands moremole, in one aligned column" {
	run env HOME="$HOME" NO_COLOR=1 "$PROJECT_ROOT/mole" --help
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"  moremole clean --dry-run           Preview cleanup"* ]] || return 1
	[[ "$output" == *"  moremole touchid enable --dry-run  Preview Touch ID setup"* ]] || return 1
	[[ "$output" == *"  --debug                            Show detailed operation logs"* ]] || return 1
	[[ "$output" != *$'\n  mo '* ]]
}

@test "update notices say run moremole update" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
mkdir -p "$HOME/.cache/mole"
printf "Update 9.8.7 available, run mo update\n" > "$HOME/.cache/mole/update_message"
read_update_message_cache "$HOME/.cache/mole/update_message"
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[ "$output" = "Update 9.8.7 available, run moremole update" ]
}

@test "V and M show their screen and return to the menu on Q or Enter" {
	run /bin/bash --noprofile --norc -c "$(prelude)"'
show_main_menu() { echo "MENU_DRAWN"; }
show_help() { echo "HELP_SHOWN"; }
show_version() { echo "VERSION_SHOWN"; }
hide_cursor() { :; }
show_cursor() { :; }
clear() { :; }
drain_pending_input() { :; }
keys=(MORE VERSION QUIT)
read_key() {
    local n=0
    [[ -f "$HOME/key-count" ]] && n=$(cat "$HOME/key-count")
    echo $((n + 1)) > "$HOME/key-count"
    echo "${keys[n]}"
}
rm -f "$HOME/key-count"
# The help screen gets an ignored key, then Q; the version screen gets Enter.
interactive_main_menu < <(printf "xq\n")
'
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"HELP_SHOWN"*"Press Enter or Q to return to the menu."*"MENU_DRAWN"*"VERSION_SHOWN"*"Press Enter"*"MENU_DRAWN"* ]]
}

@test "Tab completion covers moremole and mm, and setup uses the moremole command" {
	run "$PROJECT_ROOT/bin/completion.sh" zsh
	[ "$status" -eq 0 ] || return 1
	[[ "$output" == *"#compdef mole mo moremole mm"* ]] || return 1
	[[ "$output" == *"compdef _mole mole mo moremole mm"* ]] || return 1
	run "$PROJECT_ROOT/bin/completion.sh" bash
	[[ "$output" == *"complete -F _mole_completions mole mo moremole mm"* ]] || return 1

	mkdir -p "$HOME/stub-bin"
	printf '#!/bin/bash\n' > "$HOME/stub-bin/moremole"
	chmod +x "$HOME/stub-bin/moremole"
	run env HOME="$HOME" SHELL=/bin/zsh MOLE_DRY_RUN=1 PATH="$HOME/stub-bin:/usr/bin:/bin" \
		"$PROJECT_ROOT/bin/completion.sh"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	# shellcheck disable=SC2016  # Literal ~/.zshrc text, not an expansion.
	[[ "$output" == *'if output="$(moremole completion zsh 2>/dev/null)"; then eval "$output"; fi'* ]] || return 1

	# The line it writes is recognized again, so a rerun replaces it.
	run /bin/bash --noprofile --norc -c '
source "$1/lib/core/base.sh"
grep -Eq "$MOLE_COMPLETION_LINE_PATTERN" <<< "if output=\"\$(moremole completion zsh 2>/dev/null)\"; then eval \"\$output\"; fi"
' _ "$PROJECT_ROOT"
	[ "$status" -eq 0 ]
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
