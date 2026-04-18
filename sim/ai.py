"""Greedy AI capable of piloting any Arcana deck.

The AI enumerates every legal action each tick of the main phase, scores
each candidate, plays the best, and stops when the best score is <= 0.
It also handles pending Woe / Eyrie / Scion responses."""

from __future__ import annotations

from typing import Optional

from .cards import (
    Kind,
    NOBLE_DEFS,
    RING_COST,
    RING_DEFS,
    VERB_BURN,
    VERB_DELUGE,
    VERB_INSIGHT,
    VERB_REVIVE,
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
    def __init__(self, pid: int) -> None:
        self.pid = pid

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

    def respond(self, state: MatchState) -> None:
        if state.pending is None:
            return
        p = state.pending
        if p.responder != self.pid:
            return
        if p.kind == "woe":
            need = p.payload["need"]
            hand = state.players[self.pid].hand
            scored = sorted(range(len(hand)), key=lambda i: self._card_discard_score(hand[i]))
            chosen = scored[:need]
            state.submit_woe_discard(self.pid, chosen)
        elif p.kind == "scion":
            scion = p.payload["scion"]
            if scion == "rmrsk":
                state.submit_scion_trigger(self.pid, True, {})
            elif scion == "smrsk":
                me = state.players[self.pid]
                if not me.field:
                    state.submit_scion_trigger(self.pid, False, {})
                    return
                lowest = min(me.field, key=lambda r: r.value)
                if lowest.value * 2 <= len(me.deck):
                    state.submit_scion_trigger(self.pid, False, {})
                else:
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
            return 1.0 + c.value * 0.3
        if c.kind is Kind.INCANTATION:
            if c.verb == VERB_WRATH:
                return 5.0
            return 2.0 + c.value * 0.4
        if c.kind is Kind.DETHRONE:
            return 5.0
        if c.kind is Kind.NOBLE:
            return 4.0 + c.cost * 0.5
        if c.kind is Kind.TEMPLE:
            return 6.0 + c.cost * 0.2
        if c.kind is Kind.BIRD:
            return 3.0 + c.power * 0.3
        if c.kind is Kind.RING:
            return 4.0
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
                score = 10 + c.value + 60 * lanes_unlocked
                if c.value == 1 and 1 in before:
                    score -= 4
                actions.append((score, "ritual", (i,)))

            elif c.kind is Kind.NOBLE and not p.noble_played_this_turn:
                eff = state.effective_noble_cost(pid, c.cost)
                sac: list[int] = []
                playable = False
                if eff == 0:
                    playable = True
                elif eff > 4:
                    s = _ritual_combinations_for_value(p.field, eff)
                    if s is not None:
                        sac = s
                        playable = True
                elif eff in active:
                    playable = True
                if playable:
                    score = 60 + c.cost
                    info = NOBLE_DEFS.get(c.noble_id, {})
                    if info.get("grants_lane"):
                        if info["grants_lane"] not in active:
                            score += 40
                    if c.noble_id in ("xytzr_emanation", "yytzr_occultation", "zytzr_annihilation"):
                        score += 20
                    if sac:
                        score -= self._sac_penalty(sac)
                    actions.append((score, "noble", (i, tuple(sac))))

            elif c.kind is Kind.BIRD and not p.bird_played_this_turn:
                eff = state.effective_bird_cost(pid, c.cost)
                if eff == 0 or eff in active:
                    score = 15 + c.power
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
                    if len(would_keep_lanes) >= 2:
                        score = 55 + c.cost
                        if c.temple_id == "eyrie_feathers" and any(cc.kind is Kind.BIRD for cc in p.deck):
                            score += 30
                        actions.append((score, "temple", (i, tuple(sac))))

            elif c.kind is Kind.INCANTATION:
                s = self._score_incantation(state, pid, c)
                if s is None:
                    continue
                score, sac = s
                actions.append((score, "incantation", (i, tuple(sac) if sac else ())))

            elif c.kind is Kind.DETHRONE:
                if opp.noble_field:
                    if 4 in active:
                        sac: list[int] = []
                    else:
                        s = _ritual_combinations_for_value(p.field, 4)
                        if s is None:
                            continue
                        sac = s
                    target = max(opp.noble_field, key=lambda n: n.cost)
                    score = 40 + target.cost * 3
                    if sac:
                        score -= self._sac_penalty(sac)
                    actions.append((score, "dethrone", (i, tuple(sac), target.mid)))

        for n in p.noble_field:
            if n.used_turn == state.turn_number:
                continue
            info = NOBLE_DEFS.get(n.noble_id, {})
            if n.noble_id == "aeoiu_rituals":
                crypt_rituals = [(i, c) for i, c in enumerate(p.crypt) if c.kind is Kind.RITUAL]
                if not crypt_rituals:
                    continue
                best_idx, best_card = max(crypt_rituals, key=lambda t: t[1].value)
                score = 45 + best_card.value
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
            score += 30
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
                score -= 8
            actions.append((score, "activate_noble", (n.mid, ctx)))

        for t in p.temple_field:
            if t.used_turn == state.turn_number:
                continue
            if t.temple_id == "phaedra_illusion":
                score = 38
                actions.append((score, "activate_temple", (t.mid, {"insight_target": state.opponent(pid), "insight_bottom": 1})))
            elif t.temple_id == "delpha_oracles":
                crypt_rituals = [(i, c) for i, c in enumerate(p.crypt) if c.kind is Kind.RITUAL]
                if not p.field or not crypt_rituals:
                    continue
                ritual = min(p.field, key=lambda r: r.value)
                x = ritual.value
                if len(p.deck) < 2 * x:
                    continue
                ci, cc = max(crypt_rituals, key=lambda u: u[1].value)
                if cc.value <= ritual.value:
                    continue
                score = 25 + (cc.value - ritual.value) * 10
                actions.append((score, "activate_temple", (t.mid, {"ritual_mid": ritual.mid, "crypt_ritual_idx": ci})))
            elif t.temple_id == "gotha_illness":
                best_i = -1
                best_draw = 0
                for i, c in enumerate(p.hand):
                    if c.kind is Kind.TEMPLE:
                        continue
                    draw_n = 0
                    if c.kind is Kind.RITUAL or c.kind is Kind.INCANTATION:
                        draw_n = c.value
                    elif c.kind in (Kind.NOBLE, Kind.BIRD, Kind.RING):
                        draw_n = c.cost
                    elif c.kind is Kind.DETHRONE:
                        draw_n = 4
                    if draw_n > best_draw:
                        best_draw = draw_n
                        best_i = i
                if best_i >= 0 and best_draw >= 2:
                    score = 20 + best_draw * 3
                    actions.append((score, "activate_temple", (t.mid, {"hand_idx": best_i})))
            elif t.temple_id == "ytria_cycles":
                if len(p.hand) >= 4:
                    score = 25 + len(p.hand) * 2
                    actions.append((score, "activate_temple", (t.mid, {})))

        for b in p.bird_field:
            if b.nest_mid >= 0:
                continue
            for t in p.temple_field:
                if len(t.nested) < t.cost:
                    score = 8 + b.power
                    actions.append((score, "nest", (b.mid, t.mid)))
                    break

        if not p.bird_fight_used:
            best = self._best_fight(state, pid)
            if best is not None:
                score, atk_mid, def_mid = best
                if score > 0:
                    actions.append((score, "fight", (atk_mid, def_mid)))

        if not p.discard_draw_used and p.hand:
            score = 3.0
            scored = sorted(range(len(p.hand)), key=lambda i: self._card_discard_score(p.hand[i]))
            worst = scored[0]
            actions.append((score, "discard_draw", (worst,)))

        actions.sort(key=lambda t: t[0], reverse=True)
        if not actions or actions[0][0] <= 0:
            return False

        best = actions[0]
        self._execute(state, best)
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

    def _sac_penalty(self, sac_mids) -> float:
        return 2.0 * len(sac_mids)

    def _score_incantation(self, state: MatchState, pid: int, card) -> Optional[tuple[float, list[int]]]:
        p = state.players[pid]
        active = state.active_lanes(pid)
        eff_val = state.effective_incantation_cost(pid, card.verb, card.value)
        sac: list[int] = []
        if eff_val > 0 and eff_val not in active:
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
        score += 5
        if sac:
            score -= self._sac_penalty(sac)
        return score, sac

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
                savings += 2.0
            elif c.kind is Kind.NOBLE and "noble" in reductions:
                savings += 1.5
            elif c.kind is Kind.BIRD and "bird" in reductions:
                savings += 1.0
        score = 18.0 + savings
        host_kind, host_mid = self._pick_ring_host(state, pid, hosts)
        return (score, "ring", (hand_idx, host_kind, host_mid))

    def _pick_ring_host(self, state: MatchState, pid: int, hosts: list[tuple[str, int]]) -> tuple[str, int]:
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

    def _score_effect(self, state: MatchState, pid: int, verb: str, val: int) -> Optional[tuple[float, dict]]:
        opp = state.opponent(pid)
        opp_p = state.players[opp]
        me = state.players[pid]
        if verb == VERB_SEEK:
            return (8 + val * 3.0, {})
        if verb == VERB_INSIGHT:
            return (4 + val * 1.0, {"insight_target": opp, "insight_bottom": val})
        if verb == VERB_BURN:
            return (2 + val * 1.0, {"burn_target": opp})
        if verb == VERB_WOE:
            if not opp_p.hand:
                return None
            discards = max(val - 2, 0) + (1 if state.has_noble(pid, "zytzr_annihilation") else 0)
            if discards <= 0:
                return None
            return (5 + discards * 3.0, {"woe_target": opp})
        if verb == VERB_WRATH:
            if not opp_p.field:
                return None
            ritvals = sorted((r.value for r in opp_p.field), reverse=True)
            killed = sum(ritvals[:1 + (1 if state.has_noble(pid, "zytzr_annihilation") else 0)])
            return (10 + killed * 2.5, {})
        if verb == VERB_REVIVE:
            elig = [c for c in me.crypt if c.kind is Kind.INCANTATION and c.verb not in (VERB_REVIVE, VERB_TEARS)]
            if not elig:
                return None
            return (12, {})
        if verb == VERB_DELUGE:
            threshold = val - 1
            opp_hit = sum(1 for b in opp_p.bird_field if b.power <= threshold and b.nest_mid < 0)
            me_hit = sum(1 for b in me.bird_field if b.power <= threshold and b.nest_mid < 0)
            opp_unnest = sum(1 for b in opp_p.bird_field if b.nest_mid >= 0)
            me_unnest = sum(1 for b in me.bird_field if b.nest_mid >= 0)
            net = (opp_hit - me_hit) + (opp_unnest - me_unnest)
            if net <= 0:
                return None
            return (5 + net * 4.0, {})
        if verb == VERB_TEARS:
            crypt_birds = [i for i, c in enumerate(me.crypt) if c.kind is Kind.BIRD]
            if not crypt_birds:
                return None
            return (10, {})
        return None

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
                    score += 4.0 + d.power
                if atk_dies:
                    score -= 4.0 + a.power
                if score > 0:
                    if best is None or score > best[0]:
                        best = (score, a.mid, d.mid)
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
                ctx = eff[1] if eff else {}
                if c.verb == VERB_WRATH:
                    opp = state.players[state.opponent(pid)]
                    ritvals = sorted(opp.field, key=lambda r: -r.value)
                    killcount = 1 + (1 if state.has_noble(pid, "zytzr_annihilation") else 0)
                    ctx["wrath_targets"] = [r.mid for r in ritvals[:killcount]]
                if c.verb == VERB_REVIVE:
                    me = state.players[pid]
                    elig = [(i, cc) for i, cc in enumerate(me.crypt) if cc.kind is Kind.INCANTATION and cc.verb not in (VERB_REVIVE, VERB_TEARS)]
                    if elig:
                        def score_rev(entry):
                            cc = entry[1]
                            return {VERB_WRATH: 6, VERB_SEEK: 5, VERB_WOE: 4, VERB_BURN: 3, VERB_INSIGHT: 2}.get(cc.verb, 1) + cc.value
                        elig.sort(key=score_rev, reverse=True)
                        ctx["revive_crypt_idx"] = elig[0][0]
                state.play_incantation(pid, hand_idx, ctx, list(sac) if sac else None)
            elif kind == "dethrone":
                hand_idx, sac, target_mid = args
                state.play_dethrone(pid, hand_idx, list(sac) if sac else None, target_mid)
            elif kind == "activate_aeoiu":
                noble_mid, crypt_idx = args
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

    def _end_turn(self, state: MatchState) -> None:
        if state.pending is not None:
            return
        p = state.players[self.pid]
        hand = list(p.hand)
        if len(hand) <= 7:
            try:
                state.end_turn(self.pid, [])
            except EndOfGame:
                return
            return
        need_discard = len(hand) - 7
        scored = sorted(range(len(hand)), key=lambda i: self._card_discard_score(hand[i]))
        chosen = scored[:need_discard]
        try:
            state.end_turn(self.pid, chosen)
        except EndOfGame:
            return
