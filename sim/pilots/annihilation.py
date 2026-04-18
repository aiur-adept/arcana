"""Pilot for the Annihilation prison deck.

Zytzr is an as-soon-as-possible drop: it adds +1 ritual destroyed per
Wrath and +1 discard per Woe across the deck's entire disruption
payload. Celadon (ring) cheapens Woe 4 to lane-3 castable, smoothing
mid-game pacing. Wndrr's discard -> Woe 3 activation fires every turn.
Tmrsk's post-Wrath free Woe 3 is always accepted vs a non-empty hand."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind, VERB_BURN, VERB_INSIGHT, VERB_SEEK, VERB_WOE, VERB_WRATH
from ..match import MatchState


class AnnihilationPilot(GreedyAI):
    W_NOBLE_BIG_TRIPLET = 55.0
    W_EFFECT_WOE_PER_DISCARD = 4.5
    W_EFFECT_WRATH_PER_KILLED = 3.2

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
        if 3 not in vals and 4 not in vals and len(hand) <= 5:
            return True
        return False

    def adjust_ring_score(self, state: MatchState, pid: int, card, score: float) -> float:
        if card.ring_id == "celadon_annihilation":
            return score + 20.0
        return score

    def wrath_score_adjust(self, state: MatchState, pid: int, base: float) -> float:
        if state.has_noble(pid, "zytzr_annihilation"):
            return base + 10.0
        return base

    def scion_response(self, state: MatchState) -> None:
        p = state.pending
        scion = p.payload["scion"]
        if scion == "tmrsk":
            opp = state.opponent(self.pid)
            if state.players[opp].hand:
                state.submit_scion_trigger(self.pid, True, {"woe_target": opp})
            else:
                state.submit_scion_trigger(self.pid, False, {})
        else:
            super().scion_response(state)
