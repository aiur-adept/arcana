"""Pilot for the Topheavy Annihilator deck.

Wrath costs one ritual sacrifice (mana value 0). Other incantations still
prefer on-lane payment so the 1/2/3 ladder keeps lane 4 live. The deck's
edge is Zytzr before Wrath (two kills per cast); we bias Zytzr via
``W_NOBLE_BIG_TRIPLET``. For Wrath payment we sack the largest ritual that
still leaves at least one active lane when possible, else the smallest (same
as base) so the play is always legal."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind, VERB_WRATH
from ..match import MatchState


class TopheavyAnnihilatorPilot(GreedyAI):
    W_NOBLE_BIG_TRIPLET = 40.0

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
        has_big_play = any(
            (c.kind is Kind.INCANTATION and c.verb == VERB_WRATH) or
            (c.kind is Kind.RITUAL and c.value == 4)
            for c in hand
        )
        if not has_big_play and len(rituals) >= 3:
            return True
        return False

    def _pick_wrath_sacrifice(self, state: MatchState, pid: int) -> Optional[list[int]]:
        p = state.players[pid]
        if not p.field:
            return None
        for r in sorted(p.field, key=lambda rr: (-rr.value, rr.mid)):
            if len(self._lanes_after_sac(state, pid, [r.mid])) >= 1:
                return [r.mid]
        r0 = min(p.field, key=lambda rr: (rr.value, rr.mid))
        return [r0.mid]

    def _score_incantation(self, state: MatchState, pid: int, card) -> Optional[tuple[float, list[int]]]:
        if card.verb == VERB_WRATH:
            sac = self._pick_wrath_sacrifice(state, pid)
            if sac is None:
                return None
            eff = self._score_effect(state, pid, card.verb, card.value)
            if eff is None:
                return None
            score, _ctx = eff
            score += self.INC_BASE_BONUS - self._sac_penalty(state, pid, sac)
            score = self.adjust_incantation_score(state, pid, card, sac, score)
            if score is None:
                return None
            opp_pid = state.opponent(pid)
            gap = max(0, state.match_power(opp_pid) - state.match_power(pid))
            score += self.W_SF_INC_BEHIND * gap * card.value * 0.1
            return score, sac
        active = state.active_lanes(pid)
        eff_val = state.effective_incantation_cost(pid, card.verb, card.value)
        if eff_val > 0 and eff_val not in active:
            return None
        eff = self._score_effect(state, pid, card.verb, card.value)
        if eff is None:
            return None
        score, _ctx = eff
        score += self.INC_BASE_BONUS
        score = self.adjust_incantation_score(state, pid, card, [], score)
        if score is None:
            return None
        opp_pid = state.opponent(pid)
        gap = max(0, state.match_power(opp_pid) - state.match_power(pid))
        score += self.W_SF_INC_BEHIND * gap * card.value * 0.1
        return score, []
