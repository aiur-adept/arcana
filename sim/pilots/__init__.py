"""Per-deck pilot registry for the Arcana simulator.

Each pilot subclasses ``sim.ai.GreedyAI`` and tweaks weights / decision hooks
to steer the AI toward its archetype's meta-accurate game plan. Slug keys
match ``included_decks/index.json``."""

from __future__ import annotations

from ..ai import GreedyAI
from .ritual_reanimator import RitualReanimatorPilot
from .occultation import OccultationPilot
from .annihilation import AnnihilationPilot
from .emanation import EmanationPilot
from .bird_flock import BirdFlockPilot
from .void_temples import VoidTemplesPilot


PILOTS: dict[str, type[GreedyAI]] = {
    "ritual_reanimator":     RitualReanimatorPilot,
    "occultation":           OccultationPilot,
    "annihilation":          AnnihilationPilot,
    "emanation":             EmanationPilot,
    "bird_flock":            BirdFlockPilot,
    "void_temples":          VoidTemplesPilot,
}


def get_pilot(slug: str) -> type[GreedyAI]:
    return PILOTS.get(slug, GreedyAI)
