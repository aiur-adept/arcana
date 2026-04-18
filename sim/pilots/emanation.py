"""Pilot for the Emanation velocity deck.

Draw/filter engine deck. Drop Sybiline as soon as a host is on the
field so Seek 2 / Insight 2 become free on-lane. Rmrsk scion triggers
are always accepted for the free card. The single Dethrone is reserved
for a high-value opposing noble (cost >= 6)."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind, VERB_INSIGHT, VERB_SEEK
from ..match import MatchState


class EmanationPilot(GreedyAI):
    W_EFFECT_SEEK_VALUE = 4.0
    W_EFFECT_INSIGHT_VALUE = 2.0

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

    def adjust_ring_score(self, state: MatchState, pid: int, card, score: float) -> float:
        if card.ring_id == "sybiline_emanation":
            return score + 25.0
        return score

    def score_dethrone(self, state, card, sac, target) -> Optional[float]:
        if target is None or target.cost < 6:
            return None
        return super().score_dethrone(state, card, sac, target)

    def scion_response(self, state: MatchState) -> None:
        p = state.pending
        if p.payload["scion"] == "rmrsk":
            state.submit_scion_trigger(self.pid, True, {})
        else:
            super().scion_response(state)
