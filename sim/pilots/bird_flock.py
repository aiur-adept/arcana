"""Pilot for the Bird-Test tribal deck.

Eyrie ETB is a free bird and should be cast the moment the 4-lane
opens up. Sinofia (Ring of Feathers) prefers a high-power non-nesting
host — a Raven — so the cost reduction applies to future bird plays.
Ravens never nest: they're better as wild bird-combat threats that
nesting would take off-field. Small birds (Sparrow/Gull) are better
as nested ritual-power boosters."""

from __future__ import annotations

from typing import Optional

from ..ai import GreedyAI
from ..cards import Kind
from ..match import MatchState


class BirdFlockPilot(GreedyAI):
    W_TEMPLE_EYRIE_BONUS = 50.0
    W_BIRD_POWER_BONUS = 2.0

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
        has_bird = any(c.kind is Kind.BIRD for c in hand)
        if not has_bird and len(rituals) >= 3:
            return True
        return False

    def should_nest(self, state: MatchState, bird, temple) -> bool:
        if bird.bird_id in ("raven", "hawk", "eagle"):
            return False
        return True

    def _pick_ring_host(self, state, pid: int, card, hosts):
        p = state.players[pid]
        if card.ring_id == "sinofia_feathers":
            raven_mids = [b.mid for b in p.bird_field if b.bird_id == "raven" and b.nest_mid < 0]
            for hk, hm in hosts:
                if hk == "bird" and hm in raven_mids:
                    return (hk, hm)
            high_power = sorted(
                [(b.power, b.mid) for b in p.bird_field if b.nest_mid < 0],
                reverse=True,
            )
            for _, mid in high_power:
                for hk, hm in hosts:
                    if hk == "bird" and hm == mid:
                        return (hk, hm)
        return super()._pick_ring_host(state, pid, card, hosts)
