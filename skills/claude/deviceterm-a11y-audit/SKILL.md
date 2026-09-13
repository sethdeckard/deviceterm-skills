---
name: "deviceterm-a11y-audit"
description: "Audit an app's accessibility on a Simulator from inside a DeviceTerm tab. Use when asked to check accessibility, VoiceOver labels, a11y coverage, hit target sizes, or Dynamic Type behavior in an iOS, iPadOS, watchOS, or tvOS app. Sweeps the accessibility tree for unlabeled controls and undersized touch targets, and drives text size changes through xcrun simctl."
---

# Accessibility audit

Authored against deviceterm 0.8.0. Where this skill and `deviceterm help <verb>`
disagree, believe the binary.

## State the limit before you start

**Accessibility is Simulator-only.** `ax tree`, `ax point`, and `ax sweep` have
no implementation for a mirrored iPhone or iPad. If the target is physical
hardware, say so and stop; there is no partial version of this audit that works
there.

This audit is also not a substitute for Accessibility Inspector or for testing
with VoiceOver switched on, which `xcrun devicectl device settings voiceover`
can do on a physical device. It finds structural problems that are visible in the
tree. It cannot judge whether a label reads well aloud, whether focus order
makes sense, or whether an announcement fires at the right moment. Say that in
the report rather than implying full coverage.

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

## Per screen

Audit one screen at a time. The tree describes what is rendered now, so a single
pass covers exactly one state of the app.

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
AX_AUDIT=${AX_AUDIT:-}
if [ -n "$SKILL_DIR" ] && [ -x "$SKILL_DIR/helpers/ax-audit.py" ]; then
  AX_AUDIT=$SKILL_DIR/helpers/ax-audit.py
fi
for candidate in \
  "$HOME/.claude/skills/deviceterm-a11y-audit/helpers/ax-audit.py" \
  "$HOME/.codex/skills/deviceterm-a11y-audit/helpers/ax-audit.py"; do
  if [ -z "$AX_AUDIT" ] && [ -x "$candidate" ]; then AX_AUDIT=$candidate; fi
done
[ -x "$AX_AUDIT" ] || { echo "ax-audit.py not found; set SKILL_DIR or AX_AUDIT" >&2; exit 1; }
"$AX_AUDIT" --pane "$DT_PANE"
```

The loop covers the two standard skills directories only. **A plugin install
is not covered**, because its path carries a marketplace name and a version
with nothing stable to test for; set the variable yourself from wherever you
read this file. A relative `helpers/ax-audit.py` would resolve from your shell's
current directory, which in a DeviceTerm tab is normally the app repo rather
than the skill.

It reports two findings per node:

- `unlabeled` — an interactive node with no `label`. Nothing announces it, so
  VoiceOver reads it as its role alone. An `identifier` does not rescue it:
  `accessibilityIdentifier` is test metadata and is never spoken. Neither does a
  `value`, which carries state ("On") rather than purpose. The helper prints
  whichever of the two exists, because that is how you find the control in
  source, not because it counts as a name.
- `small-target` — an interactive node under 44 pt on either axis, the Human
  Interface Guidelines minimum. Adjust with `--min-target`.

Exit codes, which matter if you script this:

| Code | Meaning |
|------|---------|
| 0 | Clean, and coverage was complete |
| 1 | Findings reported |
| 2 | Usage error |
| 3 | Coverage incomplete, from a truncated sweep |
| 4 | The audit could not run |

**Code 3 is not a clean result.** A truncated sweep that happens to contain no
findings still exits 3, because the grid never finished and the elements it
never reached are unknown, not absent.

**Code 4 is not a finding.** It means deviceterm failed, the response would not
parse, the root frame was degenerate, or the tree came back empty. Keeping it
apart from 1 is what lets a per-screen record distinguish "this screen has
problems" from "this screen was never audited", and an empty tree is routine on
watchOS rather than exceptional.

## When the tree comes back empty

```sh
"$AX_AUDIT" --sweep --pane "$DT_PANE"
```

An empty `children` array is routine on watchOS and is by design; the response
carries a `note` saying so. The sweep grid-walks the screen with point queries
instead of relying on the tree walk.

**Read `truncated` back before trusting a sweep.** When the daemon's budget
expires mid-grid the sweep returns what it has, successfully, with
`truncated: true`. A control missing from a truncated sweep is not proven
absent. The helper warns on stderr and exits 3 when this happens, so a script
that only checks for a zero exit will not mistake partial coverage for a pass.

The remedy depends on which truncation you got, and the daemon says which in a
`note` field the helper echoes:

- **Stopped at its budget.** Buy a longer walk:
  `"$AX_AUDIT" --sweep --budget 30000 --pane "$DT_PANE"`. The budget defaults to 10000 ms and is
  clamped into `[0, 60000]`, silently, so read `budgetMs` back for what you
  actually got.
- **Stopped at the largest budget allowed.** Raising the budget is the one
  response that cannot work, since it is already at the ceiling. Widen `--step`
  instead, or retry when the pane is serving fewer accessibility reads.

Do not predict which side of the budget a sweep lands on. Sweep cost is
`ceil(1/step)^2` queries, 400 at the default step of 0.05 and 2500 at the 0.02
floor, but whether those fit depends on the host and the device. Read
`truncated`.

A sweep that truncates with `sweepedPoints` at zero never reached the bridge at
all, so it says nothing about whether accessibility is working. Retry that one.

## Dynamic Type

Text size is a `simctl` setting, not a deviceterm verb. Sweep the sizes that
break layouts:

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
AX_AUDIT=${AX_AUDIT:-}
if [ -n "$SKILL_DIR" ] && [ -x "$SKILL_DIR/helpers/ax-audit.py" ]; then
  AX_AUDIT=$SKILL_DIR/helpers/ax-audit.py
fi
for candidate in \
  "$HOME/.claude/skills/deviceterm-a11y-audit/helpers/ax-audit.py" \
  "$HOME/.codex/skills/deviceterm-a11y-audit/helpers/ax-audit.py"; do
  if [ -z "$AX_AUDIT" ] && [ -x "$candidate" ]; then AX_AUDIT=$candidate; fi
done
[ -x "$AX_AUDIT" ] || { echo "ax-audit.py not found; set SKILL_DIR or AX_AUDIT" >&2; exit 1; }

RUN=$(mktemp -d)

: > "$RUN/status.tsv"

for size in small large extra-large accessibility-extra-extra-extra-large; do
  # Both of these are preconditions, so a failure has to stop this size rather
  # than fall through. Otherwise the loop audits the *previous* text size and
  # files the result under this one, which is a wrong answer wearing the right
  # filename. `set -e` is not the fix here: the audit below deliberately runs
  # with a nonzero status and needs the loop to survive it.
  if ! xcrun simctl ui "$UDID" content_size "$size"; then
    printf '%s\tSKIPPED content_size failed\n' "$size" >> "$RUN/status.tsv"
    continue
  fi

  # A Dynamic Type change relays out the whole screen. Wait for the frames to
  # stop rather than guessing an interval: auditing mid-relayout measures
  # targets that are still moving, and the screenshot would catch the same
  # half-finished frame.
  if ! deviceterm wait surface quiescent --pane "$DT_PANE"; then
    printf '%s\tSKIPPED never settled\n' "$size" >> "$RUN/status.tsv"
    continue
  fi

  # Capture the status rather than letting it escape. Findings exit 1 and a
  # truncated sweep exits 3, so both are expected here: under `set -e` either
  # would abandon the sweep partway, and without it the screenshot below
  # overwrites `$?` and the audit result is lost.
  #
  # Not named `status`: zsh reserves that as a read-only alias for `$?`, and
  # assigning to it aborts the loop on the first iteration.
  audit_status=0
  "$AX_AUDIT" --pane "$DT_PANE" > "$RUN/a11y-$size.txt" 2>&1 || audit_status=$?

  # The screenshot is evidence, not decoration, so a failure has to reach the
  # status column. Writing the audit's number alone would file this size as
  # complete while the image that shows truncation and clipping is missing.
  if xcrun simctl io "$UDID" screenshot "$RUN/a11y-$size.png"; then
    printf '%s\t%s\n' "$size" "$audit_status" >> "$RUN/status.tsv"
  else
    printf '%s\t%s NO SCREENSHOT\n' "$size" "$audit_status" >> "$RUN/status.tsv"
  fi
done

cat "$RUN/status.tsv"
```

Read the status column before the reports. A `3` means that size was never
fully swept, so its report understates the findings and cannot be compared
against the others. A `4` means it was never audited at all. A `SKIPPED` row
means the size was never applied or the screen never settled, so no report or
screenshot exists for it. `NO SCREENSHOT` means the audit ran but its image is
missing, which matters because the image is the half that catches truncation
and clipping.

Report any of those as a gap rather than presenting three sizes as four.

The screenshot is the point of this loop. Truncation, clipping, and overlap are
layout failures the tree cannot express: a label that is cut off still reports
its full string. Read the images, do not just diff the reports.

## Reading a finding before reporting it

Node roles and labels come from private Apple accessibility frameworks and are
best-effort. Two consequences:

- A role the audit does not recognize may still be interactive. The helper
  treats an unknown role carrying a subrole as interactive for this reason, so
  expect occasional findings on things that are not really controls.
- An empty label is sometimes correct. A decorative image should not be
  announced. Judge each finding against what the control does rather than
  treating the list as a defect count.

Confirm anything you intend to report:

```sh
deviceterm ax point 0.5 0.42 --pane "$DT_PANE"
```

That resolves the single node at a point, which is cheaper than a sweep and
confirms you are looking at the control you think you are.

## Reporting

Group by screen, and for each finding give the role, the label if any, the
frame, and what a user would experience. Distinguish the three confidence
levels honestly:

- confirmed by a second `ax point` read;
- reported by the tree but not separately confirmed; and
- not covered, because the sweep truncated or the screen was never visited.

Never present a truncated sweep as full coverage.

## Never shut down a Simulator you did not boot

Do not run `xcrun simctl shutdown all`. `content_size` changes persist on the
device, so restore the original value when the audit finishes.
