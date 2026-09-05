#!/bin/sh
# Why this exists: in a Loadout-only repo, SKILL.md frontmatter is decorative.
# Loadout strips it and rebuilds it from skill.json, so the two drifting apart
# costs nothing and goes unnoticed. This repo also publishes as a Claude Code
# plugin and a Codex plugin, and both of those read the frontmatter directly.
# The same two fields are therefore authoritative on some install paths and
# ignored on others, which means a drift produces two different descriptions
# for one skill depending on how it was installed.
#
# The frontmatter is parsed with PyYAML or ruby, never by hand, so that YAML
# syntax is validated rather than approximated. A description containing ": "
# is not a legal plain scalar, which a split-on-colon reader accepts and a real
# parser rejects; `build-skills.sh` double-quotes every string scalar for the
# same reason.
#
# Checks, for every loadout/skills/<name>/ directory:
#   - skill.json is valid JSON and has name, description, and targets
#   - skill.json.name equals the directory name
#   - SKILL.md frontmatter is valid YAML with name and description
#   - the two names match, and the two descriptions match
#   - every top-level helper is executable, and every top-level Python helper
#     compiles. Files in a subdirectory of helpers/ are not checked.
#
# Exits 0 when clean, 1 on any failure.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# A real YAML parser is required, not optional. A hand-rolled reader does not
# validate YAML syntax, so a missing parser is a hard failure rather than a
# silent downgrade to approximate parsing.
if python3 -c 'import yaml' 2>/dev/null; then
    YAML_BACKEND=pyyaml
elif command -v ruby >/dev/null 2>&1 && ruby -ryaml -e '' 2>/dev/null; then
    YAML_BACKEND=ruby
else
    echo "need a YAML parser: install PyYAML (pip install pyyaml) or ruby" >&2
    exit 1
fi
export YAML_BACKEND

exec python3 - "$root" <<'PY'
import json
import os
import subprocess
import sys

root = sys.argv[1]
backend = os.environ["YAML_BACKEND"]
skills_dir = os.path.join(root, "loadout", "skills")
# The targets build-skills.sh knows how to generate a tree for. Keep in step
# with the OUTPUT layout there: an unlisted name would be built and shipped
# under a directory nothing installs from.
KNOWN_TARGETS = {"claude", "codex"}

failures = []
checked = 0


def fail(skill, message):
    failures.append("%s: %s" % (skill, message))


def parse_yaml(text, path):
    """Parse a YAML document with a real parser, never by hand."""
    if backend == "pyyaml":
        import yaml
        return yaml.safe_load(text)

    proc = subprocess.run(
        ["ruby", "-ryaml", "-rjson", "-e",
         "puts YAML.safe_load(STDIN.read).to_json"],
        input=text, capture_output=True, text=True)
    if proc.returncode != 0:
        raise ValueError(proc.stderr.strip().splitlines()[0]
                         if proc.stderr.strip() else "YAML parse failed")
    return json.loads(proc.stdout)


def frontmatter(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    if not text.startswith("---\n"):
        raise ValueError("file does not open with a --- frontmatter fence")
    rest = text[4:]
    end = rest.find("\n---\n")
    if end == -1:
        raise ValueError("frontmatter fence is never closed")
    return parse_yaml(rest[:end], path)


if not os.path.isdir(skills_dir):
    sys.stderr.write("no loadout/skills/ directory at %s\n" % skills_dir)
    sys.exit(1)

for name in sorted(os.listdir(skills_dir)):
    skill_dir = os.path.join(skills_dir, name)
    if not os.path.isdir(skill_dir):
        continue

    checked += 1
    json_path = os.path.join(skill_dir, "skill.json")
    md_path = os.path.join(skill_dir, "SKILL.md")

    if not os.path.isfile(json_path):
        fail(name, "missing skill.json")
        continue
    if not os.path.isfile(md_path):
        fail(name, "missing SKILL.md")
        continue

    try:
        with open(json_path, encoding="utf-8") as handle:
            meta = json.load(handle)
    except ValueError as exc:
        fail(name, "skill.json is not valid JSON: %s" % exc)
        continue

    for key in ("name", "description", "targets"):
        if key not in meta:
            fail(name, "skill.json is missing %r" % key)

    if meta.get("name") != name:
        fail(name, "skill.json name is %r but the directory is %r"
             % (meta.get("name"), name))

    targets = meta.get("targets")
    if not isinstance(targets, list) or not targets:
        fail(name, "skill.json targets must be a non-empty array")
    else:
        # Membership, not just non-emptiness. build-skills.sh generates one
        # directory per target name, so a typo like "codxe" yields a
        # structurally valid tree under a name no installer reads.
        unknown = [t for t in targets if t not in KNOWN_TARGETS]
        if unknown:
            fail(name, "skill.json targets has unknown %r; known are %s"
                 % (unknown, sorted(KNOWN_TARGETS)))
        # Omitting the policy is not the same as setting it false: Loadout
        # then writes no agents/openai.yaml and leaves any existing one in
        # place, so a Codex install silently keeps whatever was there before.
        if "codex" in targets:
            policy = meta.get("codex", {}).get("policy", {})
            if not isinstance(policy, dict) \
                    or "allow_implicit_invocation" not in policy:
                fail(name, "targets codex but omits "
                           "codex.policy.allow_implicit_invocation")
            elif not isinstance(policy["allow_implicit_invocation"], bool):
                fail(name, "codex.policy.allow_implicit_invocation must be a "
                           "boolean, not %r"
                     % (policy["allow_implicit_invocation"],))

    try:
        front = frontmatter(md_path)
    except ValueError as exc:
        fail(name, "SKILL.md frontmatter is not valid YAML: %s" % exc)
        continue

    if not isinstance(front, dict):
        fail(name, "SKILL.md frontmatter is not a mapping")
        continue

    for key in ("name", "description"):
        if key not in front:
            fail(name, "SKILL.md frontmatter is missing %r" % key)

    if front.get("name") != meta.get("name"):
        fail(name, "name drift: skill.json %r vs SKILL.md %r"
             % (meta.get("name"), front.get("name")))

    if front.get("description") != meta.get("description"):
        fail(name,
             "description drift between skill.json and SKILL.md frontmatter. "
             "Plugin installs ship the frontmatter; Loadout ships skill.json. "
             "They must say the same thing.")

    helpers = os.path.join(skill_dir, "helpers")
    if os.path.isdir(helpers):
        for helper in sorted(os.listdir(helpers)):
            helper_path = os.path.join(helpers, helper)
            if not os.path.isfile(helper_path):
                continue
            if not os.access(helper_path, os.X_OK):
                fail(name, "helpers/%s is not executable" % helper)
            if helper.endswith(".py"):
                # Builtin compile() rather than py_compile, which insists on
                # writing a .pyc somewhere and rejects /dev/null as a target.
                try:
                    with open(helper_path, encoding="utf-8") as handle:
                        compile(handle.read(), helper_path, "exec")
                except SyntaxError as exc:
                    fail(name, "helpers/%s does not compile: %s" % (helper, exc))

if failures:
    for line in failures:
        sys.stderr.write("FAIL %s\n" % line)
    sys.stderr.write("\n%d skill(s) checked, %d problem(s)\n"
                     % (checked, len(failures)))
    sys.exit(1)

print("ok: %d skill(s) checked with %s, metadata in sync" % (checked, backend))
PY
