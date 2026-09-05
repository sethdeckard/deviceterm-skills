# deviceterm-skills

Conventions for editing this repo. `README.md` is for people installing the
skills; this file is for whoever changes them.

## Layout

```
loadout/skills/<name>/skill.json   Loadout metadata, and the frontmatter source
loadout/skills/<name>/SKILL.md     instructions for the agent, with frontmatter
loadout/skills/<name>/references/  loaded only when SKILL.md says to read it
loadout/skills/<name>/helpers/     executable scripts SKILL.md invokes by path

skills/<tool>/<name>/              generated; never edit by hand
```

`loadout/skills/` is the source of truth, in the layout [Loadout](https://github.com/sethdeckard/loadout)
requires: it
scans `skills/` directly under whatever path it is pointed at, so the nesting
is what lets a Loadout user aim at `loadout/` while the repo root stays free
for the generated trees.

`skills/` is built from it by `scripts/build-skills.sh` and committed, so
installing needs no build step.

## Packaging

Four install paths read this repo, and they disagree about which files matter.

| Path | Reads | Notes |
|---|---|---|
| Loadout | `loadout/skills/*/skill.json` | Rebuilds frontmatter on install; needs no root manifest |
| Claude Code plugin | `skills/claude/*/SKILL.md` | Declared in `.claude-plugin/plugin.json` |
| Codex plugin | `skills/codex/*/SKILL.md` | Declared in `.codex-plugin/plugin.json`, which needs the tree carrying `agents/openai.yaml` and no `skill.json` |
| Copy by hand | `skills/<tool>/<name>/` | |

Marketplace entries live in `.claude-plugin/marketplace.json` and
`.agents/plugins/marketplace.json`.

`build-skills.sh` applies the rules Loadout applies on install: frontmatter
rebuilt from `skill.json`, the Codex `policy` block filtered out of the
frontmatter and written to `agents/openai.yaml`, and no `skill.json` in the
output.

**Keep bodies tool-neutral.** A `SKILL.md` resolves its helper by testing
candidate paths under both `~/.claude` and `~/.codex`, so the builder copies
bodies unchanged. Rewriting paths per target would have to cover every
`references/` file too, not just `SKILL.md`.

## The frontmatter isn't decorative here

This is where the repo departs from a Loadout-only library, and the thing most
likely to break without anyone noticing.

Loadout strips a source `SKILL.md`'s frontmatter and rebuilds it from
`skill.json`. In a Loadout-only repo the two can drift harmlessly, because only
`skill.json` ever ships.

The plugin paths have no `skill.json` and read the frontmatter directly. The
same two fields are authoritative on some paths and ignored on others, so a
drift gives one skill different descriptions depending on how it was installed.
Keep `name` and `description` byte-identical in both files.

**Quote every frontmatter scalar.** A description containing `": "` is not a
legal YAML plain scalar and nothing downstream will parse it. The check parses
with PyYAML or ruby and fails when neither is available, rather than
approximating YAML by hand.

## Checks

Three, all run by CI on every push and pull request from
`.github/workflows/check.yml`.

```sh
./scripts/check-metadata.sh
./scripts/check-snippets.sh
./scripts/build-skills.sh --check
```

`check-metadata.sh` compares `skill.json` against the frontmatter, and also
verifies that the directory name matches, that required fields are present,
that top-level helpers are executable, and that every top-level Python helper
compiles. Files in a subdirectory of `helpers/` aren't checked.

`check-snippets.sh` parses the fenced `sh` blocks under
`loadout/skills/*/SKILL.md` and `loadout/skills/*/references/` with `zsh -n`,
because those snippets get pasted into a DeviceTerm tab where the shell is zsh.
Root documentation is not scanned. It skips itself when zsh is absent, so CI
installs zsh explicitly rather than letting that become a silent pass.

`build-skills.sh --check` fails when `skills/` no longer matches
`loadout/skills/`.

**The snippet check catches syntax only, which is less than it sounds.** It
catches a syntax error such as `<UDID>` being read as a redirection. It does
not catch anything that only fails when run: assigning to zsh's read-only
`status`, calling a function before its definition, or passing extra operands
to `[`. Nothing in this repo checks that class.

## Authoring rules

1. **Never restate the CLI's own reference.** `deviceterm help <verb>` and
   `deviceterm agents` are generated from the parser and pinned by tests in the
   DeviceTerm repo. A skill that copies flag documentation drifts against a
   surface that can't. Step one of any procedure is to read the binary.

2. **Name the version.** Each `SKILL.md` says which deviceterm release it was
   written against, and says the CLI wins on conflict.

3. **Target both** unless there's a reason not to:
   `"targets": ["claude", "codex"]`.

4. **Declare the Codex invocation policy explicitly.** Set
   `codex.policy.allow_implicit_invocation`. Omitting it isn't the same as
   setting it false: Loadout then writes no policy file and leaves any existing
   `agents/openai.yaml` untouched.

5. **Omit `allowed-tools`.** It's a pre-approval for the invoking turn, not a
   sandbox. The Claude and Codex Bash prefixes differ by one character
   (`Bash(git *)` against `Bash(git:*)`), and Loadout passes the value through
   without validating it, so a wrong prefix installs cleanly and then matches
   nothing.

6. **Prefer a `deviceterm` verb over a helper, and a helper over an inline
   pipeline.** Codex can't reduce heredocs, `$(...)`, or redirection to a
   durable approval prefix, so a prescribed `cmd | jq '...'` prompts again on
   every call. A helper fixes that; a bare `deviceterm <verb>` fixes it better,
   needs no path resolution at all, and keeps rules like coordinate
   normalization in one place instead of copied into each recipe. Check
   `deviceterm help <verb>` before writing a helper. The CLI has absorbed
   several things these skills used to carry, and a helper that duplicates a
   verb will drift from it.

   When a helper is still right, resolve it with a loop over candidate paths,
   not `$(find ... | head -1)`, which exits nonzero under `set -o pipefail`
   when one search root is missing.

7. **Never tell an agent to shut down a Simulator it didn't boot.** No
   `simctl shutdown all`. A Simulator on the user's machine may belong to work
   that has nothing to do with the task.

## Helpers

Executable, with a comment saying why the helper exists rather than what it
does.

Test them offline by putting a stub `deviceterm` on `PATH` that prints fixture
JSON. That is how to check `tab-map.py`'s grouping against a hand-written
`tabs list` response, including a split tab whose sessions share one `tabId`,
without a running daemon.

## Docs

`README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, and this file are user-facing
documentation, and read as plain concise prose. The `SKILL.md` bodies and
everything under `references/` are instructions for an agent and follow no such
constraint.

## Commit messages

- Subject: 50 characters or fewer, capitalized, imperative mood ("Add
  feature", not "Added feature"), no trailing period.
- Blank line between subject and body.
- Body: wrapped at 72 characters. Say what changed and why, not how.

The `commit-msg` hook in `.githooks/` enforces the subject length,
capitalization, the trailing period, the blank line, and the body wrap.
Imperative mood isn't checked, because the hook can't reliably judge grammar.
That one is on the reviewer.

Git doesn't clone hooks, so a fresh clone has none until you install them:

```sh
./scripts/install-hooks.sh
```

That points `core.hooksPath` at `.githooks/` after checking every hook is
executable and parses. A hook that isn't executable is skipped silently, and a
syntax error in one surfaces only on the commit it rejects.
