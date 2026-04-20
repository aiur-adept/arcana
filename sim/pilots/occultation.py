"""Pilot for the Occultation mill deck.

Yytzr's +3 mill-per-Burn is the centerpiece, so drop it as early as
possible. Cymbil reduces Burn/Revive by 1 so every Burn 1 becomes free
to cast. Burn always targets the opponent (this is a mill deck).
Aeoiu recovers rituals from the crypt after self-mill."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind
from ..match import MatchState


class OccultationPilot(GreedyAI):
    W_NOBLE_BIG_TRIPLET = 55.0   # yytzr ~doubles deck output
    W_EFFECT_BURN_BASE = 4.0
    W_EFFECT_BURN_VALUE = 2.0
    W_REVIVE_PRIO_BURN: float = 8.0
    W_REVIVE_PRIO_WOE: float = 4.0
    W_REVIVE_PRIO_SEEK: float = 3.0
    W_REVIVE_PRIO_INSIGHT: float = 2.0
    W_REVIVE_PRIO_WRATH: float = 0.0

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
        me = state.players[pid]
        crypt_rituals = sum(1 for c in me.crypt if c.kind is Kind.RITUAL)
        has_aeoiu = state.has_noble(pid, "aeoiu_rituals")
        deck_len = len(me.deck)
        if has_aeoiu and crypt_rituals < 3 and deck_len > 2 * val + 3:
            return pid
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
