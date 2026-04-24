"""Directional grid trainer for incantation-focused pilot weights.

Usage:
    python -m sim.train_incantation_grid --deck occultation
"""

from __future__ import annotations

import argparse
import itertools
import math
import multiprocessing as mp
import random
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .decks import included_deck_slugs
from .ea_eval import eval_genome_worker
from .pilot_weights import (
    baseline_weights_for_slug,
    clamp_genome,
    default_pilot_weights_path,
    greedy_ai_float_weight_keys,
    merge_slug_into_weights_file,
    weights_for_slug_from_file,
)


@dataclass(frozen=True)
class DirectionalRange:
    key: str
    direction: int
    low: float
    high: float
    step: float

    def deltas(self) -> list[float]:
        lo = min(self.low, self.high)
        hi = max(self.low, self.high)
        if self.step <= 0:
            raise ValueError(f"step must be > 0 for key={self.key}")
        vals: list[float] = [0.0]
        x = lo
        while x <= hi + 1e-9:
            d = abs(x)
            if d > 1e-9:
                vals.append(float(self.direction) * d)
            x += self.step
        uniq = sorted({round(v, 8) for v in vals})
        return [float(v) for v in uniq]


def _log(msg: str) -> None:
    print(msg, flush=True)


def _directional_specs(extend: float) -> list[DirectionalRange]:
    scale = max(1.0, extend)
    return [
        DirectionalRange("INC_BASE_BONUS", +1, 0.0, 12.0 * scale, 4.0),
        DirectionalRange("DD_W_INC_BASE", +1, 0.0, 30.0 * scale, 10.0),
        DirectionalRange("DD_W_INC_PER_VALUE", -1, 0.0, 8.0 * scale, 2.0),
        DirectionalRange("W_DISCARD_DRAW", -1, 0.0, 20.0 * scale, 5.0),
        DirectionalRange("W_CAST_WITH_SAC_BASE", +1, 0.0, 16.0 * scale, 4.0),
        DirectionalRange("W_CAST_WITH_SAC_EXPECTED_MP_DELTA", +1, 0.0, 12.0 * scale, 3.0),
        DirectionalRange("W_CAST_WITH_SAC_PAYMENT_MP_LOSS", -1, 0.0, 10.0 * scale, 2.0),
        DirectionalRange("W_INCANTATION_SACRIFICE_RITUAL_PER_VALUE", -1, 0.0, 6.0 * scale, 1.5),
        DirectionalRange("W_SF_INC_BEHIND", +1, 0.0, 24.0 * scale, 6.0),
    ]


def _baseline_for_slug(slug: str, out_path: Path, start_from_trained: bool) -> dict[str, float]:
    base = baseline_weights_for_slug(slug)
    for k in greedy_ai_float_weight_keys():
        base.setdefault(k, 0.0)
    if start_from_trained:
        disk = weights_for_slug_from_file(out_path, slug)
        if disk:
            base.update({k: float(v) for k, v in disk.items()})
    return clamp_genome(base)


def _genome_to_signature(weights: dict[str, float]) -> tuple[tuple[str, float], ...]:
    return tuple(sorted((k, round(float(v), 8)) for k, v in weights.items()))


def _mutate_key(weights: dict[str, float], key: str, delta: float) -> dict[str, float]:
    out = dict(weights)
    out[key] = float(out.get(key, 0.0) + delta)
    return clamp_genome(out)


def _enumerate_initial_population(
    baseline: dict[str, float],
    specs: list[DirectionalRange],
    combo_keys: list[str],
    max_population: int,
    seed: int,
) -> list[dict[str, float]]:
    key_to_spec = {s.key: s for s in specs}
    for k in combo_keys:
        if k not in key_to_spec:
            raise ValueError(f"combo key {k!r} not in directional spec")
    options = [key_to_spec[k].deltas() for k in combo_keys]
    total = math.prod(len(v) for v in options) if options else 1
    _log(f"Enumerating initial population over keys={combo_keys} combinations={total}")

    pop: list[dict[str, float]] = []
    seen: set[tuple[tuple[str, float], ...]] = set()
    rng = random.Random(seed)
    combos_iter = itertools.product(*options) if options else [()]
    for deltas in combos_iter:
        g = dict(baseline)
        for k, d in zip(combo_keys, deltas):
            g[k] = g.get(k, 0.0) + float(d)
        g = clamp_genome(g)
        sig = _genome_to_signature(g)
        if sig in seen:
            continue
        seen.add(sig)
        pop.append(g)

    if len(pop) > max_population:
        pop = rng.sample(pop, max_population)
        _log(f"Population capped to {len(pop)} (sampled from full enumeration).")
    else:
        _log(f"Initial population size={len(pop)}")
    return pop


def _evaluate_population(
    slug: str,
    pop: list[dict[str, float]],
    games: int,
    seed: int,
    workers: int,
    opponent: str | None,
) -> list[float]:
    payloads: list[tuple[Any, ...]] = []
    for i, genome in enumerate(pop):
        payloads.append(
            (
                i,
                slug,
                tuple(sorted(genome.items())),
                games,
                seed * 1_000_003 + i * 17 + 1,
                "",
                False,
                opponent or "",
            )
        )
    fit = [0.0] * len(pop)
    n = len(payloads)
    t0 = time.perf_counter()
    milestone = max(1, n // 10)
    if workers <= 1:
        done = 0
        best_partial = -1.0
        for p in payloads:
            i, f = eval_genome_worker(p)
            fit[i] = f
            done += 1
            if f > best_partial:
                best_partial = f
            if done == 1 or done == n or done % milestone == 0:
                elapsed = max(1e-9, time.perf_counter() - t0)
                rate = done / elapsed
                eta = (n - done) / max(rate, 1e-9)
                _log(
                    f"  eval {done}/{n}  best_partial={best_partial:.4f}  "
                    f"elapsed={elapsed:.1f}s  eta~{eta:.1f}s"
                )
        return fit
    with mp.Pool(processes=workers) as pool:
        done = 0
        best_partial = -1.0
        for i, f in pool.imap_unordered(eval_genome_worker, payloads, chunksize=1):
            fit[i] = f
            done += 1
            if f > best_partial:
                best_partial = f
            if done == 1 or done == n or done % milestone == 0:
                elapsed = max(1e-9, time.perf_counter() - t0)
                rate = done / elapsed
                eta = (n - done) / max(rate, 1e-9)
                _log(
                    f"  eval {done}/{n}  best_partial={best_partial:.4f}  "
                    f"elapsed={elapsed:.1f}s  eta~{eta:.1f}s"
                )
    return fit


def _elite_count(n: int, elite_percent: float) -> int:
    k = int(math.ceil(float(n) * elite_percent / 100.0))
    return max(1, min(n, k))


def _breed_next_population(
    rng: random.Random,
    elites: list[dict[str, float]],
    specs: list[DirectionalRange],
    target_size: int,
) -> list[dict[str, float]]:
    key_to_spec = {s.key: s for s in specs}
    next_pop: list[dict[str, float]] = [dict(e) for e in elites]
    seen: set[tuple[tuple[str, float], ...]] = {_genome_to_signature(g) for g in next_pop}
    keys = [s.key for s in specs]
    while len(next_pop) < target_size:
        a = elites[rng.randrange(len(elites))]
        b = elites[rng.randrange(len(elites))]
        child = dict(a)
        for k in keys:
            if rng.random() < 0.5:
                child[k] = b.get(k, child.get(k, 0.0))
        mk = keys[rng.randrange(len(keys))]
        deltas = key_to_spec[mk].deltas()
        non_zero = [d for d in deltas if abs(d) > 1e-9]
        if non_zero:
            child[mk] = child.get(mk, 0.0) + rng.choice(non_zero)
        child = clamp_genome(child)
        sig = _genome_to_signature(child)
        if sig in seen:
            continue
        seen.add(sig)
        next_pop.append(child)
    return next_pop


def run_training(
    *,
    slug: str,
    generations: int,
    games: int,
    seed: int,
    workers: int,
    out_path: Path,
    start_from_trained: bool,
    extend: float,
    combo_keys: list[str],
    max_population: int,
    elite_percent: float,
    opponent: str | None,
) -> dict[str, float]:
    rng = random.Random(seed)
    baseline = _baseline_for_slug(slug, out_path, start_from_trained)
    specs = _directional_specs(extend)
    pop = _enumerate_initial_population(
        baseline=baseline,
        specs=specs,
        combo_keys=combo_keys,
        max_population=max_population,
        seed=seed,
    )
    if not pop:
        raise ValueError("empty population")

    best = dict(pop[0])
    best_fit = -1.0
    for gen in range(generations):
        t0 = time.perf_counter()
        fit = _evaluate_population(slug, pop, games, seed + gen * 101, workers, opponent)
        ranked = sorted(range(len(pop)), key=lambda i: fit[i], reverse=True)
        if fit[ranked[0]] > best_fit:
            best_fit = fit[ranked[0]]
            best = dict(pop[ranked[0]])
        k = _elite_count(len(pop), elite_percent)
        elites = [pop[i] for i in ranked[:k]]
        mean_fit = sum(fit) / len(fit)
        _log(
            f"gen {gen + 1}/{generations}  pop={len(pop)}  games/genome={games}  "
            f"elite={k}  best={fit[ranked[0]]:.4f}  mean={mean_fit:.4f}  "
            f"best_ever={best_fit:.4f}  elapsed={time.perf_counter() - t0:.2f}s"
        )
        if gen < generations - 1:
            pop = _breed_next_population(rng, elites, specs, len(pop))
    return best


def main() -> None:
    ap = argparse.ArgumentParser(description="Directional-grid incantation weight trainer")
    ap.add_argument("--deck", required=True, help="P0 deck slug (included_decks)")
    ap.add_argument("--generations", type=int, default=8)
    ap.add_argument("--games", type=int, default=100, help="games per genome (default 100)")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--workers", type=int, default=0, help="parallel workers")
    ap.add_argument("--out", type=str, default="", help="output weights JSON path")
    ap.add_argument(
        "--start-from-trained",
        action="store_true",
        help="initialize baseline from existing weights_by_slug[deck] in --out/default file",
    )
    ap.add_argument(
        "--range-extend",
        type=float,
        default=1.5,
        help="scales directional mutation range magnitudes (default 1.5x)",
    )
    ap.add_argument(
        "--combo-keys",
        type=str,
        default="INC_BASE_BONUS,DD_W_INC_BASE,W_DISCARD_DRAW,W_CAST_WITH_SAC_BASE",
        help=(
            "comma-separated keys used for full grid enumeration in initial population; "
            "others are evolved during reproduction"
        ),
    )
    ap.add_argument(
        "--max-population",
        type=int,
        default=600,
        help="cap initial enumerated population size (default 600)",
    )
    ap.add_argument(
        "--elite-percent",
        type=float,
        default=10.0,
        help="top percentile selected each generation (default 10)",
    )
    ap.add_argument(
        "--opponent",
        type=str,
        default="",
        metavar="SLUG",
        help="if set, P1 always uses this included deck (default: random P1 each game)",
    )
    args = ap.parse_args()

    slugs = included_deck_slugs()
    if args.deck not in slugs:
        raise SystemExit(f"--deck must be one of {slugs}; got {args.deck!r}")
    if args.opponent and args.opponent not in slugs:
        raise SystemExit(f"--opponent must be one of {slugs}; got {args.opponent!r}")
    if args.games <= 0:
        raise SystemExit("--games must be > 0")
    if args.generations <= 0:
        raise SystemExit("--generations must be > 0")
    if args.max_population <= 0:
        raise SystemExit("--max-population must be > 0")
    if not (0.0 < args.elite_percent <= 100.0):
        raise SystemExit("--elite-percent must be in (0, 100]")

    out_path = Path(args.out) if args.out else default_pilot_weights_path()
    workers = args.workers if args.workers > 0 else (mp.cpu_count() or 1)
    workers = max(1, workers)
    combo_keys = [x.strip() for x in args.combo_keys.split(",") if x.strip()]

    _log("=== Directional Grid Trainer ===")
    _log(f"deck={args.deck!r}  generations={args.generations}  games/genome={args.games}")
    _log(f"workers={workers}  seed={args.seed}  elite_percent={args.elite_percent}")
    _log(f"range_extend={args.range_extend}  start_from_trained={bool(args.start_from_trained)}")
    _log(f"combo_keys={combo_keys}  max_population={args.max_population}")
    _log(f"opponent={(args.opponent if args.opponent else 'random')!r}")
    _log(f"output={out_path.resolve()}")
    _log("")

    best = run_training(
        slug=args.deck,
        generations=args.generations,
        games=args.games,
        seed=args.seed,
        workers=workers,
        out_path=out_path,
        start_from_trained=bool(args.start_from_trained),
        extend=float(args.range_extend),
        combo_keys=combo_keys,
        max_population=int(args.max_population),
        elite_percent=float(args.elite_percent),
        opponent=args.opponent or None,
    )
    merge_slug_into_weights_file(out_path, args.deck, best, genome_version=1)
    _log("")
    _log(f"Done. Best genome written under weights_by_slug[{args.deck!r}] in {out_path.resolve()}")


if __name__ == "__main__":
    main()
