---
name: "deviceterm"
description: "Orient inside DeviceTerm and route to its CLI. Use when working in a DeviceTerm tab, or when a task involves driving an iOS, iPadOS, watchOS, or tvOS Simulator or a mirrored iPhone or iPad: tapping, typing, swiping, reading the accessibility tree, or managing tabs and panes. Establishes what the deviceterm CLI owns, what belongs to xcrun simctl and devicectl, and where the authoritative command reference lives."
---

# DeviceTerm

DeviceTerm is a macOS terminal that runs live Apple device panes beside your
shell. The tab is the workspace: one shell, plus the device panes that tab owns.

Authored against deviceterm 0.8.0. **The CLI is the authority.** Where this
skill and `deviceterm help <verb>` disagree, believe the binary and say so.

## Confirm you are in a tab before anything else

```sh
printf '%s\n' "${DEVICETERM_SESSION:-NOT-IN-A-DEVICETERM-TAB}"
```

If that prints the sentinel, this shell is not a DeviceTerm tab. Say so plainly
and stop. No device control is available from here, and no flag changes that.

Inside a tab four variables are set: `DEVICETERM_SESSION`,
`DEVICETERM_SESSION_CAP`, `DEVICETERM_DAEMON_SOCK`, and `DEVICETERM_SHIM_DIR`.
The CLI reads them itself. No verb takes a credential, so never pass one as an
argument, and never strip these from a subprocess environment.

## How a device gets into a tab

Pane attachment is shim-driven. `xcrun simctl boot <UDID>` run inside a tab
hits DeviceTerm's shim first, which asks the daemon to attach the booted
Simulator to that tab. A Simulator booted anywhere else stays invisible to
`deviceterm pane list` however healthy it is.

When an input command reports no device pane, check in this order:

```sh
deviceterm pane list
which xcrun
deviceterm doctor
```

`which xcrun` must resolve inside `$DEVICETERM_SHIM_DIR`. If it resolves to
`/usr/bin/xcrun`, the shim is not first on `PATH` and boots are not being
intercepted; open a fresh tab.

`deviceterm device attach <ref>` is the explicit path for a Simulator booted
elsewhere, and for mirroring a connected iPhone or iPad.

## Division of labor

The `deviceterm` CLI owns input, accessibility, and the workspace: `tap`,
`swipe`, `long-press`, `pinch`, `app-switcher`, `button`, `key`, `text`,
`rotate`, `crown`, `ax tree|point|sweep`, the `window`, `tab`, and `pane`
resources, `events`, and `doctor`.

Apple's tools own the device's lifecycle and content. **The verbs below do not
exist in deviceterm. Do not go looking for them.**

| What you want | What to run |
|---|---|
| Screenshot or video | `xcrun simctl io <udid> screenshot` / `recordVideo` |
| Install or launch an app | `xcrun simctl install` / `launch` |
| Set location | `xcrun simctl location` |
| Send a push notification | `xcrun simctl push` |
| Light/dark, Dynamic Type, status bar | `xcrun simctl ui` / `status_bar` |
| Device logs | `xcrun simctl spawn <udid> log` |
| Every Simulator on the machine | `xcrun simctl list devices` |

`deviceterm devices list` reports only what DeviceTerm owns or is mirroring, so
it is not a substitute for `simctl list`.

**On a physical device none of those `simctl` commands apply.** `xcrun
devicectl` is the counterpart, and it covers most of the same ground under
different names: `device capture screenshot`, `device install app`,
`device process launch`, `device settings appearance`,
`device simulate location`, and `device simulate statusBar`. Permission state
and Dynamic Type have no counterpart there.

Run `simctl` and `devicectl` from inside the tab, so the shim can attribute
what they do.

## Read the reference before composing a command

```
deviceterm help          # every verb, one line each
deviceterm help <verb>   # the full reference for one verb
deviceterm agents        # workflow and triage guide, organized by task
deviceterm doctor        # env, shim, socket, session, and pane diagnosis
```

`deviceterm agents` carries the traps: why a swipe collapsed into a tap, why a
crown rotation did nothing, why an accessibility tree came back empty. Read it
when debugging one of those instead of guessing.

**Prefer a verb over a script or a `jq` pipeline wherever one carries the
step.** A bare `deviceterm <verb>` reduces to a durable approval prefix, so it
prompts once rather than on every call, and it keeps rules like coordinate
normalization in the CLI instead of copied into each recipe. The blocking
`wait` verbs in particular replace hand-rolled poll loops, and they report
*which* thing failed where a loop can only report that nothing happened yet.

## Reading output

- `--json` works on lists and receipts. `ax` and `events` are always JSON.
- **Typed failures emit a newline-terminated `{"error": …}` object on stdout**
  under `--json`, and on the AX commands even without it. The human diagnostic
  still goes to stderr and the exit status is still nonzero, so check the status
  first — but the machine-readable half is there. **Branch on `.error.code`,
  never on `.error.message` or stderr prose.** A few command-specific failures
  predate the typed contract and still produce empty stdout, so handle a missing
  envelope rather than assuming one.
- Absent optional fields are omitted, not null. Test with `jq 'has("shortId")'`.
- A receipt means the daemon accepted the dispatch. It is not evidence that the
  effect happened. Read state back to confirm.
- deviceterm prints UDIDs lowercase and `simctl` prints them uppercase. Compare
  case-insensitively across that boundary.

## Authority

A live automation grant is created only by a person, through
Shell > Open Automation Tab. Three rules, and the difference between them
matters:

1. **Always gated.** Eight commands are refused without a grant no matter what
   they target: `tab open`, `tab focus`, `tab move`, `window open`,
   `window focus`, `pane focus`, `pane send-input`, and `pane capture-text`.
   They create or rearrange workspace surfaces, change focus, or read or drive
   terminal contents. The grant check is independent of target ownership, so
   owning the tab does not exempt you. That list is closed.
2. **Ownership, which a grant can stand in for.** Mutations are allowed on what
   you own, `tab close`, `window close`, `tab rename`, `tab protect`,
   `tab unprotect`, `pane split`, `pane close`, and `pane rename` among them. A
   grant satisfies the same check for someone else's visible surfaces, so your
   own tab needs no grant and a sibling's does. This list is open, unlike rule
   1, so treat an unlisted mutation as ownership-gated rather than free.
3. **Protection, which a grant cannot stand in for.** A protected tab is
   invisible to every session outside it, and no grant makes it visible.

Three edges inside rule 2. A terminal pane is its own trust unit, so owning one
terminal in a split tab does not let you close or rename its sibling.
`tab close` needs your tab to be the sole terminal, because a tab can hold
several. And `window close` needs that of every tab in the window, so one
sibling terminal anywhere in it refuses the close.

Reading rule 1 as the whole story is the trap: it suggests everything else is
unrestricted across tabs, and it is not.

There is no CLI escalation path, so a script cannot grant itself authority and
cannot open its own first tab or window. It can still `pane split` its own tab.
Under `--json` a refusal carries `intent.automationRequired` when the resolved
target needs ownership you lack or a grant, and `session.unauthorized` when
session authority itself is refused. Branch on `.error.code`.

`$DEVICETERM_SESSION_ROLE` is descriptive metadata, not permission. The role
stays descriptive when the grant is missing or revoked, so a tab can read
`automation` while holding no authority at all. A verb listed by
`deviceterm help` can still be refused.

## Never shut down a Simulator you did not boot

Do not run `xcrun simctl shutdown all`, and do not shut down or erase a
Simulator the user booted. Ask first. A Simulator on this machine may belong to
work that has nothing to do with your task.

## Related skills

- `deviceterm-app-verify` for driving an app and proving what it did.
- `deviceterm-screenshots` for App Store and marketing captures.
- `deviceterm-a11y-audit` for accessibility sweeps.
- `deviceterm-repro` for reproducing a bug report.
- `deviceterm-tab-titles` for summarizing and retitling tabs, from an
  automation tab.
