#!/bin/bash
# moremole - Software updates.
# Lists updates for Homebrew apps and command-line tools, App Store apps,
# macOS, and apps installed without Homebrew that Homebrew has a newer
# version of; then installs the ones picked. moremole-updates-go does the
# scanning; this script shows the list and runs the updates.

set -euo pipefail

# User state and installed tools must never run with inherited root privileges.
if [[ "$EUID" -eq 0 ]]; then
    printf '%s\n' 'Run moremole without sudo; it asks for your password when an update needs it.' >&2
    exit 1
fi

# shellcheck disable=SC2154
# External variables set by menu_paginated.sh
declare MOLE_SELECTION_RESULT

export MOLE_CURRENT_COMMAND="${MOLE_CURRENT_COMMAND:-updates}"
# The scan already refreshed Homebrew; each upgrade need not do it again.
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"
source "$SCRIPT_DIR/../lib/ui/menu_paginated.sh"

UPDATES_HELPER="$SCRIPT_DIR/moremole-updates-go"
UPDATES_OPEN=/usr/bin/open
# Tests swap in a fake helper and a fake open, never outside test mode.
if [[ "${MOLE_TEST_MODE:-0}" == "1" ]]; then
    UPDATES_HELPER="${MOREMOLE_TEST_UPDATES_HELPER:-$UPDATES_HELPER}"
    UPDATES_OPEN="${MOREMOLE_TEST_OPEN:-$UPDATES_OPEN}"
fi
readonly UPDATES_SETTINGS_URL="x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
readonly UPDATES_FIELD_SEP=$'\x1f'
# The order kinds are listed and installed in.
readonly UPDATES_KIND_ORDER=(app takeover store tool macos macos-settings)

# Scan results, one index per update.
U_KIND=()
U_ID=()
U_NAME=()
U_FROM=()
U_TO=()
U_SEL=()
U_NOTE=()
NOTICE_KEYS=()
NOTICE_TEXTS=()
UPDATES_MACOS_PID=""

total_updated=0
total_failed=0
UPDATE_FAILURES=()
SETTINGS_ITEMS=()

cleanup() {
    if [[ -n "$UPDATES_MACOS_PID" ]]; then
        kill "$UPDATES_MACOS_PID" 2> /dev/null || true
    fi
    show_cursor
    cleanup_temp_files
}
trap cleanup EXIT
trap 'trap - EXIT; cleanup; exit 130' INT TERM

show_updates_help() {
    cat << 'EOF'
Usage: moremole updates [OPTIONS]

Find and install updates for Homebrew apps and command-line tools,
App Store apps (with mas), macOS, and apps installed without Homebrew
that Homebrew has a newer version of. You pick which to install;
Homebrew and App Store apps start selected.

Options:
  -n, --dry-run     List available updates without installing anything
  --debug           Show detailed logs
  -h, --help        Show this help message
EOF
}

# Program paths, found on PATH or in Homebrew's folders.
find_tool() {
    local name="$1" dir
    if command -v "$name" > /dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    for dir in /opt/homebrew/bin /usr/local/bin; do
        if [[ -x "$dir/$name" ]]; then
            printf '%s\n' "$dir/$name"
            return 0
        fi
    done
    return 1
}

# Read helper rows ("kind id name installed available selected note") from
# standard input into the scan arrays; notices go to the notice arrays.
load_update_rows() {
    local kind id name from to sel note
    while IFS="$UPDATES_FIELD_SEP" read -r kind id name from to sel note || [[ -n "${kind:-}" ]]; do
        [[ -n "$kind" ]] || continue
        if [[ "$kind" == "notice" ]]; then
            NOTICE_KEYS+=("$id")
            NOTICE_TEXTS+=("$note")
            continue
        fi
        U_KIND+=("$kind")
        U_ID+=("$id")
        U_NAME+=("$name")
        U_FROM+=("$from")
        U_TO+=("$to")
        U_SEL+=("$sel")
        U_NOTE+=("$note")
    done
}

run_helper() {
    "$UPDATES_HELPER" "$1" 2> /dev/null || true
}

has_notice() {
    local key
    for key in "${NOTICE_KEYS[@]+"${NOTICE_KEYS[@]}"}"; do
        [[ "$key" == "$1" ]] && return 0
    done
    return 1
}

drop_notice() {
    local -a keys=() texts=()
    local i
    for ((i = 0; i < ${#NOTICE_KEYS[@]}; i++)); do
        [[ "${NOTICE_KEYS[i]}" == "$1" ]] && continue
        keys+=("${NOTICE_KEYS[i]}")
        texts+=("${NOTICE_TEXTS[i]}")
    done
    NOTICE_KEYS=("${keys[@]+"${keys[@]}"}")
    NOTICE_TEXTS=("${texts[@]+"${texts[@]}"}")
}

# Put the scan arrays in UPDATES_KIND_ORDER, keeping each kind's own order.
order_update_rows() {
    local -a o_kind=() o_id=() o_name=() o_from=() o_to=() o_sel=() o_note=()
    local wanted i
    for wanted in "${UPDATES_KIND_ORDER[@]}"; do
        for ((i = 0; i < ${#U_KIND[@]}; i++)); do
            [[ "${U_KIND[i]}" == "$wanted" ]] || continue
            o_kind+=("${U_KIND[i]}")
            o_id+=("${U_ID[i]}")
            o_name+=("${U_NAME[i]}")
            o_from+=("${U_FROM[i]}")
            o_to+=("${U_TO[i]}")
            o_sel+=("${U_SEL[i]}")
            o_note+=("${U_NOTE[i]}")
        done
    done
    U_KIND=("${o_kind[@]+"${o_kind[@]}"}")
    U_ID=("${o_id[@]+"${o_id[@]}"}")
    U_NAME=("${o_name[@]+"${o_name[@]}"}")
    U_FROM=("${o_from[@]+"${o_from[@]}"}")
    U_TO=("${o_to[@]+"${o_to[@]}"}")
    U_SEL=("${o_sel[@]+"${o_sel[@]}"}")
    U_NOTE=("${o_note[@]+"${o_note[@]}"}")
}

spin() {
    [[ -t 1 ]] && start_inline_spinner "$1"
    return 0
}

unspin() {
    [[ -t 1 ]] && stop_inline_spinner
    return 0
}

# Check every source. macOS takes longest, so it runs in the background
# while the others are checked.
scan_updates() {
    local macos_out
    macos_out=$(create_temp_file)
    "$UPDATES_HELPER" macos > "$macos_out" 2> /dev/null &
    UPDATES_MACOS_PID=$!

    spin "Checking Homebrew apps and tools..."
    load_update_rows < <(run_helper brew)
    unspin
    spin "Checking App Store apps..."
    load_update_rows < <(run_helper store)
    unspin
    if ! has_notice homebrew-missing; then
        spin "Checking apps installed without Homebrew..."
        load_update_rows < <(run_helper takeover)
        unspin
    fi
    spin "Checking macOS updates..."
    wait "$UPDATES_MACOS_PID" 2> /dev/null || true
    UPDATES_MACOS_PID=""
    load_update_rows < "$macos_out"
    unspin

    order_update_rows
}

# Offer to install mas, the tool that checks App Store apps, then check them.
offer_mas_install() {
    has_notice mas-missing || return 0
    has_notice homebrew-missing && return 0
    [[ "${MOLE_DRY_RUN:-0}" == "1" || ! -t 0 || ! -t 1 ]] && return 0
    local brew key
    brew=$(find_tool brew) || return 0

    echo -e "${GRAY}App Store apps need mas, a free tool, to be checked.${NC}"
    echo -ne "${PURPLE}${ICON_ARROW}${NC} Install mas with Homebrew?  ${GREEN}Enter${NC} install, ${GRAY}ESC${NC} skip: "
    IFS= read -r -s -n1 key || key="skip"
    printf '\n'
    case "$key" in
        "" | $'\n' | $'\r') ;;
        *) return 0 ;;
    esac
    if "$brew" install mas; then
        drop_notice mas-missing
        spin "Checking App Store apps..."
        load_update_rows < <(run_helper store)
        unspin
        order_update_rows
    fi
    printf '\n'
}

print_notices() {
    local i
    for ((i = 0; i < ${#NOTICE_KEYS[@]}; i++)); do
        echo -e "${YELLOW}${ICON_WARNING}${NC} $(mole_terminal_safe_text "${NOTICE_TEXTS[i]}")"
    done
    [[ ${#NOTICE_KEYS[@]} -eq 0 ]] || printf '\n'
}

kind_label() {
    case "$1" in
        app) printf 'Homebrew' ;;
        takeover) printf 'Move to Homebrew' ;;
        store) printf 'App Store' ;;
        tool) printf 'Command-line tool' ;;
        macos | macos-settings) printf 'macOS' ;;
        *) printf '%s' "$1" ;;
    esac
}

version_text() {
    local from="${U_FROM[$1]}" to="${U_TO[$1]}"
    if [[ -n "$from" && -n "$to" ]]; then
        printf '%s → %s' "$from" "$to"
    else
        printf '%s' "$to"
    fi
}

# Display width; get_display_width counts the one-cell arrow as two.
text_width() {
    get_display_width "${1//→/-}"
}

# Cut text wider than $2 cells to fit, ending in "...". Callers run it in
# $(...), so the locale change stays here.
cut_width() {
    local text="$1" max="$2"
    if (($(text_width "$text") <= max)); then
        printf '%s\n' "$text"
        return 0
    fi
    local LC_ALL=en_US.UTF-8
    # Every character takes at least one cell, so start there and step down.
    local k=$((max - 3))
    ((k <= ${#text})) || k=${#text}
    while ((k > 0)) && (($(text_width "${text:0:k}") + 3 > max)); do
        k=$((k - 1))
    done
    printf '%s...\n' "${text:0:k}"
}

# Pad or cut text to a display width.
fit_width() {
    local text width="$2"
    text=$(cut_width "$1" "$width")
    printf '%s%*s' "$text" "$((width - $(text_width "$text")))" ""
}

# Column widths that fit the terminal: names up to 32 cells, versions up
# to 26, both narrower when the terminal is.
UPDATES_NAME_W=10
UPDATES_VER_W=10
UPDATES_ROW_W=76
measure_columns() {
    local columns="${COLUMNS:-$(tput cols 2> /dev/null || echo 80)}"
    [[ "$columns" =~ ^[0-9]+$ && "$columns" -gt 0 ]] || columns=80
    # The menu puts four cells before each row.
    UPDATES_ROW_W=$((columns - 4))
    ((UPDATES_ROW_W >= 20)) || UPDATES_ROW_W=20
    UPDATES_NAME_W=10
    UPDATES_VER_W=10
    local i width
    for ((i = 0; i < ${#U_KIND[@]}; i++)); do
        width=$(text_width "$(mole_terminal_safe_text "${U_NAME[i]}")")
        ((width <= UPDATES_NAME_W)) || UPDATES_NAME_W=$width
        width=$(text_width "$(version_text "$i")")
        ((width <= UPDATES_VER_W)) || UPDATES_VER_W=$width
    done
    ((UPDATES_NAME_W <= 32)) || UPDATES_NAME_W=32
    ((UPDATES_VER_W <= 26)) || UPDATES_VER_W=26
    # Leave room for the source column on narrow terminals.
    local room=$((UPDATES_ROW_W - 14))
    ((UPDATES_NAME_W + UPDATES_VER_W <= room)) || UPDATES_NAME_W=$((room - UPDATES_VER_W))
    if ((UPDATES_NAME_W < 8)); then
        UPDATES_NAME_W=8
        UPDATES_VER_W=$((room - UPDATES_NAME_W))
        ((UPDATES_VER_W >= 4)) || UPDATES_VER_W=4
    fi
}

# One display row per update: name, versions, then where it comes from and
# any note, cut to the terminal width. Sources and notes are plain ASCII.
update_row_text() {
    local i="$1" tag room
    tag=$(kind_label "${U_KIND[i]}")
    [[ -z "${U_NOTE[i]}" ]] || tag+=" (${U_NOTE[i]})"
    tag=$(mole_terminal_safe_text "$tag")
    room=$((UPDATES_ROW_W - UPDATES_NAME_W - UPDATES_VER_W - 4))
    ((${#tag} <= room)) || tag="${tag:0:$((room - 3))}..."
    printf '%s  %s  %s' "$(fit_width "$(mole_terminal_safe_text "${U_NAME[i]}")" "$UPDATES_NAME_W")" \
        "$(fit_width "$(version_text "$i")" "$UPDATES_VER_W")" "$tag"
}

# Without a terminal, or with --dry-run, list the updates and stop.
print_update_list() {
    measure_columns
    local i marker
    echo -e "${PURPLE_BOLD}${#U_KIND[@]} updates available${NC}"
    for ((i = 0; i < ${#U_KIND[@]}; i++)); do
        marker="○"
        [[ "${U_SEL[i]}" == "1" ]] && marker="●"
        printf '  %s %s\n' "$marker" "$(update_row_text "$i")"
    done
    printf '\n%s● starts selected, ○ starts unselected.%s\n' "$GRAY" "$NC"
}

select_updates() {
    measure_columns
    local -a rows=() preselected=()
    local i
    for ((i = 0; i < ${#U_KIND[@]}; i++)); do
        rows+=("$(update_row_text "$i")")
        [[ "${U_SEL[i]}" == "1" ]] && preselected+=("$i")
    done
    MOLE_PRESELECTED_INDICES=$(
        IFS=','
        printf '%s' "${preselected[*]+"${preselected[*]}"}"
    )
    export MOLE_PRESELECTED_INDICES
    export _MOLE_MENU_SELECT_ALL=true

    MOLE_SELECTION_RESULT=""
    local rc=0
    paginated_multi_select "Select updates to install" "${rows[@]}" || rc=$?
    unset MOLE_PRESELECTED_INDICES _MOLE_MENU_SELECT_ALL
    [[ $rc -eq 0 && -n "$MOLE_SELECTION_RESULT" ]]
}

confirm_updates() {
    local -a indices=("$@")
    local idx has_app=false has_takeover=false has_store=false has_macos=false has_settings=false
    echo -e "${PURPLE_BOLD}Updates to install:${NC}"
    for idx in "${indices[@]}"; do
        printf '  %s%s%s %s %s%s · %s%s\n' "$GREEN" "$ICON_SUCCESS" "$NC" \
            "$(mole_terminal_safe_text "${U_NAME[idx]}")" "$GRAY" "$(version_text "$idx")" "$(kind_label "${U_KIND[idx]}")" "$NC"
        case "${U_KIND[idx]}" in
            app) has_app=true ;;
            takeover) has_takeover=true ;;
            store) has_store=true ;;
            macos) has_macos=true ;;
            macos-settings) has_settings=true ;;
        esac
    done
    echo ""
    if [[ "$has_app" == "true" || "$has_takeover" == "true" ]]; then
        echo -e "${GRAY}Apps being updated may quit; save your work in them first.${NC}"
    fi
    if [[ "$has_takeover" == "true" ]]; then
        echo -e "${GRAY}Apps moved to Homebrew are replaced by Homebrew's copy; their settings stay.${NC}"
    fi
    if [[ "$has_store" == "true" ]]; then
        echo -e "${GRAY}App Store updates may ask for your password.${NC}"
    fi
    if [[ "$has_macos" == "true" ]]; then
        echo -e "${GRAY}macOS updates ask for your password.${NC}"
    fi
    if [[ "$has_settings" == "true" ]]; then
        echo -e "${GRAY}Updates that restart the Mac open Software Update in System Settings.${NC}"
    fi
    echo -ne "${PURPLE}${ICON_ARROW}${NC} Install ${#indices[@]} updates  ${GREEN}Enter${NC} confirm, ${GRAY}ESC${NC} cancel: "

    local confirm
    if ! IFS= read -r -s -n1 confirm; then
        printf '\n'
        return 1
    fi
    case "$confirm" in
        "" | $'\n' | $'\r')
            printf '\r\033[K\n'
            return 0
            ;;
    esac
    printf '\n'
    return 1
}

record_update() {
    local idx="$1" ok="$2" reason="${3:-}"
    local name="${U_NAME[idx]}"
    if [[ "$ok" == "true" ]]; then
        total_updated=$((total_updated + 1))
        log_operation "$MOLE_CURRENT_COMMAND" "REBUILT" "$name" "updated to ${U_TO[idx]:-latest}, $(kind_label "${U_KIND[idx]}")"
    else
        total_failed=$((total_failed + 1))
        UPDATE_FAILURES+=("$name${reason:+: $reason}")
        log_operation "$MOLE_CURRENT_COMMAND" "FAILED" "$name" "${reason:-update failed}"
    fi
}

# Install one update, with the tool's own output shown live.
install_update() {
    local idx="$1" kind="${U_KIND[$1]}" id="${U_ID[$1]}"
    local -a cmd=()
    local tool

    case "$kind" in
        macos-settings)
            SETTINGS_ITEMS+=("${U_NAME[idx]}")
            return 0
            ;;
        app | tool | takeover)
            if ! tool=$(find_tool brew); then
                record_update "$idx" false "Homebrew not found"
                return 0
            fi
            case "$kind" in
                app) cmd=("$tool" upgrade --cask --greedy "$id") ;;
                tool) cmd=("$tool" upgrade --formula "$id") ;;
                takeover) cmd=("$tool" install --cask --force "$id") ;;
            esac
            ;;
        store)
            if ! tool=$(find_tool mas); then
                record_update "$idx" false "mas not found"
                return 0
            fi
            cmd=("$tool" upgrade "$id")
            ;;
        macos)
            if ! ensure_sudo_session "Installing macOS updates needs your password"; then
                record_update "$idx" false "needs your password"
                return 0
            fi
            cmd=(sudo -n /usr/sbin/softwareupdate --install "$id")
            ;;
        *)
            record_update "$idx" false "unknown kind $kind"
            return 0
            ;;
    esac

    echo -e "${BLUE}${ICON_ARROW} $(mole_terminal_safe_text "${U_NAME[idx]}")${NC} ${GRAY}$(version_text "$idx")${NC}"
    if "${cmd[@]}"; then
        record_update "$idx" true
    else
        record_update "$idx" false "${cmd[0]##*/} reported an error"
    fi
    printf '\n'
}

install_updates() {
    local -a indices=("$@")
    local idx
    log_operation_session_start "$MOLE_CURRENT_COMMAND"
    for idx in "${indices[@]}"; do
        [[ "$idx" =~ ^[0-9]+$ && $idx -lt ${#U_KIND[@]} ]] || continue
        install_update "$idx"
    done
    if [[ ${#SETTINGS_ITEMS[@]} -gt 0 ]]; then
        "$UPDATES_OPEN" "$UPDATES_SETTINGS_URL" 2> /dev/null || true
        local item
        for item in "${SETTINGS_ITEMS[@]}"; do
            log_operation "$MOLE_CURRENT_COMMAND" "SKIPPED" "$item" "opened Software Update in System Settings"
        done
    fi
    log_operation_session_end "$MOLE_CURRENT_COMMAND" "$total_updated" 0
}

show_updates_summary() {
    local heading="Updates installed"
    local -a details=()
    if [[ $total_failed -gt 0 ]]; then
        heading="Some updates did not install"
    elif [[ $total_updated -eq 0 ]]; then
        heading="Finish in System Settings"
    fi
    if [[ $total_updated -gt 0 ]]; then
        details+=("Updated ${GREEN}$total_updated${NC}")
    elif [[ ${#SETTINGS_ITEMS[@]} -eq 0 ]]; then
        details+=("Nothing was updated")
    fi
    local item
    for item in "${UPDATE_FAILURES[@]+"${UPDATE_FAILURES[@]}"}"; do
        details+=("${ICON_WARNING} Not updated: $(mole_terminal_safe_text "$item")")
    done
    if [[ ${#SETTINGS_ITEMS[@]} -gt 0 ]]; then
        local names="${SETTINGS_ITEMS[0]}"
        for item in "${SETTINGS_ITEMS[@]:1}"; do
            names+=", $item"
        done
        details+=("Opened Software Update for: $(mole_terminal_safe_text "$names")")
    fi
    print_summary_block "$heading" "${details[@]}"
    printf '\n'
}

main() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            "--help" | "-h")
                show_updates_help
                return 0
                ;;
            "--debug") export MO_DEBUG=1 ;;
            "--dry-run" | "-n") export MOLE_DRY_RUN=1 ;;
            *)
                echo "Unknown option: $arg" >&2
                echo "Use 'moremole updates --help' for supported options." >&2
                return 1
                ;;
        esac
    done

    if [[ ! -x "$UPDATES_HELPER" ]]; then
        echo -e "${RED}${ICON_ERROR}${NC} Software updates needs building first. In your moremole folder, run: make build" >&2
        return 1
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}, nothing will be installed"
        printf '\n'
    fi

    scan_updates
    offer_mas_install
    print_notices

    if [[ ${#U_KIND[@]} -eq 0 ]]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Everything is up to date"
        return 0
    fi

    # Without a terminal there is nobody to choose: list and stop.
    if [[ "${MOLE_DRY_RUN:-0}" == "1" || ! -t 0 || ! -t 1 ]]; then
        print_update_list
        if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
            printf 'Run moremole updates in a terminal to choose updates.\n'
        fi
        return 0
    fi

    hide_cursor
    if ! select_updates; then
        show_cursor
        printf '\n'
        return 0
    fi
    show_cursor

    local -a indices=()
    IFS=',' read -ra indices <<< "$MOLE_SELECTION_RESULT"
    confirm_updates "${indices[@]}" || return 0

    install_updates "${indices[@]}"
    show_updates_summary
    [[ $total_failed -eq 0 ]]
}

if [[ "${MOLE_TEST_MODE:-0}" != "1" ]]; then
    main "$@"
fi
