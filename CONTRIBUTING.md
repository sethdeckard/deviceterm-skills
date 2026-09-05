# Contributing

Bug reports and skill improvements are welcome. Before opening a pull request,
check that the change belongs here rather than upstream.

## What belongs here

A skill in this repo teaches an agent to compose the `deviceterm` CLI with
Apple's tools for a task: the recipes, and the traps that span both.

Three things don't belong:

- **Flag documentation.** `deviceterm help <verb>` is generated from the parser
  and pinned by tests. A skill that copies it drifts against a surface that
  can't. File the gap against DeviceTerm instead.
- **CLI behavior changes.** Those belong in
  [DeviceTerm](https://github.com/sethdeckard/deviceterm).
- **Skills for one project.** Loadout, Claude Code, and Codex all read a repo
  of your own, so a skill specific to your codebase doesn't need to live here.

## Before opening a pull request

Edit `loadout/skills/`, never `skills/`. Regenerate and check:

```sh
./scripts/build-skills.sh
./scripts/check-metadata.sh
./scripts/check-snippets.sh
```

CI runs the same checks, plus `build-skills.sh --check`, which fails when
`skills/` is stale. `AGENTS.md` describes what each one covers and, more
usefully, what they miss.

Git doesn't clone hooks. Run `./scripts/install-hooks.sh` once after cloning,
and the `commit-msg` hook checks the message format `AGENTS.md` describes.

Read `AGENTS.md` before adding a skill. It carries the layout and the seven
authoring rules.

## Saying what you verified

A skill that names CLI behavior needs that behavior checked against the version
in `README.md`, not against memory. Say in the pull request which parts you ran
against a live device and which you didn't. A recipe nobody has run is still
worth having, as long as it's labeled that way.

Helper scripts can be tested without a device by putting a stub `deviceterm` on
`PATH` that prints fixture JSON. Test the failure paths too. Both helpers
reserve exit 4 for "the lookup could not run", and it's easy to regress that
into exit 1, which one helper uses for "no findings" and the other for "no tabs
visible".

## Prose and instructions

`README.md`, `AGENTS.md`, `CHANGELOG.md`, and this file are documentation, and
read as plain concise prose. The `SKILL.md` bodies and everything under
`references/` are instructions for an agent, and follow no such constraint.
