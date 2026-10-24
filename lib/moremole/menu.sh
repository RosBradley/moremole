#!/bin/bash
# moremole: the main menu lists every command from the More screen, one row
# per command with its preview and other variants beside it, then the user's
# own commands in a section of their own, each with Edit and Remove beside
# it. Commands return to the menu.
# Sourced by the mole router after lib/manage/update.sh. Everything moremole
# changes lives here so upstream Mole updates merge with few conflicts.

set -euo pipefail

if [[ -n "${MOREMOLE_MENU_LOADED:-}" ]]; then
    return 0
fi
readonly MOREMOLE_MENU_LOADED=1

MOREMOLE_MY_COMMANDS_FILE="$HOME/.config/mole/my_commands"

# Every command from the More screen, one menu row each. Cells are separated
# by ";" and hold label|kind|args|description. "mole" runs bin/<first
# word>.sh with the remaining words; "update" runs update_mole.
readonly MOREMOLE_BUILTIN_ROWS=(
    "Clean|mole|clean|Free up disk space;Preview|mole|clean --dry-run|Show what Clean would remove, without removing anything;Protected caches|mole|clean --whitelist|Choose caches that Clean must never remove"
    "Uninstall|mole|uninstall|Remove apps completely;Preview|mole|uninstall --dry-run|Show what Uninstall would remove, without removing anything"
    "Optimize|mole|optimize|Refresh caches and services;Preview|mole|optimize --dry-run|Show what Optimize would do, without changing anything;Protected items|mole|optimize --whitelist|Choose items that Optimize must leave alone"
    "Analyze|mole|analyze|Explore disk usage;External drives|mole|analyze /Volumes|Explore disk usage on external drives only"
    "Status|mole|status|Monitor system health"
    "History|mole|history|Review cleanup activity;Export|mole|history --json|Print cleanup history as JSON"
    "Purge|mole|purge|Remove old project build files;Preview|mole|purge --dry-run|Show what Purge would remove, without removing anything;Choose folders|mole|purge --paths|Choose the folders Purge scans for projects"
    "Installer files|mole|installer|Find and remove installer files;Preview|mole|installer --dry-run|Show what would be removed, without removing anything"
    "Slim Intel code|mole|slim|Remove Intel code from universal apps;Preview|mole|slim --dry-run|Show what Slim would remove, without removing anything"
    "Touch ID|mole|touchid|Use Touch ID for sudo;Preview|mole|touchid enable --dry-run|Show what Touch ID setup would change, without changing it"
    "Shell completion|mole|completion|Set up Tab completion for moremole and mm;Preview|mole|completion --dry-run|Show the shell setup edits, without making them"
    "Software updates|mole|moremole-updates|Update apps, tools and macOS;Preview|mole|moremole-updates --dry-run|List available updates, without installing anything"
    "Update MoreMole|update||Get the latest MoreMole and Mole changes, and rebuild if needed"
)
readonly MOREMOLE_SECTION_LABEL="My commands"
readonly MOREMOLE_ADD_LABEL="+ Add a command"
readonly MOREMOLE_ADD_DESC="Add your own command to this menu"
readonly MOREMOLE_MENU_COLUMNS=3
readonly MOREMOLE_REPO_URL="github.com/RosBradley/moremole"
# Two short lines, so the banner stays within 80 columns: Mole's own line,
# then what MoreMole adds.
readonly MOREMOLE_TAGLINE=("Deep clean and optimize your Mac." "Manage, update and remove apps.")

# Lines around the items besides the banner: the line under the banner (blank,
# or "more above"); a blank line and the description; a blank line and the
# controls; plus the row the cursor rests on so the last line cannot scroll.
readonly MOREMOLE_MENU_OVERHEAD=6

# One entry per menu item, in reading order (row by row, left to right).
declare -a MOREMOLE_MENU_LABELS=()
declare -a MOREMOLE_MENU_KINDS=()
declare -a MOREMOLE_MENU_ARGS=()
declare -a MOREMOLE_MENU_DESCS=()
declare -a MOREMOLE_MENU_COLS=()
# One entry per row: index of its first item and its number of items.
declare -a MOREMOLE_MENU_ROW_START=()
declare -a MOREMOLE_MENU_ROW_LEN=()
declare -a MOREMOLE_MY_NAMES=()
declare -a MOREMOLE_MY_COMMANDS=()
# File line number of each of the user's commands.
declare -a MOREMOLE_MY_LINES=()
MOREMOLE_MENU_TOP_ROW=0
# Item the menu should select after moremole_menu_activate (1-based), and a
# one-time message shown in place of the description.
MOREMOLE_MENU_SELECTED=1
MOREMOLE_MENU_NOTICE=""

# Layout, set by _moremole_menu_layout.
declare -a MOREMOLE_LAYOUT_WIDTHS=()
MOREMOLE_LAYOUT_MAX_LABEL=1
MOREMOLE_LAYOUT_VISIBLE_ROWS=1
MOREMOLE_LAYOUT_TERM_COLS=80

# Read the user's commands. Each line is "name<TAB>command"; blank lines,
# lines starting with # and lines missing either part are skipped.
moremole_read_my_commands() {
    MOREMOLE_MY_NAMES=()
    MOREMOLE_MY_COMMANDS=()
    MOREMOLE_MY_LINES=()
    [[ -f "$MOREMOLE_MY_COMMANDS_FILE" && -r "$MOREMOLE_MY_COMMANDS_FILE" ]] || return 0

    local line name command number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        number=$((number + 1))
        [[ -z "$line" || "$line" == "#"* || "$line" != *$'\t'* ]] && continue
        name="${line%%$'\t'*}"
        command="${line#*$'\t'}"
        [[ -n "$name" && -n "$command" ]] || continue
        MOREMOLE_MY_NAMES+=("$name")
        MOREMOLE_MY_COMMANDS+=("$command")
        MOREMOLE_MY_LINES+=("$number")
    done < "$MOREMOLE_MY_COMMANDS_FILE"
}

# Append item label|kind|args|description at column $5 of the current last
# row; column 0 starts a new row.
_moremole_add_item() {
    local column="$5"
    if [[ "$column" -eq 0 ]]; then
        MOREMOLE_MENU_ROW_START+=("${#MOREMOLE_MENU_LABELS[@]}")
        MOREMOLE_MENU_ROW_LEN+=(0)
    fi
    local last_row=$((${#MOREMOLE_MENU_ROW_LEN[@]} - 1))
    MOREMOLE_MENU_ROW_LEN[last_row]=$((column + 1))
    MOREMOLE_MENU_LABELS+=("$1")
    MOREMOLE_MENU_KINDS+=("$2")
    MOREMOLE_MENU_ARGS+=("$3")
    MOREMOLE_MENU_DESCS+=("$4")
    MOREMOLE_MENU_COLS+=("$column")
}

moremole_load_menu_items() {
    MOREMOLE_MENU_LABELS=()
    MOREMOLE_MENU_KINDS=()
    MOREMOLE_MENU_ARGS=()
    MOREMOLE_MENU_DESCS=()
    MOREMOLE_MENU_COLS=()
    MOREMOLE_MENU_ROW_START=()
    MOREMOLE_MENU_ROW_LEN=()

    local spec cell label kind args column
    local -a cells=()
    for spec in "${MOREMOLE_BUILTIN_ROWS[@]}"; do
        IFS=';' read -r -a cells <<< "$spec"
        column=0
        for cell in "${cells[@]}"; do
            label="${cell%%|*}"
            cell="${cell#*|}"
            kind="${cell%%|*}"
            cell="${cell#*|}"
            args="${cell%%|*}"
            _moremole_add_item "$label" "$kind" "$args" "${cell#*|}" "$column"
            column=$((column + 1))
        done
    done

    # The user's section: a heading, Add, then one row per command with its
    # Edit and Remove actions beside it. Their args hold the command's number.
    _moremole_add_item "$MOREMOLE_SECTION_LABEL" "header" "" "" 0
    _moremole_add_item "$MOREMOLE_ADD_LABEL" "add" "" "$MOREMOLE_ADD_DESC" 0
    moremole_read_my_commands
    local i name
    for ((i = 0; i < ${#MOREMOLE_MY_NAMES[@]}; i++)); do
        name="${MOREMOLE_MY_NAMES[i]}"
        _moremole_add_item "$name" "custom" "${MOREMOLE_MY_COMMANDS[i]}" "Runs: ${MOREMOLE_MY_COMMANDS[i]}" 0
        _moremole_add_item "Edit" "edit" "$i" "Change the name or command of \"$name\"" 1
        _moremole_add_item "Remove" "remove" "$i" "Remove \"$name\" from the menu" 2
    done
}

# Prints "lines columns", falling back to 24x80 when there is no terminal.
_moremole_terminal_size() {
    local size="" lines cols
    size=$({ stty size < /dev/tty; } 2> /dev/null) || size=""
    lines="${size%% *}"
    cols="${size##* }"
    [[ "$lines" =~ ^[0-9]+$ && "$lines" -gt 0 ]] || lines=24
    [[ "$cols" =~ ^[0-9]+$ && "$cols" -gt 0 ]] || cols=80
    printf '%s %s\n' "$lines" "$cols"
}

# Width of each column (widest label plus room for the arrow and a gap) and
# how many rows fit on screen at once.
_moremole_menu_layout() {
    local term_lines term_cols overhead i column rows
    local size
    size="$(_moremole_terminal_size)"
    term_lines="${size%% *}"
    term_cols="${size##* }"
    MOREMOLE_LAYOUT_TERM_COLS=$term_cols

    # Three columns always fit: long labels are shortened instead.
    MOREMOLE_LAYOUT_MAX_LABEL=$((term_cols / MOREMOLE_MENU_COLUMNS - 4))
    ((MOREMOLE_LAYOUT_MAX_LABEL >= 8)) || MOREMOLE_LAYOUT_MAX_LABEL=8

    MOREMOLE_LAYOUT_WIDTHS=()
    for ((column = 0; column < MOREMOLE_MENU_COLUMNS; column++)); do
        MOREMOLE_LAYOUT_WIDTHS+=(0)
    done
    local length
    for ((i = 0; i < ${#MOREMOLE_MENU_LABELS[@]}; i++)); do
        column=${MOREMOLE_MENU_COLS[i]}
        length=${#MOREMOLE_MENU_LABELS[i]}
        ((length <= MOREMOLE_LAYOUT_MAX_LABEL)) || length=$MOREMOLE_LAYOUT_MAX_LABEL
        ((length + 4 <= MOREMOLE_LAYOUT_WIDTHS[column])) || MOREMOLE_LAYOUT_WIDTHS[column]=$((length + 4))
    done

    rows=${#MOREMOLE_MENU_ROW_START[@]}
    local banner="${MAIN_MENU_BANNER:-}" banner_lines=5
    if [[ -n "$banner" ]]; then
        banner_lines=$(printf '%s\n' "$banner" | wc -l)
    fi
    overhead=$((MOREMOLE_MENU_OVERHEAD + banner_lines))
    if [[ -n "${MAIN_MENU_UPDATE_MESSAGE:-}" ]]; then
        overhead=$((overhead + 2))
    fi
    MOREMOLE_LAYOUT_VISIBLE_ROWS=$((term_lines - overhead))
    # A list taller than the screen scrolls, and gives the row below it to
    # "more below"; "more above" uses the line under the banner.
    if ((rows > MOREMOLE_LAYOUT_VISIBLE_ROWS)); then
        MOREMOLE_LAYOUT_VISIBLE_ROWS=$((MOREMOLE_LAYOUT_VISIBLE_ROWS - 1))
    fi
    ((MOREMOLE_LAYOUT_VISIBLE_ROWS >= 3)) || MOREMOLE_LAYOUT_VISIBLE_ROWS=3
    ((MOREMOLE_LAYOUT_VISIBLE_ROWS <= rows)) || MOREMOLE_LAYOUT_VISIBLE_ROWS=$rows
    return 0
}

# Row of item $1 (0-based index).
_moremole_item_row() {
    local index="$1" row
    for ((row = ${#MOREMOLE_MENU_ROW_START[@]} - 1; row > 0; row--)); do
        ((index < MOREMOLE_MENU_ROW_START[row])) || break
    done
    printf '%s\n' "$row"
}

# Draw the items with $1 (1-based) selected, one terminal line per row, then
# a line describing the selected item.
moremole_show_menu_items() {
    local selected="${1:-1}"
    ((${#MOREMOLE_MENU_LABELS[@]} > 0)) || moremole_load_menu_items
    _moremole_menu_layout

    local rows=${#MOREMOLE_MENU_ROW_START[@]}
    local visible=$MOREMOLE_LAYOUT_VISIBLE_ROWS
    local max=$MOREMOLE_LAYOUT_MAX_LABEL
    local selected_row
    selected_row=$(_moremole_item_row "$((selected - 1))")

    # Scroll just far enough to keep the selection on screen.
    ((selected_row >= MOREMOLE_MENU_TOP_ROW)) || MOREMOLE_MENU_TOP_ROW=$selected_row
    ((selected_row < MOREMOLE_MENU_TOP_ROW + visible)) || MOREMOLE_MENU_TOP_ROW=$((selected_row - visible + 1))
    ((MOREMOLE_MENU_TOP_ROW <= rows - visible)) || MOREMOLE_MENU_TOP_ROW=$((rows - visible))
    ((MOREMOLE_MENU_TOP_ROW >= 0)) || MOREMOLE_MENU_TOP_ROW=0

    # The line above the list is blank, or says "more above" when items are
    # hidden above; while scrolling, the row under it is blank or says "more
    # below", so the list never jumps.
    local scrolling=false
    ((visible >= rows)) || scrolling=true
    if [[ "$scrolling" == "true" ]] && ((MOREMOLE_MENU_TOP_ROW > 0)); then
        printf '\r\033[2K  %s↑ more above%s\n' "$GRAY" "$NC"
    else
        printf '\r\033[2K\n'
    fi

    local row column index label kind line pad
    for ((row = MOREMOLE_MENU_TOP_ROW; row < MOREMOLE_MENU_TOP_ROW + visible; row++)); do
        line=""
        for ((column = 0; column < MOREMOLE_MENU_ROW_LEN[row]; column++)); do
            index=$((MOREMOLE_MENU_ROW_START[row] + column))
            label="${MOREMOLE_MENU_LABELS[index]}"
            kind="${MOREMOLE_MENU_KINDS[index]}"
            if ((${#label} > max)); then
                label="${label:0:$((max - 3))}..."
            fi
            if [[ "$kind" == "header" ]]; then
                line+="  ${BLUE}── ${label} ──${NC}"
            elif ((index + 1 == selected)); then
                line+="${CYAN}${ICON_ARROW} ${label}${NC}"
            elif [[ "$kind" == "add" ]]; then
                line+="  ${GREEN}${label}${NC}"
            else
                line+="  ${label}"
            fi
            # The last cell of a row needs no padding.
            if ((column + 1 < MOREMOLE_MENU_ROW_LEN[row])); then
                printf -v pad '%*s' "$((MOREMOLE_LAYOUT_WIDTHS[column] - 2 - ${#label}))" ''
                line+="$pad"
            fi
        done
        printf '\r\033[2K%s\n' "$line"
    done

    if [[ "$scrolling" == "true" ]]; then
        if ((MOREMOLE_MENU_TOP_ROW + visible < rows)); then
            printf '\r\033[2K  %s↓ more below%s\n' "$GRAY" "$NC"
        else
            printf '\r\033[2K\n'
        fi
    fi

    # One line only: a description wider than the window is shortened. A
    # notice from the last action shows once in its place.
    local desc="${MOREMOLE_MENU_DESCS[selected - 1]:-}" desc_color="$GRAY"
    if [[ -n "$MOREMOLE_MENU_NOTICE" ]]; then
        desc="$MOREMOLE_MENU_NOTICE" desc_color="$GREEN"
        MOREMOLE_MENU_NOTICE=""
    fi
    local room=$((MOREMOLE_LAYOUT_TERM_COLS - 4))
    if ((room > 3 && ${#desc} > room)); then
        desc="${desc:0:$((room - 3))}..."
    fi
    printf '\r\033[2K\n\r\033[2K  %s%s%s\n' "$desc_color" "$desc" "$NC"
}

# Print the item number (1-based) reached from $1 by key $2. Up and down keep
# the column where the next row has one, else take that row's last item, and
# step over the section heading.
moremole_menu_move() {
    local current="$1" key="$2"
    ((${#MOREMOLE_MENU_LABELS[@]} > 0)) || moremole_load_menu_items

    local count=${#MOREMOLE_MENU_LABELS[@]}
    local rows=${#MOREMOLE_MENU_ROW_START[@]}
    local index=$((current - 1))
    ((index >= 0 && index < count)) || index=0
    local row column target step=1
    row=$(_moremole_item_row "$index")
    column=${MOREMOLE_MENU_COLS[index]}

    case "$key" in
        LEFT) ((column == 0)) || index=$((index - 1)) ;;
        RIGHT) ((column + 1 >= MOREMOLE_MENU_ROW_LEN[row])) || index=$((index + 1)) ;;
        UP | DOWN)
            [[ "$key" == "DOWN" ]] || step=-1
            target=$((row + step))
            while ((target >= 0 && target < rows)) &&
                [[ "${MOREMOLE_MENU_KINDS[MOREMOLE_MENU_ROW_START[target]]}" == "header" ]]; do
                target=$((target + step))
            done
            if ((target >= 0 && target < rows)); then
                ((column < MOREMOLE_MENU_ROW_LEN[target])) || column=$((MOREMOLE_MENU_ROW_LEN[target] - 1))
                index=$((MOREMOLE_MENU_ROW_START[target] + column))
            fi
            ;;
        TOP) index=0 ;;
        BOTTOM) index=$((count - 1)) ;;
    esac
    printf '%s\n' "$((index + 1))"
}

# Wait for Enter or Q, the keys that leave a screen everywhere else, and
# ignore any other key. The end of input counts as Enter.
_moremole_wait_to_return() {
    local key=""
    printf '%sPress Enter or Q to return to the menu.%s' "$GRAY" "$NC"
    while IFS= read -r -s -n 1 key; do
        case "$key" in
            "" | q | Q) break ;;
        esac
    done
    printf '\n'
}

# The heading shown above a command that has no heading of its own.
_moremole_command_heading() {
    case "${1##*/}" in
        touchid.sh) printf 'Touch ID' ;;
        installer.sh) printf 'Installer files' ;;
        slim.sh) printf 'Slim Intel code' ;;
        completion.sh) printf 'Shell completion' ;;
    esac
}

# Run a command on a screen of its own, then come back to the menu.
# Full-screen commands (Analyze, Status) and commands the user cancelled
# (lib/moremole/cancel.sh) return straight away; others wait for Enter so
# their output can be read first. Also used by the 1-5 shortcuts in mole.
moremole_run_and_return() {
    show_cursor
    drain_pending_input 0.1
    clear
    local heading
    heading="$(_moremole_command_heading "$1")"
    if [[ -n "$heading" ]]; then
        printf '%s%s%s\n' "$PURPLE_BOLD" "$heading" "$NC"
        # Touch ID's own screen already starts with a blank line.
        [[ "$1" == */bin/touchid.sh && $# -eq 1 ]] || printf '\n'
    fi
    local cancel_dir="" cancelled=false
    cancel_dir="$(mktemp -d "${TMPDIR:-/tmp}/moremole-cancel.XXXXXX" 2> /dev/null)" || cancel_dir=""
    # Ctrl-C stops the command, not the menu, whose own handler would quit.
    # The command starts with the default action, so it still stops.
    trap ':' INT
    (
        [[ -z "$cancel_dir" ]] || export MOREMOLE_CANCEL_FILE="$cancel_dir/cancelled"
        run_mole_command "$@"
    ) || true
    if declare -F cleanup_and_exit > /dev/null; then
        trap cleanup_and_exit INT
    else
        trap - INT
    fi
    if [[ -n "$cancel_dir" ]]; then
        [[ ! -e "$cancel_dir/cancelled" ]] || cancelled=true
        rm -f "$cancel_dir/cancelled" # SAFE: marker inside this run's own mktemp folder
        rmdir "$cancel_dir" 2> /dev/null || true
    fi
    case "$1" in
        */bin/analyze.sh | */bin/status.sh) ;;
        *)
            if [[ "$cancelled" != "true" ]]; then
                printf '\n'
                _moremole_wait_to_return
            fi
            ;;
    esac
    hide_cursor
    clear
}

# Run item $1 (1-based) and set MOREMOLE_MENU_SELECTED to the item to select
# next. Commands, Add, Edit and Remove return to the menu; Update ends it,
# because the files it runs from may have just changed.
moremole_menu_activate() {
    local index=$(($1 - 1))
    local kind="${MOREMOLE_MENU_KINDS[index]:-}"
    local args="${MOREMOLE_MENU_ARGS[index]:-}"
    MOREMOLE_MENU_SELECTED=$1

    case "$kind" in
        mole)
            local -a words=()
            read -r -a words <<< "$args"
            if ((${#words[@]} > 1)); then
                moremole_run_and_return "$SCRIPT_DIR/bin/${words[0]}.sh" "${words[@]:1}"
            else
                moremole_run_and_return "$SCRIPT_DIR/bin/${words[0]}.sh"
            fi
            ;;
        update)
            show_cursor
            clear
            update_mole false false
            printf '\nStart moremole again to use the updated version.\n'
            exit 0
            ;;
        custom)
            local shell="${SHELL:-/bin/bash}"
            [[ -x "$shell" ]] || shell=/bin/bash
            clear
            printf '%s%s%s\n%s$ %s%s\n\n' "$BLUE" "${MOREMOLE_MENU_LABELS[index]}" "$NC" "$GRAY" "$args" "$NC"
            moremole_run_and_return "$shell" -c "$args"
            ;;
        add | edit | remove)
            show_cursor
            drain_pending_input 0.1
            clear
            "_moremole_${kind}_my_command" "$args"
            hide_cursor
            clear
            moremole_load_menu_items
            ;;
    esac
}

# Item number (1-based) of the user's command $1 (0-based), or of Add when
# there is no such command.
_moremole_my_command_item() {
    local i add_item=1
    for ((i = 0; i < ${#MOREMOLE_MENU_KINDS[@]}; i++)); do
        case "${MOREMOLE_MENU_KINDS[i]}" in
            add) add_item=$((i + 1)) ;;
            edit)
                if [[ "${MOREMOLE_MENU_ARGS[i]}" == "$1" ]]; then
                    # The command's own item sits just before its Edit.
                    printf '%s\n' "$i"
                    return 0
                fi
                ;;
        esac
    done
    printf '%s\n' "$add_item"
}

_moremole_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# Append one command to the file, creating it with a short header if needed.
# The file is only ever appended to or rewritten in place, so comments and
# hand-written lines stay and a symlinked file keeps pointing where it did.
_moremole_append_my_command() {
    local file="$MOREMOLE_MY_COMMANDS_FILE"
    mkdir -p "$(dirname "$file")"
    if [[ ! -s "$file" ]]; then
        printf '# moremole: your own menu commands, one per line as name<TAB>command.\n' > "$file"
    elif [[ -n "$(tail -c 1 "$file")" ]]; then
        # The last line has no newline yet.
        printf '\n' >> "$file"
    fi
    printf '%s\t%s\n' "$1" "$2" >> "$file"
}

# Replace line $1 of the file with $2, or remove it when $2 is empty, and keep
# every other line as it is.
_moremole_replace_file_line() {
    local target="$1" replacement="$2" line number=0
    local -a kept=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        number=$((number + 1))
        if ((number != target)); then
            kept+=("$line")
        elif [[ -n "$replacement" ]]; then
            kept+=("$replacement")
        fi
    done < "$MOREMOLE_MY_COMMANDS_FILE"
    if ((${#kept[@]} > 0)); then
        printf '%s\n' "${kept[@]}" > "$MOREMOLE_MY_COMMANDS_FILE"
    else
        : > "$MOREMOLE_MY_COMMANDS_FILE"
    fi
}

# Ask for one line of input and print the answer; $2, when given, is shown in
# brackets and kept when the answer is empty. Returns 1 at end of input.
_moremole_ask() {
    local prompt="$1" current="${2:-}" answer=""
    if [[ -n "$current" ]]; then
        printf '%s [%s]: ' "$prompt" "$current" >&2
    else
        printf '%s: ' "$prompt" >&2
    fi
    IFS= read -r answer || return 1
    answer="$(_moremole_trim "$answer")"
    printf '%s' "${answer:-$current}"
}

_moremole_add_my_command() {
    local name="" command=""
    printf '%sAdd a command%s\n%sLeave the name empty to cancel.%s\n\n' "$BLUE" "$NC" "$GRAY" "$NC"
    name="$(_moremole_ask "Name shown in the menu")" || return 0
    name="${name//$'\t'/ }"
    if [[ -z "$name" ]]; then
        MOREMOLE_MENU_NOTICE="Nothing added."
        return 0
    fi
    command="$(_moremole_ask "Command to run")" || return 0
    if [[ -z "$command" ]]; then
        MOREMOLE_MENU_NOTICE="Nothing added: the command was empty."
        return 0
    fi

    _moremole_append_my_command "$name" "$command"
    moremole_load_menu_items
    MOREMOLE_MENU_SELECTED=$(_moremole_my_command_item "$((${#MOREMOLE_MY_NAMES[@]} - 1))")
    MOREMOLE_MENU_NOTICE="Added \"$name\"."
}

_moremole_edit_my_command() {
    local number="$1"
    local old_name="${MOREMOLE_MY_NAMES[number]}" old_command="${MOREMOLE_MY_COMMANDS[number]}"
    local name="" command=""
    printf '%sEdit "%s"%s\n%sPress Enter to keep what is in brackets.%s\n\n' "$BLUE" "$old_name" "$NC" "$GRAY" "$NC"
    name="$(_moremole_ask "Name shown in the menu" "$old_name")" || return 0
    name="${name//$'\t'/ }"
    command="$(_moremole_ask "Command to run" "$old_command")" || return 0
    if [[ "$name" == "$old_name" && "$command" == "$old_command" ]]; then
        MOREMOLE_MENU_NOTICE="Nothing changed."
        return 0
    fi

    _moremole_replace_file_line "${MOREMOLE_MY_LINES[number]}" "$name"$'\t'"$command"
    moremole_load_menu_items
    MOREMOLE_MENU_SELECTED=$(_moremole_my_command_item "$number")
    MOREMOLE_MENU_NOTICE="Saved \"$name\"."
}

_moremole_remove_my_command() {
    local number="$1" answer=""
    local name="${MOREMOLE_MY_NAMES[number]}"
    printf 'Remove "%s" from the menu? (y/N): ' "$name"
    IFS= read -r answer || return 0
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        MOREMOLE_MENU_NOTICE="Nothing removed."
        return 0
    fi

    _moremole_replace_file_line "${MOREMOLE_MY_LINES[number]}" ""
    moremole_load_menu_items
    # Select the command that took its place, else the one above, else Add.
    if ((number >= ${#MOREMOLE_MY_NAMES[@]})); then
        number=$((number - 1))
    fi
    MOREMOLE_MENU_SELECTED=$(_moremole_my_command_item "$number")
    MOREMOLE_MENU_NOTICE="Removed \"$name\"."
}

# The MoreMole banner, used by the menu and the help screen in place of
# Mole's. The repository and tagline sit beside the logo when the window is
# wide enough, else under it.
show_brand_banner() {
    local -a art=(
        ' __  __                __  __       _'
        '|  \/  | ___  _ __ ___|  \/  | ___ | | ___'
        "| |\\/| |/ _ \\| '__/ _ \\ |\\/| |/ _ \\| |/ _ \\"
        '| |  | | (_) | | |  __/ |  | | (_) | |  __/'
        '|_|  |_|\___/|_|  \___|_|  |_|\___/|_|\___|'
    )
    local size cols line i
    size="$(_moremole_terminal_size)"
    cols="${size##* }"
    if ((cols >= 80)); then
        for ((i = 0; i < ${#art[@]}; i++)); do
            line="$(printf '%s%-43s%s' "$GREEN" "${art[i]}" "$NC")"
            case "$i" in
                2) line+="  ${BLUE}${MOREMOLE_REPO_URL}${NC}" ;;
                3) line+="  ${GREEN}${MOREMOLE_TAGLINE[0]}${NC}" ;;
                4) line+="  ${GREEN}${MOREMOLE_TAGLINE[1]}${NC}" ;;
            esac
            printf '%s\n' "$line"
        done
    else
        for line in "${art[@]}"; do
            printf '%s%s%s\n' "$GREEN" "$line" "$NC"
        done
        printf '%s%s%s\n' "$BLUE" "$MOREMOLE_REPO_URL" "$NC"
        printf '%s%s%s\n' "$GREEN" "${MOREMOLE_TAGLINE[0]}" "$NC" "$GREEN" "${MOREMOLE_TAGLINE[1]}" "$NC"
    fi
    printf '\n'
}

# Show a screen such as help or version, then come back to the menu.
moremole_show_and_return() {
    show_cursor
    clear
    "$@"
    _moremole_wait_to_return
    hide_cursor
    clear
}

# Mole's own help screen and update notice, kept so new commands still show.
if declare -F show_help > /dev/null; then
    eval "$(declare -f show_help | sed '1s/^show_help /_moremole_official_show_help /')"
fi
if declare -F read_update_message_cache > /dev/null; then
    eval "$(declare -f read_update_message_cache | sed '1s/^read_update_message_cache /_moremole_official_read_update_message_cache /')"
fi

# Width of the command column on the help screen: Mole's 28 plus the longer
# "moremole" name.
readonly MOREMOLE_HELP_COLUMN=34

# The help screen lists commands as "moremole <command>" instead of
# "mo <command>". Each command and option line is "  " + GREEN + the command
# padded to 28 + NC + the description; the column widens to fit the name.
# update --force and --nightly pick a Mole release channel, which MoreMole's
# update does not use, so they are left out.
show_help() {
    local line body command prefix="  ${GREEN}"
    _moremole_official_show_help | while IFS= read -r line || [[ -n "$line" ]]; do
        body="${line#"$prefix"}"
        if [[ "$line" == "$prefix"* && ("$body" == "mo" || "$body" == "mo "* || "$body" == "--"*) ]]; then
            command="${body:0:28}"
            command="${command%"${command##*[![:space:]]}"}"
            case "$command" in
                "mo update --force" | "mo update --nightly") continue ;;
            esac
            if [[ "$command" == "mo" || "$command" == "mo "* ]]; then
                command="moremole${command#mo}"
            fi
            printf '  %s%-*s%s\n' "$GREEN" "$MOREMOLE_HELP_COLUMN" "$command" "${body:28}" 2> /dev/null || return 0
        else
            printf '%s\n' "$line" 2> /dev/null || return 0
        fi
    done
}

# Update notices say "run moremole update", which runs the moremole update.
read_update_message_cache() {
    local message
    message="$(_moremole_official_read_update_message_cache "$@")"
    printf '%s' "${message//run mo update/run moremole update}"
}

# Mole's own version screen, kept so its system details stay current.
if declare -F show_version > /dev/null; then
    eval "$(declare -f show_version | sed '1s/^show_version /_moremole_official_show_version /')"
fi

# The version screen names MoreMole, credits Mole and its author, and says
# which moremole commit is running. The version line keeps the form
# "... Mole version X.Y.Z" that Mole's own scripts read the number from.
show_version() {
    local commit="" line
    if _moremole_is_git_folder; then
        commit="$(git -C "$SCRIPT_DIR" log -1 --format='%h, %cd' --date=short 2> /dev/null)" || commit=""
    fi
    _moremole_official_show_version | while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "Mole version "* ]]; then
            printf 'MoreMole version %s\n' "${line#Mole version }" 2> /dev/null || return 0
            printf 'Based on Mole by tw93: github.com/tw93/Mole\n' 2> /dev/null || return 0
            printf 'MoreMole: %s%s\n' "$MOREMOLE_REPO_URL" "${commit:+ ($commit)}" 2> /dev/null || return 0
        else
            printf '%s\n' "$line" 2> /dev/null || return 0
        fi
    done
}

# Mole's own updater, kept for copies that are not the moremole git folder.
if declare -F update_mole > /dev/null; then
    eval "$(declare -f update_mole | sed '1s/^update_mole /_moremole_official_update_mole /')"
fi

# Whether this copy runs from the root of a git folder holding the sync script.
_moremole_is_git_folder() {
    local toplevel="" here=""
    [[ -f "$SCRIPT_DIR/scripts/moremole-sync.sh" ]] || return 1
    toplevel="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2> /dev/null)" || return 1
    here="$(cd "$SCRIPT_DIR" && pwd -P)" || return 1
    [[ -n "$toplevel" && "$(cd "$toplevel" && pwd -P)" == "$here" ]]
}

# In the moremole git folder, installing the official release would erase
# moremole's changes, so update brings in Mole's latest changes with the sync
# script instead, which keeps them. Other copies update the way Mole does.
update_mole() {
    if ! _moremole_is_git_folder; then
        _moremole_official_update_mole "$@"
        return
    fi
    if [[ "${1:-false}" == "true" || "${2:-false}" == "true" ]]; then
        printf 'moremole updates by bringing in Mole'"'"'s latest changes; --force and --nightly are not used.\n\n'
    fi
    /bin/bash "$SCRIPT_DIR/scripts/moremole-sync.sh"
}
