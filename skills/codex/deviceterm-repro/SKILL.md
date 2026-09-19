---
name: "deviceterm-repro"
description: "Reproduce a reported bug on a Simulator from inside a DeviceTerm tab, and capture evidence of what happened. Use when asked to reproduce, triage, confirm, or investigate a bug report, crash, or user-reported issue in an iOS, iPadOS, watchOS, or tvOS app. Sets up device preconditions with xcrun simctl, drives to the failing state with deviceterm input, and collects screenshots, accessibility trees, and device logs. Covers what changes on a mirrored physical device, where most of that tooling does not exist."
---

# Reproduce a bug report

Authored against deviceterm 0.11.0. Where this skill and `deviceterm help <verb>`
disagree, believe the binary.

The deliverable is a verdict backed by evidence: reproduced, not reproduced, or
reproduced only under a narrower condition than the report claims. All three are
useful. Guessing is not.

## Read the report for its preconditions first

Before touching a device, extract what the report says about:

- **Device and OS.** A layout bug on a 4.7-inch screen will not appear on a
  6.9-inch one.
- **App version and build.** Reproducing on a newer build than the reporter used
  proves nothing about their build.
- **Locale, appearance, text size.**
- **Permission state.** Whether location, notifications, photos, or contacts
  were granted.
- **Network or account state.** Often the real variable, and often unstated.
- **The exact steps**, and where the reporter says it goes wrong.

Ask about anything decisive that the report leaves out, rather than picking a
value and quietly making it part of the result.

## Bind to one pane first

Every pane-targeted verb fails when the tab holds more than one device pane:

```
deviceterm: multiple panes in this tab; pass --pane <ref>:
  3eseb1      sim     4800b7e9-05f9-4c84-9c20-cf88857bb161
  rpvgzr      sim     ee15455f-838b-4721-9794-dc51c29b6d8e
```

Exit 1, with no work done. Omitting `--pane` only works while exactly one device
pane is attached, which is not a state you control. Terminal panes are panes
too, but never the target of a device verb.

Set both variables together, to the device you booted. `simctl` needs the UDID
and deviceterm needs the pane, and they are the same value:

```sh
UDID="<simulator-udid>"
DT_PANE=$UDID
```

When you did not boot it yourself, list the panes and choose one:

```sh
deviceterm pane list
```

Then set both to the UDID you mean. Taking the first row programmatically
sidesteps the loud error above, and what you get instead depends on what that
row is. The list is in layout order and includes terminal panes: a terminal
fails at once with `pane.notFound`, since a device verb cannot resolve it, while
the wrong device succeeds quietly and puts every later assertion on the wrong
screen. The quiet one is what costs a run.

Hold the **UDID**, not the short ref. Refs are minted per mount, so a Simulator
reboot reissues them and a ref baked into a script silently drives whatever
pane inherits it later.

## Set up the device

Start from a known state. Use a Simulator created for this investigation, not
one the user already had, because several of these steps destroy device state.

```sh
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
deviceterm wait pane rendering --pane "$DT_PANE"
```

**Do not look for the pane in `pane list` here.** The shim hands the boot to the
GUI and returns without waiting for the pane to be minted, so the Simulator pane
arrives after `simctl boot` has already returned. Its absence immediately
afterwards does not mean the boot bypassed the shim.

`wait pane rendering` blocks until the pane renders and exits 0. A cold boot gets
there in about a second, well inside the 30000 ms default; `--timeout <ms>` moves
the bound. Pane refs resolve case-insensitively, so the UDID needs no folding.

**Wait for `rendering` before acting**, so a readiness failure cannot be mistaken
for a missing element: a control that is absent and a pane that is not up yet
look identical. A row in `pane list` is not readiness either: when present,
`.simulator.state` is one of `booting`, `rendering`, `shutdown`, or `failed`.

The exit code narrows the problem without settling it:

- **`pane.notFound`, exit 1.** The reference matched nothing when the wait gave
  up: either no pane for that UDID ever appeared, or one appeared and then went
  away. The second arm returns immediately rather than at the deadline.
- **`wait.timeout`, exit 124.** The deadline expired: either the pane resolved
  and never reached `rendering`, or the roster request itself never completed,
  in which case nothing resolved at all.

Transport and authentication failures keep their own codes.

**Neither code proves whether the attach succeeded.** Read the error message and
the current `deviceterm pane list` before concluding that the boot bypassed the
shim, which is the diagnosis the `deviceterm` skill covers. That list is never
empty, since it carries every pane in the tab including your own terminal.


Then apply the preconditions the report names:

```sh
xcrun simctl privacy "$UDID" grant location com.example.YourApp
xcrun simctl location "$UDID" set 37.7749,-122.4194
xcrun simctl ui "$UDID" appearance dark
xcrun simctl ui "$UDID" content_size extra-large
xcrun simctl status_bar "$UDID" override --cellularMode searching
xcrun simctl install "$UDID" /path/to/ReportedBuild.app
```

Every one of these is an Apple tool. deviceterm has no verb for permissions,
location, appearance, or the status bar, by design.

**Check each one succeeded before you drive.** These are the conditions the
report names, so a silent failure means you reproduce under different
conditions than the one being reported and conclude the wrong thing about the
bug. Run them under `set -e`, or check the status of each.

## Capture the log from before the failure

Start the log stream before you drive, not after. A crash you have already
triggered is a crash whose log you have already missed:

```sh
REPRO=$(mktemp -d)
xcrun simctl spawn "$UDID" log stream \
  --predicate 'subsystem CONTAINS "com.example"' \
  > "$REPRO/device.log" &
LOG_PID=$!
```

Stop it when the run finishes: `kill "$LOG_PID"`.

## Drive to the failing state

Take one step at a time, and capture at each step rather than only at the end.
When the bug turns out to be one step earlier than the report says, only the
per-step evidence will show it.

```sh
xcrun simctl launch "$UDID" com.example.YourApp

# launch returns when the process spawns, not when the app is frontmost. An
# accessibility call in that window fails with daemon code -32020,
# `frontmostApplication returned nil`, and the wait verbs throw it rather than
# retrying through it. The window is short; retry the first call yourself
# instead of reporting that the app failed to launch.
deviceterm wait ax --label "<something only the first screen has>" --pane "$DT_PANE"

deviceterm tap --label "Continue" --role Button --pane "$DT_PANE"
deviceterm wait ax --label "<something only the next screen has>" --pane "$DT_PANE"
deviceterm wait surface quiescent --pane "$DT_PANE"
xcrun simctl io "$UDID" screenshot "$REPRO/step-1.png"
deviceterm ax tree --pane "$DT_PANE" > "$REPRO/step-1.json"
```

**Wait for the screen, then for it to stop moving.** Quiescence only proves
pixels stopped changing, which an unchanged screen satisfies perfectly — so a
tap that lands without navigating gives you a settled screenshot of the previous
step, filed under this one. In a repro that is worse than a missing file,
because it becomes evidence for the wrong claim.

Locate controls by accessibility label rather than by fixed coordinates:
`tap --label` finds the control and taps it in one command, so a repro script
carries no coordinate that a different screen size would invalidate. Name a
`--role` — without one a small decorative node can outrank the control.

Settle before capturing, so the screenshot and the tree describe the same frame
rather than two moments either side of an animation.

The `deviceterm-app-verify` skill carries the full locate-act-verify loop.

## On a mirrored physical device

Everything above assumes a Simulator. Almost none of it carries over, so decide
early which you are working with and say so in the report.

`simctl` does not apply at all. `xcrun devicectl` is its counterpart, and it
covers most of the same preconditions under different names:

| Precondition | Physical device |
|---|---|
| Install and launch | `device install app`, `device process launch` |
| Appearance | `device settings appearance` |
| Location | `device simulate location` |
| Status bar | `device simulate statusBar` |
| Biometric prompts | `device simulate biometrics` |
| Screenshot, recording | `device capture screenshot`, `capture screen-record` |
| Erase | `device settings reset` |

Run them inside the tab so the shim can attribute the pane, and check each
subcommand's `--help` for its flags.

**Two preconditions have no counterpart.** There is no equivalent of
`simctl privacy`, so permission state is a manual step on the device or a
question for the reporter. Neither is there a Dynamic Type control, so text
size is manual too. Say which of the two you set by hand.

Accessibility is the real gap. `ax tree`, `ax point`, and `ax sweep` have no
physical-device implementation, so per-step evidence is visual: you can capture
what the screen looked like, but nothing confirms which control was there.

Of deviceterm's input verbs, single-finger touch, `text`, `key`, and
`app-switcher` work. `button` and `rotate` work only when the device opens the
optional services they need. `pinch` and `crown` do not work at all.
`xcrun devicectl device orientation` can set orientation independently of
deviceterm.

State the resulting gap in the report. A physical-device reproduction is
weaker evidence than a Simulator one, because two preconditions were set by
hand and the verification was visual rather than structural.

## When it does not reproduce

A failed reproduction is a result, not a dead end. Vary one precondition at a
time and record which one changes the outcome:

- older or newer build;
- different device family or OS version;
- permission denied rather than granted;
- larger text size;
- slow or absent network.

Changing two at once and seeing the bug appear tells you nothing about which
mattered.

Report "not reproduced under these conditions" with the conditions listed. Never
report it as "cannot reproduce" without saying what you tried.

## Reporting

Give, in this order:

1. **Verdict**: reproduced, not reproduced, or reproduced under narrower
   conditions.
2. **Environment**: device, OS, build, and every precondition you set.
3. **Steps**, as run, with the evidence file for each.
4. **What happened at the failing step**, described from the screenshot and the
   tree rather than from the fact that a command succeeded.
5. **Log excerpt**, if the log shows anything at the right moment.
6. **What you could not check**, and why.

Keep the evidence directory. A verdict a reader cannot audit is an opinion.

## Never shut down a Simulator you did not boot

Do not run `xcrun simctl shutdown all`, and ask before erasing anything. Undo
the `status_bar`, `ui`, and `privacy` changes when the investigation ends, or
say in the report that they are still in place.
