#!/bin/bash
# moremole: bring in the latest Mole changes from tw93/Mole.
#
# Updates main to match upstream (fast-forward only), merges main into the
# moremole branch, and pushes both to origin. Stops before changing anything
# if there are uncommitted changes or if main has commits upstream doesn't.
#
# Usage: bash scripts/moremole-sync.sh

set -euo pipefail

readonly PERSONAL_BRANCH="moremole"
readonly MIRROR_BRANCH="main"
readonly UPSTREAM_REMOTE="upstream"

die() {
    printf 'Stopped: %s\n' "$1" >&2
    exit 1
}

# Everything runs inside main so bash has read the whole script before git
# touches the working tree.
main() {
    local repo_root
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    cd "$repo_root"

    git remote get-url "$UPSTREAM_REMOTE" > /dev/null 2>&1 ||
        die "no '$UPSTREAM_REMOTE' remote. Add it with: git remote add $UPSTREAM_REMOTE https://github.com/tw93/Mole.git"

    local current_branch
    current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
    [[ "$current_branch" == "$PERSONAL_BRANCH" ]] ||
        die "you're on '${current_branch:-a detached HEAD}'. Run: git checkout $PERSONAL_BRANCH"

    [[ -z "$(git status --porcelain)" ]] ||
        die "there are uncommitted changes. Commit them first (git status shows them)."

    local old_main
    old_main="$(git rev-parse "$MIRROR_BRANCH")"

    printf 'Fetching %s...\n' "$UPSTREAM_REMOTE"
    # Updating main through fetch refuses anything but a fast-forward, so a
    # commit made on main by mistake stops the sync instead of being merged.
    if ! git fetch "$UPSTREAM_REMOTE" "$MIRROR_BRANCH:$MIRROR_BRANCH"; then
        die "'$MIRROR_BRANCH' has commits that aren't in $UPSTREAM_REMOTE/$MIRROR_BRANCH. It should only ever mirror upstream; ask for help before going further."
    fi

    local new_main
    new_main="$(git rev-parse "$MIRROR_BRANCH")"

    if [[ "$old_main" == "$new_main" ]]; then
        printf 'Mole has no new changes since your last sync.\n'
    else
        local count
        count="$(git rev-list --count "$old_main..$new_main")"
        printf '%s new commit(s) from Mole.\n' "$count"
    fi

    git push origin "$MIRROR_BRANCH"

    if git merge-base --is-ancestor "$MIRROR_BRANCH" HEAD; then
        printf '%s already has everything from %s.\n' "$PERSONAL_BRANCH" "$MIRROR_BRANCH"
    elif ! git merge --no-edit "$MIRROR_BRANCH"; then
        printf '\nThe merge stopped on a conflict: Mole changed the same lines as moremole.\n' >&2
        printf 'Files to look at:\n' >&2
        git diff --name-only --diff-filter=U | sed 's/^/    /' >&2
        printf 'To undo the merge and get back to where you were: git merge --abort\n' >&2
        exit 1
    fi

    git push origin "$PERSONAL_BRANCH"

    if [[ "$old_main" != "$new_main" ]] &&
        [[ -n "$(git diff --name-only "$old_main" "$new_main" -- cmd go.mod go.sum)" ]]; then
        printf '\nThe Go parts (analyze, status) changed. Rebuild them with: make build\n'
    fi

    printf '\nDone. %s is up to date with Mole.\n' "$PERSONAL_BRANCH"
}

main "$@"
exit
