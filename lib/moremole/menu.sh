#!/bin/bash
# moremole: the main menu lists every command from the More screen plus the
# user's own commands. Each command gets one row, with its preview and other
# variants beside it.
# Sourced by the mole router after lib/manage/update.sh. Everything moremole
# changes lives here so upstream Mole updates merge with few conflicts.

set -euo pipefail

if [[ -n "${MOREMOLE_MENU_LOADED:-}" ]]; then
    return 0
fi
readonly MOREMOLE_MENU_LOADED=1

MOREMOLE_MY_COMMANDS_FILE="$HOME/.config/mole/my_commands"

# Every command from the More screen, one menu row each. Cells are separated
# by ";" and hold label|kind|args. "mole" runs bin/<first word>.sh with the
# remaining words; "update" runs update_mole.
readonly MOREMOLE_BUILTIN_ROWS=(
    "Clean|mole|clean;Preview|mole|clean --dry-run;Protected caches|mole|clean --whitelist"
    "Uninstall|mole|uninstall;Preview|mole|uninstall --dry-run"
    "Optimize|mole|optimize;Preview|mole|optimize --dry-run;Protected items|mole|optimize --whitelist"
    "Analyze|mole|analyze;External drives|mole|analyze /Volumes"
    "Status|mole|status"
    "History|mole|history;Export|mole|history --json"
    "Purge|mole|purge;Preview|mole|purge --dry-run;Choose folders|mole|purge --paths"
    "Installer files|mole|installer;Preview|mole|installer --dry-run"
    "Slim Intel code|mole|slim;Preview|mole|slim --dry-run"
    "Touch ID|mole|touchid;Preview|mole|touchid enable --dry-run"
    "Shell completion|mole|completion;Preview|mole|completion --dry-run"
    "Update from Mole|update|"
)
readonly MOREMOLE_EDIT_LABEL="Edit my commands..."
# The editor and the user's commands share rows, this many cells per row.
readonly MOREMOLE_MENU_COLUMNS=3

# Lines show_main_menu prints around the items: a blank line, the five-line
# banner and a blank line above; a blank line, the controls and a blank line
# below; plus the row the cursor rests on so the last line cannot scroll.
readonly MOREMOLE_MENU_OVERHEAD=11

# One entry per menu item, in reading order (row by row, left to right).
declare -a MOREMOLE_MENU_LABELS=()
declare -a MOREMOLE_MENU_KINDS=()
declare -a MOREMOLE_MENU_ARGS=()
declare -a MOREMOLE_MENU_COLS=()
# One entry per row: index of its first item and its number of items.
declare -a MOREMOLE_MENU_ROW_START=()
declare -a MOREMOLE_MENU_ROW_LEN=()
declare -a MOREMOLE_MY_NAMES=()
declare -a MOREMOLE_MY_COMMANDS=()
# File line number of each of the user's commands.
declare -a MOREMOLE_MY_LINES=()
MOREMOLE_MENU_TOP_ROW=0

# Layout, set by _moremole_menu_layout.
declare -a MOREMOLE_LAYOUT_WIDTHS=()
MOREMOLE_LAYOUT_MAX_LABEL=1
MOREMOLE_LAYOUT_VISIBLE_ROWS=1

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

# Append one item at column $4 of the current last row ($4 = 0 starts a row).
_moremole_add_item() {
    local column="$4"
    if [[ "$column" -eq 0 ]]; then
        MOREMOLE_MENU_ROW_START+=("${#MOREMOLE_MENU_LABELS[@]}")
        MOREMOLE_MENU_ROW_LEN+=(0)
    fi
    local last_row=$((${#MOREMOLE_MENU_ROW_LEN[@]} - 1))
    MOREMOLE_MENU_ROW_LEN[last_row]=$((column + 1))
    MOREMOLE_MENU_LABELS+=("$1")
    MOREMOLE_MENU_KINDS+=("$2")
    MOREMOLE_MENU_ARGS+=("$3")
    MOREMOLE_MENU_COLS+=("$column")
}

moremole_load_menu_items() {
    MOREMOLE_MENU_LABELS=()
    MOREMOLE_MENU_KINDS=()
    MOREMOLE_MENU_ARGS=()
    MOREMOLE_MENU_COLS=()
    MOREMOLE_MENU_ROW_START=()
    MOREMOLE_MENU_ROW_LEN=()

    local spec cell rest column
    local -a cells=()
    for spec in "${MOREMOLE_BUILTIN_ROWS[@]}"; do
        IFS=';' read -r -a cells <<< "$spec"
        column=0
        for cell in "${cells[@]}"; do
            rest="${cell#*|}"
            _moremole_add_item "${cell%%|*}" "${rest%%|*}" "${rest#*|}" "$column"
            column=$((column + 1))
        done
    done

    # The editor comes first, then the user's commands fill the rows after it.
    _moremole_add_item "$MOREMOLE_EDIT_LABEL" "edit" "" 0
    moremole_read_my_commands
    local i
    column=1
    for ((i = 0; i < ${#MOREMOLE_MY_NAMES[@]}; i++)); do
        ((column < MOREMOLE_MENU_COLUMNS)) || column=0
        _moremole_add_item "${MOREMOLE_MY_NAMES[i]}" "custom" "${MOREMOLE_MY_COMMANDS[i]}" "$column"
        column=$((column + 1))
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
    overhead=$MOREMOLE_MENU_OVERHEAD
    if [[ -n "${MAIN_MENU_UPDATE_MESSAGE:-}" ]]; then
        overhead=$((overhead + 2))
    fi
    MOREMOLE_LAYOUT_VISIBLE_ROWS=$((term_lines - overhead))
    # A list taller than the screen scrolls, and gives one row to the hint.
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

# Draw the items with $1 (1-based) selected, one terminal line per row.
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

    local row column index label line pad
    for ((row = MOREMOLE_MENU_TOP_ROW; row < MOREMOLE_MENU_TOP_ROW + visible; row++)); do
        line=""
        for ((column = 0; column < MOREMOLE_MENU_ROW_LEN[row]; column++)); do
            index=$((MOREMOLE_MENU_ROW_START[row] + column))
            label="${MOREMOLE_MENU_LABELS[index]}"
            if ((${#label} > max)); then
                label="${label:0:$((max - 3))}..."
            fi
            if ((index + 1 == selected)); then
                line+="${CYAN}${ICON_ARROW} ${label}${NC}"
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

    if ((visible < rows)); then
        local hint
        if ((MOREMOLE_MENU_TOP_ROW == 0)); then
            hint="↓ more below"
        elif ((MOREMOLE_MENU_TOP_ROW + visible >= rows)); then
            hint="↑ more above"
        else
            hint="↑↓ more above and below"
        fi
        printf '\r\033[2K  %s%s%s\n' "$GRAY" "$hint" "$NC"
    fi
}

# Print the item number (1-based) reached from $1 by key $2. Up and down keep
# the column where the next row has one, else take that row's last item.
moremole_menu_move() {
    local current="$1" key="$2"
    ((${#MOREMOLE_MENU_LABELS[@]} > 0)) || moremole_load_menu_items

    local count=${#MOREMOLE_MENU_LABELS[@]}
    local rows=${#MOREMOLE_MENU_ROW_START[@]}
    local index=$((current - 1))
    ((index >= 0 && index < count)) || index=0
    local row column target
    row=$(_moremole_item_row "$index")
    column=${MOREMOLE_MENU_COLS[index]}

    case "$key" in
        LEFT) ((column == 0)) || index=$((index - 1)) ;;
        RIGHT) ((column + 1 >= MOREMOLE_MENU_ROW_LEN[row])) || index=$((index + 1)) ;;
        UP | DOWN)
            if [[ "$key" == "UP" ]]; then
                target=$((row - 1))
            else
                target=$((row + 1))
            fi
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

# Run item $1 (1-based). Commands replace the menu, as in the original menu;
# the editor returns so the menu can redraw with the changes.
moremole_menu_activate() {
    local index=$(($1 - 1))
    local kind="${MOREMOLE_MENU_KINDS[index]:-}"
    local args="${MOREMOLE_MENU_ARGS[index]:-}"

    case "$kind" in
        mole)
            local -a words=()
            read -r -a words <<< "$args"
            show_cursor
            drain_pending_input 0.1
            if ((${#words[@]} > 1)); then
                run_mole_command "$SCRIPT_DIR/bin/${words[0]}.sh" "${words[@]:1}"
            else
                run_mole_command "$SCRIPT_DIR/bin/${words[0]}.sh"
            fi
            ;;
        update)
            show_cursor
            clear
            update_mole false false
            exit 0
            ;;
        custom)
            local shell="${SHELL:-/bin/bash}"
            [[ -x "$shell" ]] || shell=/bin/bash
            show_cursor
            drain_pending_input 0.1
            clear
            printf '%s%s%s\n%s$ %s%s\n\n' "$BLUE" "${MOREMOLE_MENU_LABELS[index]}" "$NC" "$GRAY" "$args" "$NC"
            run_mole_command "$shell" -c "$args"
            ;;
        edit)
            moremole_edit_my_commands
            moremole_load_menu_items
            ;;
    esac
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

# Remove line $1 of the file and keep every other line as it is.
_moremole_delete_file_line() {
    local target="$1" line number=0
    local -a kept=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        number=$((number + 1))
        if ((number != target)); then
            kept+=("$line")
        fi
    done < "$MOREMOLE_MY_COMMANDS_FILE"
    if ((${#kept[@]} > 0)); then
        printf '%s\n' "${kept[@]}" > "$MOREMOLE_MY_COMMANDS_FILE"
    else
        : > "$MOREMOLE_MY_COMMANDS_FILE"
    fi
}

_moremole_add_my_command() {
    local name="" command=""
    printf '\nName shown in the menu: '
    IFS= read -r name || return 0
    name="$(_moremole_trim "${name//$'\t'/ }")"
    if [[ -z "$name" ]]; then
        MOREMOLE_EDIT_MESSAGE="Nothing added: the name was empty."
        return 0
    fi
    printf 'Command to run: '
    IFS= read -r command || return 0
    command="$(_moremole_trim "$command")"
    if [[ -z "$command" ]]; then
        MOREMOLE_EDIT_MESSAGE="Nothing added: the command was empty."
        return 0
    fi

    _moremole_append_my_command "$name" "$command"
    MOREMOLE_EDIT_MESSAGE="Added \"$name\" to the menu."
}

_moremole_remove_my_command() {
    local count=${#MOREMOLE_MY_NAMES[@]}
    if ((count == 0)); then
        MOREMOLE_EDIT_MESSAGE="There are no commands to remove."
        return 0
    fi

    local choice="" answer=""
    printf '\nNumber to remove (Enter to cancel): '
    IFS= read -r choice || return 0
    choice="$(_moremole_trim "$choice")"
    [[ -n "$choice" ]] || return 0
    if [[ ! "$choice" =~ ^[0-9]{1,6}$ ]]; then
        MOREMOLE_EDIT_MESSAGE="There is no command number $choice."
        return 0
    fi
    # Base 10 explicitly: arithmetic would read "08" as invalid octal.
    choice=$((10#$choice))
    if ((choice < 1 || choice > count)); then
        MOREMOLE_EDIT_MESSAGE="There is no command number $choice."
        return 0
    fi

    local name="${MOREMOLE_MY_NAMES[choice - 1]}"
    printf 'Remove "%s"? (y/N): ' "$name"
    IFS= read -r answer || return 0
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        MOREMOLE_EDIT_MESSAGE="Nothing removed."
        return 0
    fi

    _moremole_delete_file_line "${MOREMOLE_MY_LINES[choice - 1]}"
    MOREMOLE_EDIT_MESSAGE="Removed \"$name\"."
}

# Plain line-based screen for adding and removing the user's commands.
moremole_edit_my_commands() {
    local choice="" i
    MOREMOLE_EDIT_MESSAGE=""
    show_cursor
    drain_pending_input 0.1

    while true; do
        moremole_read_my_commands
        clear
        printf '%sMy commands%s\n\n' "$BLUE" "$NC"
        if ((${#MOREMOLE_MY_NAMES[@]} == 0)); then
            printf '  %sNone yet.%s\n' "$GRAY" "$NC"
        fi
        for ((i = 0; i < ${#MOREMOLE_MY_NAMES[@]}; i++)); do
            printf '  %d. %s  %s%s%s\n' "$((i + 1))" "${MOREMOLE_MY_NAMES[i]}" "$GRAY" "${MOREMOLE_MY_COMMANDS[i]}" "$NC"
        done
        if [[ -n "$MOREMOLE_EDIT_MESSAGE" ]]; then
            printf '\n%s%s%s\n' "$GREEN" "$MOREMOLE_EDIT_MESSAGE" "$NC"
            MOREMOLE_EDIT_MESSAGE=""
        fi
        printf '\n  A  Add a command\n  R  Remove a command\n  Enter  Back to the menu\n\nChoice: '
        IFS= read -r choice || break
        case "$(_moremole_trim "$choice")" in
            a | A) _moremole_add_my_command ;;
            r | R) _moremole_remove_my_command ;;
            "") break ;;
            *) MOREMOLE_EDIT_MESSAGE="Type A, R, or just press Enter." ;;
        esac
    done

    clear
    hide_cursor
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
