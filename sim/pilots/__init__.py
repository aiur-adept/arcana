"""Per-deck pilot registry for the Arcana simulator.

Each pilot subclasses ``sim.ai.GreedyAI`` and tweaks weights / decision hooks
to steer the AI toward its archetype's meta-accurate game plan. Slug keys
match ``included_decks/index.json``."""

from __future__ import annotations

from ..ai import GreedyAI
from .incantations import IncantationsPilot
from .noble_test import NobleTestPilot
from .ritual_reanimator import RitualReanimatorPilot
from .topheavy_annihilator import TopheavyAnnihilatorPilot
from .occultation import OccultationPilot
from .annihilation import AnnihilationPilot
from .emanation import EmanationPilot
from .temples import TemplesPilot
from .bird_test import BirdTestPilot
from .void_temples import VoidTemplesPilot
from .revive import RevivePilot


PILOTS: dict[str, type[GreedyAI]] = {
    "incantations":          IncantationsPilot,
    "noble_test":            NobleTestPilot,
    "ritual_reanimator":     RitualReanimatorPilot,
    "topheavy_annihilator":  TopheavyAnnihilatorPilot,
    "occultation":           OccultationPilot,
    "annihilation":          AnnihilationPilot,
    "emanation":             EmanationPilot,
    "temples":               TemplesPilot,
    "bird_test":             BirdTestPilot,
    "void_temples":          VoidTemplesPilot,
    "revive":                RevivePilot,
}


def get_pilot(slug: str) -> type[GreedyAI]:
    return PILOTS.get(slug, GreedyAI)
