"""Picklable genome evaluation for EA (must live in a real module for Windows mp)."""

from __future__ import annotations

import random
from typing import Any

from .decks import included_deck_slugs, load_all_included_decks
from .pilot_weights import make_weighted_pilot
from .pilots import get_pilot
from .run import _play_one_game


def fitness_from_counts(p0_wins: int, draws: int, games: int) -> float:
    if games <= 0:
        return 0.0
    return (p0_wins + 0.5 * draws) / games


def evaluate_genome(
    slug: str,
    weights: dict[str, float],
    n_games: int,
    seed: int,
) -> dict[str, Any]:
    decks = load_all_included_decks()
    slugs = included_deck_slugs()
    if slug not in decks:
        raise ValueError(f"unknown deck slug {slug!r}")
    p0_deck = decks[slug]
    base_cls = get_pilot(slug)
    p0_cls = make_weighted_pilot(base_cls, weights)
    rng = random.Random(seed)
    p0_wins = p1_wins = draws = 0
    pilot_cache: dict[str, type] = {}
    for _ in range(n_games):
        p1_slug = slugs[rng.randrange(len(slugs))]
        p1_deck = decks[p1_slug]
        p1_cls = pilot_cache.get(p1_slug)
        if p1_cls is None:
            p1_cls = get_pilot(p1_slug)
            pilot_cache[p1_slug] = p1_cls
        game_rng = random.Random(rng.getrandbits(64))
        res = _play_one_game(p0_deck, p1_deck, game_rng, p0_cls, p1_cls)
        w = res["winner"]
        if w == 0:
            p0_wins += 1
        elif w == 1:
            p1_wins += 1
        else:
            draws += 1
    return {
        "p0_wins": p0_wins,
        "p1_wins": p1_wins,
        "draws": draws,
        "games": n_games,
        "fitness": fitness_from_counts(p0_wins, draws, n_games),
    }


def eval_genome_worker(args: tuple[Any, ...]) -> tuple[int, float]:
    idx, slug, weights_tuple, n_games, seed = args
    weights = dict(weights_tuple)
    stats = evaluate_genome(slug, weights, n_games, seed)
    return idx, float(stats["fitness"])
