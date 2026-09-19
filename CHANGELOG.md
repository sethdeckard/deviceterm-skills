# Changelog

## 0.3.0 - 2026-09-19

Requires deviceterm 0.11.0 or later, up from 0.6.0. Two breaking CLI changes
landed upstream since the first release. The first would have been 0.2.0 but was
never released on its own, so this entry covers both.

DeviceTerm 0.8.0 replaced the plural workspace namespaces with singular
resources: `panes list` became `pane list`, and `tab capture` and
`tab send-input` were removed in favor of `pane capture-text` and
`pane send-input`, which take an explicit terminal pane. Every skill called at
least one verb that had stopped existing.

- `deviceterm-tab-titles` is substantially rewritten. It reads the workspace
  with `pane list --all`, which spans every visible tab in one call, and probes
  for its automation grant with `session show` rather than provoking a refusal
  and reading the code.
- Removed `helpers/tab-map.py`. `tab list --json` reports `current`, `title`,
  and `paneCount` natively, so the helper only duplicated a verb.
- Fixed the refusal code named for the eight always-gated commands. An ungranted
  caller receives `session.unauthorized`, not `intent.automationRequired`, which
  is what an ownership check raises. Both carry rpcCode -32011, so branching on
  the number cannot tell them apart.
- Tab summaries can read `terminal.title`, a per-pane label, where a split tab
  previously offered only its single tab title.
- Fixed two readiness races in `deviceterm-app-verify` and `deviceterm-repro`.
  The Simulator pane may appear after `simctl boot` returns, so its absence from
  `pane list` immediately afterwards does not mean the boot bypassed the shim.
  And `simctl launch` returns before the app is frontmost, so the first
  accessibility call after it can fail with `frontmostApplication returned nil`
  and needs retrying rather than reporting a failed launch.
- Corrected what a failed `wait pane rendering` proves, in those two skills and
  in `deviceterm-screenshots`. `pane.notFound` and `wait.timeout` each have two
  causes, so neither settles on its own whether the pane ever attached.

## 0.1.0 - 2026-09-05

First release. Six skills for driving Apple devices from inside a DeviceTerm
tab. Requires deviceterm 0.6.0 or later.

- `deviceterm` orients an agent in a tab and routes it to `deviceterm help` and
  `deviceterm agents` instead of restating them.
- `deviceterm-app-verify` drives an app and verifies the result by reading the
  accessibility tree back, using `tap --label` to locate and act in one command
  and `wait ax` to confirm a control appeared or went away.
- `deviceterm-screenshots` captures App Store images across device families,
  locales, and appearance.
- `deviceterm-a11y-audit` reports unlabeled controls and undersized hit
  targets, and refuses to present a truncated sweep as full coverage.
- `deviceterm-repro` reproduces a bug report and collects evidence.
- `deviceterm-tab-titles` reads every visible tab from an automation tab,
  summarizes each, and retitles it after showing the plan for approval.

Installable as a Claude Code plugin, as a Codex plugin, through Loadout, or by
copying a ready-built directory out of `skills/`.
