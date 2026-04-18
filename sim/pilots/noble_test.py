"""Pilot for the Noble-Test toolbox deck.

Front-load Serraf for blanket cost reduction, then stack Power-nobles
(Krss/Trss/Yrss) for their lane grants before chaining the Incantation
nobles. Dethrone is aggressively fired at the opponent's biggest noble
since removed nobles cannot be revived."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind, NOBLE_DEFS
from ..match import MatchState

POWER_NOBLES = {"krss_power", "trss_power", "yrss_power"}
INCANT_NOBLES = {"sndrr_incantation", "indrr_incantation", "bndrr_incantation",
                 "wndrr_incantation", "rndrr_incantation"}


class NobleTestPilot(GreedyAI):
    W_NOBLE_BASE = 75.0
    W_NOBLE_GRANT_NEW_LANE = 55.0
    W_DETHRONE_PER_COST = 5.0

    def mulligan(self, state: MatchState, pid: int) -> bool:
        hand = state.players[pid].hand
        if not hand:
            return False
        rituals = [c for c in hand if c.kind is Kind.RITUAL]
        if len(rituals) == 0 or len(rituals) == len(hand):
            return True
        has_serraf = any(c.kind is Kind.RING and c.ring_id == "serraf_nobles" for c in hand)
        cheap_noble = any(c.kind is Kind.NOBLE and c.cost <= 3 for c in hand)
        has_one = any(c.kind is Kind.RITUAL and c.value == 1 for c in hand)
        if has_serraf and cheap_noble:
            return False
        if not has_one and len(rituals) >= 3:
            return True
        return False

    def score_noble_play(self, state, card, eff_cost, sac) -> Optional[float]:
        score = super().score_noble_play(state, card, eff_cost, sac)
        if score is None:
            return None
        if card.noble_id in POWER_NOBLES:
            score += 25.0
        return score

    def adjust_ring_score(self, state: MatchState, pid: int, card, score: float) -> float:
        if card.ring_id == "serraf_nobles":
            return score + 25.0
        return score
