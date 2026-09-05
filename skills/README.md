# skills/

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
