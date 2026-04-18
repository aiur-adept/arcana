"""Pilot for the Topheavy Annihilator deck.

Eight 4-rituals means Wrath/Burn/Insight/Dethrone cast on-lane for
free. The key edge this deck earns is dropping Zytzr before a Wrath so
each Wrath destroys two rituals. We bias Zytzr aggressively via
``W_NOBLE_BIG_TRIPLET`` and prefer sacrificing the *largest* available
ritual (a spare 4R, of which the deck runs eight) when a sac is
required — this protects the 1/2/3 ladder that keeps lane 4 active."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI, _ritual_combinations_for_value
from ..cards import Kind, VERB_WRATH
from ..match import MatchState


def _sac_prefer_high(p_field, target: int) -> Optional[list[int]]:
    rituals = sorted(p_field, key=lambda r: -r.value)
    chosen: list[int] = []
    total = 0
    for r in rituals:
        if total >= target:
            break
        chosen.append(r.mid)
        total += r.value
    if total < target:
        return None
    return chosen


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

    def _score_incantation(self, state: MatchState, pid: int, card) -> Optional[tuple[float, list[int]]]:
        p = state.players[pid]
        active = state.active_lanes(pid)
        eff_val = state.effective_incantation_cost(pid, card.verb, card.value)
        if eff_val > 0 and eff_val not in active:
            # Topheavy refuses to sac for incantations: the whole deck relies
            # on lane 4 staying active. Wait for on-lane casting instead.
            if card.verb == VERB_WRATH and state.has_noble(pid, "zytzr_annihilation"):
                # the one exception: Zytzr-boosted Wrath destroying 2 is
                # often worth a single high-value sac
                s = _sac_prefer_high(p.field, eff_val)
                if s is None:
                    return None
                after = self._lanes_after_sac(state, pid, s)
                if len(after) < 1:
                    return None
                eff = self._score_effect(state, pid, card.verb, card.value)
                if eff is None:
                    return None
                score, _ctx = eff
                score += self.INC_BASE_BONUS - self._sac_penalty(s)
                return score, s
            return None
        eff = self._score_effect(state, pid, card.verb, card.value)
        if eff is None:
            return None
        score, _ctx = eff
        score += self.INC_BASE_BONUS
        return score, []
