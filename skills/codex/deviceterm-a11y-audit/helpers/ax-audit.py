#!/usr/bin/env python3
# Why this exists: an accessibility audit is a set of predicates over every node
# in the tree, and writing them as a jq pipeline puts a fresh, unapprovable
# command in every step on Codex. It also centralizes the two checks that are
# easy to get wrong by hand: reading `truncated` back off a sweep before
# trusting its coverage, and refusing to run at all when the root frame is
# degenerate rather than reporting every control as undersized.
#
# Usage:  ax-audit.py [--pane <ref>] [--sweep] [--budget <ms>] [--min-target 44]
#
# Reads the accessibility tree and reports two findings:
#
#   unlabeled    an interactive node with no `label`. Neither `identifier` nor
#                `value` counts: the first is test metadata that is never
#                announced, and the second is state rather than purpose.
#   small-target an interactive node whose frame is under the minimum on either
#                axis
#
# Prints one finding per line, then a summary to stderr. Exit codes:
#
#   0  clean, and coverage was complete
#   1  findings reported
#   2  usage error
#   3  coverage incomplete (truncated sweep); findings, if any, are partial and
#      a clean report proves nothing
#   4  the audit could not run: deviceterm failed, the response would not
#      parse or had the wrong shape, the root frame was degenerate, or the
#      non-sweep tree had no children. An empty sweep is not an error: it means
#      the bridge answered and found nothing, so it reports 0, or 3 when
#      truncated.
#
# 4 is separate from 1 on purpose. A caller recording exit status per screen
# cannot otherwise tell "this screen has problems" from "this screen was never
# audited", and an empty tree is routine on watchOS rather than exceptional.
#
# `--sweep` reads `ax sweep` instead of `ax tree`, for a screen whose tree comes
# back empty. Its children carry ordinary point frames, so the hit-target check
# reads them directly. An `ax tree` root is still fetched in that mode, to
# reject a degenerate pane and to report the screen size in the summary; the
# sweep root's own frame is a normalized placeholder and says nothing.

import json
import subprocess
import sys

# Roles that a user is expected to be able to reach and operate. A missing label
# on a static image is a different, softer finding than one on a button, so the
# audit reports only these rather than every node in the tree.
INTERACTIVE_ROLES = {
    "Button",
    "Link",
    "SearchField",
    "TextField",
    "SecureTextField",
    "Switch",
    "Slider",
    "Stepper",
    "Tab",
    "MenuItem",
    "CheckBox",
    "RadioButton",
    "PopUpButton",
    "SegmentedControl",
}


def run(cmd):
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as exc:
        # deviceterm absent from PATH, or present and unlaunchable. Uncaught,
        # this raises and Python exits 1 — which this audit defines as
        # "findings", so a broken install would read as a clean run that found
        # problems. Same reasoning as the returncode branch below.
        sys.stderr.write("could not run `%s`: %s\n" % (" ".join(cmd), exc))
        sys.exit(4)
    if proc.returncode != 0:
        # deviceterm reports errors as human prose on stderr even under --json.
        # Translate to 4 rather than passing the status through: deviceterm's
        # own 1 would be indistinguishable from this audit's "findings".
        sys.stderr.write(proc.stderr)
        sys.exit(4)
    try:
        return json.loads(proc.stdout)
    except ValueError as exc:
        sys.stderr.write("could not parse %s: %s\n" % (" ".join(cmd), exc))
        sys.exit(4)


def ax(verb, pane, extra=None):
    cmd = ["deviceterm", "ax", verb]
    if extra:
        cmd += extra
    if pane:
        cmd += ["--pane", pane]
    payload = run(cmd)

    # Validate the envelope here rather than indexing ["tree"] at the call site.
    # Valid JSON of the wrong shape would raise an uncaught KeyError, and Python
    # exits 1 on an uncaught exception, which is exactly the collision with
    # "findings reported" that code 4 exists to prevent.
    if not isinstance(payload, dict) or not isinstance(payload.get("tree"), dict):
        sys.stderr.write(
            "`deviceterm ax %s` returned no `tree` object; got keys %s\n"
            % (verb, sorted(payload) if isinstance(payload, dict) else type(payload).__name__))
        sys.exit(4)
    return payload["tree"]


def walk(node):
    yield node
    for child in node.get("children") or []:
        # Validate rather than assuming. A child that is not an object raises
        # AttributeError on the `.get` above, and an uncaught one exits 1 —
        # which this audit defines as "findings", so a malformed tree would
        # read as a clean run that found problems.
        if not isinstance(child, dict):
            sys.stderr.write(
                "accessibility tree has a %s child where an object was "
                "expected\n" % type(child).__name__)
            sys.exit(4)
        for found in walk(child):
            yield found


def is_interactive(node):
    role = node.get("role") or ""
    if role in INTERACTIVE_ROLES:
        return True
    # Roles come from private Apple frameworks and are best-effort, so treat an
    # unknown role carrying a subrole as interactive rather than skipping it.
    return bool(node.get("subrole")) and role not in ("StaticText", "Image")


def has_label(node):
    # Only `label` counts as an accessible name. `identifier` is
    # accessibilityIdentifier, which is test metadata and is never announced.
    # `value` carries state ("On"), not purpose, so a switch with a value and no
    # label still tells a VoiceOver user nothing about what it controls.
    label = node.get("label")
    return isinstance(label, str) and bool(label.strip())


def main():
    args = sys.argv[1:]
    pane = None
    use_sweep = False
    budget = None
    min_target = 44.0

    while args:
        arg = args.pop(0)
        if arg == "--pane":
            if not args:
                sys.stderr.write("--pane needs a value\n")
                return 2
            pane = args.pop(0)
        elif arg == "--sweep":
            use_sweep = True
        elif arg == "--budget":
            if not args:
                sys.stderr.write("--budget needs a value in milliseconds\n")
                return 2
            budget = args.pop(0)
        elif arg == "--min-target":
            if not args:
                sys.stderr.write("--min-target needs a value\n")
                return 2
            try:
                min_target = float(args.pop(0))
            except ValueError:
                sys.stderr.write("--min-target needs a number\n")
                return 2
        else:
            sys.stderr.write("unexpected argument: %s\n" % arg)
            return 2

    # Node frames are in displayed space and already in points, so the hit-target
    # check compares against them directly. The root is read for a different
    # reason: a degenerate root frame means the bridge returned nothing useful,
    # and continuing would report every control on the screen as undersized.
    tree_root = ax("tree", pane)
    frame = tree_root.get("frame") or {}
    width = frame.get("w") or 0
    height = frame.get("h") or 0
    if not width or not height:
        sys.stderr.write(
            "root frame has no size (w=%s h=%s); cannot judge hit targets\n"
            % (width, height)
        )
        return 4

    truncated = False

    if use_sweep:
        extra = ["--budget", budget] if budget else None
        result = ax("sweep", pane, extra)
        if result.get("truncated"):
            truncated = True
            sys.stderr.write(
                "WARNING: sweep truncated after %s of a planned grid at step %s, "
                "under budgetMs=%s. Coverage is partial, so an element absent "
                "from this report is not proven absent from the screen.\n"
                % (result.get("sweepedPoints"), result.get("step"),
                   result.get("budgetMs"))
            )
            # The daemon decides the remedy and states it in `note`, keyed on
            # whether the budget was already at the ceiling. Echo its text
            # rather than restating the rule, so this cannot drift from it.
            note = result.get("note")
            if note:
                sys.stderr.write("  daemon note: %s\n" % note)
            elif not budget:
                sys.stderr.write(
                    "  no note returned; try --budget with a larger value.\n")
        root = result
    else:
        root = tree_root
        if not (root.get("children") or []):
            note = root.get("note")
            sys.stderr.write(
                "tree root has no children%s. Re-run with --sweep.\n"
                % (": " + note if note else "")
            )
            return 4

    unlabeled = 0
    small = 0

    for node in walk(root):
        if node is root or not is_interactive(node):
            continue

        role = node.get("role", "?")
        node_frame = node.get("frame") or {}
        x = node_frame.get("x")
        y = node_frame.get("y")
        w = node_frame.get("w")
        h = node_frame.get("h")

        if not has_label(node):
            unlabeled += 1
            # Print the identifier when there is one. It does not count as a
            # label, but it is how the developer finds this control in source.
            hint = node.get("identifier") or node.get("value") or ""
            print(
                "unlabeled\t%s\tframe=%s,%s %sx%s\t%s"
                % (role, x, y, w, h, hint)
            )

        if w is not None and h is not None and (w < min_target or h < min_target):
            small += 1
            print(
                "small-target\t%s\t%s\t%sx%s (min %s)"
                % (role, node.get("label", ""), w, h, min_target)
            )

    sys.stderr.write(
        "%d unlabeled, %d under %gpt, root %gx%g%s\n"
        % (unlabeled, small, min_target, width, height,
           ", COVERAGE INCOMPLETE" if truncated else "")
    )

    # A truncated sweep outranks a clean result. Returning 0 here would let a
    # caller read partial coverage as "no problems found", which is the failure
    # this whole skill is written to prevent.
    if truncated:
        return 3
    return 1 if (unlabeled or small) else 0


if __name__ == "__main__":
    sys.exit(main())
