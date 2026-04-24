"""Arcana match engine for Monte Carlo simulation.

Mirrors arcana_match_state.gd. Deck `top` is the end of the `deck` list:
draw = deck.pop(), burn = deck.pop(), insight-to-bottom = deck.insert(0, ...).
Match power is ritual-power (sum of active ritual values) plus one per bird in
play. Win at >=20 or having higher
match power than the opponent on an empty-deck draw attempt.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field as dc_field
from typing import Optional

from .cards import (
    BIRD_DEFS,
    Card,
    Kind,
    NOBLE_DEFS,
    RING_COST,
    RING_DEFS,
    TEMPLE_DEFS,
    VERB_BURN,
    VERB_DELUGE,
    VERB_DETHRONE,
    VERB_FLIGHT,
    VERB_INSIGHT,
    VERB_REVIVE,
    VERB_RENEW,
    VERB_SEEK,
    VERB_TEARS,
    VERB_WOE,
    VERB_WRATH,
)


WIN_POWER = 20
HAND_CAP = 7
DEFAULT_TURN_CAP = 400


@dataclass
class Ritual:
    mid: int
    value: int


@dataclass
class Noble:
    mid: int
    noble_id: str
    cost: int
    used_turn: int = -1
    rings: list[str] = dc_field(default_factory=list)  # ring_ids attached


@dataclass
class Temple:
    mid: int
    temple_id: str
    cost: int
    used_turn: int = -1
    nested: list[int] = dc_field(default_factory=list)  # bird mids


@dataclass
class Bird:
    mid: int
    bird_id: str
    cost: int
    power: int
    damage: int = 0
    nest_mid: int = -1  # temple mid if nested, else -1
    rings: list[str] = dc_field(default_factory=list)  # ring_ids attached


@dataclass
class Player:
    deck: list[Card] = dc_field(default_factory=list)
    hand: list[Card] = dc_field(default_factory=list)
    field: list[Ritual] = dc_field(default_factory=list)
    noble_field: list[Noble] = dc_field(default_factory=list)
    temple_field: list[Temple] = dc_field(default_factory=list)
    bird_field: list[Bird] = dc_field(default_factory=list)
    crypt: list[Card] = dc_field(default_factory=list)
    inc_abyss: list[Card] = dc_field(default_factory=list)
    ritual_played_this_turn: bool = False
    noble_played_this_turn: bool = False
    temple_played_this_turn: bool = False
    bird_played_this_turn: bool = False
    bird_fight_used: bool = False
    bird_nested_this_turn: bool = False
    discard_draw_used: bool = False


@dataclass
class Pending:
    kind: str               # "woe" | "eyrie" | "scion"
    responder: int          # player id who must respond
    payload: dict = dc_field(default_factory=dict)


class EndOfGame(Exception):
    """Raised to short-circuit out of effect resolution when a game ends."""


class MatchState:
    def __init__(self, decks: tuple[list[Card], list[Card]], rng: random.Random, turn_cap: int = DEFAULT_TURN_CAP) -> None:
        self.rng = rng
        self.turn_cap = turn_cap
        self.players: list[Player] = [Player(), Player()]
        for pid in (0, 1):
            d = list(decks[pid])
            rng.shuffle(d)
            self.players[pid].deck = d
        self.active: int = rng.randrange(2)
        self.turn_number: int = 0
        self.pending: Optional[Pending] = None
        self._next_mid: int = 1
        self.game_over_flag: bool = False
        self.winner: int = -2   # -1 draw, 0 or 1 winner, -2 unresolved
        self.end_reason: str = ""
        self.power_curve_markers: list[int] = [1, 3, 5, 10, 15, 20]
        self.power_curve_p0: list[Optional[int]] = [None] * len(self.power_curve_markers)
        self.power_curve_p1: list[Optional[int]] = [None] * len(self.power_curve_markers)
        self.non_ritual_plays_from_hand: list[dict[str, int]] = [{}, {}]

    def mid(self) -> int:
        m = self._next_mid
        self._next_mid += 1
        return m

    def opponent(self, pid: int) -> int:
        return 1 - pid

    # ------------------------------------------------------------------ setup

    def start(self, mulligan_heuristic=None) -> None:
        for pid in (0, 1):
            self._draw_n(pid, 5, can_lose=False)
        if mulligan_heuristic is not None:
            for pid in (0, 1):
                if mulligan_heuristic(self, pid):
                    p = self.players[pid]
                    p.deck.extend(p.hand)
                    p.hand.clear()
                    self.rng.shuffle(p.deck)
                    self._draw_n(pid, 5, can_lose=False)
                    if p.hand:
                        idx = self._mulligan_bottom_pick(pid)
                        card = p.hand.pop(idx)
                        p.deck.insert(0, card)
        self.turn_number = 1
        self._start_turn(self.active)

    def _mulligan_bottom_pick(self, pid: int) -> int:
        hand = self.players[pid].hand
        rituals = [i for i, c in enumerate(hand) if c.kind is Kind.RITUAL]
        non_rituals = [i for i in range(len(hand)) if i not in rituals]
        val_count = {1: 0, 2: 0, 3: 0, 4: 0}
        for c in hand:
            if c.kind is Kind.RITUAL:
                val_count[c.value] = val_count.get(c.value, 0) + 1
        if rituals and non_rituals:
            for r_idx in rituals:
                v = hand[r_idx].value
                if val_count[v] > 1:
                    return r_idx
            return non_rituals[0] if len(non_rituals) == 1 else rituals[0]
        return 0

    # ----------------------------------------------------------------- zones

    def _draw_n(self, pid: int, n: int, can_lose: bool = True) -> int:
        p = self.players[pid]
        drawn = 0
        for _ in range(n):
            if not p.deck:
                if can_lose:
                    self._end_deck_out(pid)
                    return drawn
                return drawn
            p.hand.append(p.deck.pop())
            drawn += 1
        return drawn

    def _mill(self, target_pid: int, n: int) -> None:
        p = self.players[target_pid]
        for _ in range(n):
            if not p.deck:
                return
            p.crypt.append(p.deck.pop())

    def _end_deck_out(self, drawer_pid: int) -> None:
        mp0 = self.match_power(0)
        mp1 = self.match_power(1)
        if mp0 > mp1:
            self._finish(0, "deck_out")
        elif mp1 > mp0:
            self._finish(1, "deck_out")
        else:
            self._finish(-1, "deck_out")

    def _finish(self, winner: int, reason: str) -> None:
        if self.game_over_flag:
            return
        self.game_over_flag = True
        self.winner = winner
        self.end_reason = reason
        self._sample_power_curve(force=True)
        raise EndOfGame()

    # --------------------------------------------------------------- lanes

    def has_noble(self, pid: int, noble_id: str) -> bool:
        return any(n.noble_id == noble_id for n in self.players[pid].noble_field)

    def has_temple(self, pid: int, temple_id: str) -> bool:
        return any(t.temple_id == temple_id for t in self.players[pid].temple_field)

    def active_lanes(self, pid: int) -> set[int]:
        p = self.players[pid]
        ritual_vals = {r.value for r in p.field}
        granted: set[int] = set()
        for n in p.noble_field:
            lane = NOBLE_DEFS.get(n.noble_id, {}).get("grants_lane")
            if lane:
                granted.add(lane)
        active: set[int] = set()
        for v in range(1, 9):
            if v == 1:
                if 1 in ritual_vals or 1 in granted:
                    active.add(1)
            else:
                have = (v in ritual_vals) or (v in granted)
                if have and all(k in active for k in range(1, v)):
                    active.add(v)
        wild_bird_power = sum(b.power for b in p.bird_field if b.nest_mid < 0)
        if wild_bird_power > 0 and wild_bird_power <= 4:
            base = {v for v in range(1, 9) if (v in ritual_vals) or (v in granted)}
            chain = set()
            for v in range(1, 9):
                if v == 1:
                    if 1 in base or wild_bird_power == 1:
                        chain.add(1)
                else:
                    have = (v in base) or (v == wild_bird_power)
                    if have and all(k in chain for k in range(1, v)):
                        chain.add(v)
            active = chain
        return active

    def ritual_power(self, pid: int) -> int:
        p = self.players[pid]
        active = self.active_lanes(pid)
        total = 0
        for r in p.field:
            if r.value in active:
                total += r.value
        return total

    def match_power(self, pid: int) -> int:
        p = self.players[pid]
        return self.ritual_power(pid) + len(p.bird_field)

    def match_power_loss_remove_ritual(self, pid: int, mid: int) -> int:
        p = self.players[pid]
        if not any(r.mid == mid for r in p.field):
            return 10**9
        before = self.match_power(pid)
        trial = [r for r in p.field if r.mid != mid]
        old = p.field
        p.field = trial
        after = self.match_power(pid)
        p.field = old
        return before - after

    # --------------------------------------------------------------- ring reductions

    def _sum_ring_reduction(self, pid: int, key: str) -> int:
        p = self.players[pid]
        total = 0
        for n in p.noble_field:
            for rid in n.rings:
                total += RING_DEFS.get(rid, {}).get("reductions", {}).get(key, 0)
        for b in p.bird_field:
            for rid in b.rings:
                total += RING_DEFS.get(rid, {}).get("reductions", {}).get(key, 0)
        return total

    def effective_incantation_cost(self, pid: int, verb: str, value: int) -> int:
        return max(0, value - self._sum_ring_reduction(pid, verb))

    def effective_noble_cost(self, pid: int, cost: int) -> int:
        return max(0, cost - self._sum_ring_reduction(pid, "noble"))

    def effective_bird_cost(self, pid: int, cost: int) -> int:
        return max(0, cost - self._sum_ring_reduction(pid, "bird"))

    # --------------------------------------------------------------- turn

    def _start_turn(self, pid: int) -> None:
        if self.game_over_flag:
            return
        p = self.players[pid]
        p.ritual_played_this_turn = False
        p.noble_played_this_turn = False
        p.temple_played_this_turn = False
        p.bird_played_this_turn = False
        p.bird_fight_used = False
        p.bird_nested_this_turn = False
        p.discard_draw_used = False
        if not self.has_temple(pid, "gotha_illness"):
            self._draw_n(pid, 1, can_lose=True)
        self._sample_power_curve()

    def _sample_power_curve(self, force: bool = False) -> None:
        for i, t in enumerate(self.power_curve_markers):
            if force or self.turn_number >= t:
                if self.power_curve_p0[i] is None:
                    self.power_curve_p0[i] = self.match_power(0)
                if self.power_curve_p1[i] is None:
                    self.power_curve_p1[i] = self.match_power(1)

    def end_turn(self, pid: int, discard_hand_indices: list[int]) -> None:
        if self.pending is not None:
            return
        p = self.players[pid]
        idxs = sorted(set(discard_hand_indices), reverse=True)
        for i in idxs:
            if 0 <= i < len(p.hand):
                p.crypt.append(p.hand.pop(i))
        while len(p.hand) > HAND_CAP:
            p.crypt.append(p.hand.pop())
        self.active = self.opponent(pid)
        self.turn_number += 1
        if self.turn_number > self.turn_cap:
            mp0, mp1 = self.match_power(0), self.match_power(1)
            if mp0 > mp1:
                self._finish(0, "turn_cap")
            elif mp1 > mp0:
                self._finish(1, "turn_cap")
            else:
                self._finish(-1, "turn_cap")
            return
        self._start_turn(self.active)
        self._check_power_win()

    def _check_power_win(self) -> None:
        for pid in (0, 1):
            if self.match_power(pid) >= WIN_POWER:
                self._finish(pid, "power_win")
                return

    def _note_non_ritual_play(self, pid: int, card: Card) -> None:
        if card.kind is Kind.RITUAL:
            return
        lab = card.label()
        d = self.non_ritual_plays_from_hand[pid]
        d[lab] = d.get(lab, 0) + 1

    # --------------------------------------------------------------- plays

    def play_ritual(self, pid: int, hand_idx: int) -> None:
        p = self.players[pid]
        if p.ritual_played_this_turn or self.pending is not None:
            return
        if not (0 <= hand_idx < len(p.hand)):
            return
        c = p.hand[hand_idx]
        if c.kind is not Kind.RITUAL:
            return
        p.hand.pop(hand_idx)
        p.field.append(Ritual(mid=self.mid(), value=c.value))
        p.ritual_played_this_turn = True
        self._check_power_win()

    def play_noble(self, pid: int, hand_idx: int, sac_mids: Optional[list[int]] = None) -> None:
        p = self.players[pid]
        if p.noble_played_this_turn or self.pending is not None:
            return
        if not (0 <= hand_idx < len(p.hand)):
            return
        c = p.hand[hand_idx]
        if c.kind is not Kind.NOBLE:
            return
        eff = self.effective_noble_cost(pid, c.cost)
        al = self.active_lanes(pid)
        if eff > 0:
            if eff in al:
                pass
            elif eff < 6:
                return
            else:
                if not sac_mids or self._sac_total(pid, sac_mids) < eff:
                    return
                self._sacrifice(pid, sac_mids)
        p.hand.pop(hand_idx)
        self._note_non_ritual_play(pid, c)
        p.noble_field.append(Noble(mid=self.mid(), noble_id=c.noble_id, cost=c.cost))
        p.noble_played_this_turn = True
        self._check_power_win()

    def play_bird(self, pid: int, hand_idx: int) -> None:
        p = self.players[pid]
        if p.bird_played_this_turn or self.pending is not None:
            return
        if not (0 <= hand_idx < len(p.hand)):
            return
        c = p.hand[hand_idx]
        if c.kind is not Kind.BIRD:
            return
        eff = self.effective_bird_cost(pid, c.cost)
        if eff > 0 and eff not in self.active_lanes(pid):
            return
        p.hand.pop(hand_idx)
        self._note_non_ritual_play(pid, c)
        p.bird_field.append(Bird(mid=self.mid(), bird_id=c.bird_id, cost=c.cost, power=c.power))
        p.bird_played_this_turn = True
        self._check_power_win()

    def play_temple(self, pid: int, hand_idx: int, sac_mids: list[int]) -> None:
        p = self.players[pid]
        if p.temple_played_this_turn or self.pending is not None:
            return
        if not (0 <= hand_idx < len(p.hand)):
            return
        c = p.hand[hand_idx]
        if c.kind is not Kind.TEMPLE:
            return
        total = self._sac_total(pid, sac_mids)
        if total < c.cost:
            return
        self._sacrifice(pid, sac_mids)
        p.hand.pop(hand_idx)
        self._note_non_ritual_play(pid, c)
        t = Temple(mid=self.mid(), temple_id=c.temple_id, cost=c.cost)
        p.temple_field.append(t)
        p.temple_played_this_turn = True
        if c.temple_id == "eyrie_feathers":
            self._eyrie_etb(pid)
        self._check_power_win()

    def ring_legal_hosts(self, pid: int) -> list[tuple[str, int]]:
        """Return list of (host_kind, host_mid) pairs a ring can attach to."""
        p = self.players[pid]
        out: list[tuple[str, int]] = []
        for n in p.noble_field:
            out.append(("noble", n.mid))
        for b in p.bird_field:
            if b.nest_mid < 0:  # nested birds can't host (they can't have rings)
                out.append(("bird", b.mid))
        return out

    def play_ring(self, pid: int, hand_idx: int, host_kind: str, host_mid: int) -> None:
        p = self.players[pid]
        if self.pending is not None:
            return
        if not (0 <= hand_idx < len(p.hand)):
            return
        c = p.hand[hand_idx]
        if c.kind is not Kind.RING:
            return
        if RING_COST not in self.active_lanes(pid):
            return
        host = None
        if host_kind == "noble":
            host = next((n for n in p.noble_field if n.mid == host_mid), None)
        elif host_kind == "bird":
            host = next((b for b in p.bird_field if b.mid == host_mid and b.nest_mid < 0), None)
        if host is None:
            return
        p.hand.pop(hand_idx)
        self._note_non_ritual_play(pid, c)
        host.rings.append(c.ring_id)
        self._check_power_win()

    def _shed_rings_to_crypt(self, owner_pid: int, ring_ids: list[str]) -> None:
        p = self.players[owner_pid]
        for rid in ring_ids:
            p.crypt.append(Card(kind=Kind.RING, ring_id=rid, name=RING_DEFS.get(rid, {}).get("name", rid), cost=RING_COST))

    def _sac_total(self, pid: int, sac_mids: list[int]) -> int:
        p = self.players[pid]
        by_mid = {r.mid: r.value for r in p.field}
        seen: set[int] = set()
        total = 0
        for m in sac_mids:
            if m in seen or m not in by_mid:
                return -1
            seen.add(m)
            total += by_mid[m]
        return total

    def _sacrifice(self, pid: int, sac_mids: list[int]) -> None:
        p = self.players[pid]
        keep: list[Ritual] = []
        sacked_vals: list[int] = []
        ms = set(sac_mids)
        for r in p.field:
            if r.mid in ms:
                sacked_vals.append(r.value)
            else:
                keep.append(r)
        p.field = keep
        for v in sacked_vals:
            p.crypt.append(Card(kind=Kind.RITUAL, value=v))

    # --------------------------------------------------------------- incantation play

    def _wrath_zero_sac_ok(self, pid: int, sac_mids: Optional[list[int]]) -> bool:
        if not sac_mids or len(sac_mids) != 1:
            return False
        m = int(sac_mids[0])
        return any(r.mid == m for r in self.players[pid].field)

    def _wrath_instigator_sac_ok(
        self, pid: int, need_payment_sac: bool, payment_mids: set[int], ctx: dict
    ) -> bool:
        tx = ctx.get("wrath_instigator_sac_mid")
        if need_payment_sac:
            if tx is not None and int(tx) in payment_mids:
                return False
            return True
        if tx is None:
            return False
        txi = int(tx)
        p = self.players[pid]
        if not any(r.mid == txi for r in p.field):
            return False
        if txi in payment_mids:
            return False
        return True

    def play_incantation(self, pid: int, hand_idx: int, ctx: dict, sac_mids: Optional[list[int]] = None) -> None:
        p = self.players[pid]
        if self.pending is not None:
            return
        if not (0 <= hand_idx < len(p.hand)):
            return
        c = p.hand[hand_idx]
        if c.kind is not Kind.INCANTATION:
            return
        eff_val = self.effective_incantation_cost(pid, c.verb, c.value)
        if c.verb == VERB_WRATH:
            if not self._wrath_zero_sac_ok(pid, sac_mids):
                return
            need_payment_sac = True
        else:
            if not self._can_pay_value(pid, eff_val, sac_mids):
                return
            need_payment_sac = eff_val > 0 and eff_val not in self.active_lanes(pid)
        pay_set = set(sac_mids or [])
        if c.verb == VERB_WRATH:
            if not self._wrath_instigator_sac_ok(pid, need_payment_sac, pay_set, ctx):
                return
        if c.verb == VERB_RENEW:
            if "renew_second_ritual_crypt_idx" in ctx:
                return
            if "yytzr_extra_discard_hand_idx" in ctx:
                return
        if sac_mids:
            self._sacrifice(pid, sac_mids)
        card = p.hand.pop(hand_idx)
        self._note_non_ritual_play(pid, card)
        resolved = self._resolve_incantation_effect(pid, card, ctx)
        if resolved.get("to_abyss"):
            p.inc_abyss.append(card)
        else:
            p.crypt.append(card)
        if self.pending is None and bool(ctx.get("count_for_triggers", True)):
            self._post_effect_scion_trigger(pid, card.verb)
        self._check_power_win()

    def _can_pay_value(self, pid: int, value: int, sac_mids: Optional[list[int]]) -> bool:
        if value <= 0:
            return True
        if value in self.active_lanes(pid) and not sac_mids:
            return True
        if sac_mids is None:
            sac_mids = []
        return self._sac_total(pid, sac_mids) >= value

    def play_dethrone(self, pid: int, hand_idx: int, sac_mids: Optional[list[int]], target_mid: int) -> None:
        p = self.players[pid]
        if self.pending is not None:
            return
        if not (0 <= hand_idx < len(p.hand)):
            return
        c = p.hand[hand_idx]
        if not (c.kind is Kind.INCANTATION and c.verb == VERB_DETHRONE):
            return
        opp = self.players[self.opponent(pid)]
        if not opp.noble_field:
            return
        if not self._can_pay_value(pid, 4, sac_mids):
            return
        if sac_mids:
            self._sacrifice(pid, sac_mids)
        p.hand.pop(hand_idx)
        self._note_non_ritual_play(pid, c)
        self._destroy_noble(self.opponent(pid), target_mid)
        p.crypt.append(c)
        self._check_power_win()

    def _destroy_noble(self, owner_pid: int, mid: int) -> None:
        p = self.players[owner_pid]
        keep = []
        killed: Optional[Noble] = None
        for n in p.noble_field:
            if n.mid == mid and killed is None:
                killed = n
            else:
                keep.append(n)
        if killed is None and p.noble_field:
            killed = p.noble_field[0]
            keep = p.noble_field[1:]
        p.noble_field = keep
        if killed is not None:
            p.crypt.append(Card(kind=Kind.NOBLE, noble_id=killed.noble_id, cost=killed.cost,
                                name=NOBLE_DEFS[killed.noble_id]["name"]))
            if killed.rings:
                self._shed_rings_to_crypt(owner_pid, killed.rings)

    # --------------------------------------------------------------- effect resolution

    def _resolve_incantation_effect(self, pid: int, card: Card, ctx: dict) -> dict:
        verb = card.verb
        val = card.value
        cft = bool(ctx.get("count_for_triggers", True))
        if verb == VERB_SEEK:
            self._effect_seek(pid, val)
        elif verb == VERB_INSIGHT:
            target = ctx.get("insight_target", pid)
            self._effect_insight(pid, val, target, ctx, count_for_triggers=cft)
        elif verb == VERB_BURN:
            target = ctx.get("burn_target", self.opponent(pid))
            self._effect_burn(pid, val, target, count_for_triggers=cft)
        elif verb == VERB_WOE:
            target = ctx.get("woe_target", self.opponent(pid))
            self._effect_woe(pid, val, target, ctx)
        elif verb == VERB_WRATH:
            self._effect_wrath(pid, val, ctx)
        elif verb == VERB_REVIVE:
            return self._effect_revive(pid, val, ctx, count_for_triggers=cft)
        elif verb == VERB_RENEW:
            self._effect_renew(pid, ctx)
            return {}
        elif verb == VERB_DELUGE:
            self._effect_deluge(pid, val)
        elif verb == VERB_TEARS:
            self._effect_tears(pid, ctx)
        elif verb == VERB_FLIGHT:
            self._effect_flight(pid)
        return {}

    def _effect_seek(self, pid: int, n: int) -> None:
        extra = 1 if self.has_noble(pid, "xytzr_emanation") else 0
        self._draw_n(pid, n + extra, can_lose=True)

    def _effect_insight(self, pid: int, n: int, target_pid: int, ctx: dict, count_for_triggers: bool = True) -> None:
        extra = 1 if self.has_noble(pid, "xytzr_emanation") else 0
        eff = n + extra
        tgt = self.players[target_pid]
        take = min(eff, len(tgt.deck))
        if take <= 0:
            return
        top = tgt.deck[-take:]
        tgt.deck[-take:] = []
        if "insight_top" in ctx or "insight_bottom" in ctx:
            top_idx = [int(i) for i in ctx.get("insight_top", [])]
            bottom_idx = [int(i) for i in ctx.get("insight_bottom", [])]
            seen: set[int] = set()
            valid = len(top_idx) + len(bottom_idx) == take
            if valid:
                for i in top_idx + bottom_idx:
                    if i < 0 or i >= take or i in seen:
                        valid = False
                        break
                    seen.add(i)
            if valid:
                # top[] is in deck order (oldest -> newest), so index from reveal order (newest first).
                reveal = top[::-1]
                for i in range(len(top_idx) - 1, -1, -1):
                    tgt.deck.append(reveal[top_idx[i]])
                for i in bottom_idx:
                    tgt.deck.insert(0, reveal[i])
                if count_for_triggers:
                    self._post_effect_scion_trigger(pid, VERB_INSIGHT)
                return
        send_bottom = int(ctx.get("insight_bottom", 0))
        send_bottom = max(0, min(send_bottom, take))
        bottom_cards = top[:send_bottom]
        keep_top = top[send_bottom:]
        for c in bottom_cards:
            tgt.deck.insert(0, c)
        tgt.deck.extend(keep_top)
        if count_for_triggers:
            self._post_effect_scion_trigger(pid, VERB_INSIGHT)

    def _effect_burn(self, pid: int, n: int, target_pid: int, count_for_triggers: bool = True) -> None:
        extra = 3 if self.has_noble(pid, "yytzr_occultation") else 0
        self._mill(target_pid, 2 * n + extra)
        if count_for_triggers:
            self._post_effect_scion_trigger(pid, VERB_BURN)

    def _effect_woe(self, pid: int, n: int, target_pid: int, ctx: dict) -> None:
        extra = 1 if self.has_noble(pid, "zytzr_annihilation") else 0
        base = max(n - 1, 0)
        need = base + extra
        victim = self.players[target_pid]
        need = min(need, len(victim.hand))
        if need <= 0:
            return
        if target_pid == pid:
            chosen = list(ctx.get("woe_indices", []))[:need]
            chosen = sorted(set(chosen), reverse=True)
            chosen = [i for i in chosen if 0 <= i < len(victim.hand)]
            if len(chosen) < need and need > 0:
                remaining = need - len(chosen)
                others = [i for i in range(len(victim.hand) - 1, -1, -1) if i not in chosen]
                chosen.extend(others[:remaining])
                chosen.sort(reverse=True)
            for i in chosen:
                victim.crypt.append(victim.hand.pop(i))
        else:
            self.pending = Pending(
                kind="woe",
                responder=target_pid,
                payload={
                    "need": need,
                    "instigator": pid,
                    "skip_woe_tmrsk": bool(ctx.get("skip_woe_tmrsk", False)),
                },
            )

    def _effect_wrath(self, pid: int, n: int, ctx: dict) -> None:
        if n not in (0, 4):
            return
        destroy_count = 1 + (1 if self.has_noble(pid, "zytzr_annihilation") else 0)
        opp_pid = self.opponent(pid)
        opp = self.players[opp_pid]
        targets: list[int] = list(ctx.get("wrath_targets", []))
        mids = []
        for m in targets:
            if any(r.mid == m for r in opp.field) and m not in mids:
                mids.append(m)
        while len(mids) < destroy_count and len(mids) < len(opp.field):
            remaining = [r for r in opp.field if r.mid not in mids]
            if not remaining:
                break
            remaining.sort(key=lambda r: r.value)
            mids.append(remaining[0].mid)
        killed_vals: list[int] = []
        keep: list[Ritual] = []
        for r in opp.field:
            if r.mid in mids:
                killed_vals.append(r.value)
            else:
                keep.append(r)
        opp.field = keep
        for v in killed_vals:
            opp.crypt.append(Card(kind=Kind.RITUAL, value=v))
        self._post_effect_scion_trigger(pid, VERB_WRATH)

    def _effect_revive(self, pid: int, n: int, ctx: dict, count_for_triggers: bool = True) -> dict:
        p = self.players[pid]
        crypt_inc_indices = [i for i, c in enumerate(p.crypt)
                             if c.kind is Kind.INCANTATION and c.verb not in (VERB_REVIVE, VERB_TEARS, VERB_DETHRONE)]
        if not crypt_inc_indices:
            return {}
        picked_idx: Optional[int] = ctx.get("revive_crypt_idx")
        if picked_idx is None or picked_idx not in crypt_inc_indices:
            p.crypt.sort(key=lambda c: (0, 0))  # no-op to avoid lint
            picked_idx = self._pick_best_revive_target(pid, crypt_inc_indices)
            if picked_idx is None:
                return {}
        sub = p.crypt.pop(picked_idx)
        sub_ctx = dict(ctx.get("revive_sub_ctx", {}))
        sub_ctx.setdefault("insight_target", self.opponent(pid))
        sub_ctx.setdefault("burn_target", self.opponent(pid))
        sub_ctx.setdefault("woe_target", self.opponent(pid))
        self._resolve_incantation_effect(pid, sub, sub_ctx)
        yytzr_renew_idx = ctx.get("yytzr_renew_ritual_crypt_idx")
        if yytzr_renew_idx is not None and self.has_noble(pid, "yytzr_occultation"):
            ritual_indices = [i for i, c in enumerate(p.crypt) if c.kind is Kind.RITUAL]
            yidx = int(yytzr_renew_idx)
            if 0 <= yidx < len(ritual_indices):
                rc = p.crypt.pop(ritual_indices[yidx])
                p.field.append(Ritual(mid=self.mid(), value=rc.value))
                if count_for_triggers:
                    self._post_effect_scion_trigger(pid, VERB_RENEW)
        if self.pending is None:
            p.inc_abyss.append(sub)
            if count_for_triggers:
                self._post_effect_scion_trigger(pid, VERB_REVIVE)
        else:
            self.pending.payload["revive_subcast"] = sub
        return {}

    def _pick_best_revive_target(self, pid: int, indices: list[int]) -> Optional[int]:
        p = self.players[pid]
        best = None
        best_score = -1
        for i in indices:
            c = p.crypt[i]
            score = c.value
            if c.verb == VERB_SEEK:
                score += 2
            elif c.verb == VERB_INSIGHT:
                score += 1
            elif c.verb == VERB_BURN:
                score += 1
            elif c.verb == VERB_WOE:
                score += 2
            if score > best_score:
                best_score = score
                best = i
        return best

    def _effect_renew(self, pid: int, ctx: dict) -> None:
        p = self.players[pid]
        ritual_indices = [i for i, c in enumerate(p.crypt) if c.kind is Kind.RITUAL]
        if not ritual_indices:
            return
        rf = ctx.get("renew_ritual_crypt_idx")
        if rf is None:
            return
        rf = int(rf)
        if rf < 0 or rf >= len(ritual_indices):
            return
        g0 = ritual_indices[rf]
        if "renew_second_ritual_crypt_idx" in ctx:
            return
        c = p.crypt.pop(g0)
        p.field.append(Ritual(mid=self.mid(), value=c.value))

    def _effect_deluge(self, pid: int, n: int) -> None:
        threshold = n - 1
        for q in (0, 1):
            p = self.players[q]
            keep = []
            for b in p.bird_field:
                if b.power <= threshold and b.nest_mid < 0:
                    p.crypt.append(Card(kind=Kind.BIRD, bird_id=b.bird_id, cost=b.cost, power=b.power,
                                        name=BIRD_DEFS[b.bird_id]["name"]))
                    if b.rings:
                        self._shed_rings_to_crypt(q, b.rings)
                else:
                    keep.append(b)
            p.bird_field = keep
            for b in p.bird_field:
                b.nest_mid = -1
            for t in p.temple_field:
                if t.nested:
                    t.nested = []

    def _effect_tears(self, pid: int, ctx: dict) -> None:
        p = self.players[pid]
        idx = ctx.get("tears_idx")
        if idx is None:
            for i, c in enumerate(p.crypt):
                if c.kind is Kind.BIRD:
                    idx = i
                    break
        if idx is None or idx < 0 or idx >= len(p.crypt):
            return
        c = p.crypt[idx]
        if c.kind is not Kind.BIRD:
            return
        p.crypt.pop(idx)
        p.bird_field.append(Bird(mid=self.mid(), bird_id=c.bird_id, cost=c.cost, power=c.power))

    def _effect_flight(self, pid: int) -> None:
        self._draw_n(pid, len(self.players[pid].bird_field), can_lose=True)

    # --------------------------------------------------------------- scion triggers

    def _post_effect_scion_trigger(self, pid: int, verb: str) -> None:
        if self.pending is not None:
            return
        if verb == VERB_INSIGHT and self.has_noble(pid, "rmrsk_emanation"):
            self.pending = Pending(kind="scion", responder=pid, payload={"scion": "rmrsk", "trigger_verb": verb})
        elif verb in (VERB_BURN, VERB_REVIVE, VERB_RENEW) and self.has_noble(pid, "smrsk_occultation"):
            if any(True for _ in self.players[pid].field):
                self.pending = Pending(kind="scion", responder=pid, payload={"scion": "smrsk", "trigger_verb": verb})
        elif verb == VERB_WRATH and self.has_noble(pid, "tmrsk_annihilation"):
            self.pending = Pending(kind="scion", responder=pid, payload={"scion": "tmrsk", "trigger_verb": verb})
        elif verb == VERB_WOE and self.has_noble(pid, "tmrsk_annihilation"):
            pass

    # --------------------------------------------------------------- responses

    def submit_woe_discard(self, victim_pid: int, indices: list[int]) -> None:
        if self.pending is None or self.pending.kind != "woe" or self.pending.responder != victim_pid:
            return
        payload = self.pending.payload
        need = payload["need"]
        instigator = payload["instigator"]
        p = self.players[victim_pid]
        chosen = sorted(set(indices), reverse=True)
        chosen = [i for i in chosen if 0 <= i < len(p.hand)]
        chosen = chosen[:need]
        for i in chosen:
            p.crypt.append(p.hand.pop(i))
        if "revive_subcast" in payload:
            p_inst = self.players[instigator]
            p_inst.inc_abyss.append(payload["revive_subcast"])
        self.pending = None
        if not bool(payload.get("skip_woe_tmrsk", False)):
            self._post_effect_scion_trigger(instigator, VERB_WOE)
        self._check_power_win()

    def submit_scion_trigger(self, pid: int, accept: bool, ctx: Optional[dict] = None) -> None:
        if self.pending is None or self.pending.kind != "scion" or self.pending.responder != pid:
            return
        payload = self.pending.payload
        scion = payload["scion"]
        self.pending = None
        if not accept:
            self._check_power_win()
            return
        if scion == "rmrsk":
            self._draw_n(pid, 1, can_lose=True)
        elif scion == "smrsk":
            p = self.players[pid]
            if not p.field:
                return
            sac_mid = (ctx or {}).get("sac_mid")
            r = None
            if sac_mid is not None:
                for rr in p.field:
                    if rr.mid == sac_mid:
                        r = rr
                        break
            if r is None:
                p.field.sort(key=lambda rr: rr.value)
                r = p.field[0]
            x = r.value
            p.field = [rr for rr in p.field if rr.mid != r.mid]
            p.crypt.append(Card(kind=Kind.RITUAL, value=x))
            self._mill(pid, 2 * x)
        elif scion == "tmrsk":
            target = (ctx or {}).get("woe_target", self.opponent(pid))
            self._effect_woe(pid, 3, target, {})
        self._check_power_win()

    # --------------------------------------------------------------- Eyrie

    def _eyrie_etb(self, pid: int) -> None:
        p = self.players[pid]
        deck_bird_indices = [i for i, c in enumerate(p.deck) if c.kind is Kind.BIRD]
        take = deck_bird_indices[:1]
        if not take:
            self.rng.shuffle(p.deck)
            return
        take_sorted = sorted(take, reverse=True)
        pulled: list[Card] = []
        for i in take_sorted:
            pulled.append(p.deck.pop(i))
        for c in pulled:
            p.bird_field.append(Bird(mid=self.mid(), bird_id=c.bird_id, cost=c.cost, power=c.power))
        self.rng.shuffle(p.deck)

    # --------------------------------------------------------------- activations

    def activate_noble(self, pid: int, noble_mid: int, ctx: Optional[dict] = None) -> None:
        if self.pending is not None:
            return
        p = self.players[pid]
        n = next((x for x in p.noble_field if x.mid == noble_mid), None)
        if n is None or n.used_turn == self.turn_number:
            return
        ctx = ctx or {}
        info = NOBLE_DEFS.get(n.noble_id, {})
        verb = info.get("activated_verb")
        val = info.get("activated_value", 0)
        if n.noble_id == "aeoiu_rituals":
            ritual_mids = [i for i, c in enumerate(p.crypt) if c.kind is Kind.RITUAL]
            idx = ctx.get("crypt_ritual_idx")
            if idx is None:
                p_crypt = p.crypt
                best = None
                best_val = -1
                for i in ritual_mids:
                    if p_crypt[i].value > best_val:
                        best_val = p_crypt[i].value
                        best = i
                idx = best
            if idx is None or idx < 0 or idx >= len(p.crypt) or p.crypt[idx].kind is not Kind.RITUAL:
                return
            card = p.crypt.pop(idx)
            p.field.append(Ritual(mid=self.mid(), value=card.value))
            n.used_turn = self.turn_number
            self._check_power_win()
            return
        if verb is None:
            return
        ndrr = n.noble_id in (
            "indrr_incantation",
            "bndrr_incantation",
            "wndrr_incantation",
            "sndrr_incantation",
            "rndrr_incantation",
        )
        ctx_use = dict(ctx)
        if ndrr:
            ctx_use["count_for_triggers"] = False
        if n.noble_id == "wndrr_incantation":
            ctx_use["skip_woe_tmrsk"] = True
        if info.get("activation_discard"):
            if not p.hand:
                return
            di = ctx_use.get("discard_hand_idx", 0)
            if not (0 <= di < len(p.hand)):
                return
            p.crypt.append(p.hand.pop(di))
        pseudo = Card(kind=Kind.INCANTATION, verb=verb, value=val)
        self._resolve_incantation_effect(pid, pseudo, ctx_use)
        n.used_turn = self.turn_number
        if self.pending is not None:
            self.pending.payload["noble_activation_mid"] = n.mid
        elif not ndrr:
            self._post_effect_scion_trigger(pid, verb)
        self._check_power_win()

    def activate_temple(self, pid: int, temple_mid: int, ctx: Optional[dict] = None) -> None:
        if self.pending is not None:
            return
        p = self.players[pid]
        t = next((x for x in p.temple_field if x.mid == temple_mid), None)
        if t is None or t.used_turn == self.turn_number:
            return
        ctx = ctx or {}
        if t.temple_id == "phaedra_illusion":
            target = ctx.get("insight_target", self.opponent(pid))
            self._effect_insight(pid, 1, target, ctx, count_for_triggers=False)
            self._draw_n(pid, 1, can_lose=True)
            t.used_turn = self.turn_number
        elif t.temple_id == "delpha_oracles":
            ritual_mid = ctx.get("ritual_mid")
            r = next((x for x in p.field if x.mid == ritual_mid), None) if ritual_mid is not None else None
            if r is None:
                return
            x = r.value
            crypt_ritual_idx = ctx.get("crypt_ritual_idx")
            if crypt_ritual_idx is None:
                best = None
                best_val = -1
                for i, c in enumerate(p.crypt):
                    if c.kind is Kind.RITUAL and c.value > best_val:
                        best_val = c.value
                        best = i
                crypt_ritual_idx = best
            if crypt_ritual_idx is None:
                return
            p.field = [rr for rr in p.field if rr.mid != r.mid]
            p.inc_abyss.append(Card(kind=Kind.RITUAL, value=x))
            self._mill(pid, 2 * x)
            if 0 <= crypt_ritual_idx < len(p.crypt) and p.crypt[crypt_ritual_idx].kind is Kind.RITUAL:
                card = p.crypt.pop(crypt_ritual_idx)
                p.field.append(Ritual(mid=self.mid(), value=card.value))
            t.used_turn = self.turn_number
        elif t.temple_id == "gotha_illness":
            hi = ctx.get("hand_idx", -1)
            if not (0 <= hi < len(p.hand)):
                return
            card = p.hand[hi]
            if card.kind is Kind.TEMPLE:
                return
            draw_n = 0
            if card.kind is Kind.RITUAL or card.kind is Kind.INCANTATION:
                draw_n = card.value
            elif card.kind is Kind.NOBLE:
                draw_n = card.cost
            elif card.kind is Kind.BIRD:
                draw_n = card.cost
            elif card.kind is Kind.RING:
                draw_n = card.cost
            p.hand.pop(hi)
            p.crypt.append(card)
            if draw_n > 0:
                self._draw_n(pid, draw_n, can_lose=True)
            t.used_turn = self.turn_number
        elif t.temple_id == "ytria_cycles":
            count = len(p.hand)
            p.crypt.extend(p.hand)
            p.hand.clear()
            if count > 0:
                self._draw_n(pid, count, can_lose=True)
            t.used_turn = self.turn_number
        self._check_power_win()

    # --------------------------------------------------------------- nesting

    def nest_bird(self, pid: int, bird_mid: int, temple_mid: int) -> None:
        if self.pending is not None:
            return
        p = self.players[pid]
        if p.bird_nested_this_turn:
            return
        b = next((x for x in p.bird_field if x.mid == bird_mid and x.nest_mid < 0), None)
        t = next((x for x in p.temple_field if x.mid == temple_mid), None)
        if b is None or t is None:
            return
        if b.rings:
            return
        if len(t.nested) >= t.cost:
            return
        b.nest_mid = t.mid
        t.nested.append(b.mid)
        p.bird_nested_this_turn = True
        self._check_power_win()

    # --------------------------------------------------------------- bird combat

    def bird_fight_simple(self, pid: int, attacker_mid: int, defender_mid: int) -> None:
        if self.pending is not None:
            return
        p = self.players[pid]
        if p.bird_fight_used:
            return
        opp_pid = self.opponent(pid)
        opp = self.players[opp_pid]
        atk = next((b for b in p.bird_field if b.mid == attacker_mid and b.nest_mid < 0), None)
        dfn = next((b for b in opp.bird_field if b.mid == defender_mid and b.nest_mid < 0), None)
        if atk is None or dfn is None:
            return
        atk.damage += dfn.power
        dfn.damage += atk.power
        self._cleanup_dead_birds(pid)
        self._cleanup_dead_birds(opp_pid)
        p.bird_fight_used = True
        self._check_power_win()

    def _cleanup_dead_birds(self, pid: int) -> None:
        p = self.players[pid]
        live: list[Bird] = []
        for b in p.bird_field:
            if b.damage >= b.power:
                p.crypt.append(Card(kind=Kind.BIRD, bird_id=b.bird_id, cost=b.cost, power=b.power,
                                    name=BIRD_DEFS[b.bird_id]["name"]))
                if b.rings:
                    self._shed_rings_to_crypt(pid, b.rings)
            else:
                b.damage = 0
                live.append(b)
        p.bird_field = live

    # --------------------------------------------------------------- discard for draw

    def discard_for_draw(self, pid: int, hand_idx: int) -> None:
        if self.pending is not None:
            return
        p = self.players[pid]
        if p.discard_draw_used:
            return
        if not (0 <= hand_idx < len(p.hand)):
            return
        p.crypt.append(p.hand.pop(hand_idx))
        p.discard_draw_used = True
        self._draw_n(pid, 1, can_lose=True)
        self._check_power_win()

