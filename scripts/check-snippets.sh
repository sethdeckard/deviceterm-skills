#!/bin/sh
# Why this exists: skill snippets are written to be pasted into a DeviceTerm
# tab, where the shell is normally zsh, so they are parsed with `zsh -n`.
#
# Scope is `loadout/skills/*/SKILL.md` and the Markdown files directly under
# `loadout/skills/*/references/`. Not recursive, and not the generated `skills/`
# tree. Root documentation is not scanned either, so a fenced block in
# README.md goes unchecked.
#
# `zsh -n` parses without executing, so it is safe to run over documentation.
# It catches syntax errors such as `<UDID>` being read as a redirection. It
# does not catch anything that only fails when run: assigning to zsh's
# read-only `status`, calling a function before its definition, a wrong
# `simctl` subcommand, or a bad jq filter.
#
# `references/matrix.md` is assembled into one script before checking, because
# its blocks are sections of a single file and only parse as a whole.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

command -v zsh >/dev/null 2>&1 || {
    echo "zsh not found; skipping snippet syntax check" >&2
    exit 0
}

exec python3 - "$root" <<'PY'
import glob
import os
import re
import subprocess
import sys
import tempfile

root = sys.argv[1]
os.chdir(root)

paths = sorted(glob.glob("loadout/skills/*/SKILL.md")
                + glob.glob("loadout/skills/*/references/*.md"))
failures = 0
groups = 0

for path in paths:
    blocks = re.findall(r"```sh\n(.*?)```", open(path, encoding="utf-8").read(), re.S)
    if path.endswith("matrix.md"):
        candidates = [("\n".join(blocks), "assembled")]
    else:
        candidates = [(b, "block %d" % i) for i, b in enumerate(blocks, 1)]

    for source, label in candidates:
        groups += 1
        handle = tempfile.NamedTemporaryFile(
            "w", suffix=".zsh", delete=False, encoding="utf-8")
        handle.write(source)
        handle.close()
        result = subprocess.run(
            ["zsh", "-n", handle.name], capture_output=True, text=True)
        if result.returncode != 0:
            failures += 1
            sys.stderr.write("FAIL %s %s\n  %s\n"
                             % (path, label, result.stderr.strip()))
        os.unlink(handle.name)

if failures:
    sys.stderr.write("\n%d snippet group(s) checked, %d syntax failure(s)\n"
                     % (groups, failures))
    sys.exit(1)

print("ok: %d snippet group(s) across %d files parse under zsh" % (groups, len(paths)))
PY
