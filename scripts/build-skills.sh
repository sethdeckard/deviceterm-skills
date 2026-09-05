#!/bin/sh
# Why this exists: `loadout/skills/` is the source of truth, in the layout
# Loadout requires, and it carries a `skill.json` that only Loadout reads.
# Every other consumer wants a directory with nothing extraneous in it, and
# Codex additionally wants the invocation policy as `agents/openai.yaml`, which
# Loadout materializes on install and a plain copy would never get.
#
# So this generates per-target trees under `skills/`, applying the same rules
# Loadout applies: frontmatter rebuilt from `skill.json`, `name` and
# `description` from the top level, then that target's metadata block sorted,
# with Codex's `policy` filtered out of the frontmatter and written to
# `agents/openai.yaml` instead.
#
# String scalars are emitted double-quoted, because a description containing
# ": " is not a legal YAML plain scalar and no install path that reads
# frontmatter would parse it. Booleans and numbers are emitted bare, which is
# valid YAML for both; no frontmatter key carries one today.
#
# Bodies are copied unchanged. They resolve helpers under both ~/.claude and
# ~/.codex rather than naming one tool, so a per-target rewrite is unnecessary
# here and would have to cover references/ as well as SKILL.md.
#
# `skills/` is committed so users can copy without running anything, and both
# plugin manifests point into it. Run with --check to fail when it is stale,
# which is what CI does.
#
# Usage:  build-skills.sh [--check]

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

exec python3 - "$root" "${1:-}" <<'PY'
import json
import os
import shutil
import stat
import sys
import tempfile

root = sys.argv[1]
check_only = sys.argv[2] == "--check"
os.chdir(root)

SOURCE = "loadout/skills"
OUTPUT = "skills"


def emit_scalar(value):
    """YAML-safe scalar. json.dumps is valid YAML for strings, ints, and bools."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return json.dumps(value)
    return json.dumps(str(value))


def build_frontmatter(meta, target):
    lines = ["name: %s" % emit_scalar(meta["name"]),
             "description: %s" % emit_scalar(meta["description"])]

    block = dict(meta.get(target) or {})
    # Codex's invocation policy is not a frontmatter key. Loadout writes it to
    # agents/openai.yaml, and leaving it in the frontmatter would ship a key
    # the Agent Skills spec does not define.
    block.pop("policy", None)

    for key in sorted(block):
        lines.append("%s: %s" % (key, emit_scalar(block[key])))

    return "---\n" + "\n".join(lines) + "\n---\n"


def body_of(path):
    text = open(path, encoding="utf-8").read()
    rest = text[4:]
    return rest[rest.find("\n---\n") + 5:]


def copy_tree(src, dst):
    shutil.copytree(src, dst)
    for base, _dirs, files in os.walk(dst):
        for name in files:
            path = os.path.join(base, name)
            mode = os.stat(path).st_mode
            if base.endswith("helpers"):
                os.chmod(path, mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


README = """# skills/

**Generated. Do not edit.** Built from `loadout/skills/` by
`scripts/build-skills.sh`. Edits here are erased by the next build, and CI
fails when this tree does not match its source.

One directory per tool, each holding installable skills with the frontmatter
already built:

- `claude/<name>/` for Claude Code, and what `.claude-plugin/plugin.json`
  points at.
- `codex/<name>/` for Codex, carrying the `agents/openai.yaml` invocation
  policy, and what `.codex-plugin/plugin.json` points at.

Install one by copying the whole directory, not the `SKILL.md` alone, because
two of the skills invoke a helper script that sits beside it and two keep a
`references/` page:

```sh
cp -R skills/claude/deviceterm ~/.claude/skills/
```

To change a skill, edit `loadout/skills/<name>/` and re-run
`scripts/build-skills.sh`. `AGENTS.md` has the layout and the authoring rules.
"""


def build_into(out_root):
    # The notice lives in the generated tree so it cannot drift from it, and so
    # a build cannot quietly delete a hand-written one.
    with open(os.path.join(out_root, "README.md"), "w",
              encoding="utf-8") as handle:
        handle.write(README)

    for name in sorted(os.listdir(SOURCE)):
        skill_dir = os.path.join(SOURCE, name)
        if not os.path.isdir(skill_dir):
            continue

        meta = json.load(open(os.path.join(skill_dir, "skill.json"),
                              encoding="utf-8"))

        for target in meta.get("targets", []):
            dest = os.path.join(out_root, target, name)
            os.makedirs(dest)

            body = body_of(os.path.join(skill_dir, "SKILL.md"))
            with open(os.path.join(dest, "SKILL.md"), "w",
                      encoding="utf-8") as handle:
                handle.write(build_frontmatter(meta, target) + body)

            for extra in ("helpers", "references"):
                src = os.path.join(skill_dir, extra)
                if os.path.isdir(src):
                    copy_tree(src, os.path.join(dest, extra))

            policy = (meta.get(target) or {}).get("policy")
            if target == "codex" and policy:
                agents = os.path.join(dest, "agents")
                os.makedirs(agents)
                lines = ["policy:"]
                for key in sorted(policy):
                    lines.append("    %s: %s" % (key, emit_scalar(policy[key])))
                with open(os.path.join(agents, "openai.yaml"), "w",
                          encoding="utf-8") as handle:
                    handle.write("\n".join(lines) + "\n")


def snapshot(base):
    files = {}
    for dirpath, _dirs, names in os.walk(base):
        for name in names:
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, base)
            executable = bool(os.stat(path).st_mode & stat.S_IXUSR)
            files[rel] = (open(path, "rb").read(), executable)
    return files


staging = tempfile.mkdtemp(prefix="deviceterm-dist-")
try:
    build_into(staging)
    fresh = snapshot(staging)

    if check_only:
        current = snapshot(OUTPUT) if os.path.isdir(OUTPUT) else {}
        added = sorted(set(fresh) - set(current))
        removed = sorted(set(current) - set(fresh))
        changed = sorted(k for k in set(fresh) & set(current)
                         if fresh[k] != current[k])
        if added or removed or changed:
            for rel in added:
                sys.stderr.write("skills/ missing:   %s\n" % rel)
            for rel in removed:
                sys.stderr.write("skills/ stale:     %s\n" % rel)
            for rel in changed:
                sys.stderr.write("skills/ different: %s\n" % rel)
            sys.stderr.write("\nskills/ is out of date. Run scripts/build-skills.sh\n")
            sys.exit(1)
        print("ok: skills/ matches loadout/skills/ (%d files)" % len(fresh))
    else:
        if os.path.isdir(OUTPUT):
            shutil.rmtree(OUTPUT)
        shutil.copytree(staging, OUTPUT)
        print("built skills/ (%d files)" % len(fresh))
finally:
    shutil.rmtree(staging, ignore_errors=True)
PY
