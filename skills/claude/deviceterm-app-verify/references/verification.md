# Verification recipes

Longer patterns for when one locate-act-verify pass is not enough. Everything
here runs inside a DeviceTerm tab.

Every recipe passes `$DT_PANE`. Set it to the **UDID** of the device you booted,
not a short ref: refs are minted per mount, so a Simulator reboot reissues them
and a ref baked into a script silently drives whatever pane inherits it later.

```sh
UDID="<simulator-udid>"
DT_PANE=$UDID
RUN=$(mktemp -d)
```

`$RUN` is where every recipe below writes evidence. Set it once per run, here:
two DeviceTerm sessions working at the same time then cannot overwrite each
other's files and leave you asserting against the wrong screenshot. Making a
fresh one inside each recipe instead would scatter one run's evidence across
several directories.

**Prefer a `deviceterm` verb over a shell loop or a `jq` pipeline.** Each verb
below blocks until its condition holds and carries its own deadline, so none of
these recipes needs a hand-rolled poll. A bare `deviceterm <verb>` also reduces
to a durable approval prefix, where a script or a pipeline prompts again on
every call.

**Name a `--role` when the coordinate will be tapped.** Matches rank
presentational-last then smallest-area-first, and only `StaticText` and `Image`
count as presentational — everything else sorts as actionable, so a small
decorative node outranks the control you want. Omit `--role` only when you are
asking whether a string is on screen at all and will not act on the result.

## Wait for a pane to start rendering

```sh
if ! xcrun simctl boot "$UDID"; then
  printf 'failed to boot Simulator %s\n' "$UDID" >&2
  exit 1
fi

deviceterm wait pane rendering --pane "$DT_PANE"
```

`deviceterm events` has no replay, so a subscription established after the
change never sees it. `wait` probes current state immediately and then blocks,
which is the shape that cannot miss the transition.

A cold boot reaches `rendering` in about a second, well inside the 30000 ms
default. The exit code distinguishes causes a hand-rolled poll cannot: 124 is
the deadline, while transport, authentication and pane-resolution failures keep
their own codes.

## Wait for an element instead of sleeping

A fixed `sleep` after a tap is either too short, and flaky, or too long, and
slow. Wait for the thing you expect:

```sh
deviceterm wait ax --label "Sign out" --pane "$DT_PANE"
```

And for the other half — the control you tapped going away:

```sh
deviceterm wait ax --label "Sign in" --state absent --pane "$DT_PANE"
```

**Read `--state absent`'s outcome precisely.** It reports `ax.disappears` only
after an observation that saw everything and matched nothing. While the element
is still there it rides its deadline and exits 124. When the observation could
not see everything — a truncated sweep, or a tree the daemon caught omitting an
on-screen element — it fails `wait.inconclusive`, which means **could not tell**
and never *still there*. Treating an inconclusive as a pass asserts the opposite
of what was observed.

## Settle before a screenshot

```sh
deviceterm wait surface quiescent --pane "$DT_PANE"
xcrun simctl io "$UDID" screenshot "$RUN/step-3.png"
```

Returns once the rendered surface has held unchanged for 500 ms; `--settle <ms>`
moves that window. Use it after a transition with no element to wait for — a
Dynamic Type change, a theme flip, an animation landing.

**It answers *when*, never *which*.** A screen that never changed is perfectly
quiescent, so on its own this will happily settle on the previous screen after a
tap that did not navigate, or on SpringBoard while a slow launch is still
coming up. Whenever the capture is meant to show a particular screen, wait for
something only that screen has first, then settle:

```sh
deviceterm wait ax --label "Categories" --pane "$DT_PANE"
deviceterm wait surface quiescent --pane "$DT_PANE"
```

**Keep `--settle` well under `--timeout` yourself — nothing checks it.** A
settle window at or above the deadline cannot close before the deadline does, so
the command is guaranteed to fail `wait.timeout`, which reads as "the screen
never settled" rather than "those two numbers are incompatible."

## A login flow, end to end

Each step acts and then proves the act landed. No coordinate crosses the shell:
`tap --label` locates and taps in one command, so there is nothing to capture,
re-read, or accidentally reuse.

```sh
# 1. Email.
deviceterm tap --label "Email" --role TextField --pane "$DT_PANE"
deviceterm text "user@example.com" --pane "$DT_PANE"

# 2. Read the field back rather than trusting the receipt.
deviceterm wait ax --label "Email" --value "user@example.com" \
  --match contains --pane "$DT_PANE"

# 3. Password.
deviceterm tap --label "Password" --role SecureTextField --pane "$DT_PANE"
deviceterm text "hunter2" --pane "$DT_PANE"

# 4. Submit.
deviceterm tap --label "Sign in" --role Button --pane "$DT_PANE"

# 5. Verify by presence, then capture a screenshot as evidence.
deviceterm wait ax --label "Sign out" --timeout 15000 --pane "$DT_PANE"
deviceterm wait surface quiescent --pane "$DT_PANE"
xcrun simctl io "$UDID" screenshot "$RUN/signed-in.png"
```

**Step 2 is why `--value` exists, and getting it wrong is a silent pass.** Typed
text lands in the field's `value`; its `label` stays whatever the field is
called. So `wait ax --label "user@example.com"` does *not* find the field — it
can instead match a transient autocomplete suggestion whose label happens to be
the typed string, and report success while testing nothing. Name the field with
`--label` and narrow it with `--value`, which filters the element you already
named rather than being a third way to name one.

The password step deliberately has no read-back: a secure field does not expose
its value through accessibility, so the only honest verification is the state
that follows submission.

## Scroll until an element is on screen

Accessibility reports what is rendered. An element below the fold is genuinely
absent from the tree, so scroll and re-read rather than concluding it is
missing.

There is no non-blocking "is it there right now" query, so use a short
`--timeout` as the probe and read the exit code:

```sh
# Reset both. These snippets are pasted into a tab's shell, which persists
# between runs, so a `found=1` left by an earlier successful run would satisfy
# the check at the bottom even after this run exhausted every swipe.
found=
swipes=0
while :; do
  # Capture the status in both branches. A false `if` with no `else` reports
  # the compound command as successful, so a bare `rc=$?` after `fi` reads 0
  # and the check below then exits 0 without ever having found the element.
  if deviceterm wait ax --label "Delete account" --role Button \
      --timeout 1000 --pane "$DT_PANE" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  [ "$rc" -eq 0 ] && { found=1; break; }
  # Only 124 means "not on screen yet". Anything else is a real failure, and
  # swiping more times would bury it.
  [ "$rc" -ne 124 ] && { printf 'lookup failed (exit %s)\n' "$rc" >&2; exit "$rc"; }

  # Check once more after the last swipe. A `for` over five iterations swipes
  # five times but looks only five times, so whatever the fifth swipe revealed
  # is reported as never found.
  [ "$swipes" -ge 5 ] && break
  swipes=$(( swipes + 1 ))

  deviceterm swipe 0.5 0.8 0.5 0.3 --duration 250 --pane "$DT_PANE"
  deviceterm wait surface quiescent --settle 200 --pane "$DT_PANE"
done
[ -n "${found:-}" ] || { printf 'never saw Delete account\n' >&2; exit 1; }
```

`--duration 250` matters. Below the one-frame floor of 32 ms the swipe collapses
into a tap and the receipt reports `dispatched=tap`.

Waiting for quiescence rather than sleeping between swipes means the next read
happens once the scroll has actually stopped, not after a guess.

## Web views need a sweep

The tree walk does not see web content at all. A fully-loaded Wikipedia article
yields 6 nodes through `ax tree` — Safari's own chrome — and 46 through a sweep.
A near-empty tree over a visibly full screen is the signal.

```sh
deviceterm wait ax --label "Continue" --source sweep --budget 20000 --pane "$DT_PANE"
```

A sweep queries by point across a grid, so it reaches what the walk cannot. It
is much slower, and `truncated: true` means the budget expired before the grid
finished — an element missing from a truncated sweep is not evidence it is
absent.

## Capture evidence for a report

Keep the artifacts alongside the claim, so a reader can check the work:

```sh
STEP=3
deviceterm wait surface quiescent --pane "$DT_PANE"
xcrun simctl io "$UDID" screenshot "$RUN/step-$STEP.png"
deviceterm ax tree --pane "$DT_PANE" > "$RUN/step-$STEP.json"
```

The tree is the machine-checkable half and the screenshot is the human-readable
half. A report that includes both can be audited; one that only says the tap
succeeded cannot.

Capture both after the same quiescence wait, so the tree and the image describe
the same frame rather than two moments either side of an animation.

## UDID case

deviceterm prints UDIDs lowercase and `simctl` prints them uppercase. Pane refs
resolve case-insensitively, so this never bites `--pane`; it bites only a
literal string comparison between the two tools' output.

## When accessibility is not available

On a mirrored iPhone or iPad there is no `ax` implementation at all, so every
`ax` verb, `wait ax`, and `tap --label` are unavailable. Single touch, `text`,
`key`, and `app-switcher` work; `pinch` and `crown` do not. `wait pane
rendering` and `wait surface quiescent` do work, since neither reads
accessibility — so the settle-then-capture pattern above still holds.

Verify by screenshot, and say in the report that verification was visual rather
than structural.
