"""Evolutionary training for GreedyAI pilot weights (sim harness).

Writes JSON consumed by Godot: data/pilot_weights.json

Usage:
    python -m sim.train_ea --deck bird_test --generations 30 --population 24 --games 400 [--seed 0]
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
    default_pilot_weights_path,
    greedy_ai_float_weight_keys,
    merge_slug_into_weights_file,
)


def _log(msg: str) -> None:
    print(msg, flush=True)


def _mutate(rng: random.Random, w: dict[str, float], sigma: float) -> dict[str, float]:
    out = {}
    for k, v in w.items():
        out[k] = v + rng.gauss(0.0, sigma)
    return clamp_genome(out)


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
) -> dict[str, float]:
    rng = random.Random(seed)
    baseline = baseline_weights_for_slug(slug)
    keys = list(greedy_ai_float_weight_keys())

    pop: list[dict[str, float]] = []
    for _ in range(population):
        g = _mutate(rng, baseline, sigma_init * 2.0)
        for k in keys:
            if k not in g:
                g[k] = baseline[k]
        pop.append(clamp_genome(g))

    best_ever: dict[str, float] = baseline.copy()
    best_fit = -1.0

    _log(
        f"Initial population ready: {population} individuals, {len(keys)} genes each "
        f"(mutated from pilot {slug!r} baseline)."
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
                payloads.append((i, slug, wt, games_per_eval, eval_seed))

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

            next_gen: list[dict[str, float]] = [best_ever.copy()]
            while len(next_gen) < population:
                p1 = _tournament_pick(rng, pop, fitness, tournament_k)
                p2 = _tournament_pick(rng, pop, fitness, tournament_k)
                child: dict[str, float] = {}
                for k in keys:
                    if rng.random() < 0.5:
                        child[k] = p1[k]
                    else:
                        child[k] = p2[k]
                child = _mutate(rng, child, sigma)
                for k in keys:
                    if k not in child:
                        child[k] = baseline[k]
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
    )

    merge_slug_into_weights_file(out_path, args.deck, best, genome_version=1)
    _log("")
    _log(f"Done. Best genome written under weights_by_slug[{args.deck!r}] in {out_path.resolve()}")


if __name__ == "__main__":
    main()
