---
name: "deviceterm-tab-titles"
description: "Read every visible DeviceTerm tab, summarize what each one is doing, and retitle it so the tab strip is scannable. Use when asked to name, label, retitle, or tidy up tabs, or to say what each tab is working on. Requires an automation tab, because reading and retitling another tab needs a live automation grant that only a person can issue from the GUI. Proposes every title for approval before renaming anything."
---

# Retitle the tabs

Authored against deviceterm 0.11.0. Where this skill and `deviceterm help <verb>`
disagree, believe the binary.

Read each visible tab, work out what it is doing, and give it a short title.
The user ends up with a tab strip they can scan instead of a row of identical
shell names.

## This needs an automation tab

`pane capture-text` and cross-tab `tab rename` both require a live automation
grant. Only a person can issue one, from **Shell > Open Automation Tab**. There
is no CLI escalation path, so if you are not in such a tab, this skill cannot
run and no flag changes that.

Ask the daemon directly rather than inferring:

```sh
deviceterm session show --json
```

`automationGrant` is always present and always a boolean, and it is the
authority. A tab holding no grant gets `false` and **exit 0**, not a refusal, so
this costs nothing to check first.

```jsonc
{"automationGrant":false,"id":"c5974ee1-...","role":"agent"}
```

Three ways to read this wrong:

- **`role` is not the grant.** It is descriptive metadata and can read
  `"automation"` while `automationGrant` is false, which is what you see once
  the issuing GUI connection drops. Never branch on it, and never branch on
  `$DEVICETERM_SESSION_ROLE` either.
- **A missing daemon is not a missing grant.** An unreachable daemon fails with
  `transport.unavailable` or `transport.timeout`, a nonzero exit, and no
  `automationGrant` key at all. "You hold no grant" and "DeviceTerm is not
  running" send the user to opposite fixes.
- **`id` and `role` are absent outside a DeviceTerm tab.** That is still a
  successful report with `automationGrant: false`.

On `false`, say so, tell the user to open an automation tab with
**Shell > Open Automation Tab** and rerun there, and stop.

## Read the whole workspace in one call

```sh
deviceterm pane list --all --json
```

`--all` spans every caller-visible tab in every window, ordered window, then
tab, then layout. Without it you see only your own tab, which turns a
workspace-wide job into a tab-local one without saying so. Passing `--all` and
`--tab` together is a usage error.

Every row carries the tab context, so this one call is both the tab list and the
pane list:

- `tabId` is the rename target and the grouping key.
- `tabTitle` is the tab's current display title.
- `windowId` groups tabs into windows.
- `current` is true for your own terminal pane. **Drop that row's tab** unless
  the user asked for the automation tab to be retitled too.
- `kind` is `terminal`, `simulator`, or `device`. Only `terminal` rows can be
  captured, and their `id` is what `pane capture-text` wants.

Group the rows by `tabId` and you have the tabs, each with the terminals it
holds. Counting its `kind == "terminal"` rows tells you how many captures that
tab costs.

**`tabTitle` is not the pane's title.** It follows the tab's focused pane, so
every row in a split tab carries the same `tabTitle` and it describes only one
of them. When the focused pane is a Simulator it takes that pane's name, and a
terminal row's `tabTitle` then names something that is not a terminal at all.

A result holding only your own row means no other tabs are visible. **That is
not proof the workspace has one tab**, because protected tabs are absent from
it.

## `terminal.title` is free signal

Every terminal row carries `terminal.title`, the pane's own label. It resolves
to the first of these that survives normalization: the OSC 0/2 title the running
program set, the pane's `name`, the basename of the shell's OSC 7 directory,
then `"shell"`.

Read it before deciding whether a capture is worth it. A row reporting
`vim Login.swift` has already told you what that pane is doing; a row reporting
`"shell"` has told you it will not.

It is also the answer for a split tab, where one `tabTitle` covers several
panes that are doing different things. Each terminal reports its own.

Three things to know:

- **`pane rename` writes `name`, which ranks below the OSC title**, so a renamed
  pane keeps reporting whatever set that title. A shell normally sets one, so a
  pane name usually never surfaces as the title at all. Read `name` for what the
  user called the pane and `title` for what it is doing now.
- **It can be absent.** `--json` relays the GUI's bytes unchanged, so a CLI
  from a newer bundle paired with an older GUI emits terminal rows with no
  `title` until DeviceTerm restarts. Test for the field and fall back to the
  capture; why it is missing does not change what you do about it.
- **It is live.** A title read moments apart can differ, because it follows
  whatever the shell is doing.

## Capture the terminals worth capturing

```sh
deviceterm pane capture-text "$paneId"
```

**Capture every terminal a tab holds, not just the first.** A split tab is often
split precisely because two different things are happening in it, and reading
one side gives you a title for half the tab. Say which panes produced the signal
when you report.

**Capture is the visible viewport, with no scrollback.** What you get is the
screen right now. A tab whose interesting work scrolled off shows a bare prompt,
and a tab running a full-screen editor shows that editor rather than the project.

So the signal is uneven, and you should say which kind you got:

- A build, test run, or REPL mid-flight is usually legible.
- A bare prompt tells you almost nothing beyond the working directory.
- A full-screen TUI tells you the tool, and often the file, but not the task.

## The working directory comes free

Terminal rows in that same `pane list --all` response carry a live working
directory at `terminal.cwd`, so a bare prompt still tells you which project the
tab belongs to. No extra call is needed.

It is the one field in that response the grant gates. From an automation tab it
appears on every terminal row, including panes in other tabs; from an ordinary
tab the command still succeeds and the field is simply gone, even for the
caller's own pane. Owning the terminal is not an exemption.

Four things to know before you title from it:

- **Absent is routine.** Besides the ungranted case, DeviceTerm omits it when
  the terminal's identity cannot be verified, process metadata cannot be read,
  identity changes during the read, or a fallback finds more than one qualifying
  process. Check whether the field is there rather than treating a missing value
  as an empty one.
- **It is a snapshot of the foreground process.** A nested interactive shell
  reports its own directory, and a foreground command that changes directory
  temporarily replaces the shell's value. Two reads can legitimately disagree.
- **One read can be inconclusive** during a process handoff. If a title depends
  on it, read again rather than accepting the gap.
- **It is never an identifier.** Two tabs in the same directory are still two
  tabs, and `tabId` is what you key on.

A `pane capture-text` receipt nests its own copy of the pane object, and that
copy carries no `cwd` even for a granted caller. Read the directory from
`pane list`, not from the capture.

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
deviceterm tab rename "$tabId" "Auth: login screen"
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
directory or a `terminal.title` can carry a client's name. Summarize what the
tab is for, and keep both out of the title and out of your report.

## Confirm the rename landed

A rename receipt means the GUI returned success for the mutation, not that the
title changed. Read it back:

```sh
deviceterm tab list --all --json
```

This is the one step `pane list` cannot do, because a pane row carries no tab
`name`. Key on `id`, the same column you renamed by.

**A landed rename makes `name` and `title` agree.** `tab rename` assigns the
name, and the GUI puts a manual rename at the top of the precedence chain behind
the displayed title, so both read the value you set. `name` on its own is model
metadata; `title` is the label in the tab strip, which is the thing this skill
set out to change.

**An unnamed tab has no `name` key at all.** It is absent rather than empty, so
test for its presence; comparing it as a string treats every never-renamed tab
as though it were named `""`.

## Undoing it

A quoted empty string clears the name and returns the tab to its automatic
title:

```sh
deviceterm tab rename "$tabId" ""
```

That removes the `name` key outright and lets `title` fall back to the live
shell title. A bare `deviceterm tab rename` is a usage error rather than a
reset. Tell the user the empty-string form exists when you report, so a wrong
title is not something they have to live with.

## What you cannot see

Protected tabs are invisible to you. They do not appear in `pane list` or
`tab list`, cannot be resolved by reference, and cannot be captured or renamed,
and an automation grant does not change any of that. They are absent rather than
refused, so a short list is not proof of how many tabs the workspace has.

Report the count you acted on rather than implying you covered everything.

## When a tab refuses

A refusal on one tab is not a reason to stop on the rest. Record it, continue,
and list the skipped tabs in the report.

Two codes, and they mean different things:

- **`session.unauthorized`** is the grant being gone. `pane capture-text` is
  refused before the request reaches the GUI, so this is what a capture returns
  with no live grant. After a successful probe it usually means the grant was
  revoked mid-run, which happens when the issuing GUI connection drops. Re-run
  `session show` before concluding anything else.
- **`intent.automationRequired`** is an ownership check the GUI raised on a
  specific target, which is what `tab rename` returns for a tab you neither own
  nor hold a grant for.

Both carry `rpcCode -32011`, so the number cannot tell them apart. Branch on
`.error.code`.
