---
name: "deviceterm-screenshots"
description: "Capture App Store and marketing screenshots of an app across device families, locales, and light or dark appearance, from inside a DeviceTerm tab. Use when asked for App Store screenshots, store listing images, marketing captures, or a screenshot matrix. Combines xcrun simctl for status bar, appearance, and capture with deviceterm input for navigating to each screen."
---

# App Store screenshots

Authored against deviceterm 0.11.0. Where this skill and `deviceterm help <verb>`
disagree, believe the binary.

A screenshot run is a matrix. Each cell is one device family, one locale, one
appearance, and one screen of the app. The work is making every cell reach the
same state, and making the chrome identical across all of them.

## Before starting, agree on the matrix

Ask for anything not already specified:

- **Device families.** App Store Connect wants specific sizes; confirm which.
- **Locales**, if more than one.
- **Appearance**: light, dark, or both.
- **Screens**: the list of app states to capture, in order.
- **Output layout**: where files go and how they are named.

Write the matrix down before capturing. A run that discovers halfway through
that it needed dark mode has to start over, because appearance is set before
launch.

## Never wipe the fleet

**Do not run `xcrun simctl shutdown all`.** Do not shut down or erase a
Simulator you did not boot. Switching families is exactly where this is
tempting, and a running Simulator on this machine may belong to unrelated work.

Boot what you need, leave everything else alone, and shut down only what you
booted, only after asking.

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

## Per-cell sequence

Order matters. Appearance and status bar are set before the app launches, and
the pane must be attached before deviceterm can drive it.

```sh
# 1. Boot inside the tab so the shim attaches a pane.
xcrun simctl boot "$UDID"

# 2. Wait for the device, then for the pane. `simctl boot` returns once boot
#    has been *started*, so everything below would otherwise run against a
#    device that is still coming up: the status bar override and appearance
#    can be dropped, and the launch can fail outright. Neither is recoverable
#    later, and both produce a full directory of wrong images.
xcrun simctl bootstatus "$UDID" -b
deviceterm wait pane rendering --pane "$DT_PANE"

# 3. Create the output directory. `simctl io screenshot` does not make one,
#    and fails on a path that does not exist.
mkdir -p out/iphone-17-pro/light

# 4. Freeze the chrome. Without this, every screenshot carries a different
#    clock and a different battery level, which App Store review notices.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --cellularBars 4 \
  --wifiBars 3

# 5. Appearance and locale.
xcrun simctl ui "$UDID" appearance light

# 6. Install and launch.
xcrun simctl install "$UDID" /path/to/YourApp.app
xcrun simctl launch "$UDID" com.example.YourApp

# 7. Prove the screen is the one you mean, then that it has stopped moving,
#    then capture. Both waits are needed and neither substitutes for the
#    other: the label says *which* screen, quiescence says *when*.
deviceterm wait ax --label "Home" --pane "$DT_PANE"
deviceterm wait surface quiescent --pane "$DT_PANE"
xcrun simctl io "$UDID" screenshot "out/iphone-17-pro/light/01-home.png"

# 8. Then navigate, and confirm the new screen the same way.
deviceterm tap --label "Browse" --role Button --pane "$DT_PANE"
deviceterm wait ax --label "Categories" --pane "$DT_PANE"
deviceterm wait surface quiescent --pane "$DT_PANE"
xcrun simctl io "$UDID" screenshot "out/iphone-17-pro/light/02-browse.png"
```

**Quiescence alone is not a screen check.** It proves pixels stopped changing,
which a static SpringBoard satisfies just as well as your launched app — so a
slow launch yields a correctly named screenshot of the wrong screen, and a tap
that lands without navigating yields `02-browse.png` showing the home screen.
Wait for something only the intended screen has, then settle. Substitute a real
label from the screen for `Home` and `Categories`.

Capture before you tap, and name the file after the screen it actually holds.
Writing a post-tap frame to `01-home.png` is one of the failure modes this skill
exists to catch: every command succeeds, every file is present, and only the
pictures are wrong.

**Steps 4 and 5 are preconditions, so check they succeeded.** A silently failed
`status_bar override` leaves the real clock and battery in every frame, which is
exactly what that step exists to prevent and what App Store review notices. Run
the block under `set -e`, or check each status.

**If step 2 fails, diagnose before rerunning.** `wait pane rendering` blocks
until the pane renders and exits 0; a cold boot gets there in about a second,
well inside the 30000 ms default, and `--timeout <ms>` moves the bound. Its exit
code narrows the problem without settling it:

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
empty, since it carries every pane in the tab including your own terminal. A row
in it is not readiness either: when present, `.simulator.state` is one of
`booting`, `rendering`, `shutdown`, or `failed`, so wait for `rendering` before
acting.


## Landscape

Use the absolute form:

```sh
deviceterm rotate landscape-left --pane "$DT_PANE"
```

The relative form, `deviceterm rotate left`, rotates from deviceterm's own last
rotation. An app that forces its own orientation leaves that base stale, so
relative rotations drift over a long run. Absolute is idempotent.

After rotating, re-read coordinates. Normalized coordinates are in displayed
space, so `(0,0)` is the top left of what the device is showing now, not of the
portrait screen.

## Locales

Locale is set at boot through the device's preferences, not by a deviceterm
verb. Erasing and re-preparing a Simulator per locale is the usual approach, and
it destroys that device's state, so use a Simulator created for this run rather
than one the user already had.

## Navigating reliably

Do not hardcode tap coordinates across families. A layout that centres a button
on one screen size will not on another. Locate the control by its accessibility
label each time:

```sh
deviceterm tap --label "Browse" --role Button --pane "$DT_PANE"
```

That locates and taps in one command, so nothing family-specific is computed or
stored. Name a `--role`: without one a small decorative node can outrank the
control, and tapping it returns a clean receipt while changing nothing.

When you need the coordinate rather than the tap, ask for it bare with
`deviceterm wait ax --label "Browse" --role Button --print center --pane
"$DT_PANE"`. Either way the normalization is the CLI's, computed against the
root frame — do not divide frames yourself.

The `deviceterm-app-verify` skill carries the full set of traps.

## Verify before moving to the next cell

Read the screenshot back and confirm it shows the screen you meant. A capture of
a loading spinner is still a successful `simctl io` call, and a matrix run
compounds one wrong cell into a whole directory of them.

Check the first cell of every family by eye before letting the rest of that
family run.

A full driver script covering families, appearances, landscape cells, and the
four failure modes that produce successful commands and unusable files is in
[references/matrix.md](references/matrix.md). Read it before scripting a run of
more than a couple of cells.
