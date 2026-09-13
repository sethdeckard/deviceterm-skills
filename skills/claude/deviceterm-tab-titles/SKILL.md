---
name: "deviceterm-tab-titles"
description: "Read every visible DeviceTerm tab, summarize what each one is doing, and retitle it so the tab strip is scannable. Use when asked to name, label, retitle, or tidy up tabs, or to say what each tab is working on. Requires an automation tab, because reading and retitling another tab needs a live automation grant that only a person can issue from the GUI. Proposes every title for approval before renaming anything."
---

# Retitle the tabs

Authored against deviceterm 0.8.0. Where this skill and `deviceterm help <verb>`
disagree, believe the binary.

Read each visible tab, work out what it is doing, and give it a short title.
The user ends up with a tab strip they can scan instead of a row of identical
shell names.

## This needs an automation tab

`pane capture-text` and cross-tab `tab rename` both require a live automation
grant. Only a person can issue one, from **Shell > Open Automation Tab**. There
is no CLI escalation path, so if you are not in such a tab, this skill cannot
run and no flag changes that.

**Do not decide from the role string.** `$DEVICETERM_SESSION_ROLE` is
descriptive metadata. A caller whose role still reads `automation` is refused
like any other once the grant is gone, and it goes when the issuing GUI
connection drops. Probe instead:

```sh
deviceterm pane capture-text current >/dev/null
```

`current` resolves to your own terminal pane, so the probe reads a screen you
are already looking at. Without a grant it fails with
`intent.automationRequired`. Say so, tell the user to open an automation tab
with **Shell > Open Automation Tab** and rerun there, and stop.

## Build the tab list

```sh
deviceterm tab list --all --json
```

One row per tab. `--all` reaches every visible window; without it you see only
your own window, which turns a workspace-wide job into a window-local one
without saying so.

Four fields carry this skill:

- `id` is the rename target and the read-back key.
- `title` is the GUI's current display title, always present.
- `name` is the assigned name, absent until someone sets one.
- `current` is true for the one tab your own terminal sits in.

**Exclude your own tab by dropping the row where `current` is true.** One row
per tab means one flag per tab, so there is no grouping to do.

Keep that row only if the user asks for the automation tab to be retitled too.
Its default name is usually the more useful label.

A list holding only your own row means no other tabs are visible. **That is not
proof the workspace has one tab**, because protected tabs are absent from it.

## Read each tab

One `tab show` per tab, then one capture per terminal pane it holds:

```sh
deviceterm tab show "$id" --json
deviceterm pane capture-text "$paneId"
```

`tab show` returns the tab plus `.panes[]`, each entry carrying a `kind`. Read
that array and take the entries whose `kind` is `terminal`: those are the only
ones `pane capture-text` accepts, and their `id` is what it wants.

**Capture every terminal the tab holds, not just the first.** A split tab is
often split precisely because two different things are happening in it, and
reading one side gives you a title for half the tab. Say which panes produced
the signal when you report.

Count those terminal entries to know how many captures a tab costs. `paneCount`
on the `tab list` row will not tell you: it counts every pane in the layout, so
a tab holding a shell and a Simulator reports two and captures once.

**Capture is the visible viewport, with no scrollback.** What you get is the
screen right now. A tab whose interesting work scrolled off shows a bare prompt,
and a tab running a full-screen editor shows that editor rather than the project.

So the signal is uneven, and you should say which kind you got:

- A build, test run, or REPL mid-flight is usually legible.
- A bare prompt tells you almost nothing beyond the working directory.
- A full-screen TUI tells you the tool, and often the file, but not the task.

### The working directory comes free

The same `tab show` response carries each terminal's live working directory, so
a bare prompt still tells you which project the tab belongs to. Each terminal
entry holds it at `terminal.cwd`; no extra call is needed.

Four things to know before you title from it:

- **Absent is routine.** The field is omitted when the terminal's identity
  cannot be verified, process metadata cannot be read, identity changes during
  the read, or a fallback finds more than one qualifying process. The command
  still succeeds. Check whether the field is there, rather than treating a
  missing value as an empty one.
- **It is a snapshot of the foreground process.** A nested interactive shell
  reports its own directory, and a foreground command that changes directory
  temporarily replaces the shell's value. Two reads can legitimately disagree.
- **One read can be inconclusive** during a process handoff. If a title depends
  on it, read again rather than accepting the gap.
- **It is never an identifier.** Two tabs in the same directory are still two
  tabs, and `id` is what you key on.

It requires the same grant the capture does, so an ordinary tab sees the command
succeed with the field simply missing.

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
deviceterm tab rename "$id" "Auth: login screen"
```

The reference and the name are both positional. A name beginning with `-` is
read as a flag, so put `--` before it.

## Writing the title

The tab pill is narrow, so the title is read at a glance or not at all.

- **Two to four words.** Longer gets truncated by the pill.
- **Lead with the distinguishing noun.** Across five tabs in one project, the
  project name is the part that carries no information; the task is what does.
- **Say the work, not the tool.** "Auth tests" beats "npm", and "Prod DB"
  beats "psql".
- **Skip generic words.** "terminal", "shell", "session", and "tab" describe
  every tab equally.

**Never copy captured text or a path into a title verbatim.** A viewport can
hold an API key, a token, a customer name, or a password prompt, and a working
directory can carry a client's name. Summarize what the tab is for, and keep
both out of the title and out of your report.

## Confirm the rename landed

A rename receipt means the GUI returned success for the mutation, not that the
title changed. Read it back:

```sh
deviceterm tab list --all --json
```

Key on `id`, the same column you renamed by.

**Compare both `name` and `title`.** `tab rename` assigns the name, and the GUI
puts a manual rename at the top of the precedence chain behind the displayed
title, so a rename that landed makes the two agree. `name` on its own is model
metadata; `title` is the label in the tab strip, which is the thing this skill
set out to change.

## Undoing it

A quoted empty string clears the name and returns the tab to its automatic
title:

```sh
deviceterm tab rename "$id" ""
```

A bare `deviceterm tab rename` is a usage error rather than a reset. Tell the
user the empty-string form exists when you report, so a wrong title is not
something they have to live with.

## What you cannot see

Protected tabs are invisible to you. They do not appear in `tab list`, cannot be
resolved by reference, and cannot be captured or renamed, and an automation
grant does not change any of that. They are absent rather than refused, so a
short list is not proof of how many tabs the workspace has.

Report the count you acted on rather than implying you covered everything.

## When a tab refuses

A refusal on one tab is not a reason to stop on the rest. Record it, continue,
and list the skipped tabs in the report. `intent.automationRequired` on a single
tab after a successful probe usually means the grant was revoked mid-run, which
happens when the issuing GUI connection drops; re-probe before concluding
anything else.
