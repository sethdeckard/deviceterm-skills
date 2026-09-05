#!/bin/sh
# Why this exists: git hooks are not cloned, so `.githooks/` does nothing until
# a checkout points `core.hooksPath` at it. That is one command, but it also has
# to be run once per clone and per worktree, and a hook that is not executable
# or does not parse fails silently at commit time rather than at install time.
#
# Checks every hook before pointing git at the directory: a non-executable hook
# is skipped by git without a word, and a syntax error in one only surfaces on
# the commit it rejects.
#
# Usage:  install-hooks.sh [--check]
#
# --check verifies the hooks without changing git config, which is what CI runs.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

check_only=false
if [ "${1:-}" = "--check" ]; then
    check_only=true
elif [ $# -gt 0 ]; then
    echo "usage: install-hooks.sh [--check]" >&2
    exit 2
fi

if [ ! -d .githooks ]; then
    echo "install-hooks.sh: no .githooks/ directory at $root" >&2
    exit 1
fi

count=0
for hook in .githooks/*; do
    [ -e "$hook" ] || continue
    if [ ! -x "$hook" ]; then
        echo "install-hooks.sh: $hook is not executable" >&2
        exit 1
    fi
    if ! bash -n "$hook"; then
        echo "install-hooks.sh: $hook has a syntax error" >&2
        exit 1
    fi
    count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
    echo "install-hooks.sh: .githooks/ is empty" >&2
    exit 1
fi

if [ "$check_only" = true ]; then
    echo "ok: $count hook(s) executable and parse"
    exit 0
fi

git config core.hooksPath .githooks
echo "ok: git hooks installed (.githooks/), $count hook(s) executable and parse"
