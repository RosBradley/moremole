#!/bin/bash
# MoreMole: lets a command tell the menu that the user cancelled it, so the
# menu comes straight back instead of asking for Enter. The menu names an
# empty marker path in MOREMOLE_CANCEL_FILE for each command it runs; marked
# lines in the commands' cancel paths call moremole_note_cancel.

moremole_note_cancel() {
    local marker="${MOREMOLE_CANCEL_FILE:-}"
    [[ -n "$marker" && ! -e "$marker" ]] || return 0
    : > "$marker" 2> /dev/null || true
}
