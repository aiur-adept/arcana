"""Meta-analysis: run ``--runs`` games with every deck as P0 (P1 uniformly
sampled from all included decks) and emit a CSV matchup matrix.

Each cell ``M[row, col]`` is the expected match points for the **column** deck
as P1 facing the **row** deck as P0: ``(3*p1_wins + 1*draws) / games`` (loss = 0).
Row labels are the P0 opponent; column headers are the focal deck as P1.
This avoids win-rate distortion when some matchups draw often.

Usage:
    # Trained-first pilots from data/pilot_weights.json (per slug when present)
    python -m sim.meta --runs 100000 --seed 42 [--out sim_meta_matrix.csv]

    # Baseline pilots only (class defaults; no JSON overrides)
    python -m sim.meta --runs 100000 --seed 42 --baseline-pilots

Common flags: ``--workers N``, ``--games-out``, ``--gameplay-out``.

``--gameplay-out`` writes per-deck P1 focal stats (pooled over all P0) with
IQR / Tukey outlier flags for incantations, discard-to-draw, 20+ power route
wins, etc.

This reuses ``sim.run.run_shard`` (multiprocess shards per P0 slug) so the
per-game pilot / mulligan / invariant plumbing is identical to the CLI
runner. The only difference is the top-level loop over every P0 slug and
the CSV assembly step at the end."""

from __future__ import annotations

import argparse
import csv
import math
import multiprocessing as mp
import os
import statistics
import time
from pathlib import Path
from typing import Any, Callable

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


def _cell_expected_mp_p1(bucket: dict[str, Any]) -> tuple[float, int]:
    g = bucket["games"]
    if g == 0:
        return (0.0, 0)
    pts = 3 * bucket["p1_wins"] + bucket["draws"]
    return (pts / g, g)


def _pool_p1_focal(
    slugs: list[str], all_agg: dict[str, dict[str, dict[str, Any]]], col_slug: str
) -> dict[str, Any] | None:
    gtot = 0
    exp_pts = 0.0
    turns = 0
    p1_inc = 0
    p1_dd = 0
    p1_wins = 0
    p1_wbp = 0
    p1_psum = 0
    er: dict[str, int] = {}
    for row_slug in slugs:
        b = all_agg[row_slug].get(col_slug)
        if b is None or b["games"] == 0:
            continue
        g = b["games"]
        gtot += g
        mp, _ = _cell_expected_mp_p1(b)
        exp_pts += mp * g
        turns += b["turns_sum"]
        p1_inc += b["p1_incant_plays_sum"]
        p1_dd += b["p1_discard_draws_sum"]
        p1_wins += b["p1_wins"]
        p1_wbp += b["p1_wins_by_power"]
        p1_psum += b["p1_power_sum"]
        for k, v in b["end_reason_counts"].items():
            er[k] = er.get(k, 0) + v
    if gtot == 0:
        return None
    exp = exp_pts / gtot
    return {
        "games": gtot,
        "exp_mp_p1": exp,
        "avg_turns": turns / gtot,
        "p1_incant_per_game": p1_inc / gtot,
        "p1_discard_draw_per_game": p1_dd / gtot,
        "p1_incant_per_turn": (p1_inc / turns) if turns > 0 else 0.0,
        "p1_win_rate": p1_wins / gtot,
        "p1_wins_20p_share": (p1_wbp / p1_wins) if p1_wins > 0 else 0.0,
        "games_ended_power_rule": er.get("power_win", 0) / gtot,
        "games_ended_deck_out": er.get("deck_out", 0) / gtot,
        "games_ended_turn_cap": er.get("turn_cap", 0) / gtot,
        "avg_p1_final_power": p1_psum / gtot,
    }


def _tukey_fences(values: list[float]) -> tuple[float, float, float, float, float, float] | None:
    xs = [x for x in values if not math.isnan(x)]
    if len(xs) < 2:
        return None
    qs = statistics.quantiles(xs, n=4, method="inclusive")
    q1, q2, q3 = qs[0], qs[1], qs[2]
    iqr = q3 - q1
    return (q1, q2, q3, iqr, q1 - 1.5 * iqr, q3 + 1.5 * iqr)


def _outlier_flag(
    v: float,
    fences: tuple[float, float, float, float, float, float] | None,
) -> bool:
    if fences is None or math.isnan(v):
        return False
    _, _, _, _, lo, hi = fences
    return v < lo or v > hi


def _iqr_by_metric(
    per_deck: list[tuple[str, dict[str, Any]]],
) -> dict[str, tuple[float, float, float, float, float, float] | None]:
    out: dict[str, tuple[float, float, float, float, float, float] | None] = {}
    spec: list[tuple[str, Callable[[dict[str, Any]], float]]] = [
        ("p1_incant_per_game", lambda r: r["p1_incant_per_game"]),
        ("p1_discard_draw_per_game", lambda r: r["p1_discard_draw_per_game"]),
        ("p1_wins_20p_share", lambda r: r["p1_wins_20p_share"]),
        ("games_ended_power_rule", lambda r: r["games_ended_power_rule"]),
        ("exp_mp_p1", lambda r: r["exp_mp_p1"]),
        ("avg_p1_final_power", lambda r: r["avg_p1_final_power"]),
        ("p1_incant_per_turn", lambda r: r["p1_incant_per_turn"]),
        ("avg_turns", lambda r: r["avg_turns"]),
    ]
    for name, f in spec:
        vals = [f(r) for _, r in per_deck]
        out[name] = _tukey_fences(vals)
    return out


def _print_gameplay_section(
    slugs: list[str],
    all_agg: dict[str, dict[str, dict[str, Any]]],
) -> tuple[
    list[tuple[str, dict[str, Any]]], dict[str, tuple[float, float, float, float, float, float] | None]
]:
    per_deck: list[tuple[str, dict[str, Any]]] = []
    for col in slugs:
        rowd = _pool_p1_focal(slugs, all_agg, col)
        if rowd is not None:
            per_deck.append((col, rowd))
    if not per_deck:
        return per_deck, {}
    fences = _iqr_by_metric(per_deck)
    print()
    print("--- P1 focal gameplay (pooled over all P0 opponents; 20+ power wins = end_reason power_win) ---")
    for key, t in sorted(fences.items(), key=lambda kv: kv[0]):
        f = t
        if f is None:
            print(f"  {key}: IQR n/a (need >=2 distinct decks)")
        else:
            q1, q2, q3, iqr, lo, hi = f
            print(
                f"  {key}:  Q1={q1:.4f}  Q2={q2:.4f}  Q3={q3:.4f}  "
                f"IQR={iqr:.4f}  fences=[{lo:.4f}, {hi:.4f}]"
            )
    w = max(len(s) for s, _ in per_deck) + 2
    mkeys = list(fences.keys())
    print()
    print(
        f"{'slug':{w}s}  {'G':>8s}  {'expMP':>8s}  "
        f"{'inc/g':>8s}  {'dd/g':>8s}  {'inc/turn':>8s}  "
        f"{'20+p|P1W':>9s}  {'pwrG':>7s}  "
        f"{'avgP1P':>8s}  {'TURN':>7s}  outlier"
    )
    ocols = mkeys
    for slug, r in sorted(per_deck, key=lambda x: -x[1]["exp_mp_p1"]):
        oset = {k for k in ocols if _outlier_flag(r.get(k, float("nan")), fences.get(k))}
        oflag = ",".join(sorted(oset)) if oset else ""
        print(
            f"{slug:{w}s}  {r['games']:8d}  {r['exp_mp_p1']:8.3f}  "
            f"{r['p1_incant_per_game']:8.3f}  {r['p1_discard_draw_per_game']:8.3f}  {r['p1_incant_per_turn']:8.3f}  "
            f"{r['p1_wins_20p_share']*100:8.1f}%  {r['games_ended_power_rule']*100:6.1f}%  "
            f"{r['avg_p1_final_power']:8.2f}  {r['avg_turns']:7.2f}  {oflag or '-'}"
        )
    for h in ("void_temples", "bird_flock"):
        p = next(((s, d) for s, d in per_deck if s == h), None)
        if p is None:
            continue
        s, r = p
        oset = {k for k in ocols if _outlier_flag(r.get(k, float("nan")), fences.get(k))}
        print()
        print(f"  (highlight) {s}:  expMP {r['exp_mp_p1']:.3f}  "
              f"incant/game {r['p1_incant_per_game']:.3f}  "
              f"discard-draw/game {r['p1_discard_draw_per_game']:.3f}  "
              f"P1 win share 20+ route {r['p1_wins_20p_share']*100:.1f}%  "
              f"games end power rule {r['games_ended_power_rule']*100:.1f}%  "
              f"outlier metrics: {', '.join(sorted(oset)) or 'none'}")
    return per_deck, fences


def _write_gameplay_csv(
    path: Path, per_deck: list[tuple[str, dict[str, Any]]],
    fences: dict[str, tuple[float, float, float, float, float, float] | None],
) -> None:
    if not per_deck:
        return
    fkeys = sorted(f for f in (fences or {}))
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "slug", "games", "exp_mp_p1", "p1_incant_per_game", "p1_discard_draw_per_game",
                "p1_incant_per_turn", "p1_win_rate", "p1_wins_20p_power_share", "games_ended_power_rule_rate",
                "games_ended_deck_out_rate", "games_ended_turn_cap_rate", "avg_p1_final_power", "avg_turns",
            ]
            + [f"outlier__{k}" for k in fkeys]
        )
        for slug, r in per_deck:
            out = {k: _outlier_flag(r.get(k, float("nan")), fences.get(k)) for k in fkeys}
            w.writerow(
                [
                    slug, r["games"],
                    f"{r['exp_mp_p1']:.6f}", f"{r['p1_incant_per_game']:.6f}",
                    f"{r['p1_discard_draw_per_game']:.6f}", f"{r['p1_incant_per_turn']:.6f}",
                    f"{r['p1_win_rate']:.6f}", f"{r['p1_wins_20p_share']:.6f}", f"{r['games_ended_power_rule']:.6f}",
                    f"{r['games_ended_deck_out']:.6f}", f"{r['games_ended_turn_cap']:.6f}",
                    f"{r['avg_p1_final_power']:.6f}", f"{r['avg_turns']:.6f}",
                ]
                + [str(out[k]) for k in fkeys]
            )


def run_meta(runs_per_deck: int, seed: int, workers: int,
             out_path: Path,
             games_out_path: Path | None = None,
             gameplay_out_path: Path | None = None,
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
        w.writerow(["exp_match_pts_col"] + slugs)
        for row_slug in slugs:
            row = [row_slug]
            for col_slug in slugs:
                bucket = all_agg[row_slug].get(col_slug)
                if bucket is None or bucket["games"] == 0:
                    row.append("")
                else:
                    mp, _ = _cell_expected_mp_p1(bucket)
                    row.append(f"{mp:.4f}")
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

    _print_summary_table(slugs, all_agg)
    per_deck, fence_map = _print_gameplay_section(slugs, all_agg)
    if gameplay_out_path is not None and per_deck:
        _write_gameplay_csv(gameplay_out_path, per_deck, fence_map)
        print(f"Wrote gameplay summary: {gameplay_out_path}")


def _print_summary_table(slugs: list[str],
                         all_agg: dict[str, dict[str, dict[str, Any]]]) -> None:
    print()
    print("--- overall expected MP (P1 / column deck, 3/1/0; uniform random P0) ---")
    rows = []
    for col_slug in slugs:
        total_pts = 0.0
        total_g = 0
        for row_slug in slugs:
            bucket = all_agg[row_slug].get(col_slug)
            if bucket is None or bucket["games"] == 0:
                continue
            mp, g = _cell_expected_mp_p1(bucket)
            total_pts += mp * g
            total_g += g
        avg = (total_pts / total_g) if total_g > 0 else 0.0
        rows.append((col_slug, avg, total_g))
    rows.sort(key=lambda r: -r[1])
    width = max(len(s) for s in slugs)
    for slug, avg, g in rows:
        print(f"  {slug:<{width}s}   {avg:6.3f}  ({g} games)")


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
    ap.add_argument("--gameplay-out", type=str, default="",
                    help="optional: write P1 focal gameplay + outlier flags (CSV)")
    ap.add_argument(
        "--baseline-pilots",
        action="store_true",
        help="use class-default pilots only (ignore pilot_weights.json; default behavior is trained-first when available)",
    )
    ap.add_argument(
        "--use-saved-weights",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    ap.add_argument("--weights", type=str, default="",
                    help="pilot_weights.json path; only used with --use-saved-weights "
                    "(default: <project>/data/pilot_weights.json)")
    args = ap.parse_args()

    workers = args.workers if args.workers > 0 else (os.cpu_count() or 1)
    workers = max(1, min(workers, args.runs))
    out_path = Path(args.out)
    games_out_path = Path(args.games_out) if args.games_out else None
    gameplay_out_path = Path(args.gameplay_out) if args.gameplay_out else None
    use_saved_weights = not bool(args.baseline_pilots)
    weights_path_str = ""
    if use_saved_weights:
        wp = Path(args.weights) if args.weights else default_pilot_weights_path()
        weights_path_str = str(wp.resolve())
    run_meta(
        args.runs, args.seed, workers, out_path,
        games_out_path,
        gameplay_out_path,
        weights_path_str, use_saved_weights,
    )


if __name__ == "__main__":
    main()
