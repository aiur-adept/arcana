"""Card schema and Set-1 catalogs for the Arcana Monte Carlo simulator.

Mirrors the card definitions in deck_editor.gd and the effect semantics in
arcana_match_state.gd. Every card is represented as an immutable tuple-like
dataclass; runtime per-instance state (damage, nest link, used_turn) lives
on wrapper dicts inside match.py."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class Kind(Enum):
    RITUAL = "Ritual"
    INCANTATION = "Incantation"
    DETHRONE = "Dethrone"
    NOBLE = "Noble"
    TEMPLE = "Temple"
    BIRD = "Bird"
    RING = "Ring"


VERB_SEEK = "seek"
VERB_INSIGHT = "insight"
VERB_BURN = "burn"
VERB_WOE = "woe"
VERB_WRATH = "wrath"
VERB_REVIVE = "revive"
VERB_DELUGE = "deluge"
VERB_TEARS = "tears"
VERB_VOID = "void"  # reactive counterspell; not modeled in the MC simulator


@dataclass(frozen=True)
class Card:
    kind: Kind
    value: int = 0           # ritual value / incantation value / dethrone 4
    verb: str = ""           # incantation verb
    noble_id: str = ""
    temple_id: str = ""
    bird_id: str = ""
    ring_id: str = ""
    name: str = ""
    cost: int = 0            # temple play cost, bird play cost, noble play cost, ring play cost
    power: int = 0           # bird power

    def label(self) -> str:
        if self.kind is Kind.RITUAL:
            return f"Ritual {self.value}"
        if self.kind is Kind.INCANTATION:
            return f"{self.verb.capitalize()} {self.value}"
        if self.kind is Kind.DETHRONE:
            return "Dethrone 4"
        if self.kind is Kind.NOBLE:
            return self.name or self.noble_id
        if self.kind is Kind.TEMPLE:
            return self.name or self.temple_id
        if self.kind is Kind.BIRD:
            return self.name or self.bird_id
        if self.kind is Kind.RING:
            return self.name or self.ring_id
        return "?"


NOBLE_DEFS: dict[str, dict] = {
    "krss_power":          {"cost": 2, "name": "Krss, Noble of Power",         "grants_lane": 1},
    "trss_power":          {"cost": 3, "name": "Trss, Noble of Power",         "grants_lane": 2},
    "yrss_power":          {"cost": 4, "name": "Yrss, Noble of Power",         "grants_lane": 3},
    "xytzr_emanation":     {"cost": 6, "name": "Xytzr, Noble of Emanation"},
    "yytzr_occultation":   {"cost": 6, "name": "Yytzr, Noble of Occultation"},
    "zytzr_annihilation":  {"cost": 6, "name": "Zytzr, Noble of Annihilation"},
    "aeoiu_rituals":       {"cost": 8, "name": "Aeoiu, Scion of Rituals"},
    "sndrr_incantation":   {"cost": 3, "name": "Sndrr, Noble of Incantation", "activated_verb": VERB_SEEK,    "activated_value": 1, "activation_discard": True},
    "indrr_incantation":   {"cost": 3, "name": "Indrr, Noble of Incantation", "activated_verb": VERB_INSIGHT, "activated_value": 1},
    "bndrr_incantation":   {"cost": 3, "name": "Bndrr, Noble of Incantation", "activated_verb": VERB_BURN,    "activated_value": 2},
    "wndrr_incantation":   {"cost": 3, "name": "Wndrr, Noble of Incantation", "activated_verb": VERB_WOE,     "activated_value": 3, "activation_discard": True},
    "rndrr_incantation":   {"cost": 3, "name": "Rndrr, Noble of Incantation", "activated_verb": VERB_REVIVE,  "activated_value": 1},
    "rmrsk_emanation":     {"cost": 2, "name": "Rmrsk, Scion of Emanation"},
    "smrsk_occultation":   {"cost": 2, "name": "Smrsk, Scion of Occultation"},
    "tmrsk_annihilation":  {"cost": 2, "name": "Tmrsk, Scion of Annihilation"},
}


TEMPLE_DEFS: dict[str, dict] = {
    "eyrie_feathers":   {"cost": 6, "name": "Eyrie, Temple of Feathers"},
    "phaedra_illusion": {"cost": 7, "name": "Phaedra, Temple of Illusion"},
    "delpha_oracles":   {"cost": 7, "name": "Delpha, Temple of Oracles"},
    "gotha_illness":    {"cost": 7, "name": "Gotha, Temple of Illness"},
    "ytria_cycles":     {"cost": 9, "name": "Ytria, Temple of Cycles"},
}


RING_COST = 2

# Reductions keyed by incantation verb, or by the pseudo-keys "noble" / "bird".
RING_DEFS: dict[str, dict] = {
    "sybiline_emanation":   {"name": "Sybiline, Ring of Emanation",    "reductions": {VERB_SEEK: 1, VERB_INSIGHT: 1}},
    "cymbil_occultation":   {"name": "Cymbil, Ring of Occultation",    "reductions": {VERB_BURN: 1, VERB_REVIVE: 1}},
    "celadon_annihilation": {"name": "Celadon, Ring of Annihilation",  "reductions": {VERB_WOE: 1, VERB_WRATH: 1}},
    "serraf_nobles":        {"name": "Serraf, Ring of Nobles",         "reductions": {"noble": 1}},
    "sinofia_feathers":     {"name": "Sinofia, Ring of Feathers",      "reductions": {"bird": 1, VERB_TEARS: 1}},
}


BIRD_DEFS: dict[str, dict] = {
    "wren":    {"cost": 2, "power": 1, "name": "Wren"},
    "sparrow": {"cost": 2, "power": 1, "name": "Sparrow"},
    "finch":   {"cost": 2, "power": 1, "name": "Finch"},
    "kestrel": {"cost": 3, "power": 2, "name": "Kestrel"},
    "shrike":  {"cost": 3, "power": 2, "name": "Shrike"},
    "gull":    {"cost": 3, "power": 2, "name": "Gull"},
    "hawk":    {"cost": 4, "power": 3, "name": "Hawk"},
    "eagle":   {"cost": 4, "power": 3, "name": "Eagle"},
    "raven":   {"cost": 4, "power": 3, "name": "Raven"},
}


def make_ritual(value: int) -> Card:
    return Card(kind=Kind.RITUAL, value=value)


def make_incantation(verb: str, value: int) -> Card:
    return Card(kind=Kind.INCANTATION, verb=verb, value=value)


def make_dethrone() -> Card:
    return Card(kind=Kind.DETHRONE, value=4)


def make_noble(noble_id: str) -> Card:
    d = NOBLE_DEFS[noble_id]
    return Card(kind=Kind.NOBLE, noble_id=noble_id, name=d["name"], cost=d["cost"])


def make_temple(temple_id: str) -> Card:
    d = TEMPLE_DEFS[temple_id]
    return Card(kind=Kind.TEMPLE, temple_id=temple_id, name=d["name"], cost=d["cost"])


def make_bird(bird_id: str) -> Card:
    d = BIRD_DEFS[bird_id]
    return Card(kind=Kind.BIRD, bird_id=bird_id, name=d["name"], cost=d["cost"], power=d["power"])


def make_ring(ring_id: str) -> Card:
    d = RING_DEFS[ring_id]
    return Card(kind=Kind.RING, ring_id=ring_id, name=d["name"], cost=RING_COST)
