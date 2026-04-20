"""Pilot for the Occultation ramp/mill deck.

Yytzr fuels mill; Cymbil discounts Burn/Revive/Renew. Prefer **Renew** from
hand before **Revive** so Renew hits crypt first; Revive still fires for
crypt Renew once Renew is out of hand, and is biased for crypt **Burn** chains.
Revived **Burn** uses the same self/opponent heuristic as hand Burns."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind, VERB_BURN, VERB_DETHRONE, VERB_REVIVE, VERB_RENEW, VERB_TEARS
from ..match import MatchState


class OccultationPilot(GreedyAI):
    W_NOBLE_BIG_TRIPLET = 55.0
    W_EFFECT_BURN_BASE = 4.0
    W_EFFECT_BURN_VALUE = 2.0
    W_REVIVE_PRIO_RENEW = 30.0
    W_REVIVE_PRIO_BURN = 18.0
    W_REVIVE_PRIO_WOE = 4.0
    W_REVIVE_PRIO_SEEK = 3.0
    W_REVIVE_PRIO_INSIGHT = 2.0
    W_REVIVE_PRIO_WRATH = 0.0
    W_REVIVE_PLAY_BIAS_BURN = 16.0
    W_REVIVE_PLAY_BIAS_CRYPT_RENEW_NO_HAND_RENEW = 18.0
    W_REVIVE_PLAY_ELIG_MISC = 4.0

    def _hand_has_renew(self, state: MatchState, pid: int) -> bool:
        return any(
            c.kind is Kind.INCANTATION and c.verb == VERB_RENEW for c in state.players[pid].hand
        )

    def _revive_play_crypt_bias(self, state: MatchState, pid: int) -> float:
        me = state.players[pid]
        elig_idx = [
            i
            for i, c in enumerate(me.crypt)
            if c.kind is Kind.INCANTATION and c.verb not in (VERB_REVIVE, VERB_TEARS, VERB_DETHRONE)
        ]
        if not elig_idx:
            return 0.0
        pick = self.choose_revive_target(state, pid, elig_idx)
        if pick is None:
            return 0.0
        v = me.crypt[pick].verb
        if v == VERB_RENEW:
            if self._hand_has_renew(state, pid):
                return 0.0
            return self.W_REVIVE_PLAY_BIAS_CRYPT_RENEW_NO_HAND_RENEW
        if v == VERB_BURN:
            return self.W_REVIVE_PLAY_BIAS_BURN
        return self.W_REVIVE_PLAY_ELIG_MISC

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

    def choose_burn_target(self, state: MatchState, pid: int, val: int) -> int:
        me = state.players[pid]
        opp = state.opponent(pid)
        crypt_rituals = sum(1 for c in me.crypt if c.kind is Kind.RITUAL)
        deck_rituals = sum(1 for c in me.deck if c.kind is Kind.RITUAL)
        deck_len = len(me.deck)
        has_aeoiu = state.has_noble(pid, "aeoiu_rituals")
        yyt = state.has_noble(pid, "yytzr_occultation")
        behind = state.match_power(opp) > state.match_power(pid)

        if deck_len <= 2 * val + 1:
            return opp
        if crypt_rituals < 3 and deck_rituals >= 2:
            return pid
        if yyt and crypt_rituals < 5 and deck_rituals >= 1:
            return pid
        if has_aeoiu and crypt_rituals < 3 and deck_len > 2 * val + 3:
            return pid
        if behind and crypt_rituals < 3 and deck_rituals >= 1:
            return pid
        return opp

    def amend_revive_ctx(self, state: MatchState, pid: int, crypt_idx: int, ctx: dict) -> dict:
        me = state.players[pid]
        if crypt_idx < 0 or crypt_idx >= len(me.crypt):
            return ctx
        card = me.crypt[crypt_idx]
        if card.kind is Kind.INCANTATION and card.verb == VERB_BURN:
            if self.choose_burn_target(state, pid, card.value) == pid:
                sub = dict(ctx.get("revive_sub_ctx", {}))
                sub["burn_target"] = pid
                ctx["revive_sub_ctx"] = sub
        return ctx

    def adjust_incantation_score(self, state: MatchState, pid: int, card, sac: list[int], score: float) -> Optional[float]:
        out = super().adjust_incantation_score(state, pid, card, sac, score)
        if out is None:
            return None
        if card.verb == VERB_REVIVE:
            out += 6.0 + self._revive_play_crypt_bias(state, pid)
        elif card.verb == VERB_RENEW:
            out += 14.0
        return out

    def adjust_ring_score(self, state: MatchState, pid: int, card, score: float) -> float:
        if card.ring_id == "cymbil_occultation":
            return score + 15.0
        return score

    def score_noble_play(self, state, card, eff_cost, sac) -> Optional[float]:
        score = super().score_noble_play(state, card, eff_cost, sac)
        if score is None:
            return None
        if card.noble_id == "aeoiu_rituals":
            score += 30.0
        return score
