"""Leave-one-out deck analysis: remove each deck slot, run Monte Carlo games, rank by win-rate drop.

Usage:
    python -m sim.card_impact --deck void_temples --baseline-runs 3000 --runs-per-variant 400

Uses the same matchmaking as sim.run (P0 fixed slug vs random included opponent, uniform).
Positive delta_vs_baseline means removing that card *hurts* P0 win rate (card helps wins)."""

from __future__ import annotations

import argparse
import multiprocessing as mp
import os
import random
import time
from pathlib import Path
from typing import Any

from .ai import GreedyAI
from .cards import Card
from .decks import included_deck_slugs, load_all_included_decks
from .pilot_weights import default_pilot_weights_path, pilot_class_for_slug
from .run import _play_one_game


def _p0_wins_in_block(
    p0_deck: list[Card],
    p0_slug: str,
    runs: int,
    seed: int,
    wpath: Path | None,
    use_saved: bool,
) -> int:
    decks = load_all_included_decks()
    slugs = included_deck_slugs()
    rng = random.Random(seed)
    p0_pilot_cls = pilot_class_for_slug(p0_slug, wpath, use_saved)
    pilot_cache: dict[str, type[GreedyAI]] = {p0_slug: p0_pilot_cls}
    wins = 0
    for _ in range(runs):
        p1_slug = slugs[rng.randrange(len(slugs))]
        p1_deck = decks[p1_slug]
        p1_pilot_cls = pilot_cache.get(p1_slug)
        if p1_pilot_cls is None:
            p1_pilot_cls = pilot_class_for_slug(p1_slug, wpath, use_saved)
            pilot_cache[p1_slug] = p1_pilot_cls
        game_rng = random.Random(rng.getrandbits(64))
        res = _play_one_game(p0_deck, p1_deck, game_rng, p0_pilot_cls, p1_pilot_cls)
        if res["winner"] == 0:
            wins += 1
    return wins


def _variant_task(args: tuple[Any, ...]) -> tuple[int, int, int]:
    remove_idx, p0_deck_full, p0_slug, runs, seed, weights_path_str, use_saved = args
    wpath = Path(weights_path_str) if weights_path_str else None
    variant = p0_deck_full[:remove_idx] + p0_deck_full[remove_idx + 1 :]
    wins = _p0_wins_in_block(variant, p0_slug, runs, seed, wpath, use_saved)
    return remove_idx, wins, runs


def main() -> None:
    ap = argparse.ArgumentParser(description="Leave-one-out card impact (39-card P0 vs random opponents)")
    ap.add_argument("--deck", required=True, help="P0 deck slug (included_decks/index.json)")
    ap.add_argument("--baseline-runs", type=int, default=2_000, help="games with full deck (0 = skip baseline)")
    ap.add_argument("--runs-per-variant", type=int, default=400, help="games per removed slot")
    ap.add_argument("--seed", type=int, default=0, help="master RNG seed")
    ap.add_argument("--workers", type=int, default=0, help="parallel workers (default: cpu count)")
    ap.add_argument("--use-saved-weights", action="store_true")
    ap.add_argument("--weights", type=str, default="", help="pilot_weights.json path")
    args = ap.parse_args()

    slugs = included_deck_slugs()
    if args.deck not in slugs:
        raise SystemExit(f"--deck must be one of {slugs}; got {args.deck!r}")

    weights_path_str = ""
    if args.use_saved_weights:
        wp = Path(args.weights) if args.weights else default_pilot_weights_path()
        weights_path_str = str(wp.resolve())
    wpath = Path(weights_path_str) if weights_path_str else None

    full = load_all_included_decks()[args.deck]
    n = len(full)
    if n < 2:
        raise SystemExit("deck too small for leave-one-out")

    workers = args.workers if args.workers > 0 else (os.cpu_count() or 1)
    workers = max(1, workers)

    t0 = time.perf_counter()
    baseline_rate: float | None = None
    if args.baseline_runs > 0:
        bw = _p0_wins_in_block(
            full,
            args.deck,
            args.baseline_runs,
            args.seed,
            wpath,
            args.use_saved_weights,
        )
        baseline_rate = bw / args.baseline_runs

    tasks = [
        (
            i,
            full,
            args.deck,
            args.runs_per_variant,
            args.seed * 1_000_003 + (i + 1) * 97,
            weights_path_str,
            args.use_saved_weights,
        )
        for i in range(n)
    ]

    results: list[tuple[int, int, int]] = []
    if workers == 1 or n == 1:
        for t in tasks:
            results.append(_variant_task(t))
    else:
        with mp.Pool(processes=min(workers, n)) as pool:
            results = pool.map(_variant_task, tasks)

    elapsed = time.perf_counter() - t0

    rows: list[tuple[int, str, float, float | None]] = []
    for remove_idx, wins, runs in sorted(results, key=lambda x: x[0]):
        card = full[remove_idx]
        lab = card.label()
        wr = wins / runs
        delta = (baseline_rate - wr) if baseline_rate is not None else None
        rows.append((remove_idx, lab, wr, delta))

    if baseline_rate is not None:
        rows_by_impact = sorted(rows, key=lambda r: (r[3] or 0.0, r[1], r[0]), reverse=True)
    else:
        rows_by_impact = sorted(rows, key=lambda r: (r[2], r[1], r[0]))

    print()
    print(
        f"=== Leave-one-out: P0={args.deck}  deck_size={n}  "
        f"runs/slot={args.runs_per_variant}  workers={workers}  elapsed={elapsed:.2f}s ==="
    )
    if baseline_rate is not None:
        print(f"Baseline ({n}-card) P0 win rate: {100.0 * baseline_rate:.2f}%  (n={args.baseline_runs})")
    else:
        print("Baseline skipped (--baseline-runs 0); delta column omitted.")
    print()
    hdr = f"{'idx':>4}  {'removed_card':36}  {'win%':>8}  "
    hdr += f"{'dWR_pp':>10}" if baseline_rate is not None else ""
    print(hdr)
    print("-" * len(hdr))
    for remove_idx, lab, wr, delta in sorted(rows, key=lambda r: r[0]):
        line = f"{remove_idx:4d}  {lab:36}  {100.0 * wr:7.2f}%  "
        if delta is not None:
            line += f"{100.0 * delta:+9.2f}pp"
        print(line)

    print()
    if baseline_rate is not None:
        print("--- Most important to P0 wins (largest win-rate drop when removed) ---")
        for remove_idx, lab, wr, delta in rows_by_impact[:15]:
            if delta is None or delta <= 0:
                continue
            print(f"  {lab:36}  slot {remove_idx:2d}  dWR {100.0 * delta:+.2f}pp  (39-card WR {100.0 * wr:.2f}%)")
        if not any(r[3] and r[3] > 0 for r in rows):
            print("  (no positive deltas; try more --runs-per-variant)")
    else:
        print("--- Lowest 39-card win rates (proxy: important slots; add --baseline-runs for dWR) ---")
        for remove_idx, lab, wr, _ in rows_by_impact[:15]:
            print(f"  {lab:36}  slot {remove_idx:2d}  WR {100.0 * wr:.2f}%")

    print()
    if baseline_rate is not None:
        print("--- Best cards to cut (removal *raises* win rate; noise if CI wide) ---")
        for remove_idx, lab, wr, delta in sorted(rows, key=lambda r: (r[3] if r[3] is not None else 0.0, r[1]))[:10]:
            if delta is None or delta >= 0:
                continue
            print(f"  {lab:36}  slot {remove_idx:2d}  dWR {100.0 * delta:+.2f}pp  (39-card WR {100.0 * wr:.2f}%)")

    if baseline_rate is not None:
        by_label: dict[str, list[float]] = {}
        for _, lab, _, delta in rows:
            if delta is None:
                continue
            by_label.setdefault(lab, []).append(delta)
        print()
        print("--- Average dWR (percentage points) vs baseline by card label ---")
        agg = [(lab, sum(ds) / len(ds), len(ds)) for lab, ds in by_label.items()]
        agg.sort(key=lambda t: -t[1])
        for lab, mean_d, k in agg[:20]:
            print(f"  {lab:36}  avg dWR {100.0 * mean_d:+.2f}pp  ({k} slot(s))")


if __name__ == "__main__":
    main()
