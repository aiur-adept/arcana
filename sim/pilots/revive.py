"""Pilot for the pure Revive-engine deck.

Every non-ritual is cost 1 or 2, so a 1R + 2R opener runs the entire
deck. Rndrr's free-Revive-1 activation every turn is the whole engine;
the base class already activates nobles whose effects score positively.
Revive targeting prefers the highest-value Seek/Insight (these decks
want to draw through the deck to stack rituals, not recur removal)."""

from __future__ import annotations

from ..ai import GreedyAI
from ..cards import Kind, VERB_INSIGHT, VERB_SEEK
from ..match import MatchState


class RevivePilot(GreedyAI):
    REVIVE_VERB_PRIORITY = {
        VERB_SEEK: 10,
        VERB_INSIGHT: 6,
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
        if 2 not in vals and len(rituals) >= 3:
            return True
        return False

    def score_noble_play(self, state, card, eff_cost, sac):
        score = super().score_noble_play(state, card, eff_cost, sac)
        if score is None:
            return None
        if card.noble_id == "rndrr_incantation":
            score += 30.0
        return score
