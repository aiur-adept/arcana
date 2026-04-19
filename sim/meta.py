"""Meta-analysis: run ``--runs`` games with every deck as P0 (P1 uniformly
sampled from all included decks) and emit a CSV matchup matrix.

Each matrix cell ``M[row, col]`` is P(row beats col) = p0_wins / games,
computed from the shard where ``row`` is P0 and ``col`` is a P1 opponent.

Usage:
    # Baseline pilots (class default GreedyAI weights; no JSON overrides)
    python -m sim.meta --runs 100000 --seed 42 [--out sim_meta_matrix.csv]

    # Trained weights from data/pilot_weights.json (per slug when present)
    python -m sim.meta --runs 100000 --seed 42 --use-saved-weights [--weights PATH]

Common flags: ``--workers N``, ``--include-draws-as-half``, ``--games-out``.

This reuses ``sim.run.run_shard`` (multiprocess shards per P0 slug) so the
per-game pilot / mulligan / invariant plumbing is identical to the CLI
runner. The only difference is the top-level loop over every P0 slug and
the CSV assembly step at the end."""

from __future__ import annotations

import argparse
import csv
import multiprocessing as mp
import os
import time
from pathlib import Path
from typing import Any

from .decks import included_deck_slugs
from .pilot_weights import default_pilot_weights_path
from .run import _empty_bucket, _merge_bucket, _validate_invariants, run_shard


def _simulate_p0(p0_slug: str, total_runs: int, seed: int, seed_offset: int,
                 workers: int, weights_path_str: str, use_saved_weights: bool) -> dict[str, dict[str, Any]]:
    per_shard = total_runs // workers
    remainder = total_runs - per_shard * workers
    shard_args = []
    for i in range(workers):
        runs_i = per_shard + (1 if i < remainder else 0)
        shard_seed = seed * 1_000_003 + seed_offset * 10_007 + i * 17 + 1
        shard_args.append((p0_slug, runs_i, shard_seed, weights_path_str, use_saved_weights))
    agg: dict[str, dict[str, Any]] = {}
    if workers == 1:
        shard = run_shard(shard_args[0])
        for slug, bucket in shard.items():
            dst = agg.setdefault(slug, _empty_bucket())
            _merge_bucket(dst, bucket)
    else:
        with mp.Pool(processes=workers) as pool:
            for shard in pool.imap_unordered(run_shard, shard_args):
                for slug, bucket in shard.items():
                    dst = agg.setdefault(slug, _empty_bucket())
                    _merge_bucket(dst, bucket)
    _validate_invariants(agg, total_runs)
    return agg


def _cell_winrate(bucket: dict[str, Any], count_draws_as_half: bool) -> tuple[float, int]:
    g = bucket["games"]
    if g == 0:
        return (0.0, 0)
    w = bucket["p0_wins"]
    if count_draws_as_half:
        w += 0.5 * bucket["draws"]
    return (w / g, g)


def run_meta(runs_per_deck: int, seed: int, workers: int,
             out_path: Path, count_draws_as_half: bool,
             games_out_path: Path | None = None,
             weights_path_str: str = "",
             use_saved_weights: bool = False) -> None:
    slugs = included_deck_slugs()
    all_agg: dict[str, dict[str, dict[str, Any]]] = {}
    t0 = time.perf_counter()
    print(f"Meta-run: {len(slugs)} decks x {runs_per_deck} runs "
          f"(seed={seed}, workers={workers})")
    if use_saved_weights:
        print(f"Pilot weights: trained ({weights_path_str}; per-slug when present)")
    else:
        print("Pilot weights: baseline (class defaults; greedy, no JSON overrides)")
    for si, p0_slug in enumerate(slugs):
        t_deck = time.perf_counter()
        agg = _simulate_p0(p0_slug, runs_per_deck, seed, si, workers, weights_path_str, use_saved_weights)
        all_agg[p0_slug] = agg
        dt = time.perf_counter() - t_deck
        print(f"  [{si + 1:2d}/{len(slugs):2d}] {p0_slug:22s}  {dt:6.2f}s")
    elapsed = time.perf_counter() - t0
    print(f"Total meta runtime: {elapsed:.1f}s")

    with out_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["row_beats_col"] + slugs)
        for row_slug in slugs:
            row = [row_slug]
            for col_slug in slugs:
                bucket = all_agg[row_slug].get(col_slug)
                if bucket is None or bucket["games"] == 0:
                    row.append("")
                else:
                    wr, _ = _cell_winrate(bucket, count_draws_as_half)
                    row.append(f"{wr:.4f}")
            w.writerow(row)
    print(f"Wrote matchup matrix: {out_path}")

    if games_out_path is not None:
        with games_out_path.open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["games_row_vs_col"] + slugs)
            for row_slug in slugs:
                row = [row_slug]
                for col_slug in slugs:
                    bucket = all_agg[row_slug].get(col_slug)
                    row.append(str(bucket["games"]) if bucket else "0")
                w.writerow(row)
        print(f"Wrote sample-size matrix: {games_out_path}")

    _print_summary_table(slugs, all_agg, count_draws_as_half)


def _print_summary_table(slugs: list[str],
                         all_agg: dict[str, dict[str, dict[str, Any]]],
                         count_draws_as_half: bool) -> None:
    print()
    print("--- overall row-deck win% (averaged across all columns) ---")
    rows = []
    for row_slug in slugs:
        total_w = 0.0
        total_g = 0
        for col_slug in slugs:
            bucket = all_agg[row_slug].get(col_slug)
            if bucket is None or bucket["games"] == 0:
                continue
            wr, g = _cell_winrate(bucket, count_draws_as_half)
            total_w += wr * g
            total_g += g
        avg = (total_w / total_g) if total_g > 0 else 0.0
        rows.append((row_slug, avg, total_g))
    rows.sort(key=lambda r: -r[1])
    width = max(len(s) for s in slugs)
    for slug, avg, g in rows:
        print(f"  {slug:<{width}s}   {avg * 100:6.2f}%  ({g} games)")


def main() -> None:
    ap = argparse.ArgumentParser(description="Arcana meta matchup matrix")
    ap.add_argument("--runs", type=int, default=100_000,
                    help="games per P0 deck (default 100000)")
    ap.add_argument("--seed", type=int, default=42,
                    help="master RNG seed (default 42)")
    ap.add_argument("--workers", type=int, default=0,
                    help="override worker count (default: os.cpu_count())")
    ap.add_argument("--out", type=str, default="sim_meta_matrix.csv",
                    help="output CSV path")
    ap.add_argument("--games-out", type=str, default="",
                    help="optional: write a second CSV with per-cell sample sizes")
    ap.add_argument("--include-draws-as-half", action="store_true",
                    help="count each draw as 0.5 of a win (default: draws count as losses)")
    ap.add_argument(
        "--use-saved-weights",
        action="store_true",
        help="load trained weights per slug from pilot_weights.json (omit flag for baseline/greedy pilots)",
    )
    ap.add_argument("--weights", type=str, default="",
                    help="pilot_weights.json path; only used with --use-saved-weights "
                    "(default: <project>/data/pilot_weights.json)")
    args = ap.parse_args()

    workers = args.workers if args.workers > 0 else (os.cpu_count() or 1)
    workers = max(1, min(workers, args.runs))
    out_path = Path(args.out)
    games_out_path = Path(args.games_out) if args.games_out else None
    weights_path_str = ""
    if args.use_saved_weights:
        wp = Path(args.weights) if args.weights else default_pilot_weights_path()
        weights_path_str = str(wp.resolve())
    run_meta(
        args.runs, args.seed, workers, out_path,
        args.include_draws_as_half, games_out_path,
        weights_path_str, args.use_saved_weights,
    )


if __name__ == "__main__":
    main()
