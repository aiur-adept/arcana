"""Pilot for the Scion toolbox deck.

Three cost-2 scions (Rmrsk/Smrsk/Tmrsk) all want to hit the field
early; Serraf drops them to effective cost 1 for a fast stack. The
deck runs no Revive, so Smrsk's sacrifice-Burn-self trigger is
essentially never correct — always decline it."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind
from ..match import MatchState

SCION_IDS = {"rmrsk_emanation", "smrsk_occultation", "tmrsk_annihilation"}


class ScionsPilot(GreedyAI):
    W_NOBLE_BASE = 70.0

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

    def score_noble_play(self, state, card, eff_cost, sac) -> Optional[float]:
        score = super().score_noble_play(state, card, eff_cost, sac)
        if score is None:
            return None
        if card.noble_id in SCION_IDS:
            score += 15.0
        return score

    def adjust_ring_score(self, state: MatchState, pid: int, card, score: float) -> float:
        if card.ring_id == "serraf_nobles":
            return score + 22.0
        return score

    def scion_response(self, state: MatchState) -> None:
        p = state.pending
        scion = p.payload["scion"]
        if scion == "rmrsk":
            state.submit_scion_trigger(self.pid, True, {})
        elif scion == "smrsk":
            state.submit_scion_trigger(self.pid, False, {})
        elif scion == "tmrsk":
            opp = state.opponent(self.pid)
            if state.players[opp].hand:
                state.submit_scion_trigger(self.pid, True, {"woe_target": opp})
            else:
                state.submit_scion_trigger(self.pid, False, {})
