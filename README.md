# deviceterm-skills

Agent skills for [DeviceTerm](https://deviceterm.com), the macOS terminal that
runs live Apple device panes beside your shell. They teach an agent what it can
do from inside a DeviceTerm tab, and how to compose the `deviceterm` CLI with
Apple's own tools.

DeviceTerm already carries agent guidance in the binary, under `deviceterm help`
and `deviceterm agents`. These skills don't restate it. They tell an agent that
it exists, and they hold the task-shaped recipes the CLI deliberately refuses:
"No recipe library. Workflow scripting is the shell's job."

## Skills

| Skill | What it does |
|-------|--------------|
| [deviceterm](loadout/skills/deviceterm) | Orient in a tab and route to the CLI's own reference. Start here. |
| [deviceterm-app-verify](loadout/skills/deviceterm-app-verify) | Drive an app and prove what it did, instead of trusting a receipt |
| [deviceterm-screenshots](loadout/skills/deviceterm-screenshots) | App Store captures across device families, locales, and appearance |
| [deviceterm-a11y-audit](loadout/skills/deviceterm-a11y-audit) | Sweep for unlabeled controls and undersized hit targets |
| [deviceterm-repro](loadout/skills/deviceterm-repro) | Reproduce a bug report and capture evidence |
| [deviceterm-tab-titles](loadout/skills/deviceterm-tab-titles) | Summarize the tabs it can see and retitle them. Needs an automation tab |

All six target Claude Code and Codex.

## Install

### Claude Code

Run these inside Claude Code, not in a shell:

```
/plugin marketplace add sethdeckard/deviceterm-skills
/plugin install deviceterm@deviceterm-skills
```

### Codex

```sh
codex plugin marketplace add sethdeckard/deviceterm-skills
```

Then browse `/plugins` in the Codex CLI and install DeviceTerm.

### Loadout

If you already manage skills with
[Loadout](https://github.com/sethdeckard/loadout), it scans `skills/` under
whatever path it is pointed at, so point it at `loadout/` rather than the repo
root:

```sh
git clone https://github.com/sethdeckard/deviceterm-skills
loadout init --repo "$PWD/deviceterm-skills/loadout"
loadout equip deviceterm --target claude
```

`loadout init --clone` does not work against this repo. It sets the repo path
to the clone root, where `skills/` holds the generated per-tool trees, and
Loadout would read `claude` and `codex` as two malformed skills rather than
finding nothing.

With a repo of your own, Loadout points at a single repo, so you can't
subscribe to this one alongside yours. Copy the skill directories you want into
your repo's `skills/`:

```sh
cp -R deviceterm-skills/loadout/skills/deviceterm* your-skills/skills/
```

Record the commit you took them from, and bump that pin in the same commit that
re-copies them. The pin is the only record of where the copies came from.

### Copy a skill by hand

`skills/` holds ready-to-install trees, one per tool, with the frontmatter
built and nothing extraneous in them:

```sh
cp -R skills/claude/deviceterm ~/.claude/skills/
cp -R skills/codex/deviceterm  ~/.codex/skills/
```

Copy from `skills/`, not from `loadout/skills/`. The source tree carries a
`skill.json` that only Loadout reads, and the Codex tree additionally carries
the `agents/openai.yaml` invocation policy a copy of the source would not have.
Copy the whole directory rather than the `SKILL.md` alone: two of the skills
invoke a helper script that sits beside it, and two keep a `references/` page
their `SKILL.md` links to.

## Requirements

The skills expect to run in a DeviceTerm tab. The orientation skill checks
`DEVICETERM_SESSION` and stops if the shell isn't one, because no flag makes
device control reachable from outside.

Most workflows also use `xcrun simctl`, which comes with Xcode. The
accessibility audit and tab-titles skills each ship a `python3` helper; the
other four have no bundled helper and need no interpreter.

## Versions

Requires deviceterm 0.8.0 or later.

DeviceTerm is 0.x, where a minor release may break the CLI, so every skill tells
the agent to believe `deviceterm help <verb>` over the skill when the two
disagree.

## Editing

`CONTRIBUTING.md` covers what belongs here, and `AGENTS.md` carries the layout,
the packaging rules, and the authoring rules.

`loadout/skills/` is the source of truth and `skills/` is generated from it by
`scripts/build-skills.sh`. Never edit `skills/` by hand.

## License

MIT.
