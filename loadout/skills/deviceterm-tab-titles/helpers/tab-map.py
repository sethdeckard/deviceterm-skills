#!/usr/bin/env python3
# Why this exists: `tabs list` returns one row per terminal session, not per GUI
# tab. A tab with split terminals produces several rows, so renaming straight
# from that list retitles the same tab once per split and captures a different
# pane each time.
#
# Every row carries `tabId`, and the sessions of one GUI tab share it, so
# grouping on it collapses the splits without asking the daemon anything more.
# Doing that inline would be a jq pipeline in every prescribed step, which Codex
# cannot reduce to a durable approval prefix.
#
# Usage:  tab-map.py [--include-self]
#
# Prints one tab-separated row per GUI tab:
#
#         <tabId>\t<sessionCount>\t<displayTitle>
#
# `tabId` resolves directly with `--tab`. A session's own `shortId` is not used
# as the ref: it identifies one terminal rather than the tab, and it does not
# reliably resolve as a `--tab` ref for a session other than your own.
#
# The caller's own tab is excluded unless --include-self is passed. Exclusion is
# per *group*, not per row: only one row of a split tab carries `current`, so
# filtering rows on it would drop your own terminal and leave its sibling in the
# list as though it were someone else's tab.
#
# Exit codes:
#
#   0  at least one row emitted
#   1  no row emitted: no tabs are visible, or the only one is the caller's own
#      and --include-self was not passed
#   2  usage error
#   4  the lookup could not run: deviceterm failed, or its response would not
#      parse or had the wrong shape
#
# 4 is separate from 1 so a caller cannot read a broken daemon as an empty
# workspace, which is the reading that matters here: an empty result is also
# what a workspace of protected tabs looks like.

import json
import subprocess
import sys


def deviceterm(args):
    try:
        proc = subprocess.run(
            ["deviceterm"] + args + ["--json"], capture_output=True, text=True)
    except OSError as exc:
        # deviceterm absent from PATH, or present and unlaunchable. Uncaught,
        # this raises and Python exits 1 — which this helper defines as "no
        # tabs visible", the one reading it must never produce by accident,
        # since that is also what a workspace of protected tabs looks like.
        sys.stderr.write("could not run `deviceterm`: %s\n" % exc)
        sys.exit(4)
    if proc.returncode != 0:
        # Errors are human prose on stderr even under --json, and there is no
        # JSON error envelope, so pass the text through rather than decoding.
        # The status becomes 4: deviceterm's own 1 would read as "no tabs".
        sys.stderr.write(proc.stderr)
        sys.exit(4)
    try:
        return json.loads(proc.stdout)
    except ValueError as exc:
        sys.stderr.write("could not parse `deviceterm %s --json`: %s\n"
                         % (" ".join(args), exc))
        sys.exit(4)


def main():
    args = sys.argv[1:]
    include_self = False
    while args:
        arg = args.pop(0)
        if arg == "--include-self":
            include_self = True
        else:
            sys.stderr.write("usage: tab-map.py [--include-self]\n")
            return 2

    rows = deviceterm(["tabs", "list"])
    if not isinstance(rows, list):
        sys.stderr.write("expected an array from `tabs list --json`\n")
        return 4

    tabs = {}
    for row in rows:
        # Validate rather than skipping. A row that is not an object raises
        # AttributeError on `.get`, and an uncaught one exits 1 — which this
        # helper defines as "no tabs visible". A row that is an object but
        # carries no `tabId` is the same problem quieter: the grouping key is
        # required, so its absence is a response this build cannot read, not a
        # workspace with fewer tabs in it.
        if not isinstance(row, dict):
            sys.stderr.write(
                "`tabs list --json` returned a %s where an object was "
                "expected\n" % type(row).__name__)
            return 4
        tab_id = row.get("tabId")
        if not tab_id:
            sys.stderr.write(
                "`tabs list --json` row has no `tabId`; this build cannot "
                "group tabs without it\n")
            return 4

        entry = tabs.setdefault(tab_id, {
            "count": 0,
            "isCurrent": False,
            "title": "",
            "name": "",
        })
        entry["count"] += 1
        # OR across the group. `current` marks the calling session's own row,
        # so at most one row of your tab carries it.
        entry["isCurrent"] = entry["isCurrent"] or bool(row.get("current"))
        # Collected separately so a `name` on an early row cannot shut out a
        # real `displayTitle` on a later one. displayTitle is absent on a
        # freshly split row until its shell draws a title, and after a daemon
        # restart until the GUI republishes it, and rows arrive in no
        # guaranteed order, so the group's best answer may come last.
        if not entry["title"]:
            entry["title"] = row.get("displayTitle") or ""
        if not entry["name"]:
            entry["name"] = row.get("name") or ""

    emitted = 0
    for tab_id, entry in tabs.items():
        if entry["isCurrent"] and not include_self:
            continue
        # `name` is the fallback, applied only once the whole group has been
        # read and no row offered a displayTitle.
        print("%s\t%d\t%s"
              % (tab_id, entry["count"], entry["title"] or entry["name"]))
        emitted += 1

    if not emitted:
        sys.stderr.write(
            "no other tabs visible. Protected tabs are invisible to you even "
            "with an automation grant, so this is not proof the workspace has "
            "only one tab.\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
