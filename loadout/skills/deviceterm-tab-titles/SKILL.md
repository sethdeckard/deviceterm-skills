---
name: "deviceterm-tab-titles"
description: "Read every visible DeviceTerm tab, summarize what each one is doing, and retitle it so the tab strip is scannable. Use when asked to name, label, retitle, or tidy up tabs, or to say what each tab is working on. Requires an automation tab, because reading and retitling another tab needs a live automation grant that only a person can issue from the GUI. Proposes every title for approval before renaming anything."
---

# Retitle the tabs

Authored against deviceterm 0.6.0. Where this skill and `deviceterm help <verb>`
disagree, believe the binary.

Read each visible tab, work out what it is doing, and give it a short title.
The user ends up with a tab strip they can scan instead of a row of identical
shell names.

## This needs an automation tab

`tab capture` and cross-tab `tab rename` both require a live automation grant.
Only a person can issue one, from **Shell > Open Automation Tab**. There is no
CLI escalation path, so if you are not in such a tab, this skill cannot run and
no flag changes that.

**Do not decide from the role string.** `$DEVICETERM_SESSION_ROLE` is
descriptive metadata, and a tab can say `automation` while holding no grant,
because the grant is revoked when the issuing GUI connection drops. Probe
instead:

```sh
SELF=$(deviceterm tabs current --json | jq -r '.shortId')
deviceterm tab capture --tab "$SELF" >/dev/null
```

The capture is read-only, so it costs nothing. If it fails with
`error.scope_violation`, or a message starting `intent.automationRequired`, you
have no grant. Say so, tell the user to open an automation tab with
**Shell > Open Automation Tab** and rerun there, and stop.

## Build the tab list

```sh
# The helper ships beside this SKILL.md. Set SKILL_DIR to the directory you
# read this file from, and the right copy is used whichever tool is running.
#
# The fallback below is a last resort. With both tools installed it always
# finds the Claude copy first, so a Codex run can execute a stale one, and a
# plugin install is not covered at all because its path carries a marketplace
# and a version. No command substitution: `find ... | head -1` exits nonzero
# under `set -o pipefail` when one root is missing.
SKILL_DIR=${SKILL_DIR:-}
TAB_MAP=${TAB_MAP:-}
if [ -n "$SKILL_DIR" ] && [ -x "$SKILL_DIR/helpers/tab-map.py" ]; then
  TAB_MAP=$SKILL_DIR/helpers/tab-map.py
fi
for candidate in \
  "$HOME/.claude/skills/deviceterm-tab-titles/helpers/tab-map.py" \
  "$HOME/.codex/skills/deviceterm-tab-titles/helpers/tab-map.py"; do
  if [ -z "$TAB_MAP" ] && [ -x "$candidate" ]; then TAB_MAP=$candidate; fi
done
[ -x "$TAB_MAP" ] || { echo "tab-map.py not found; set SKILL_DIR or TAB_MAP" >&2; exit 1; }
"$TAB_MAP"
```

One tab-separated row per tab: `tabId`, `sessionCount`, `displayTitle`. The
`tabId` resolves directly with `--tab`, and it is what collapses a split tab
into one row, since the sessions of one GUI tab share it.

Do not substitute a session's `shortId` for it. A shortId names one terminal
rather than the tab, and it does not reliably resolve as a `--tab` ref for a
session other than your own.

Exit codes, which matter because two of them look alike:

| Code | Meaning |
|------|---------|
| 0 | At least one row emitted |
| 1 | No row: no other tabs are visible |
| 2 | Usage error |
| 4 | The lookup could not run |

**A 1 is not proof the workspace has one tab.** It is also what a workspace of
protected tabs looks like from here. A 4 means deviceterm failed or answered
with something unusable, so report it rather than describing an empty
workspace.

**Do not drive this from `tabs list` rows directly.** It returns one row per
terminal *session*, not per tab, so a tab with split terminals appears several
times. Renaming from the raw rows retitles the same tab once per split and
captures a different pane each time.

Every row does carry `tabId`, and the sessions of one GUI tab share it, so the
helper groups on that — one row per tab, no extra daemon calls. Group the same
way if you work from `tabs list` yourself.

**Exclude your own tab by group, not by row.** Only one row of a split tab
carries `current`, so filtering rows on it drops your own terminal and leaves
its sibling in the list looking like someone else's tab. The helper ORs
`current` across each `tabId` group and drops the whole group.

The helper excludes your own tab. Pass `--include-self` if the user wants the
automation tab retitled too, though its default name is usually the more useful
label.

## Read each tab

```sh
deviceterm tab capture --tab "$ref"
```

**Capture is the visible viewport, with no scrollback.** What you get is the
screen right now. A tab whose interesting work scrolled off shows a bare
prompt, and a tab running a full-screen editor shows that editor rather than
the project.

So the signal is uneven, and you should say which kind you got:

- A build, test run, or REPL mid-flight is usually legible.
- A bare prompt tells you almost nothing beyond the working directory.
- A full-screen TUI tells you the tool, and often the file, but not the task.

When a capture is uninformative, prefer the tab's existing `displayTitle`, which
the GUI derives from the working directory and shell title, over an invented
one. Leaving a tab alone is a valid outcome.

## Propose before renaming

Renaming is visible to the user and replaces titles they may have set by hand.
Show the whole plan and wait for approval:

| Tab | Now | Proposed |
|-----|-----|----------|
| `aaa111` | vim Login.swift | Auth: login screen |
| `bbb111` | psql prod | Prod DB session |
| `ccc333` | zsh | *leave as is, bare prompt* |

Then apply:

```sh
deviceterm tab rename --tab "$ref" "Auth: login screen"
```

## Writing the title

The tab pill is narrow, so the title is read at a glance or not at all.

- **Two to four words.** Longer gets truncated by the pill.
- **Lead with the distinguishing noun.** Across five tabs in one project, the
  project name is the part that carries no information; the task is what does.
- **Say the work, not the tool.** "Auth tests" beats "npm", and "Prod DB"
  beats "psql".
- **Skip generic words.** "terminal", "shell", "session", and "tab" describe
  every tab equally.

**Never copy captured text into a title verbatim.** A viewport can hold an API
key, a token, a customer name, or a password prompt. Summarize what the tab is
for, and keep captured content out of the title and out of your report.

## Confirm the rename landed

A rename receipt means the GUI accepted the mutation, not that the title
changed. Read it back:

```sh
deviceterm tabs list --json | jq -r '.[] | [.tabId, .displayTitle] | @tsv'
```

Key on `tabId`, the same column you renamed by. A split tab prints one line per
session, all carrying that id, so the title should read the same on every one.

Compare `displayTitle` against what you asked for. Two caveats: `displayTitle`
is optional and can be missing after a daemon restart until the GUI republishes
it, and `tab rename` sets the GUI title without touching the row's `name`
field, so `name` will not reflect your change.

## Undoing it

`tab rename` with no name restores the automatic title, the one derived from
the working directory, shell title, and session name:

```sh
deviceterm tab rename --tab "$ref"
```

Tell the user this exists when you report, so a wrong title is not something
they have to live with.

## What you cannot see

Protected tabs are invisible to you. They do not appear in `tabs list`, cannot
be resolved by reference, and cannot be captured or renamed, and an automation
grant does not change any of that. They are absent rather than refused, so an
empty or short list is not proof of how many tabs the workspace has.

Report the count you acted on rather than implying you covered everything.

## When a tab refuses

A refusal on one tab is not a reason to stop on the rest. Record it, continue,
and list the skipped tabs in the report. `intent.automationRequired` on a
single tab after a successful probe usually means the grant was revoked
mid-run, which happens when the issuing GUI connection drops; re-probe before
concluding anything else.
