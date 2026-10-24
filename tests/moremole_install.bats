#!/usr/bin/env bats
# moremole: scripts/moremole-install.sh sets up the moremole and mm commands.

load helpers/common

setup_file() {
	mole_test_setup_home "moremole-install"
}

teardown_file() {
	mole_test_teardown_home
}

# A fake moremole folder holding the installer, already built, and a brew
# stub that reports whether Mole is installed ($BREW_HAS_MOLE) and logs calls.
setup() {
	rm -rf "${HOME:?}/home" "${HOME:?}/repo" "${HOME:?}/stubs" # SAFE: test-owned mktemp HOME under tests/tmp-*
	FAKE_HOME="$HOME/home"
	REPO="$HOME/repo"
	STUBS="$HOME/stubs"
	mkdir -p "$FAKE_HOME" "$REPO/scripts" "$REPO/lib/moremole" "$REPO/bin" "$STUBS"
	cp "$PROJECT_ROOT/scripts/moremole-install.sh" "$REPO/scripts/"
	printf '#!/bin/bash\necho MOREMOLE\n' > "$REPO/mole"
	: > "$REPO/lib/moremole/menu.sh"
	printf '#!/bin/bash\n' > "$REPO/bin/analyze-go"
	printf '#!/bin/bash\n' > "$REPO/bin/status-go"
	chmod +x "$REPO/mole" "$REPO/bin/analyze-go" "$REPO/bin/status-go"
	cat > "$STUBS/brew" << 'EOF'
#!/bin/bash
echo "brew $*" >> "$BREW_LOG"
if [[ "$1" == "list" ]]; then
    [[ "${BREW_HAS_MOLE:-0}" == "1" ]]
fi
EOF
	chmod +x "$STUBS/brew"
	BREW_LOG="$HOME/brew.log"
	rm -f "$BREW_LOG"
	export FAKE_HOME REPO STUBS BREW_LOG
}

install() {
	env HOME="$FAKE_HOME" PATH="$STUBS:/usr/bin:/bin" BREW_LOG="$BREW_LOG" \
		BREW_HAS_MOLE="${BREW_HAS_MOLE:-0}" /bin/bash "$REPO/scripts/moremole-install.sh" < /dev/null
}

@test "installer links moremole and mm to the folder and adds PATH once" {
	run install
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[ "$(readlink "$FAKE_HOME/.local/bin/moremole")" = "$REPO/mole" ] || return 1
	[ "$(readlink "$FAKE_HOME/.local/bin/mm")" = "$REPO/mole" ] || return 1
	[ "$("$FAKE_HOME/.local/bin/mm")" = "MOREMOLE" ] || return 1
	[[ "$output" == *"Open a new Terminal window"* ]] || return 1
	[[ "$output" == *"To set up Tab completion for moremole and mm, run: moremole completion"* ]] || return 1

	run install
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	# shellcheck disable=SC2016  # Literal ~/.zshrc text, not an expansion.
	[ "$(grep -c 'export PATH="$HOME/.local/bin:$PATH"' "$FAKE_HOME/.zshrc")" -eq 1 ]
}

@test "installer replaces the old mm alias and keeps every other line" {
	# shellcheck disable=SC2016  # Literal ~/.zshrc text, not an expansion.
	printf '# mine\nalias ll="ls -l"\nalias mm="$HOME/Developer/moremole/mole"\nexport EDITOR=vim\n' > "$FAKE_HOME/.zshrc"
	run install
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *'Removed the old "alias mm=" line'* ]] || return 1
	! grep -q 'alias mm=' "$FAKE_HOME/.zshrc" || return 1
	[[ "$(cat "$FAKE_HOME/.zshrc")" == $'# mine\nalias ll="ls -l"\nexport EDITOR=vim\n\n# moremole'* ]]
}

@test "installer never replaces a real file where a link would go" {
	mkdir -p "$FAKE_HOME/.local/bin"
	printf 'mine\n' > "$FAKE_HOME/.local/bin/mm"
	run install
	[ "$status" -ne 0 ] || return 1
	[[ "$output" == *"already exists and is not a link"* ]] || return 1
	[ "$(cat "$FAKE_HOME/.local/bin/mm")" = "mine" ]
}

@test "installer only suggests removing a Homebrew Mole without a terminal" {
	BREW_HAS_MOLE=1 run install
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"installed with Homebrew"*"To remove it, run: brew uninstall mole"* ]] || return 1
	! grep -q "uninstall" "$BREW_LOG" || return 1
	# A kept Homebrew Mole is not reported a second time as some other install.
	[[ "$output" != *"not installed with Homebrew"* ]]
}

@test "installer warns that mo remove would trash the settings of another Mole" {
	printf '#!/bin/bash\n' > "$STUBS/mo"
	chmod +x "$STUBS/mo"
	run install
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
	[[ "$output" == *"Another Mole is still installed: $STUBS/mo"* ]] || return 1
	[[ "$output" == *'Do not remove it with "mo remove"'* ]]
}
