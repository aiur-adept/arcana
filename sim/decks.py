"""Load Arcana deck JSONs from included_decks/ into list[Card]."""

from __future__ import annotations

import json
from pathlib import Path

from .cards import (
    Card,
    Kind,
    make_bird,
    make_incantation,
    make_noble,
    make_ring,
    make_ritual,
    make_temple,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
INCLUDED_DECKS_DIR = REPO_ROOT / "included_decks"
INDEX_JSON = INCLUDED_DECKS_DIR / "index.json"


def _card_from_json(entry: dict) -> Card | None:
    t = entry.get("type", "")
    if t == "Ritual":
        return make_ritual(int(entry["value"]))
    if t == "Incantation":
        return make_incantation(str(entry["verb"]), int(entry["value"]))
    if t == "Noble":
        return make_noble(str(entry["noble_id"]))
    if t == "Temple":
        return make_temple(str(entry["temple_id"]))
    if t == "Bird":
        return make_bird(str(entry["bird_id"]))
    if t == "Ring":
        return make_ring(str(entry["ring_id"]))
    return None


def load_deck(slug: str) -> list[Card]:
    path = INCLUDED_DECKS_DIR / f"{slug}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    out: list[Card] = []
    for entry in data.get("cards", []):
        c = _card_from_json(entry)
        if c is not None:
            out.append(c)
    return out


def included_deck_slugs() -> list[str]:
    data = json.loads(INDEX_JSON.read_text(encoding="utf-8"))
    return list(data.get("slugs", []))


def load_all_included_decks() -> dict[str, list[Card]]:
    return {slug: load_deck(slug) for slug in included_deck_slugs()}


if __name__ == "__main__":
    for slug, deck in load_all_included_decks().items():
        kinds: dict[str, int] = {}
        for c in deck:
            kinds[c.kind.name] = kinds.get(c.kind.name, 0) + 1
        print(f"{slug:28s} size={len(deck):2d}  {kinds}")
