"""Compare worktree vs git-committed pilot weights; merge per-deck winners into one JSON.

Steps:
  1. Copy current data/pilot_weights.json to a backup path (worktree / "new" candidate).
  2. git checkout <ref> -- data/pilot_weights.json (restore "old" committed file in place).
  3. For each included deck as P0, run the same Monte Carlo schedule (matched seed) against
     the field with each weights file; pick higher P0 win rate (ties -> old).
  4. Write data/pilot_weights_best_of.json with weights_by_slug built from the winners.

After this script, data/pilot_weights.json is the OLD (git) version; the previous file is
only in the backup path. Copy pilot_weights_best_of.json over pilot_weights.json when satisfied.

Usage (repo root):
  python compare_pilot_weight_sets.py [--runs 20000] [--seed 42] [--git-ref HEAD] [--workers N]
"""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
DEFAULT_WEIGHTS = DATA / "pilot_weights.json"
WORKTREE_BACKUP = DATA / "pilot_weights.worktree_backup.json"
MERGED_OUT = DATA / "pilot_weights_best_of.json"


def _field_winrate_p0(
    p0_slug: str,
    runs: int,
    seed: int,
    weights_path: Path,
    workers: int,
) -> tuple[float, int, int, int]:
    from sim.run import _empty_bucket, _merge_bucket, _validate_invariants, run_shard

    wp = str(weights_path.resolve())
    workers = max(1, min(workers, runs))
    per = runs // workers
    rem = runs - per * workers
    shard_args: list[tuple[Any, ...]] = []
    for i in range(workers):
        ri = per + (1 if i < rem else 0)
        shard_args.append((p0_slug, ri, seed * 1_000_003 + i * 17 + 1, wp, True))

    agg: dict[str, dict[str, Any]] = {}
    if workers == 1:
        shard = run_shard(shard_args[0])
        for slug, bucket in shard.items():
            dst = agg.setdefault(slug, _empty_bucket())
            _merge_bucket(dst, bucket)
    else:
        with mp.Pool(processes=workers) as pool:
            for shard in pool.imap_unordered(run_shard, shard_args, chunksize=1):
                for slug, bucket in shard.items():
                    dst = agg.setdefault(slug, _empty_bucket())
                    _merge_bucket(dst, bucket)
    _validate_invariants(agg, runs)
    p0_w = sum(b["p0_wins"] for b in agg.values())
    p1_w = sum(b["p1_wins"] for b in agg.values())
    dr = sum(b["draws"] for b in agg.values())
    return (p0_w / runs if runs else 0.0, p0_w, p1_w, dr)


def _load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        d = json.load(f)
    if not isinstance(d, dict):
        raise ValueError(f"{path} root must be a JSON object")
    return d


def _weights_by_slug(data: dict[str, Any]) -> dict[str, dict[str, float]]:
    raw = data.get("weights_by_slug", {})
    if not isinstance(raw, dict):
        return {}
    out: dict[str, dict[str, float]] = {}
    for sk, sv in raw.items():
        if isinstance(sv, dict) and sv:
            out[str(sk)] = {str(k): float(v) for k, v in sv.items() if isinstance(v, (int, float))}
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Merge best per-deck weights from worktree vs git HEAD")
    ap.add_argument("--runs", type=int, default=20_000, help="games per deck per weights file")
    ap.add_argument("--seed", type=int, default=42, help="base seed (same schedule for old vs new per deck)")
    ap.add_argument("--git-ref", type=str, default="HEAD", help="git ref for old pilot_weights.json")
    ap.add_argument("--backup", type=Path, default=WORKTREE_BACKUP, help="where to save current file")
    ap.add_argument("--out", type=Path, default=MERGED_OUT, help="merged JSON output")
    ap.add_argument("--workers", type=int, default=0, help="sim worker processes (default: CPU count)")
    ap.add_argument(
        "--skip-git-checkout",
        action="store_true",
        help="do not run git checkout; expect OLD at data/pilot_weights.json and NEW at --backup already",
    )
    args = ap.parse_args()

    if not DEFAULT_WEIGHTS.is_file():
        print(f"Missing {DEFAULT_WEIGHTS}", file=sys.stderr)
        return 1

    workers = args.workers if args.workers > 0 else (os.cpu_count() or 1)

    if not args.skip_git_checkout:
        print(f"Backing up worktree -> {args.backup.resolve()}")
        shutil.copy2(DEFAULT_WEIGHTS, args.backup)
        print(f"git checkout {args.git_ref} -- data/pilot_weights.json")
        r = subprocess.run(
            ["git", "checkout", args.git_ref, "--", "data/pilot_weights.json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        if r.returncode != 0:
            print(r.stderr or r.stdout, file=sys.stderr)
            return r.returncode

    old_path = DEFAULT_WEIGHTS
    new_path = args.backup
    if not new_path.is_file():
        print(f"Missing NEW weights at {new_path}", file=sys.stderr)
        return 1

    old_data = _load_json(old_path)
    new_data = _load_json(new_path)
    old_wbs = _weights_by_slug(old_data)
    new_wbs = _weights_by_slug(new_data)

    from sim.decks import included_deck_slugs

    slugs = included_deck_slugs()
    merged: dict[str, dict[str, float]] = {}
    rows: list[tuple[str, float, float, str]] = []

    print(f"Comparing field win rate (P0 wins / games), {args.runs} games each, paired seeds\n")
    for i, slug in enumerate(slugs):
        deck_seed = args.seed + i * 97_771
        t0 = time.perf_counter()
        wr_old, *counts_o = _field_winrate_p0(slug, args.runs, deck_seed, old_path, workers)
        wr_new, *counts_n = _field_winrate_p0(slug, args.runs, deck_seed, new_path, workers)
        dt = time.perf_counter() - t0

        if wr_new > wr_old:
            pick = "new"
            src = new_wbs.get(slug)
        else:
            pick = "old"
            src = old_wbs.get(slug)
        if src:
            merged[slug] = dict(sorted(src.items()))
        rows.append((slug, wr_old, wr_new, pick))
        print(
            f"  {slug:22s}  old={wr_old:.4f}  new={wr_new:.4f}  -> {pick:4s}  ({dt:.1f}s)"
        )

    out_doc = {
        "genome_version": int(old_data.get("genome_version", 1)),
        "weights_by_slug": {k: merged[k] for k in sorted(merged.keys())},
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as f:
        json.dump(out_doc, f, indent=2, sort_keys=False)
        f.write("\n")

    print(f"\nWrote {args.out.resolve()}  ({len(merged)} slugs with saved weights)")
    print("data/pilot_weights.json is now the git OLD version; NEW is at", new_path.resolve())
    print("Install: copy or move pilot_weights_best_of.json to data/pilot_weights.json when ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
