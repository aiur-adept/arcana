"""Greedy AI capable of piloting any Arcana deck.

Now organized as a hookable base class: scoring weights are class attributes,
and per-deck decisions live in override hooks used by ``sim.pilots``. The
default behavior of ``GreedyAI`` is preserved for any deck without a
specialized pilot."""

from __future__ import annotations

from typing import Optional

from .cards import (
    Kind,
    NOBLE_DEFS,
    RING_COST,
    RING_DEFS,
    VERB_BURN,
    VERB_DELUGE,
    VERB_DETHRONE,
    VERB_INSIGHT,
    VERB_REVIVE,
    VERB_RENEW,
    VERB_SEEK,
    VERB_TEARS,
    VERB_WOE,
    VERB_WRATH,
)
from .match import EndOfGame, MatchState, Ritual


def _ritual_combinations_for_value(p_field, target: int) -> Optional[list[int]]:
    rituals = sorted(p_field, key=lambda r: r.value)
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


def _minimal_sac_for_lane(p_field, target: int) -> Optional[list[int]]:
    return _ritual_combinations_for_value(p_field, target)


def simple_mulligan(state: MatchState, pid: int) -> bool:
    hand = state.players[pid].hand
    if not hand:
        return False
    rituals = [c for c in hand if c.kind is Kind.RITUAL]
    if len(rituals) == 0:
        return True
    if len(rituals) == len(hand):
        return True
    low = [c for c in rituals if c.value == 1]
    if len(low) == 0 and len(rituals) >= 3:
        return True
    return False


class GreedyAI:
    # -------------------------------------------------------------- weights
    W_RITUAL_BASE: float = 10.0
    W_RITUAL_VALUE_BONUS: float = 1.0       # multiplied by c.value
    W_RITUAL_NEW_LANE: float = 60.0
    W_RITUAL_DUP_LANE_1: float = -4.0

    W_NOBLE_BASE: float = 60.0
    W_NOBLE_COST_BONUS: float = 1.0         # multiplied by c.cost
    W_NOBLE_GRANT_NEW_LANE: float = 40.0
    W_NOBLE_BIG_TRIPLET: float = 20.0       # xytzr/yytzr/zytzr static boost

    W_BIRD_BASE: float = 15.0
    W_BIRD_POWER_BONUS: float = 1.0         # multiplied by c.power

    W_TEMPLE_BASE: float = 55.0
    W_TEMPLE_COST_BONUS: float = 1.0        # multiplied by c.cost
    W_TEMPLE_EYRIE_BONUS: float = 30.0

    W_RING_BASE: float = 18.0

    W_DETHRONE_BASE: float = 40.0
    W_DETHRONE_PER_COST: float = 3.0

    SAC_PENALTY_PER_RITUAL: float = 2.0
    SAC_W_FIELD_POWER: float = 0.0   # × sum of ritual values on our field (sac aversion scales with board mass)
    SAC_W_HIGH_RITUAL: float = 0.0   # × max ritual value on our field
    INC_BASE_BONUS: float = 5.0

    W_NOBLE_ACTIVATION: float = 30.0
    W_NOBLE_ACTIVATION_DISCARD_PENALTY: float = 8.0
    W_AEOIU_ACTIVATION_BASE: float = 45.0

    W_TEMPLE_PHAEDRA_ACT: float = 38.0
    W_TEMPLE_DELPHA_ACT_BASE: float = 25.0
    W_TEMPLE_GOTHA_ACT_BASE: float = 20.0
    W_TEMPLE_YTRIA_ACT_BASE: float = 25.0

    W_NEST_BASE: float = 8.0
    W_FIGHT_KILL_BASE: float = 4.0
    W_DISCARD_DRAW: float = 3.0
    DD_W_FIELD_CONTRIB: float = 0.0  # × _card_discard_score(worst card): keep-affinity of the card we would bin
    DD_W_CARD_COST: float = 0.0    # × value/cost of that card

    DD_W_RITUAL_BASE: float = 1.0
    DD_W_RITUAL_PER_VALUE: float = 0.3
    DD_W_INC_BASE: float = 2.0
    DD_W_INC_PER_VALUE: float = 0.4
    DD_W_INC_DETHRONE: float = 5.0
    DD_W_INC_WRATH: float = 5.0
    DD_W_NOBLE_BASE: float = 4.0
    DD_W_NOBLE_PER_COST: float = 0.5
    DD_W_TEMPLE_BASE: float = 6.0
    DD_W_TEMPLE_PER_COST: float = 0.2
    DD_W_BIRD_BASE: float = 3.0
    DD_W_BIRD_PER_POWER: float = 0.3
    DD_W_RING: float = 4.0

    W_RING_SAVE_INC: float = 2.0
    W_RING_SAVE_NOBLE: float = 1.5
    W_RING_SAVE_BIRD: float = 1.0

    W_NEST_POWER_BONUS: float = 1.0
    W_AEOIU_RITUAL_VALUE: float = 1.0
    W_TEMPLE_DELPHA_PER_DELTA: float = 10.0
    W_TEMPLE_GOTHA_PER_DRAW: float = 3.0
    W_TEMPLE_YTRIA_PER_HAND: float = 2.0

    W_REVIVE_PRIO_WRATH: float = 6.0
    W_REVIVE_PRIO_SEEK: float = 5.0
    W_REVIVE_PRIO_WOE: float = 4.0
    W_REVIVE_PRIO_BURN: float = 3.0
    W_REVIVE_PRIO_INSIGHT: float = 2.0
    W_REVIVE_PRIO_RENEW: float = 0.0

    W_SF_RITUAL_MP_PUSH: float = 0.0
    W_SF_INC_BEHIND: float = 0.0
    W_SF_RING_OPP_BOARD: float = 0.0
    W_SF_DISCARD_FLOOD: float = 0.0

    # verb effect scoring
    W_EFFECT_SEEK_BASE: float = 8.0
    W_EFFECT_SEEK_VALUE: float = 3.0
    W_EFFECT_INSIGHT_BASE: float = 4.0
    W_EFFECT_INSIGHT_VALUE: float = 1.0
    W_EFFECT_BURN_BASE: float = 2.0
    W_EFFECT_BURN_VALUE: float = 1.0
    W_EFFECT_WOE_BASE: float = 5.0
    W_EFFECT_WOE_PER_DISCARD: float = 3.0
    W_EFFECT_WRATH_BASE: float = 10.0
    W_EFFECT_WRATH_PER_KILLED: float = 2.5
    W_EFFECT_REVIVE_BASE: float = 12.0
    W_EFFECT_DELUGE_BASE: float = 5.0
    W_EFFECT_DELUGE_PER_NET: float = 4.0
    W_EFFECT_TEARS_BASE: float = 10.0

    def __init__(self, pid: int) -> None:
        self.pid = pid

    # -------------------------------------------------------------- mulligan
    def mulligan(self, state: MatchState, pid: int) -> bool:
        return simple_mulligan(state, pid)

    # --------------------------------------------------------------- turn
    def play_turn(self, state: MatchState) -> None:
        if state.game_over_flag:
            return
        guard = 200
        while guard > 0:
            guard -= 1
            if state.pending is not None:
                return
            if not self._take_best_action(state):
                break
        self._end_turn(state)

    # --------------------------------------------------------------- responses
    def respond(self, state: MatchState) -> None:
        if state.pending is None:
            return
        p = state.pending
        if p.responder != self.pid:
            return
        if p.kind == "woe":
            indices = self.woe_response(state)
            state.submit_woe_discard(self.pid, indices)
        elif p.kind == "scion":
            self.scion_response(state)

    def woe_response(self, state: MatchState) -> list[int]:
        p = state.pending
        need = p.payload["need"]
        hand = state.players[self.pid].hand
        scored = sorted(range(len(hand)), key=lambda i: self._card_discard_score(hand[i]))
        return scored[:need]

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

    # --------------------------------------------------------------- scoring
    def _card_discard_score(self, c) -> float:
        if c.kind is Kind.RITUAL:
            return self.DD_W_RITUAL_BASE + c.value * self.DD_W_RITUAL_PER_VALUE
        if c.kind is Kind.INCANTATION:
            if c.verb == VERB_DETHRONE:
                return self.DD_W_INC_DETHRONE
            if c.verb == VERB_WRATH:
                return self.DD_W_INC_WRATH
            return self.DD_W_INC_BASE + c.value * self.DD_W_INC_PER_VALUE
        if c.kind is Kind.NOBLE:
            return self.DD_W_NOBLE_BASE + c.cost * self.DD_W_NOBLE_PER_COST
        if c.kind is Kind.TEMPLE:
            return self.DD_W_TEMPLE_BASE + c.cost * self.DD_W_TEMPLE_PER_COST
        if c.kind is Kind.BIRD:
            return self.DD_W_BIRD_BASE + c.power * self.DD_W_BIRD_PER_POWER
        if c.kind is Kind.RING:
            return self.DD_W_RING
        return 0.0

    def _take_best_action(self, state: MatchState) -> bool:
        try:
            return self._enumerate_and_act(state)
        except EndOfGame:
            return False

    def _enumerate_and_act(self, state: MatchState) -> bool:
        pid = self.pid
        p = state.players[pid]
        opp = state.players[state.opponent(pid)]
        active = state.active_lanes(pid)
        actions: list[tuple[float, str, tuple]] = []

        for i, c in enumerate(p.hand):
            if c.kind is Kind.RITUAL and not p.ritual_played_this_turn:
                before = active
                lanes_unlocked = self._count_new_lanes_if_ritual(state, pid, c.value)
                score = self.score_ritual_play(state, c, before, lanes_unlocked)
                actions.append((score, "ritual", (i,)))

            elif c.kind is Kind.NOBLE and not p.noble_played_this_turn:
                eff = state.effective_noble_cost(pid, c.cost)
                sac: list[int] = []
                playable = False
                if eff == 0:
                    playable = True
                elif eff in active:
                    playable = True
                elif eff < 6:
                    playable = False
                else:
                    s = _ritual_combinations_for_value(p.field, eff)
                    if s is not None:
                        sac = s
                        playable = True
                if playable:
                    score = self.score_noble_play(state, c, eff, sac)
                    if score is not None:
                        actions.append((score, "noble", (i, tuple(sac))))

            elif c.kind is Kind.BIRD and not p.bird_played_this_turn:
                eff = state.effective_bird_cost(pid, c.cost)
                if eff == 0 or eff in active:
                    score = self.score_bird_play(state, c)
                    actions.append((score, "bird", (i,)))

            elif c.kind is Kind.RING:
                if RING_COST in active:
                    ring_act = self._score_ring(state, pid, c, i)
                    if ring_act is not None:
                        actions.append(ring_act)

            elif c.kind is Kind.TEMPLE and not p.temple_played_this_turn:
                sac = _minimal_sac_for_lane(p.field, c.cost)
                if sac is not None:
                    would_keep_lanes = self._lanes_after_sac(state, pid, sac)
                    score = self.score_temple_play(state, c, sac, would_keep_lanes)
                    if score is not None:
                        actions.append((score, "temple", (i, tuple(sac))))

            elif c.kind is Kind.INCANTATION and c.verb == VERB_DETHRONE:
                if opp.noble_field:
                    if 4 in active:
                        sac_d: list[int] = []
                    else:
                        s = _ritual_combinations_for_value(p.field, 4)
                        if s is None:
                            continue
                        sac_d = s
                    target = self.choose_dethrone_target(state, pid)
                    if target is None:
                        continue
                    score = self.score_dethrone(state, c, sac_d, target)
                    if score is None:
                        continue
                    actions.append((score, "dethrone", (i, tuple(sac_d), target.mid)))

            elif c.kind is Kind.INCANTATION:
                s = self._score_incantation(state, pid, c)
                if s is None:
                    continue
                score, sac = s
                actions.append((score, "incantation", (i, tuple(sac) if sac else ())))

        for n in p.noble_field:
            if n.used_turn == state.turn_number:
                continue
            info = NOBLE_DEFS.get(n.noble_id, {})
            if n.noble_id == "aeoiu_rituals":
                crypt_rituals = [(i, c) for i, c in enumerate(p.crypt) if c.kind is Kind.RITUAL]
                if not crypt_rituals:
                    continue
                best_idx, best_card = max(crypt_rituals, key=lambda t: t[1].value)
                score = self.W_AEOIU_ACTIVATION_BASE + best_card.value * self.W_AEOIU_RITUAL_VALUE
                actions.append((score, "activate_aeoiu", (n.mid, best_idx)))
                continue
            verb = info.get("activated_verb")
            if not verb:
                continue
            val = info.get("activated_value", 0)
            if info.get("activation_discard") and not p.hand:
                continue
            eff = self._score_effect(state, pid, verb, val)
            if eff is None:
                continue
            score, ctx = eff
            score += self.W_NOBLE_ACTIVATION
            if info.get("activation_discard"):
                ctx = dict(ctx or {})
                worst_i = 0
                worst_score = None
                for ci, cc in enumerate(p.hand):
                    cs = cc.cost if cc.cost else cc.value
                    if worst_score is None or cs < worst_score:
                        worst_score = cs
                        worst_i = ci
                ctx["discard_hand_idx"] = worst_i
                score -= self.W_NOBLE_ACTIVATION_DISCARD_PENALTY
            actions.append((score, "activate_noble", (n.mid, ctx)))

        for t in p.temple_field:
            if t.used_turn == state.turn_number:
                continue
            ta = self._score_temple_activation(state, pid, t)
            if ta is not None:
                actions.append(ta)

        if not p.bird_nested_this_turn:
            for b in p.bird_field:
                if b.nest_mid >= 0:
                    continue
                for t in p.temple_field:
                    if len(t.nested) < t.cost:
                        if self.should_nest(state, b, t):
                            score = self.W_NEST_BASE + b.power * self.W_NEST_POWER_BONUS
                            actions.append((score, "nest", (b.mid, t.mid)))
                        break

        if not p.bird_fight_used:
            best = self._best_fight(state, pid)
            if best is not None:
                score, atk_mid, def_mid = best
                if score > 0:
                    actions.append((score, "fight", (atk_mid, def_mid)))

        if not p.discard_draw_used and p.hand:
            scored = sorted(range(len(p.hand)), key=lambda i: self._card_discard_score(p.hand[i]))
            worst = scored[0]
            worst_c = p.hand[worst]
            score = self._discard_draw_action_score(state, worst_c)
            actions.append((score, "discard_draw", (worst,)))

        actions.sort(key=lambda t: t[0], reverse=True)
        if not actions or actions[0][0] <= 0:
            return False

        best = actions[0]
        self._execute(state, best)
        return True

    # --------------------------------------------------------------- per-action scoring hooks

    def score_ritual_play(self, state: MatchState, card, before_lanes: set[int], lanes_unlocked: int) -> float:
        score = self.W_RITUAL_BASE + card.value * self.W_RITUAL_VALUE_BONUS + self.W_RITUAL_NEW_LANE * lanes_unlocked
        if card.value == 1 and 1 in before_lanes:
            score += self.W_RITUAL_DUP_LANE_1
        deficit = max(0, 18 - state.match_power(self.pid))
        score += self.W_SF_RITUAL_MP_PUSH * deficit * lanes_unlocked
        return score

    def score_noble_play(self, state: MatchState, card, eff_cost: int, sac: list[int]) -> Optional[float]:
        score = self.W_NOBLE_BASE + card.cost * self.W_NOBLE_COST_BONUS
        info = NOBLE_DEFS.get(card.noble_id, {})
        active = state.active_lanes(self.pid)
        if info.get("grants_lane"):
            if info["grants_lane"] not in active:
                score += self.W_NOBLE_GRANT_NEW_LANE
        if card.noble_id in ("xytzr_emanation", "yytzr_occultation", "zytzr_annihilation"):
            score += self.W_NOBLE_BIG_TRIPLET
        if sac:
            score -= self._sac_penalty(state, self.pid, sac)
        return score

    def score_bird_play(self, state: MatchState, card) -> float:
        return self.W_BIRD_BASE + card.power * self.W_BIRD_POWER_BONUS

    def score_temple_play(self, state: MatchState, card, sac: list[int], lanes_after_sac: set[int]) -> Optional[float]:
        if len(lanes_after_sac) < 2:
            return None
        p = state.players[self.pid]
        score = self.W_TEMPLE_BASE + card.cost * self.W_TEMPLE_COST_BONUS
        if card.temple_id == "eyrie_feathers" and any(cc.kind is Kind.BIRD for cc in p.deck):
            score += self.W_TEMPLE_EYRIE_BONUS
        if sac:
            score -= self._sac_penalty(state, self.pid, sac)
        return score

    def score_dethrone(self, state: MatchState, card, sac: list[int], target) -> Optional[float]:
        score = self.W_DETHRONE_BASE + target.cost * self.W_DETHRONE_PER_COST
        if sac:
            score -= self._sac_penalty(state, self.pid, sac)
        return score

    def choose_dethrone_target(self, state: MatchState, pid: int):
        opp = state.players[state.opponent(pid)]
        if not opp.noble_field:
            return None
        return max(opp.noble_field, key=lambda n: n.cost)

    def should_nest(self, state: MatchState, bird, temple) -> bool:
        return True

    # --------------------------------------------------------------- helpers

    def _count_new_lanes_if_ritual(self, state: MatchState, pid: int, value: int) -> int:
        before = state.active_lanes(pid)
        p = state.players[pid]
        p.field.append(Ritual(mid=-999, value=value))
        after = state.active_lanes(pid)
        p.field = [r for r in p.field if r.mid != -999]
        return len(after - before)

    def _lanes_after_sac(self, state: MatchState, pid: int, sac_mids: list[int]) -> set[int]:
        p = state.players[pid]
        saved = list(p.field)
        p.field = [r for r in p.field if r.mid not in set(sac_mids)]
        lanes = state.active_lanes(pid)
        p.field = saved
        return lanes

    def _sac_field_stats(self, state: MatchState, pid: int) -> tuple[float, float]:
        p = state.players[pid]
        field_power = sum(r.value for r in p.field)
        highest = max((r.value for r in p.field), default=0)
        return float(field_power), float(highest)

    def _sac_penalty(self, state: MatchState, pid: int, sac_mids: list[int]) -> float:
        if not sac_mids:
            return 0.0
        fp, hi = self._sac_field_stats(state, pid)
        return (
            self.SAC_PENALTY_PER_RITUAL * len(sac_mids)
            + self.SAC_W_FIELD_POWER * fp
            + self.SAC_W_HIGH_RITUAL * hi
        )

    def _card_dd_cost(self, c) -> float:
        if c.kind is Kind.RITUAL:
            return float(c.value)
        if c.kind is Kind.INCANTATION:
            return float(c.value)
        if c.kind is Kind.NOBLE:
            return float(c.cost)
        if c.kind is Kind.TEMPLE:
            return float(c.cost)
        if c.kind is Kind.BIRD:
            return float(c.cost)
        if c.kind is Kind.RING:
            return float(RING_COST)
        return 0.0

    def _discard_draw_action_score(self, state: MatchState, worst_card) -> float:
        contrib = self._card_discard_score(worst_card)
        cost = self._card_dd_cost(worst_card)
        p = state.players[self.pid]
        flood = max(0, len(p.hand) - 6)
        return (
            self.W_DISCARD_DRAW
            + self.DD_W_FIELD_CONTRIB * contrib
            + self.DD_W_CARD_COST * cost
            + self.W_SF_DISCARD_FLOOD * flood
        )

    def _ritual_match_power_gain_if_played(self, state: MatchState, pid: int, value: int) -> int:
        p = state.players[pid]
        before = state.match_power(pid)
        p.field.append(Ritual(mid=-1001, value=value))
        after = state.match_power(pid)
        p.field = [r for r in p.field if r.mid != -1001]
        return max(0, after - before)

    def _card_insight_value(self, state: MatchState, pid: int, card) -> float:
        if card.kind is Kind.RITUAL:
            gain = self._ritual_match_power_gain_if_played(state, pid, card.value)
            if gain > 0:
                return float(gain)
        active = state.active_lanes(pid)
        if card.kind is Kind.INCANTATION:
            eff = state.effective_incantation_cost(pid, card.verb, card.value)
            can_play_now = 1 if (eff <= 0 or eff in active) else 0
            return float(card.value * can_play_now)
        if card.kind is Kind.NOBLE:
            eff = state.effective_noble_cost(pid, card.cost)
            can_play_now = 1 if (eff == 0 or eff in active or eff >= 6) else 0
            return float(card.cost * can_play_now)
        if card.kind is Kind.BIRD:
            eff = state.effective_bird_cost(pid, card.cost)
            can_play_now = 1 if (eff <= 0 or eff in active) else 0
            return float(card.cost * can_play_now)
        if card.kind is Kind.TEMPLE:
            can_play_now = 1 if _minimal_sac_for_lane(state.players[pid].field, card.cost) is not None else 0
            return float(card.cost * can_play_now)
        if card.kind is Kind.RING:
            can_play_now = 1 if RING_COST in active else 0
            return float(RING_COST * can_play_now)
        return 0.0

    def choose_insight_order(self, state: MatchState, pid: int, target_pid: int, revealed_cards: list, must_top_best: bool = True) -> tuple[list[int], list[int]]:
        scored = [(self._card_insight_value(state, pid, c), i) for i, c in enumerate(revealed_cards)]
        if not scored:
            return ([], [])
        scored.sort(key=lambda t: (-t[0], t[1]))
        top = [idx for score, idx in scored if score > 0]
        bottom = [idx for score, idx in scored if score <= 0]
        if must_top_best and top:
            best_idx = top[0]
            rest = [x for x in top[1:]]
            top = [best_idx] + rest
        return (top, bottom)

    def _score_incantation(self, state: MatchState, pid: int, card) -> Optional[tuple[float, list[int]]]:
        p = state.players[pid]
        active = state.active_lanes(pid)
        eff_val = state.effective_incantation_cost(pid, card.verb, card.value)
        sac: list[int] = []
        if card.verb == VERB_WRATH:
            if not p.field:
                return None
            r = min(p.field, key=lambda rr: (rr.value, rr.mid))
            sac = [r.mid]
        elif eff_val > 0 and eff_val not in active:
            s = _ritual_combinations_for_value(p.field, eff_val)
            if s is None:
                return None
            after = self._lanes_after_sac(state, pid, s)
            if len(after) < 1:
                return None
            sac = s
        eff = self._score_effect(state, pid, card.verb, card.value)
        if eff is None:
            return None
        score, ctx = eff
        score += self.INC_BASE_BONUS
        if sac:
            score -= self._sac_penalty(state, pid, sac)
        score = self.adjust_incantation_score(state, pid, card, sac, score)
        if score is None:
            return None
        opp_pid = state.opponent(pid)
        gap = max(0, state.match_power(opp_pid) - state.match_power(pid))
        score += self.W_SF_INC_BEHIND * gap * card.value * 0.1
        return score, sac

    def adjust_incantation_score(self, state: MatchState, pid: int, card, sac: list[int], score: float) -> Optional[float]:
        return score

    def _score_ring(self, state: MatchState, pid: int, card, hand_idx: int) -> Optional[tuple[float, str, tuple]]:
        p = state.players[pid]
        hosts = state.ring_legal_hosts(pid)
        if not hosts:
            return None
        if card.ring_id in {r for n in p.noble_field for r in n.rings} | {r for b in p.bird_field for r in b.rings}:
            return None
        reductions = RING_DEFS.get(card.ring_id, {}).get("reductions", {})
        savings = 0.0
        for c in p.hand + p.deck:
            if c.kind is Kind.INCANTATION and c.verb in reductions:
                savings += self.W_RING_SAVE_INC
            elif c.kind is Kind.NOBLE and "noble" in reductions:
                savings += self.W_RING_SAVE_NOBLE
            elif c.kind is Kind.BIRD and "bird" in reductions:
                savings += self.W_RING_SAVE_BIRD
        score = self.W_RING_BASE + savings
        score = self.adjust_ring_score(state, pid, card, score)
        opp = state.players[state.opponent(pid)]
        score += self.W_SF_RING_OPP_BOARD * (len(opp.field) + len(opp.bird_field))
        host_kind, host_mid = self._pick_ring_host(state, pid, card, hosts)
        return (score, "ring", (hand_idx, host_kind, host_mid))

    def adjust_ring_score(self, state: MatchState, pid: int, card, score: float) -> float:
        return score

    def _pick_ring_host(self, state: MatchState, pid: int, card, hosts: list[tuple[str, int]]) -> tuple[str, int]:
        p = state.players[pid]
        for hk, hm in hosts:
            if hk == "noble":
                n = next((x for x in p.noble_field if x.mid == hm), None)
                if n is not None and NOBLE_DEFS.get(n.noble_id, {}).get("grants_lane"):
                    return (hk, hm)
        for hk, hm in hosts:
            if hk == "noble":
                return (hk, hm)
        return hosts[0]

    def _score_temple_activation(self, state: MatchState, pid: int, t) -> Optional[tuple[float, str, tuple]]:
        p = state.players[pid]
        if t.temple_id == "phaedra_illusion":
            score = self.W_TEMPLE_PHAEDRA_ACT
            target = state.opponent(pid)
            take = min(1, len(state.players[target].deck))
            revealed = state.players[target].deck[-take:][::-1]
            top_idx, bottom_idx = self.choose_insight_order(state, pid, target, revealed, True)
            return (score, "activate_temple", (t.mid, {"insight_target": target, "insight_top": top_idx, "insight_bottom": bottom_idx}))
        if t.temple_id == "delpha_oracles":
            crypt_rituals = [(i, c) for i, c in enumerate(p.crypt) if c.kind is Kind.RITUAL]
            if not p.field or not crypt_rituals:
                return None
            ritual = min(p.field, key=lambda r: r.value)
            x = ritual.value
            if len(p.deck) < 2 * x:
                return None
            ci, cc = max(crypt_rituals, key=lambda u: u[1].value)
            if cc.value <= ritual.value:
                return None
            score = self.W_TEMPLE_DELPHA_ACT_BASE + (cc.value - ritual.value) * self.W_TEMPLE_DELPHA_PER_DELTA
            return (score, "activate_temple", (t.mid, {"ritual_mid": ritual.mid, "crypt_ritual_idx": ci}))
        if t.temple_id == "gotha_illness":
            best_i = -1
            best_draw = 0
            for i, c in enumerate(p.hand):
                if c.kind is Kind.TEMPLE:
                    continue
                if not self.gotha_hand_allowed(state, c):
                    continue
                draw_n = 0
                if c.kind is Kind.RITUAL or c.kind is Kind.INCANTATION:
                    draw_n = c.value
                elif c.kind in (Kind.NOBLE, Kind.BIRD, Kind.RING):
                    draw_n = c.cost
                if draw_n > best_draw:
                    best_draw = draw_n
                    best_i = i
            if best_i >= 0 and best_draw >= 2:
                score = self.W_TEMPLE_GOTHA_ACT_BASE + best_draw * self.W_TEMPLE_GOTHA_PER_DRAW
                return (score, "activate_temple", (t.mid, {"hand_idx": best_i}))
            return None
        if t.temple_id == "ytria_cycles":
            if len(p.hand) >= self.ytria_min_hand(state):
                score = self.W_TEMPLE_YTRIA_ACT_BASE + len(p.hand) * self.W_TEMPLE_YTRIA_PER_HAND
                return (score, "activate_temple", (t.mid, {}))
        return None

    def gotha_hand_allowed(self, state: MatchState, card) -> bool:
        return True

    def ytria_min_hand(self, state: MatchState) -> int:
        return 4

    # --------------------------------------------------------------- verb scoring
    def _score_effect(self, state: MatchState, pid: int, verb: str, val: int) -> Optional[tuple[float, dict]]:
        opp = state.opponent(pid)
        opp_p = state.players[opp]
        me = state.players[pid]
        if verb == VERB_SEEK:
            return (self.W_EFFECT_SEEK_BASE + val * self.W_EFFECT_SEEK_VALUE, {})
        if verb == VERB_INSIGHT:
            take = min(val + (1 if state.has_noble(pid, "xytzr_emanation") else 0), len(opp_p.deck))
            revealed = opp_p.deck[-take:][::-1]
            top_idx, bottom_idx = self.choose_insight_order(state, pid, opp, revealed, True)
            return (self.W_EFFECT_INSIGHT_BASE + val * self.W_EFFECT_INSIGHT_VALUE,
                    {"insight_target": opp, "insight_top": top_idx, "insight_bottom": bottom_idx})
        if verb == VERB_BURN:
            target = self.choose_burn_target(state, pid, val)
            return (self.W_EFFECT_BURN_BASE + val * self.W_EFFECT_BURN_VALUE, {"burn_target": target})
        if verb == VERB_WOE:
            if not opp_p.hand:
                return None
            discards = max(val - 2, 0) + (1 if state.has_noble(pid, "zytzr_annihilation") else 0)
            if discards <= 0:
                return None
            return (self.W_EFFECT_WOE_BASE + discards * self.W_EFFECT_WOE_PER_DISCARD,
                    {"woe_target": opp})
        if verb == VERB_WRATH:
            if not opp_p.field:
                return None
            ritvals = sorted((r.value for r in opp_p.field), reverse=True)
            killed = sum(ritvals[:1 + (1 if state.has_noble(pid, "zytzr_annihilation") else 0)])
            base = self.W_EFFECT_WRATH_BASE + killed * self.W_EFFECT_WRATH_PER_KILLED
            return (self.wrath_score_adjust(state, pid, base), {})
        if verb == VERB_REVIVE:
            elig = [c for c in me.crypt if c.kind is Kind.INCANTATION and c.verb not in (VERB_REVIVE, VERB_TEARS, VERB_DETHRONE)]
            if not elig:
                return None
            return (self.W_EFFECT_REVIVE_BASE, {})
        if verb == VERB_RENEW:
            ritual_idx = [i for i, c in enumerate(me.crypt) if c.kind is Kind.RITUAL]
            if not ritual_idx:
                return None
            best_i = 0
            best_v = -1
            for j, ci in enumerate(ritual_idx):
                v = me.crypt[ci].value
                if v > best_v:
                    best_v = v
                    best_i = j
            return (self.W_EFFECT_REVIVE_BASE, {"renew_ritual_crypt_idx": best_i})
        if verb == VERB_DELUGE:
            threshold = val - 1
            opp_hit = sum(1 for b in opp_p.bird_field if b.power <= threshold and b.nest_mid < 0)
            me_hit = sum(1 for b in me.bird_field if b.power <= threshold and b.nest_mid < 0)
            opp_unnest = sum(1 for b in opp_p.bird_field if b.nest_mid >= 0)
            me_unnest = sum(1 for b in me.bird_field if b.nest_mid >= 0)
            net = (opp_hit - me_hit) + (opp_unnest - me_unnest)
            if net <= 0:
                return None
            return (self.W_EFFECT_DELUGE_BASE + net * self.W_EFFECT_DELUGE_PER_NET, {})
        if verb == VERB_TEARS:
            crypt_birds = [i for i, c in enumerate(me.crypt) if c.kind is Kind.BIRD]
            if not crypt_birds:
                return None
            return (self.W_EFFECT_TEARS_BASE, {})
        return None

    def wrath_score_adjust(self, state: MatchState, pid: int, base: float) -> float:
        return base

    def choose_burn_target(self, state: MatchState, pid: int, val: int) -> int:
        return state.opponent(pid)

    def choose_insight_bottom(self, state: MatchState, pid: int, target_pid: int, val: int) -> int:
        return val

    # --------------------------------------------------------------- combat
    def _best_fight(self, state: MatchState, pid: int) -> Optional[tuple[float, int, int]]:
        me = state.players[pid]
        opp = state.players[state.opponent(pid)]
        best: Optional[tuple[float, int, int]] = None
        for a in me.bird_field:
            if a.nest_mid >= 0:
                continue
            for d in opp.bird_field:
                if d.nest_mid >= 0:
                    continue
                atk_dies = a.power <= d.power
                def_dies = d.power <= a.power
                score = 0.0
                if def_dies:
                    score += self.W_FIGHT_KILL_BASE + d.power
                if atk_dies:
                    score -= self.W_FIGHT_KILL_BASE + a.power
                if score > 0:
                    if best is None or score > best[0]:
                        best = (score, a.mid, d.mid)
        return best

    # --------------------------------------------------------------- wrath / revive target picks
    def choose_wrath_targets(self, state: MatchState, pid: int, count: int) -> list[int]:
        opp = state.players[state.opponent(pid)]
        ritvals = sorted(opp.field, key=lambda r: -r.value)
        return [r.mid for r in ritvals[:count]]

    def choose_wrath_instigator_sac(self, state: MatchState, pid: int) -> Optional[int]:
        p = state.players[pid]
        if not p.field:
            return None
        r = min(p.field, key=lambda rr: (rr.value, rr.mid))
        return r.mid

    def _revive_verb_prio_bonus(self, verb: str) -> float:
        v = verb.lower()
        if v == VERB_WRATH:
            return self.W_REVIVE_PRIO_WRATH
        if v == VERB_SEEK:
            return self.W_REVIVE_PRIO_SEEK
        if v == VERB_WOE:
            return self.W_REVIVE_PRIO_WOE
        if v == VERB_BURN:
            return self.W_REVIVE_PRIO_BURN
        if v == VERB_INSIGHT:
            return self.W_REVIVE_PRIO_INSIGHT
        if v == VERB_RENEW:
            return self.W_REVIVE_PRIO_RENEW
        return 0.0

    def choose_revive_target(self, state: MatchState, pid: int, crypt_indices: list[int]) -> Optional[int]:
        p = state.players[pid]
        best = None
        best_score = -10**9
        for i in crypt_indices:
            c = p.crypt[i]
            score = c.value + self._revive_verb_prio_bonus(c.verb)
            if score > best_score:
                best_score = score
                best = i
        return best

    # --------------------------------------------------------------- dispatch
    def _execute(self, state: MatchState, action: tuple) -> None:
        score, kind, args = action
        pid = self.pid
        try:
            if kind == "ritual":
                state.play_ritual(pid, args[0])
            elif kind == "noble":
                state.play_noble(pid, args[0], list(args[1]) if len(args) > 1 and args[1] else None)
            elif kind == "bird":
                state.play_bird(pid, args[0])
            elif kind == "temple":
                state.play_temple(pid, args[0], list(args[1]))
            elif kind == "incantation":
                hand_idx, sac = args
                c = state.players[pid].hand[hand_idx]
                eff = self._score_effect(state, pid, c.verb, c.value)
                ctx = dict(eff[1]) if eff else {}
                if c.verb == VERB_WRATH:
                    killcount = 1 + (1 if state.has_noble(pid, "zytzr_annihilation") else 0)
                    ctx["wrath_targets"] = self.choose_wrath_targets(state, pid, killcount)
                if c.verb == VERB_REVIVE:
                    me = state.players[pid]
                    elig_idx = [i for i, cc in enumerate(me.crypt) if cc.kind is Kind.INCANTATION and cc.verb not in (VERB_REVIVE, VERB_TEARS, VERB_DETHRONE)]
                    pick = self.choose_revive_target(state, pid, elig_idx)
                    if pick is not None:
                        ctx["revive_crypt_idx"] = pick
                        ctx = self.amend_revive_ctx(state, pid, pick, ctx)
                state.play_incantation(pid, hand_idx, ctx, list(sac) if sac else None)
            elif kind == "dethrone":
                hand_idx, sac, target_mid = args
                state.play_dethrone(pid, hand_idx, list(sac) if sac else None, target_mid)
            elif kind == "activate_aeoiu":
                noble_mid, crypt_idx = args
                crypt_idx = self.choose_aeoiu_crypt_ritual(state, pid, crypt_idx)
                state.activate_noble(pid, noble_mid, {"crypt_ritual_idx": crypt_idx})
            elif kind == "activate_noble":
                noble_mid, ctx = args
                state.activate_noble(pid, noble_mid, ctx)
            elif kind == "activate_temple":
                temple_mid, ctx = args
                state.activate_temple(pid, temple_mid, ctx)
            elif kind == "nest":
                bird_mid, temple_mid = args
                state.nest_bird(pid, bird_mid, temple_mid)
            elif kind == "fight":
                atk_mid, def_mid = args
                state.bird_fight_simple(pid, atk_mid, def_mid)
            elif kind == "discard_draw":
                state.discard_for_draw(pid, args[0])
            elif kind == "ring":
                hand_idx, host_kind, host_mid = args
                state.play_ring(pid, hand_idx, host_kind, host_mid)
        except EndOfGame:
            return

    def choose_aeoiu_crypt_ritual(self, state: MatchState, pid: int, default_idx: int) -> int:
        return default_idx

    def amend_revive_ctx(self, state: MatchState, pid: int, crypt_idx: int, ctx: dict) -> dict:
        return ctx

    def _end_turn(self, state: MatchState) -> None:
        if state.pending is not None:
            return
        chosen = self.end_turn_discards(state, self.pid)
        try:
            state.end_turn(self.pid, chosen)
        except EndOfGame:
            return

    def end_turn_discards(self, state: MatchState, pid: int) -> list[int]:
        p = state.players[pid]
        hand = list(p.hand)
        if len(hand) <= 7:
            return []
        need_discard = len(hand) - 7
        scored = sorted(range(len(hand)), key=lambda i: self._card_discard_score(hand[i]))
        return scored[:need_discard]
