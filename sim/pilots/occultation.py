"""Pilot for the Occultation mill deck.

Yytzr's +3 mill-per-Burn is the centerpiece, so drop it as early as
possible. Cymbil reduces Burn/Revive by 1 so every Burn 1 becomes free
to cast. Burn always targets the opponent (this is a mill deck).
Aeoiu recovers rituals from the crypt after self-mill."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind, VERB_BURN, VERB_INSIGHT, VERB_REVIVE, VERB_SEEK, VERB_WOE
from ..match import MatchState


class OccultationPilot(GreedyAI):
    W_NOBLE_BIG_TRIPLET = 55.0   # yytzr ~doubles deck output
    W_EFFECT_BURN_BASE = 4.0
    W_EFFECT_BURN_VALUE = 2.0
    REVIVE_VERB_PRIORITY = {
        VERB_BURN: 8,
        VERB_WOE: 4,
        VERB_SEEK: 3,
        VERB_INSIGHT: 2,
    }

    def mulligan(self, state: MatchState, pid: int) -> bool:
        hand = state.players[pid].hand
        if not hand:
            return False
        rituals = [c for c in hand if c.kind is Kind.RITUAL]
        if len(rituals) == 0 or len(rituals) == len(hand):
            return True
        vals = {c.value for c in rituals}
        if 1 not in vals:
            return True
        return False

    def choose_burn_target(self, state: MatchState, pid: int, val: int) -> int:
        return state.opponent(pid)

    def adjust_ring_score(self, state: MatchState, pid: int, card, score: float) -> float:
        if card.ring_id == "cymbil_occultation":
            return score + 15.0
        return score

    def score_noble_play(self, state, card, eff_cost, sac) -> Optional[float]:
        score = super().score_noble_play(state, card, eff_cost, sac)
        if score is None:
            return None
        if card.noble_id == "aeoiu_rituals":
            score += 30.0
        return score
