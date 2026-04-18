"""Pilot for the Void Temples reactive deck.

NOTE: The simulator does NOT model ``VERB_VOID`` (see ``sim/README.md``).
Void cards sit dead in hand and never cast, so this archetype is
structurally weaker in the sim than it is in the real game. The pilot
focuses on what *is* modeled: stacking temples, casting cheap birds,
and correctly sequencing temple plays the way ``TemplesPilot`` does.

The ``_card_discard_score`` default already rates Void the cheapest
incantation (value 0), so hand-cap cleanup naturally dumps them first."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind
from ..match import MatchState
from .temples import TEMPLE_PLAY_PRIORITY


class VoidTemplesPilot(GreedyAI):
    W_TEMPLE_COST_BONUS = 0.0
    W_TEMPLE_EYRIE_BONUS = 35.0

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
        if len(rituals) >= 4 and 4 not in vals and 3 not in vals:
            return True
        return False

    def score_temple_play(self, state, card, sac, lanes_after_sac) -> Optional[float]:
        score = super().score_temple_play(state, card, sac, lanes_after_sac)
        if score is None:
            return None
        return score + TEMPLE_PLAY_PRIORITY.get(card.temple_id, 0.0)

    def ytria_min_hand(self, state: MatchState) -> int:
        return 5
