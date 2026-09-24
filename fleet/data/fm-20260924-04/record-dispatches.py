#!/usr/bin/env python3
"""Record the four crew dispatches in the ledger (skill §3.5: identity before/at dispatch)."""
import json
import pathlib

TASKS = pathlib.Path("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/state/tasks.json")
d = json.loads(TASKS.read_text())
rows = {t["id"]: t for t in d["tasks"]}

dispatch = {
    "fm-20260923-16": ("Fm16Ship", "2026-09-24T08:33:00Z",
                       "Dispatched on the moved tree. Brief carries the rebase requirement + the "
                       "least-code directive; the crew must decide the uncommitted occlusion delta by "
                       "exercising the closed/hidden-window case, not by keeping it by default."),
    "fm-20260923-25": ("Fm25Ship", "2026-09-24T08:33:00Z",
                       "Dispatched on the moved tree. Known rebase trap in the brief: keep the delivery "
                       "tip's params.noTimestamps = false while re-applying the debugMode hunk in "
                       "WhisperEngine.swift."),
    "fm-20260923-17": ("Fm17Ship", "2026-09-24T08:33:00Z",
                       "Dispatched on the moved tree. Slice review found the work is the captain's own "
                       "verbatim asks (guard, clean-up, reference, language display) and ~+1030 lines, "
                       "never built; brief addendum orders commit-then-rebase, repairs the three test "
                       "signature breaks, and requires the missing Settings/display surfaces before the "
                       "feature counts as landed."),
    "fm-20260924-01": ("Fm24Measure", "2026-09-24T08:38:00Z",
                       "Dispatched. Runs in a purpose-made worktree (fm/fm-20260924-01 at 5e51124) so the "
                       "captain's identity-signed instance in the primary checkout is not rebuilt or "
                       "re-signed mid-run; brief amended accordingly."),
}
for tid, (agent, ts, note) in dispatch.items():
    r = rows[tid]
    r["status"] = "in-flight"
    r["subagentId"] = f"{agent}@{ts}"
    r["updated"] = ts
    r["note"] = note
    if tid == "fm-20260924-01":
        r["worktree"] = ("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/"
                         "OpenSuperWhisper-fm-fm-20260924-01")
        r["branch"] = "fm/fm-20260924-01"
d["tasks"].sort(key=lambda t: t["id"])
TASKS.write_text(json.dumps(d, indent=2) + "\n")
print("rows:", len(d["tasks"]))
print({t["id"]: t["status"] for t in d["tasks"] if t["status"] == "in-flight"})
