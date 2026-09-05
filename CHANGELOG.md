# Changelog

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
