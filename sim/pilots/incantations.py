"""Pilot for the Incantations starter deck.

A pure spell-slinger that wants its 1R+2R lanes online immediately. The
one-of Wrath is a precious answer that should only be fired when it
actually wipes meaningful opposing ritual power. Revive 2 targeting
emphasizes high-impact verbs (Woe/Burn) over simple card draw."""

from __future__ import annotations

from ..ai import GreedyAI
from ..cards import Kind, VERB_BURN, VERB_INSIGHT, VERB_SEEK, VERB_WOE, VERB_WRATH
from ..match import MatchState


class IncantationsPilot(GreedyAI):
    W_REVIVE_PRIO_WOE: float = 7.0
    W_REVIVE_PRIO_BURN: float = 5.0
    W_REVIVE_PRIO_WRATH: float = 9.0
    W_REVIVE_PRIO_SEEK: float = 3.0
    W_REVIVE_PRIO_INSIGHT: float = 2.0

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
        if 2 not in vals and len(hand) <= 5:
            return True
        return False

    def wrath_score_adjust(self, state: MatchState, pid: int, base: float) -> float:
        opp = state.players[state.opponent(pid)]
        rit_power = sum(r.value for r in opp.field)
        if len(opp.field) < 2 and rit_power < 5:
            return base - 20.0
        return base + 4.0
