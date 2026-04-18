"""Monte Carlo runner for the Arcana simulator.

Usage:
    python -m sim.run --deck noble_test --runs 100000 [--seed 0]

Splits runs across os.cpu_count() processes. Workers fold their shard into a
per-P1-slug bucket dict keyed by opponent slug; the runner merges shards with
elementwise sums. Reports per-opponent win/loss/draw plus global match-power
progression and final-power histograms."""

from __future__ import annotations

import argparse
import multiprocessing as mp
import os
import random
import time
from typing import Any

from .ai import GreedyAI, simple_mulligan
from .decks import included_deck_slugs, load_all_included_decks
from .match import EndOfGame, MatchState
from .pilots import get_pilot


POWER_CURVE_MARKERS = [1, 3, 5, 10, 15, 20]
FINAL_POWER_HIST_BINS = 21   # 0..20+


def _empty_bucket() -> dict[str, Any]:
    return {
        "games": 0,
        "p0_wins": 0,
        "p1_wins": 0,
        "draws": 0,
        "turns_sum": 0,
        "p0_power_sum": 0,
        "p1_power_sum": 0,
        "final_power_hist_p0": [0] * FINAL_POWER_HIST_BINS,
        "final_power_hist_p1": [0] * FINAL_POWER_HIST_BINS,
        "power_curve_p0_sum": [0] * len(POWER_CURVE_MARKERS),
        "power_curve_p0_count": [0] * len(POWER_CURVE_MARKERS),
        "power_curve_p1_sum": [0] * len(POWER_CURVE_MARKERS),
        "power_curve_p1_count": [0] * len(POWER_CURVE_MARKERS),
        "end_reason_counts": {"power_20": 0, "deck_out": 0, "turn_cap": 0},
    }


def _merge_bucket(dst: dict[str, Any], src: dict[str, Any]) -> None:
    for k, v in src.items():
        if isinstance(v, list):
            acc = dst[k]
            for i, x in enumerate(v):
                acc[i] += x
        elif isinstance(v, dict):
            acc = dst[k]
            for kk, vv in v.items():
                acc[kk] = acc.get(kk, 0) + vv
        else:
            dst[k] += v


def _play_one_game(p0_deck_cards, p1_deck_cards, rng: random.Random,
                   p0_pilot_cls: type[GreedyAI], p1_pilot_cls: type[GreedyAI]) -> dict[str, Any]:
    state = MatchState((p0_deck_cards, p1_deck_cards), rng)
    ai0 = p0_pilot_cls(0)
    ai1 = p1_pilot_cls(1)
    ais = (ai0, ai1)

    def pilot_mulligan(s: MatchState, pid: int) -> bool:
        return ais[pid].mulligan(s, pid)

    try:
        state.start(mulligan_heuristic=pilot_mulligan)
        while not state.game_over_flag:
            if state.pending is not None:
                ais[state.pending.responder].respond(state)
                if state.pending is not None:
                    break
                continue
            ais[state.active].play_turn(state)
            if state.turn_number > state.turn_cap:
                break
    except EndOfGame:
        pass
    state._sample_power_curve(force=True)
    return {
        "winner": state.winner if state.winner in (-1, 0, 1) else -1,
        "turns": state.turn_number,
        "p0_final_power": state.match_power(0),
        "p1_final_power": state.match_power(1),
        "p0_curve": state.power_curve_p0,
        "p1_curve": state.power_curve_p1,
        "end_reason": state.end_reason or "turn_cap",
    }


def _record_result(bucket: dict[str, Any], res: dict[str, Any]) -> None:
    bucket["games"] += 1
    bucket["turns_sum"] += res["turns"]
    bucket["p0_power_sum"] += res["p0_final_power"]
    bucket["p1_power_sum"] += res["p1_final_power"]
    w = res["winner"]
    if w == 0:
        bucket["p0_wins"] += 1
    elif w == 1:
        bucket["p1_wins"] += 1
    else:
        bucket["draws"] += 1
    p0_bin = min(max(res["p0_final_power"], 0), FINAL_POWER_HIST_BINS - 1)
    p1_bin = min(max(res["p1_final_power"], 0), FINAL_POWER_HIST_BINS - 1)
    bucket["final_power_hist_p0"][p0_bin] += 1
    bucket["final_power_hist_p1"][p1_bin] += 1
    for i, snap in enumerate(res["p0_curve"]):
        if snap is not None:
            bucket["power_curve_p0_sum"][i] += snap
            bucket["power_curve_p0_count"][i] += 1
    for i, snap in enumerate(res["p1_curve"]):
        if snap is not None:
            bucket["power_curve_p1_sum"][i] += snap
            bucket["power_curve_p1_count"][i] += 1
    reason = res["end_reason"] or "turn_cap"
    if reason not in bucket["end_reason_counts"]:
        reason = "turn_cap"
    bucket["end_reason_counts"][reason] += 1


def run_shard(args: tuple) -> dict[str, dict[str, Any]]:
    p0_slug, runs_in_shard, shard_seed = args
    decks = load_all_included_decks()
    slugs = included_deck_slugs()
    rng = random.Random(shard_seed)
    p0_deck = decks[p0_slug]
    p0_pilot_cls = get_pilot(p0_slug)
    pilot_cache: dict[str, type[GreedyAI]] = {p0_slug: p0_pilot_cls}
    stats: dict[str, dict[str, Any]] = {}
    for _ in range(runs_in_shard):
        p1_slug = slugs[rng.randrange(len(slugs))]
        p1_deck = decks[p1_slug]
        p1_pilot_cls = pilot_cache.get(p1_slug)
        if p1_pilot_cls is None:
            p1_pilot_cls = get_pilot(p1_slug)
            pilot_cache[p1_slug] = p1_pilot_cls
        game_rng = random.Random(rng.getrandbits(64))
        res = _play_one_game(p0_deck, p1_deck, game_rng, p0_pilot_cls, p1_pilot_cls)
        bucket = stats.setdefault(p1_slug, _empty_bucket())
        _record_result(bucket, res)
    return stats


def _validate_invariants(agg: dict[str, dict[str, Any]], expected_total: int) -> None:
    total_games = 0
    for slug, b in agg.items():
        g = b["games"]
        assert b["p0_wins"] + b["p1_wins"] + b["draws"] == g, f"outcome mismatch for {slug}"
        assert sum(b["end_reason_counts"].values()) == g, f"end-reason mismatch for {slug}"
        assert sum(b["final_power_hist_p0"]) == g, f"p0 hist mismatch for {slug}"
        assert sum(b["final_power_hist_p1"]) == g, f"p1 hist mismatch for {slug}"
        for i in range(len(POWER_CURVE_MARKERS)):
            assert b["power_curve_p0_count"][i] <= g
            assert b["power_curve_p1_count"][i] <= g
        total_games += g
    assert total_games == expected_total, f"global game count mismatch: {total_games} vs {expected_total}"


def _fmt_pct(n: int, d: int) -> str:
    return f"{(100.0 * n / d):6.2f}%" if d > 0 else "   n/a "


def _avg(s: int, c: int) -> float:
    return (s / c) if c > 0 else 0.0


def _print_report(p0_slug: str, agg: dict[str, dict[str, Any]], total_runs: int, elapsed: float) -> None:
    print()
    print(f"=== Arcana Monte Carlo: P0={p0_slug}  total_runs={total_runs}  elapsed={elapsed:.2f}s ===")
    print()
    header = (
        f"{'opponent':22s}  {'games':>6s}  "
        f"{'P0_win%':>8s}  {'P0_loss%':>9s}  {'draw%':>7s}  "
        f"{'avg_turns':>9s}  {'avg_P0_pwr':>10s}  {'avg_P1_pwr':>10s}  "
        f"{'power_20':>8s}  {'deck_out':>8s}  {'turn_cap':>8s}"
    )
    print(header)
    print("-" * len(header))
    slugs = sorted(agg.keys())
    totals = _empty_bucket()
    for slug in slugs:
        b = agg[slug]
        g = b["games"]
        print(
            f"{slug:22s}  {g:6d}  "
            f"{_fmt_pct(b['p0_wins'], g)}  {_fmt_pct(b['p1_wins'], g)}  {_fmt_pct(b['draws'], g)}  "
            f"{_avg(b['turns_sum'], g):9.2f}  {_avg(b['p0_power_sum'], g):10.2f}  {_avg(b['p1_power_sum'], g):10.2f}  "
            f"{b['end_reason_counts']['power_20']:8d}  {b['end_reason_counts']['deck_out']:8d}  {b['end_reason_counts']['turn_cap']:8d}"
        )
        _merge_bucket(totals, b)
    print("-" * len(header))
    g = totals["games"]
    print(
        f"{'TOTAL':22s}  {g:6d}  "
        f"{_fmt_pct(totals['p0_wins'], g)}  {_fmt_pct(totals['p1_wins'], g)}  {_fmt_pct(totals['draws'], g)}  "
        f"{_avg(totals['turns_sum'], g):9.2f}  {_avg(totals['p0_power_sum'], g):10.2f}  {_avg(totals['p1_power_sum'], g):10.2f}  "
        f"{totals['end_reason_counts']['power_20']:8d}  {totals['end_reason_counts']['deck_out']:8d}  {totals['end_reason_counts']['turn_cap']:8d}"
    )
    print()
    print("--- match-power progression (avg across all matchups) ---")
    print(f"{'turn':>6s}  {'P0 avg power':>14s}  {'P1 avg power':>14s}")
    for i, t in enumerate(POWER_CURVE_MARKERS):
        s0, c0 = totals["power_curve_p0_sum"][i], totals["power_curve_p0_count"][i]
        s1, c1 = totals["power_curve_p1_sum"][i], totals["power_curve_p1_count"][i]
        print(f"{t:>6d}  {_avg(s0, c0):>14.2f}  {_avg(s1, c1):>14.2f}")
    print()
    print("--- final match-power histogram (P0) ---")
    _print_hist(totals["final_power_hist_p0"])
    print()
    print("--- final match-power histogram (P1) ---")
    _print_hist(totals["final_power_hist_p1"])


def _print_hist(hist: list[int]) -> None:
    total = sum(hist)
    max_count = max(hist) if hist else 1
    width = 40
    for i, n in enumerate(hist):
        label = f"{i:>3d}+" if i == len(hist) - 1 else f"{i:>3d} "
        bar = "#" * int(width * n / max_count) if max_count > 0 else ""
        pct = 100.0 * n / total if total else 0.0
        print(f"  {label}  {n:7d}  ({pct:5.2f}%)  {bar}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Arcana Monte Carlo sim")
    ap.add_argument("--deck", required=True, help="P0 deck slug (must exist in included_decks/index.json)")
    ap.add_argument("--runs", type=int, default=100_000, help="total number of simulated games")
    ap.add_argument("--seed", type=int, default=0, help="master RNG seed for reproducibility")
    ap.add_argument("--workers", type=int, default=0, help="override worker count (default: os.cpu_count())")
    args = ap.parse_args()

    slugs = included_deck_slugs()
    if args.deck not in slugs:
        raise SystemExit(f"--deck must be one of {slugs}; got {args.deck!r}")

    workers = args.workers if args.workers > 0 else (os.cpu_count() or 1)
    workers = max(1, min(workers, args.runs))
    per_shard = args.runs // workers
    remainder = args.runs - per_shard * workers
    shard_args = []
    for i in range(workers):
        runs_i = per_shard + (1 if i < remainder else 0)
        shard_args.append((args.deck, runs_i, args.seed * 1_000_003 + i * 17 + 1))

    print(f"Launching {workers} worker(s); total runs={args.runs} (per-shard ~={per_shard})")
    t0 = time.perf_counter()
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
    elapsed = time.perf_counter() - t0
    _validate_invariants(agg, args.runs)
    _print_report(args.deck, agg, args.runs, elapsed)


if __name__ == "__main__":
    main()
