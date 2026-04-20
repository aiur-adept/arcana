"""Pilot for the Temples (big-ritual toolbox) deck.

All four temples are here as singletons. Correct sequencing is:

1. **Phaedra** first for draw smoothing,
2. **Delpha** next to guarantee ritual recovery after temple sacrifices,
3. **Gotha** for card advantage,
4. **Ytria** last (needs a full hand to convert into fresh cards).

We override the per-temple play-score to enforce the order: the base
class's ``55 + cost`` makes Ytria (cost 9) play first, which is wrong."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind
from ..match import MatchState


TEMPLE_PLAY_PRIORITY = {
    "phaedra_illusion": 30.0,
    "delpha_oracles":   25.0,
    "gotha_illness":    15.0,
    "eyrie_feathers":   20.0,
    "ytria_cycles":     0.0,
}


class TemplesPilot(GreedyAI):
    W_TEMPLE_BASE = 55.0
    W_TEMPLE_COST_BONUS = 0.0  # ignore the raw cost term; use explicit priority

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
        if 2 not in vals and len(rituals) >= 3:
            return True
        return False

    def score_temple_play(self, state, card, sac, lanes_after_sac) -> Optional[float]:
        score = super().score_temple_play(state, card, sac, lanes_after_sac)
        if score is None:
            return None
        return score + TEMPLE_PLAY_PRIORITY.get(card.temple_id, 0.0)

    def ytria_min_hand(self, state: MatchState) -> int:
        return 5
