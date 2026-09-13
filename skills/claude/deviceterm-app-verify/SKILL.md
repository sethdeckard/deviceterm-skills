---
name: "deviceterm-app-verify"
description: "Drive an app on a Simulator from inside a DeviceTerm tab and verify what it actually did. Use when asked to test, exercise, walk through, smoke-check, or confirm a flow in an iOS, iPadOS, watchOS, or tvOS app: tapping through a screen, typing into a field, or confirming a control or label appeared. Pairs deviceterm input with accessibility reads and screenshots as evidence rather than trusting a command receipt. Covers what changes on a mirrored physical device, where structural verification is not available."
---

# Drive and verify an app

Authored against deviceterm 0.8.0. Where this skill and `deviceterm help <verb>`
disagree, believe the binary.

The whole job is one loop, run once per step of the flow:

**locate → act → verify**

Skipping the verify half is the failure this skill exists to prevent. A
`deviceterm tap` receipt says the daemon accepted a touch at a coordinate. It
says nothing about whether a button was there, whether the app reacted, or
whether the screen changed.

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

## Preconditions

Boot inside the tab so the shim attaches the pane:

```sh
xcrun simctl boot "$UDID"
```

If `deviceterm pane list` shows no Simulator pane for `$UDID`, that Simulator is
not attached to this tab and input cannot reach it. The list is never empty: it
carries every pane in the tab, your own terminal included.

Then wait for it to be ready. A row in `pane list` is not readiness: when
present, `.simulator.state` is one of `booting`, `rendering`, `shutdown`, or
`failed`. **Wait for `rendering` before acting**, so a readiness failure cannot
be mistaken for a missing element: a control that is absent and a pane that is
not up yet look identical.

```sh
deviceterm wait pane rendering --pane "$DT_PANE"
```

It blocks until the pane renders and exits 0. A cold boot reaches `rendering` in
about a second, well inside the 30000 ms default; `--timeout <ms>` moves the
bound. Pane refs resolve case-insensitively, so the UDID needs no folding.

The exit code says which thing went wrong, which a hand-rolled poll cannot: 124
is the deadline, while transport, authentication and pane-resolution failures
each keep their own code. Do not wrap this in a retry loop — it is already the
loop, and retrying hides the codes that tell you what broke.

If you need orientation on DeviceTerm itself, or the pane never appears, use the
`deviceterm` skill.

## Get the build onto the device

Run these inside the tab, so the shim can attribute what they do:

```sh
xcrun simctl install "$UDID" /path/to/YourApp.app
xcrun simctl launch "$UDID" com.example.YourApp
```

deviceterm has no install or launch verb. That is deliberate, not an omission
to work around.

## Locate

**Prefer a `deviceterm` verb over a script or a `jq` pipeline wherever one
carries the step.** A bare `deviceterm <verb>` is the most approval-prefixable
form available, so it prompts once instead of on every call, and the CLI keeps
the coordinate rules in one place rather than in each recipe.

The strongest form does not produce a coordinate at all — it locates and taps in
one command:

```sh
deviceterm tap --label "Continue" --role Button --pane "$DT_PANE"
```

When you need the coordinate itself, ask for it bare:

```sh
deviceterm wait ax --label "Continue" --role Button --print center --pane "$DT_PANE"
# 0.500000 0.365370
```

Two numbers on stdout and nothing else, ready to pass as `tap`'s two positional
arguments with no receipt to strip first. Both verbs block until the element
appears, so they replace a locate-then-poll loop as well.

To inspect rather than act, read the matches:

```sh
deviceterm wait ax --label "Continue" --match contains --pane "$DT_PANE" --json
```

Each match carries `role`, `label`, `identifier`, `value`, `frame`, and a
daemon-computed `normalizedCenter` already normalized against the root. The
field is **omitted** when the element's centre is off screen, so
`select(.normalizedCenter)` is the eligibility test — you do not need to
recompute or bounds-check geometry yourself.

**Name a `--role` whenever you intend to tap. This is required, not advisory.**
Matches are ranked presentational-last and then smallest-area-first, and only
`StaticText` and `Image` count as presentational. Everything else sorts as
actionable, so a tiny decorative node outranks the control you want: on a
29-match page, `GenericElement "Cellular"` and `"100% battery power"` ranked
above every Button and Link. Both carried a `normalizedCenter`, so preferring
the first match with a centre does not save you. Only `--role` does.

**One selector at a time.** `--identifier` and `--label` are mutually exclusive.
`--value` is a filter that narrows whichever of those you named, not a third
way to name an element — pair it with `--label` to disambiguate two controls
sharing a label. `--match contains` folds case and reaches a label carrying a
count or an ellipsis; `exact` is the default.

**`matchCount` is the true total; `matches` stops at 20.** When the list is
trimmed the receipt carries `matchesTruncated: true`, so an absent element is
not proven by a full list.

**Web views need `ax sweep`.** The tree walk does not see web content at all — a
Wikipedia article yields 6 nodes through `ax tree` (Safari's own chrome) and 46
through a sweep. Add `--source sweep` to `wait ax`, or call `deviceterm ax
sweep` directly, whenever the screen under test is a web view. A near-empty tree
over a visibly full screen is the signal.

`ax point <x> <y>` resolves a single node and is much cheaper than a sweep when
you already know roughly where to look. **Its node arrives under `element`, not
`tree`.** Decoding it as `tree` yields nothing and looks exactly like a
coordinate-mapping failure, which is a documented way to lose a round of
debugging.

When `ax tree` returns an empty `children` array, fall back to
`deviceterm ax sweep`. On watchOS the empty tree is by design and the response
carries a `note` saying so. `ax point` and `ax sweep` both echo `rootFrame`, so
the screen scale comes back with the result: never scale by the sweep root's own
frame, which is a normalized `0,0,1,1` placeholder rather than the screen.

## Act

```sh
deviceterm tap 0.5 0.5 --pane "$DT_PANE"
deviceterm text "hello@example.com" --pane "$DT_PANE"
deviceterm swipe 0.5 0.8 0.5 0.2 --duration 250 --pane "$DT_PANE"
deviceterm long-press 0.5 0.5 --duration 600 --pane "$DT_PANE"
deviceterm button home --pane "$DT_PANE"
```

`text` is ASCII only, and it never echoes what you typed back in the receipt.
Run `deviceterm help <verb>` for the rest.

## Verify

Every act step needs one of these before you move on, and prefer the first.
Set a per-run evidence directory once, before the steps below:

```sh
RUN=$(mktemp -d)
```

Write evidence into that directory, so two DeviceTerm sessions running at once
cannot overwrite each other's files and leave you asserting against the wrong
screenshot. Set it once rather than per step: a fresh `mktemp -d` inside each
step would scatter one run's evidence across several directories.

1. **Wait for the structural change.** The strongest evidence, and it blocks
   until it holds rather than sampling once:

   ```sh
   # the control you expected appeared
   deviceterm wait ax --label "Welcome" --pane "$DT_PANE"
   # the control you tapped is gone
   deviceterm wait ax --label "Continue" --state absent --pane "$DT_PANE"
   ```

2. **Screenshot.** `xcrun simctl io "$UDID" screenshot "$RUN/step-3.png"`, then
   read the image. Use this for anything the accessibility tree cannot express,
   such as layout, clipping, or colour.
3. **Ask the app.** Log output through `xcrun simctl spawn "$UDID" log stream`
   when the effect is not on screen at all.

**Read `--state absent`'s outcome precisely.** It reports `ax.disappears` only
after an observation that saw everything and matched nothing. While the element
is still there it rides its deadline and exits 124. When the observation could
not see everything — a truncated sweep, or a tree the daemon caught omitting an
on-screen element — it fails `wait.inconclusive`, which means **could not tell**
and never *still there*. Do not read an inconclusive as a pass.

**Settle before a screenshot** rather than sleeping a fixed interval:

```sh
deviceterm wait surface quiescent --pane "$DT_PANE"
```

It returns once the pane's rendered surface has held unchanged for 500 ms;
`--settle <ms>` moves that window. Stillness means *unchanged*, not advanced by
some amount, so it works the same on a Simulator and a mirrored device.

**Keep `--settle` well under `--timeout` yourself — nothing checks it.** A
settle window at or above the deadline cannot close before the deadline does, so
the command is guaranteed to fail `wait.timeout`, which reads as "the screen
never settled" rather than "those two numbers are incompatible."

## Traps that cost the most time

Run `deviceterm agents` for the full triage guide. These four account for most
wasted loops:

- **`dispatched=tap` in a swipe receipt** means `--duration` fell below the
  one-frame floor of 32 ms and the gesture collapsed into a tap. Re-run at
  `--duration 100` or higher.
- **`truncated: true` in a sweep** means the budget expired before the grid
  finished. An element missing from a truncated sweep is not evidence it is
  absent from the screen. Raise `ax sweep --budget <ms>`, unless the returned
  `note` says you are already at the ceiling, in which case widen `--step` or
  retry when the pane is quieter.
- **UDID case.** deviceterm prints lowercase, `simctl` prints uppercase.
  Compare case-insensitively or the two will never match.
- **Accessibility is Simulator-only.** `ax tree`, `ax point`, and `ax sweep`
  have no implementation for a mirrored iPhone or iPad. See the section below
  for what to do instead.

## On a mirrored physical device

The loop still holds, but two of its three steps change, so establish which
kind of device you are on before planning a run.

**Locate** has no structural option. Accessibility is Simulator-only, so every
`ax` verb, `wait ax`, and `tap --label` are unavailable. Work from the pane
visually and drive by coordinate, accepting that a coordinate is tied to one
layout and one orientation. `wait pane rendering` and `wait surface quiescent`
do work, since neither reads accessibility.

**Act** is narrower. Single-finger touch, `text`, `key`, and `app-switcher`
work. `button` and `rotate` work only when the device opens the optional
services they need. `pinch` and `crown` do not work at all.

**Verify** is visual rather than structural, but it is not manual. `xcrun
simctl` does not apply to physical hardware; `xcrun devicectl` does:

- `xcrun devicectl device capture screenshot` for a still, and
  `capture screen-record` for a recording.
- `xcrun devicectl device install app` and
  `xcrun devicectl device process launch` to get the build on and running.

Run these inside the tab, so the shim can attribute the pane. Check each
subcommand's `--help` for its flags.

Say in the report that verification was visual rather than structural. The
evidence is as capturable as on a Simulator; what is missing is the
accessibility tree, so nothing confirms *why* a screen looks right.

## Reporting

Report what you observed, not what you dispatched. For each step, give the
action and the evidence that it worked. When a step cannot be verified, say so
rather than inferring success from a successful receipt.

Longer end-to-end recipes, including a login flow and a scroll-until-visible
pass, are in [references/verification.md](references/verification.md). Read it
when a single locate-act-verify pass is not enough.

## Never shut down a Simulator you did not boot

Do not run `xcrun simctl shutdown all`, and ask before shutting down or erasing
any Simulator. Leave the fleet as you found it.
