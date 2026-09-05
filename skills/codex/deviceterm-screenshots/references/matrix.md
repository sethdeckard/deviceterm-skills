# Driving the matrix

A complete run over device families and appearances, written to be edited
rather than run as-is. Everything here runs inside a DeviceTerm tab.

## Shape of the driver

The sections below are one script, split up for reading. **Assemble them with
every function defined before the call that uses it.** Zsh does not hoist
function definitions, so a driver loop placed above them dies on the first
call with `command not found`, and `set -e` turns that into a silent partial
run. The loop is wrapped in `main` here for that reason, and `main "$@"` is
the last line of the assembled file.

```sh
#!/bin/zsh
set -euo pipefail

APP=/path/to/YourApp.app
BUNDLE_ID=com.example.YourApp
OUT=out

# Simulators created for this run. Do not put a Simulator the user already
# booted in this list: the run boots, drives, and shuts down everything here.
typeset -A DEVICES=(
  "iphone-17-pro"  "<udid>"
  "iphone-17"      "<udid>"
  "ipad-pro-13"    "<udid>"
)

APPEARANCES=(light dark)

main() {
for family udid in ${(kv)DEVICES}; do
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b

  # A row is not readiness. Only `rendering` answers input or an AX read, so
  # wait for it: capturing earlier yields black frames from successful commands.
  deviceterm wait pane rendering --pane "$udid"

  xcrun simctl status_bar "$udid" override \
    --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3

  xcrun simctl install "$udid" "$APP"

  # Bind to this family's pane. Every pane-targeted verb fails with a
  # disambiguation list once the tab holds more than one device pane.
  DT_PANE=$udid

  for appearance in $APPEARANCES; do
    xcrun simctl ui "$udid" appearance "$appearance"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true

    # Relaunching is not the same as resetting. An app that restores its last
    # navigation state comes back on whatever screen the previous appearance
    # pass ended on, so the second pass would file that screen as 01-home.
    reset_app_state "$udid"

    xcrun simctl launch "$udid" "$BUNDLE_ID"
    wait_for_label "Home"

    mkdir -p "$OUT/$family/$appearance"
    capture_screens "$udid" "$OUT/$family/$appearance"
  done

  # Only ever shut down a Simulator this script booted.
  xcrun simctl shutdown "$udid"
done
}
```

`xcrun simctl bootstatus "$udid" -b` is worth the wait. Capturing before the
device finishes booting produces a directory of black rectangles that each
represent a successful command.

## Getting back to a known baseline

`simctl terminate` plus `launch` restarts the process. It does not clear state
the app persisted, so state restoration survives it.

Pick whichever of these your app needs, and be sure it actually runs between
passes:

```sh
reset_app_state() {
  local udid=$1

  # Strongest, and destroys the app's data along with any signed-in session:
  xcrun simctl uninstall "$udid" "$BUNDLE_ID"
  xcrun simctl install "$udid" "$APP"

  # Or, if the app takes a reset flag or a launch environment variable, prefer
  # that: it is faster and keeps the account you signed in once.
  #   xcrun simctl launch "$udid" "$BUNDLE_ID" -ResetUIState YES
}
```

An app with no state restoration needs neither, and the `wait_for_label "Home"`
guard is then enough on its own. Confirm which case you are in before assuming
the cheap path, because the failure is silent: the run completes and the wrong
screen is filed under the right name.

## Capturing one family's screens

Locate every control by label rather than by coordinate, because the same tap
point lands on different controls across screen sizes.

```sh
screenshot() {
  # Settle first. A capture taken mid-animation is a successful command and an
  # unusable file, and that is the failure this whole section exists to avoid.
  deviceterm wait surface quiescent --pane "$DT_PANE"
  xcrun simctl io "$1" screenshot "$2"
}

tap_label() {
  # Role, then label. Without the role a small decorative node outranks the
  # control, and tapping it returns a clean receipt while changing nothing.
  deviceterm tap --label "$2" --role "$1" --pane "$DT_PANE"
}

wait_for_label() {
  deviceterm wait ax --label "$1" --pane "$DT_PANE"
}
```

Both wrappers are one line because the CLI carries the whole step: `tap --label`
locates and taps in a single command, so no coordinate crosses the shell to be
captured, re-read, or reused after a rotation. `wait ax` blocks until the
element appears and exits 124 on its own deadline, so there is no poll loop to
get wrong under `set -e`.

Keep them as functions anyway — they name what the step means, and `$DT_PANE`
stays in one place.

This section no longer depends on `deviceterm-app-verify` being installed.

## Landscape cells

Rotate absolutely, and re-locate afterwards:

```sh
rotate_and_settle() {
  # `rotate` confirms: it reports the pane's `observedOrientation` and fails
  # `rotate.unconfirmed` if the device never turned, so it is the wait as well
  # as the request. Waiting on a label instead would be satisfied instantly,
  # because the label exists in the pre-rotation tree too.
  deviceterm rotate "$1" --pane "$DT_PANE"

  # Confirmation is the orientation property, not the relayout. Let the frames
  # stop before capturing.
  deviceterm wait surface quiescent --pane "$DT_PANE"
}
```

**A portrait-locked app fails here, and that is the point.** `rotate` waits up
to 4000 ms for the device to confirm, then fails `rotate.unconfirmed` with
`observedOrientation` naming what it actually saw. That is a diagnosis, where a
root-frame poll could only report that nothing changed. Settings on an iPhone
is a locked app you can test this against.

Do not read `surface` dimensions to detect the turn: they stay in the portrait
buffer's terms and do not swap on rotation.

Call it from inside `capture_screens`, where `$udid` and `$dir` are in scope
and the app is already on the screen you want in landscape. At top level, after
`main` has returned, none of those are set and no landscape cell runs at all:

```sh
capture_screens() {
  local udid=$1 dir=$2

  screenshot "$udid" "$dir/01-home.png"

  tap_label Button "Browse"
  wait_for_label "Categories"
  screenshot "$udid" "$dir/02-browse.png"

  rotate_and_settle landscape-left
  screenshot "$udid" "$dir/03-browse-landscape.png"
  rotate_and_settle portrait

  tap_label Button "Settings"
  wait_for_label "Account"
  screenshot "$udid" "$dir/04-settings.png"
}
```

Normalized coordinates follow what the device is showing, so a control's
coordinates change when the device turns, and any cached before the rotation are
wrong after it. Locating by label on each step, as `tap_label` does, sidesteps
that entirely: there is no coordinate to go stale.

Settle the return to portrait too. Leaving the next cell to start mid-rotation
moves the bug rather than fixing it.

## Running it

`main` is defined near the top but must be called at the very bottom, after
every function it reaches has been defined:

```sh
main "$@"
```

## Checking the output

Before accepting a run, look at one image per family and appearance. Four
failure modes all produce successful commands and unusable files:

- a screenshot taken during a launch animation or a loading state;
- a status bar override that did not apply, leaving the real clock in frame;
- an appearance change that the app read only at launch, so the relaunch in the
  loop above is what makes it take effect; and
- a second appearance pass that resumed on the first pass's last screen, filing
  it under `01-home.png`.

The relaunch between appearances handles the third. An app that reads the trait
at startup will otherwise render every cell in whichever mode it launched in
first.

The reset and the `wait_for_label` guard handle the fourth, which is the one
most likely to survive review: every file is present, every command succeeded,
and only the pictures are wrong.
