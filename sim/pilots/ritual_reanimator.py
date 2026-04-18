"""Pilot for the Ritual Reanimator (Aeoiu + Burn + Phaedra) deck.

Aeoiu is the engine: mill yourself with Burns, replay the biggest ritual
from crypt each turn. Phaedra sculpts draws. Burn targets self when the
crypt is light on rituals so Aeoiu has fuel."""

from __future__ import annotations

from ..ai import GreedyAI
from ..cards import Kind, VERB_BURN
from ..match import MatchState


class RitualReanimatorPilot(GreedyAI):
    W_AEOIU_ACTIVATION_BASE = 70.0
    W_TEMPLE_BASE = 65.0
    W_NOBLE_BIG_TRIPLET = 25.0  # aeoiu not in the triplet set; leave alone

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
        has_action = any(c.kind is Kind.INCANTATION for c in hand)
        if not has_action and len(rituals) >= 3:
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

    def score_noble_play(self, state, card, eff_cost, sac):
        score = super().score_noble_play(state, card, eff_cost, sac)
        if score is None:
            return None
        if card.noble_id == "aeoiu_rituals":
            score += 50.0
        return score

    def score_temple_play(self, state, card, sac, lanes_after_sac):
        score = super().score_temple_play(state, card, sac, lanes_after_sac)
        if score is None:
            return None
        if card.temple_id == "phaedra_illusion":
            p = state.players[self.pid]
            if len(p.hand) >= 4:
                score += 15.0
        return score
