"""Evolutionary training for GreedyAI pilot weights (sim harness).

Writes JSON consumed by Godot: data/pilot_weights.json

Usage:
    python -m sim.train_ea --deck bird_flock --generations 30 --population 24 --games 400 [--seed 0]
"""

from __future__ import annotations

import argparse
import multiprocessing as mp
import os
import random
import time
from pathlib import Path
from typing import Any

from .decks import included_deck_slugs
from .ea_eval import eval_genome_worker
from .pilot_weights import (
    DEFAULT_PILOT_WEIGHTS_FILENAME,
    baseline_weights_for_slug,
    clamp_genome,
    default_ea_p1_snapshot_path,
    default_pilot_weights_path,
    greedy_ai_float_weight_keys,
    merge_slug_into_weights_file,
    weights_for_slug_from_file,
    write_ea_opponent_snapshot,
)


def _log(msg: str) -> None:
    print(msg, flush=True)


def _select_trainable_keys(train_discard_weights_only: bool) -> list[str]:
    keys = list(greedy_ai_float_weight_keys())
    if not train_discard_weights_only:
        return keys
    return [k for k in keys if k == "W_DISCARD_DRAW" or k.startswith("DD_")]


def _mutate(
    rng: random.Random,
    w: dict[str, float],
    sigma: float,
    trainable_keys: list[str],
) -> dict[str, float]:
    out = dict(w)
    for k in trainable_keys:
        out[k] = out.get(k, 0.0) + rng.gauss(0.0, sigma)
    return clamp_genome(out)


def _init_individual(
    rng: random.Random,
    baseline: dict[str, float],
    keys: list[str],
    sigma_init: float,
    init_spread: float,
    init_uniform_fraction: float,
    init_uniform_delta: float,
) -> dict[str, float]:
    g = dict(baseline)
    if rng.random() < init_uniform_fraction:
        for k in keys:
            lo = baseline[k] - init_uniform_delta
            hi = baseline[k] + init_uniform_delta
            g[k] = rng.uniform(lo, hi)
        return clamp_genome(g)
    for k in keys:
        g[k] = baseline[k] + rng.gauss(0.0, sigma_init * 2.0 * init_spread)
    return clamp_genome(g)


def _tournament_pick(
    rng: random.Random,
    pop: list[dict[str, float]],
    fitness: list[float],
    k: int,
) -> dict[str, float]:
    idxs = [rng.randrange(len(pop)) for _ in range(k)]
    best_i = max(idxs, key=lambda i: fitness[i])
    return pop[best_i].copy()


def run_ea(
    slug: str,
    generations: int,
    population: int,
    games_per_eval: int,
    seed: int,
    sigma_init: float,
    sigma_floor: float,
    sigma_decay: float,
    tournament_k: int,
    workers: int,
    weights_file_path: Path,
    init_spread: float,
    init_uniform_fraction: float,
    init_uniform_delta: float,
    p1_use_saved_weights: bool,
    p1_snapshot_path: Path | None,
    initial_weights: dict[str, float] | None = None,
    trainable_keys: list[str] | None = None,
) -> dict[str, float]:
    rng = random.Random(seed)
    baseline = baseline_weights_for_slug(slug)
    if initial_weights:
        for k, v in initial_weights.items():
            baseline[k] = float(v)
    keys = trainable_keys if trainable_keys is not None else list(greedy_ai_float_weight_keys())

    pop: list[dict[str, float]] = []
    for _ in range(population):
        pop.append(
            _init_individual(
                rng, baseline, keys, sigma_init,
                init_spread, init_uniform_fraction, init_uniform_delta,
            )
        )

    best_ever: dict[str, float] = baseline.copy()
    best_fit = -1.0

    if p1_use_saved_weights:
        if p1_snapshot_path is None:
            raise ValueError("p1_snapshot_path required when p1_use_saved_weights")
        p1_snap_str = str(p1_snapshot_path.resolve())
        snap0 = dict(baseline)
        disk_w = weights_for_slug_from_file(weights_file_path, slug)
        if disk_w:
            for k in greedy_ai_float_weight_keys():
                if k in disk_w:
                    snap0[k] = disk_w[k]
        write_ea_opponent_snapshot(p1_snapshot_path, weights_file_path, slug, snap0)
        _log(
            f"P1 opponents: trained weights from snapshot (merged with {weights_file_path.name}); "
            f"snapshot file: {p1_snap_str}"
        )
    else:
        p1_snap_str = ""
        _log("P1 opponents: baseline pilot classes (no JSON weights).")

    _log(
        f"Initial population ready: {population} individuals, {len(keys)} genes each "
        f"(pilot {slug!r}; init_spread={init_spread}, uniform_frac={init_uniform_fraction})."
    )

    pool = None
    if workers > 1:
        pool = mp.Pool(processes=workers)
        _log(f"Using process pool: {workers} worker(s) for fitness evaluation.")

    try:
        for gen in range(generations):
            t0 = time.perf_counter()
            sigma = max(sigma_floor, sigma_init * (sigma_decay**gen))
            fitness: list[float] = [0.0] * population

            payloads: list[tuple[Any, ...]] = []
            for i in range(population):
                eval_seed = seed + gen * 1_000_003 + i * 17 + 1
                wt = tuple(sorted(pop[i].items()))
                payloads.append(
                    (i, slug, wt, games_per_eval, eval_seed, p1_snap_str, p1_use_saved_weights)
                )

            _log("")
            _log(
                f"--- Generation {gen + 1}/{generations}  "
                f"(sigma={sigma:.3f})  "
                f"evaluating {population} genomes x {games_per_eval} games each ---"
            )
            eval_t0 = time.perf_counter()

            if pool is not None:
                done = 0
                best_partial = -1.0
                milestone = max(1, population // 4)
                for idx, fit in pool.imap_unordered(eval_genome_worker, payloads, chunksize=1):
                    fitness[idx] = fit
                    done += 1
                    if fit > best_partial:
                        best_partial = fit
                    if done == 1 or done == population or done % milestone == 0:
                        _log(
                            f"  fitness {done}/{population}  "
                            f"best_partial={best_partial:.4f}  "
                            f"elapsed={time.perf_counter() - eval_t0:.1f}s"
                        )
            else:
                for j, p in enumerate(payloads):
                    idx, fit = eval_genome_worker(p)
                    fitness[idx] = fit
                    _log(
                        f"  genome {j + 1}/{population}  idx={idx}  fitness={fit:.4f}  "
                        f"elapsed={time.perf_counter() - eval_t0:.1f}s"
                    )

            for i in range(population):
                if fitness[i] > best_fit:
                    best_fit = fitness[i]
                    best_ever = pop[i].copy()

            if p1_use_saved_weights:
                write_ea_opponent_snapshot(p1_snapshot_path, weights_file_path, slug, best_ever)

            next_gen: list[dict[str, float]] = [best_ever.copy()]
            while len(next_gen) < population:
                p1 = _tournament_pick(rng, pop, fitness, tournament_k)
                p2 = _tournament_pick(rng, pop, fitness, tournament_k)
                child: dict[str, float] = baseline.copy()
                for k in keys:
                    if rng.random() < 0.5:
                        child[k] = p1.get(k, baseline[k])
                    else:
                        child[k] = p2.get(k, baseline[k])
                child = _mutate(rng, child, sigma, keys)
                next_gen.append(clamp_genome(child))
            pop = next_gen

            elapsed = time.perf_counter() - t0
            _log(
                f"gen {gen + 1}/{generations} complete  "
                f"best_this_gen={max(fitness):.4f}  best_ever={best_fit:.4f}  "
                f"sigma={sigma:.3f}  gen_elapsed={elapsed:.2f}s"
            )
    finally:
        if pool is not None:
            pool.close()
            pool.join()

    return best_ever


def main() -> None:
    ap = argparse.ArgumentParser(description="EA training for Arcana pilot weights")
    ap.add_argument("--deck", required=True, help="P0 deck slug (included_decks)")
    ap.add_argument("--generations", type=int, default=25)
    ap.add_argument("--population", type=int, default=20)
    ap.add_argument("--games", type=int, default=300, help="games per genome per generation")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--sigma", type=float, default=4.0, help="initial mutation sigma")
    ap.add_argument("--sigma-floor", type=float, default=0.5)
    ap.add_argument("--sigma-decay", type=float, default=0.97)
    ap.add_argument("--tournament-k", type=int, default=3)
    ap.add_argument("--workers", type=int, default=0, help="parallel eval (default: cpu count)")
    ap.add_argument(
        "--out",
        type=str,
        default="",
        help=f"output JSON path (default: data/{DEFAULT_PILOT_WEIGHTS_FILENAME} under project root)",
    )
    ap.add_argument(
        "--init-spread",
        type=float,
        default=1.0,
        help="multiplier on Gaussian init sigma (default 1.0)",
    )
    ap.add_argument(
        "--init-uniform-fraction",
        type=float,
        default=0.0,
        help="fraction of population initialized uniformly in [baseline ± delta] (default 0)",
    )
    ap.add_argument(
        "--init-uniform-delta",
        type=float,
        default=0.0,
        help="half-width for uniform init per gene; if 0, uses 3 * --sigma (default 0)",
    )
    ap.add_argument(
        "--p1-trained-weights",
        action="store_true",
        help="P1 uses weights from --out JSON merged with per-generation best for training slug",
    )
    ap.add_argument(
        "--p1-snapshot",
        type=str,
        default="",
        help="EA P1 snapshot JSON path (default: %%TEMP%%/arcana_ea_p1/<deck>.json; avoids OneDrive dotfiles in data/)",
    )
    ap.add_argument(
        "--init-weights",
        type=str,
        default="",
        help="optional weights JSON path used to initialize the training baseline for --deck",
    )
    ap.add_argument(
        "--start-from-trained",
        action="store_true",
        help="initialize baseline from existing weights_by_slug[--deck] in --out (or default output file)",
    )
    ap.add_argument(
        "--train-discard-weights-only",
        action="store_true",
        help="only train W_DISCARD_DRAW and DD_* contextual discard weights",
    )
    args = ap.parse_args()

    slugs = included_deck_slugs()
    if args.deck not in slugs:
        raise SystemExit(f"--deck must be one of {slugs}; got {args.deck!r}")

    workers = args.workers if args.workers > 0 else (os.cpu_count() or 1)
    workers = max(1, min(workers, args.population))

    out_path = Path(args.out) if args.out else default_pilot_weights_path()

    est_games = args.generations * args.population * args.games
    _log("=== EA pilot training ===")
    _log(
        f"deck={args.deck!r}  population={args.population}  generations={args.generations}  "
        f"games_per_genome={args.games}"
    )
    _log(
        f"sigma={args.sigma}  sigma_floor={args.sigma_floor}  sigma_decay={args.sigma_decay}  "
        f"tournament_k={args.tournament_k}"
    )
    _log(f"seed={args.seed}  workers={workers}")
    _log(f"output: {out_path.resolve()}")
    trainable_keys = _select_trainable_keys(args.train_discard_weights_only)
    _log(f"train_discard_weights_only={bool(args.train_discard_weights_only)}")
    _log(f"trainable_genes={len(trainable_keys)}")
    udelta = args.init_uniform_delta if args.init_uniform_delta > 0 else (args.sigma * 3.0)
    _log(
        f"init: spread={args.init_spread}  uniform_fraction={args.init_uniform_fraction}  "
        f"uniform_delta={udelta}"
    )
    _log(f"p1_trained_weights={bool(args.p1_trained_weights)}")
    init_weights: dict[str, float] | None = None
    if args.init_weights:
        iw_path = Path(args.init_weights).resolve()
        iw = weights_for_slug_from_file(iw_path, args.deck)
        if iw:
            init_weights = clamp_genome(iw)
            _log(f"init_weights: using saved genome for {args.deck!r} from {iw_path}")
        else:
            _log(f"init_weights: no saved genome for {args.deck!r} in {iw_path}; using pilot baseline")
    elif args.start_from_trained:
        iw = weights_for_slug_from_file(out_path, args.deck)
        if iw:
            init_weights = clamp_genome(iw)
            _log(f"start_from_trained: using saved genome for {args.deck!r} from {out_path.resolve()}")
        else:
            _log(
                f"start_from_trained: no saved genome for {args.deck!r} in {out_path.resolve()}; "
                "using pilot baseline"
            )
    p1_snap: Path | None = None
    if args.p1_trained_weights:
        p1_snap = Path(args.p1_snapshot).resolve() if args.p1_snapshot else default_ea_p1_snapshot_path(args.deck)
        _log(f"p1_snapshot: {p1_snap}")
    _log(f"~{est_games} total simulated games upper bound (gen x pop x games/eval)")
    _log("")

    best = run_ea(
        slug=args.deck,
        generations=args.generations,
        population=args.population,
        games_per_eval=args.games,
        seed=args.seed,
        sigma_init=args.sigma,
        sigma_floor=args.sigma_floor,
        sigma_decay=args.sigma_decay,
        tournament_k=args.tournament_k,
        workers=workers,
        weights_file_path=out_path,
        init_spread=args.init_spread,
        init_uniform_fraction=args.init_uniform_fraction,
        init_uniform_delta=udelta,
        p1_use_saved_weights=args.p1_trained_weights,
        p1_snapshot_path=p1_snap,
        initial_weights=init_weights,
        trainable_keys=trainable_keys,
    )

    merge_slug_into_weights_file(out_path, args.deck, best, genome_version=1)
    _log("")
    _log(f"Done. Best genome written under weights_by_slug[{args.deck!r}] in {out_path.resolve()}")


if __name__ == "__main__":
    main()
