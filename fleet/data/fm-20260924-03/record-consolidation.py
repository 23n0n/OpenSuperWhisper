#!/usr/bin/env python3
"""Record the consolidation and the falsified determinism premise in the fleet ledger."""
import json
import pathlib

FH = pathlib.Path("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet")
TASKS = FH / "state" / "tasks.json"
d = json.loads(TASKS.read_text())
rows = {t["id"]: t for t in d["tasks"]}

# fm-20260924-03 — preservation: done, verified by restore
r = rows["fm-20260924-03"]
r["status"] = "done"
r["updated"] = "2026-09-24T08:45:00Z"
r["note"] = (
    "Snapshot verified by restore, not by write: archive/opensuperwhisper-20260924.bundle (thin, "
    "^origin/develop c8e6fe7) restores all 16 branch tips (checked 4: delivery, fm-15, fm-16, fm-09), "
    "file count 160 at the delivery tip, and every worktree patch applies clean (git apply --check) "
    "against the restored tips. Uncommitted work captured per worktree (status + patch + untracked "
    "copies). Fleet records tarballed (145 entries). Option A only: nothing pushed, nothing deleted."
)

# fm-20260923-27 — the premise is falsified by inspection of the delivery tip
r = rows["fm-20260923-27"]
r["status"] = "queued"
r["note"] = (
    "PREMISE FALSIFIED 2026-09-24 by the sampler scout, never dispatched. In-process sampling is "
    "already seed-pinned: Llama.swift:270-278 builds top_k(40)->top_p(0.95)->min_p(0.05)->temp(0.2)"
    "->dist(seed=0) and the chain is rebuilt and freed per request (Llama.swift:158-159), KV cleared "
    "at :156, so no RNG state carries over; no llama_set_rng_seed anywhere. The only unseeded path is "
    "the optional HTTP override (TranslationService.swift:334 sends temperature 0.2, no seed). So the "
    "residual run-to-run difference, if it reproduces, comes from backend reduction nondeterminism "
    "(Metal/threaded), not from seed handling — a fixed seed cannot fix it, and greedy would only make "
    "it rarer. Awaiting a measure-or-drop decision; no code written."
)

# fm-20260924-04 — this session's own ops task
if "fm-20260924-04" not in rows:
    d["tasks"].append({
        "id": "fm-20260924-04",
        "kind": "ops",
        "mode": "",
        "project": "OpenSuperWhisper",
        "repoDir": "/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo",
        "worktree": "",
        "branch": "",
        "subagentId": "",
        "status": "done",
        "retries": 0,
        "brief": "",
        "created": "2026-09-24T08:23:00Z",
        "updated": "2026-09-24T08:45:00Z",
        "note": (
            "Captain-directed consolidation: /Volumes/home/zenon/Projects/OpenSuperWhisper-fork with "
            "repo/, worktrees/, fleet/, docs/, archive/. Removed the five merged worktrees (fm-12, -13, "
            "-22, -23, -27; ~11 GB of build products, branches intact). Repaired the worktree admin "
            "links and the moved worktree submodule links (git 2.54 keeps relative pointers, which a "
            "move invalidates) and rewrote absolute paths in 48 fleet record files. Symlink "
            "/Volumes/home/zenon/firstmate-home -> fork/fleet kept for stale paths. Verified: main repo "
            "clean, all three preserved worktrees report their exact recorded entry counts (5/1/10), "
            "submodules clean everywhere."
        ),
    })

TASKS.write_text(json.dumps(d, indent=2) + "\n")
print("tasks.json rows:", len(d["tasks"]))

logs = {
    "fm-20260924-03": [
        "2026-09-24T08:45:00Z preservation done (option A, local-only): bundle 16 branch refs "
        "(delivery 5e51124 + all fm/*), thin against origin/develop c8e6fe7; per-worktree patches "
        "+ untracked copies for fm-15/-16/-17; fleet records tarball; manifest with submodule pins. "
        "Verified by restoring the bundle into a scratch repo: 4/4 tips match, 160 files at the "
        "delivery tip (expected 160), all 3 patches apply clean (git apply --check). 632 KB total. "
        "Nothing pushed, nothing deleted."
    ],
    "fm-20260924-04": [
        "2026-09-24T08:23:00Z dispatched by the first mate on the captain's instruction, no crew.",
        "2026-09-24T08:45:00Z done: fork work consolidated under Projects/OpenSuperWhisper-fork "
        "(repo/, worktrees/, fleet/, docs/, archive/); 5 merged worktrees removed (~11 GB); worktree + "
        "submodule links repaired; 48 fleet record files rewritten to the new paths; README written. "
        "Verified: repo clean, worktree entry counts 5/1/10 as recorded, submodules clean."
    ],
    "fm-20260923-27": [
        "2026-09-24T08:40:00Z NOT dispatched. Read-only scout on the delivery tip falsified the "
        "premise: the in-process sampler is already seed-pinned (Llama.swift:270-278, dist(seed=0)) "
        "and rebuilt per request (Llama.swift:158-159), KV cleared at :156, no llama_set_rng_seed. "
        "Only the optional HTTP override is unseeded (TranslationService.swift:334). Evidence: "
        "libllama/llama.cpp src/llama-sampler.cpp:1399-1409 (mt19937 seeded from the seed), "
        ":340-353 (only LLAMA_DEFAULT_SEED randomises). No code written."
    ],
}
for tid, lines in logs.items():
    p = FH / "data" / tid / "status.log"
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a") as fh:
        fh.write("\n".join(lines) + "\n")
    print("logged", tid)
