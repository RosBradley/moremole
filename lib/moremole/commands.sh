#!/bin/bash
# MoreMole: fork-only commands for help and completions, listed after slim.
# lib/core/commands.sh sources this after defining MOLE_COMMANDS.

_moremole_commands=()
for _moremole_entry in "${MOLE_COMMANDS[@]}"; do
    _moremole_commands+=("$_moremole_entry")
    [[ "$_moremole_entry" == slim:* ]] && _moremole_commands+=("updates:Update apps, tools and macOS")
done
MOLE_COMMANDS=("${_moremole_commands[@]}")
unset _moremole_commands _moremole_entry
