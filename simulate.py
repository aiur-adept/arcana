import json
import math
import random
import statistics
from dataclasses import dataclass, field
from enum import Enum, auto
from multiprocessing import Pool, cpu_count
from pathlib import Path
from typing import List, Dict, Tuple, Optional, Any


# --------- Core data structures ---------

class CardType(Enum):
    RITUAL = auto()
    INCANTATION = auto()
    NOBLE = auto()
    DETHRONE = auto()


@dataclass
class Card:
    type: CardType
    value: int = 0           # cost / ritual value
    verb: Optional[str] = None
    noble_id: Optional[str] = None
    name: Optional[str] = None


@dataclass
class PlayerState:
    deck: List[Card] = field(default_factory=list)
    hand: List[Card] = field(default_factory=list)
    rituals: List[int] = field(default_factory=list)           # ritual values on field
    nobles: List[Card] = field(default_factory=list)
    crypt: List[Card] = field(default_factory=list)
    inc_abyss: List[Card] = field(default_factory=list)
    deck_crypt: List[Card] = field(default_factory=list)
    noble_used_this_turn: Dict[str, bool] = field(default_factory=dict)

    def reset_turn_flags(self) -> None:
        self.noble_used_this_turn.clear()


WIN_POWER = 20
START_HAND = 5
MAX_HAND_END = 7


# --------- Deck loading ---------

def load_decks(base_dir: Path) -> List[List[Card]]:
    path = base_dir / "included_decks.json"
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    out: List[List[Card]] = []
    for d in data.get("decks", []):
        cards_raw = d.get("cards") or d.get("payload", {}).get("cards", [])
        deck: List[Card] = []
        for c in cards_raw:
            ctype = str(c.get("type", "")).lower()
            if ctype == "ritual":
                deck.append(Card(type=CardType.RITUAL, value=int(c.get("value", 0))))
            elif ctype == "incantation":
                deck.append(
                    Card(
                        type=CardType.INCANTATION,
                        value=int(c.get("value", 0)),
                        verb=str(c.get("verb", "")).lower() or None,
                    )
                )
            elif ctype == "noble":
                deck.append(
                    Card(
                        type=CardType.NOBLE,
                        noble_id=str(c.get("noble_id", "")).lower() or None,
                        name=c.get("name"),
                    )
                )
            elif ctype == "dethrone":
                deck.append(Card(type=CardType.DETHRONE, value=int(c.get("value", 0))))
        if len(deck) == 40:
            out.append(deck)
    if not out:
        raise RuntimeError("No valid 40-card decks found in included_decks.json")
    return out


# --------- Ritual activity and lanes ---------

def active_mask_for_field(rituals: List[int]) -> List[bool]:
    n = len(rituals)
    if n == 0:
        return []
    active = [False] * n
    order = list(range(n))
    order.sort(key=lambda i: rituals[i])
    for idx in order:
        v = rituals[idx]
        if v == 1:
            active[idx] = True
        else:
            ok = True
            for k in range(1, v):
                found = False
                for j in range(n):
                    if rituals[j] == k and active[j]:
                        found = True
                        break
                if not found:
                    ok = False
                    break
            active[idx] = ok
    return active


def ritual_power(rituals: List[int]) -> int:
    act = active_mask_for_field(rituals)
    return sum(v for v, a in zip(rituals, act) if a)


def has_lane(rituals: List[int], lane: int) -> bool:
    act = active_mask_for_field(rituals)
    for v, a in zip(rituals, act):
        if v == lane and a:
            return True
    return False


# --------- Noble helpers (simplified passives) ---------

def extra_incantation_lanes_from_nobles(nobles: List[Card]) -> List[int]:
    lanes: set[int] = set()
    for n in nobles:
        nid = (n.noble_id or "").lower()
        if nid == "krss_power":
            lanes.add(1)
        elif nid == "trss_power":
            lanes.add(2)
        elif nid == "yrss_power":
            lanes.add(3)
    return sorted(lanes)


def has_active_incantation_lane(p: PlayerState, n: int) -> bool:
    if has_lane(p.rituals, n):
        return True
    return n in extra_incantation_lanes_from_nobles(p.nobles)


def noble_cost(nid: Optional[str]) -> int:
    nid = (nid or "").lower()
    if not nid:
        return 0
    # Based on design doc and GDScript definitions
    if nid in {
        "krss_power",
        "trss_power",
        "yrss_power",
        "xytzr_emanation",
        "yytzr_occultation",
        "zytzr_annihilation",
        "aeoiu_rituals",
    }:
        return 4
    if nid in {
        "bndrr_incantation",
        "indrr_incantation",
        "rndrr_incantation",
        "sndrr_incantation",
        "wndrr_incantation",
        "rmrsk_emanation",
        "smrsk_occultation",
        "tmrsk_annihilation",
    }:
        return 3
    return 0


def noble_on_field(nobles: List[Card], nid: str) -> bool:
    nid = nid.lower()
    return any((n.noble_id or "").lower() == nid for n in nobles)


# --------- Sacrifice helpers ---------

def can_sacrifice(rituals: List[int], need: int) -> bool:
    return sum(rituals) >= need


def greedy_sacrifice_indices(rituals: List[int], need: int) -> List[int]:
    indexed = list(enumerate(rituals))
    indexed.sort(key=lambda kv: kv[1])  # lowest first
    out: List[int] = []
    total = 0
    for idx, v in indexed:
        out.append(idx)
        total += v
        if total >= need:
            return out
    return []


def apply_sacrifice(p: PlayerState, indices: List[int]) -> None:
    if not indices:
        return
    kill = set(indices)
    keep: List[int] = []
    for i, v in enumerate(p.rituals):
        if i in kill:
            p.crypt.append(Card(type=CardType.RITUAL, value=v))
        else:
            keep.append(v)
    p.rituals = keep


# --------- Game mechanics ---------

def draw_one(p: PlayerState) -> bool:
    if not p.deck:
        return False
    p.hand.append(p.deck.pop())
    return True


def draw_n(p: PlayerState, n: int) -> None:
    for _ in range(n):
        if not draw_one(p):
            break


def mill(p: PlayerState, x: int) -> None:
    n = min(x, len(p.deck))
    for _ in range(n):
        p.deck_crypt.append(p.deck.pop())


def mulligan_decision(hand: List[Card]) -> bool:
    rituals = sum(1 for c in hand if c.type == CardType.RITUAL)
    return rituals <= 1


def do_london_mulligan(p: PlayerState, rng: random.Random) -> None:
    if not mulligan_decision(p.hand):
        return
    p.deck.extend(p.hand)
    p.hand.clear()
    rng.shuffle(p.deck)
    for _ in range(START_HAND):
        draw_one(p)
    if p.hand:
        idx = rng.randrange(len(p.hand))
        card = p.hand.pop(idx)
        p.deck.insert(0, card)


# --------- Spell application (simplified) ---------

def effective_wrath_destroy_count(p: PlayerState) -> int:
    base = 2  # Wrath 4
    if noble_on_field(p.nobles, "zytzr_annihilation"):
        return base + 1
    return base


def apply_incantation(
    verb: str,
    value: int,
    self_p: PlayerState,
    opp_p: PlayerState,
    rng: random.Random,
    depth: int = 0,
) -> None:
    if depth > 2:
        return
    v = verb.lower()
    if v == "seek":
        n = value
        if noble_on_field(self_p.nobles, "xytzr_emanation"):
            n += 1
        draw_n(self_p, n)
    elif v == "insight":
        # Reordering ignored; impact is minor for bulk stats
        pass
    elif v == "burn":
        mill_n = value * 2
        if noble_on_field(self_p.nobles, "yytzr_occultation"):
            mill_n += 3
        mill(opp_p, mill_n)
    elif v == "woe":
        need = min(value, len(opp_p.hand))
        if noble_on_field(self_p.nobles, "zytzr_annihilation"):
            need = min(need + 1, len(opp_p.hand))
        if need > 0:
            idxs = list(range(len(opp_p.hand)))
            rng.shuffle(idxs)
            idxs = idxs[:need]
            for i in sorted(idxs, reverse=True):
                opp_p.crypt.append(opp_p.hand.pop(i))
    elif v == "wrath":
        if not opp_p.rituals:
            return
        destroy = min(effective_wrath_destroy_count(self_p), len(opp_p.rituals))
        if destroy <= 0:
            return
        indexed = list(enumerate(opp_p.rituals))
        indexed.sort(key=lambda kv: kv[1])
        kill_indices = [idx for idx, _ in indexed[:destroy]]
        new_rit: List[int] = []
        for i, val in enumerate(opp_p.rituals):
            if i in kill_indices:
                opp_p.crypt.append(Card(type=CardType.RITUAL, value=val))
            else:
                new_rit.append(val)
        opp_p.rituals = new_rit
    elif v == "revive":
        incs_from_crypt = [c for c in self_p.crypt if c.type == CardType.INCANTATION]
        if not incs_from_crypt:
            return
        c = rng.choice(incs_from_crypt)
        if (c.verb or "").lower() in {"wrath"}:
            return
        self_p.crypt.remove(c)
        if c.type == CardType.INCANTATION:
            apply_incantation(c.verb or "", int(c.value), self_p, opp_p, rng, depth + 1)
            self_p.inc_abyss.append(c)
        elif c.type == CardType.NOBLE:
            self_p.nobles.append(c)
            self_p.inc_abyss.append(c)


# --------- Noble activation (simplified) ---------

def can_activate_noble(n: Card, p: PlayerState) -> bool:
    nid = (n.noble_id or "").lower()
    if p.noble_used_this_turn.get(nid, False):
        return False
    if nid in {
        "bndrr_incantation",
        "wndrr_incantation",
        "sndrr_incantation",
        "rndrr_incantation",
        "indrr_incantation",
        "aeoiu_rituals",
    }:
        return True
    return False


def activate_noble(n: Card, self_p: PlayerState, opp_p: PlayerState, rng: random.Random) -> None:
    nid = (n.noble_id or "").lower()
    if nid == "bndrr_incantation":
        apply_incantation("burn", 1, self_p, opp_p, rng)
    elif nid == "wndrr_incantation":
        apply_incantation("woe", 1, self_p, opp_p, rng)
    elif nid == "sndrr_incantation":
        apply_incantation("seek", 1, self_p, opp_p, rng)
    elif nid == "indrr_incantation":
        apply_incantation("insight", 2, self_p, opp_p, rng)
    elif nid == "rndrr_incantation":
        apply_incantation("revive", 1, self_p, opp_p, rng)
    elif nid == "aeoiu_rituals":
        rituals_in_crypt = [c for c in self_p.crypt if c.type == CardType.RITUAL]
        if rituals_in_crypt:
            c = rituals_in_crypt[0]
            self_p.crypt.remove(c)
            self_p.rituals.append(c.value)
    self_p.noble_used_this_turn[nid] = True


# --------- Turn AI ---------

def choose_dethrone_target(opp: PlayerState, rng: random.Random) -> Optional[int]:
    if not opp.nobles:
        return None
    return rng.randrange(len(opp.nobles))


def destroy_noble(opp: PlayerState, idx: int) -> None:
    if idx < 0 or idx >= len(opp.nobles):
        return
    opp.crypt.append(opp.nobles.pop(idx))


def ai_play_turn(
    p: PlayerState,
    opp: PlayerState,
    rng: random.Random,
    discard_draw_used: bool,
) -> Tuple[bool, bool, int]:
    ritual_played = False
    noble_played = False
    noble_activations = 0

    # One ritual
    if not ritual_played:
        best_idx = -1
        best_val = -1
        for i, c in enumerate(p.hand):
            if c.type != CardType.RITUAL:
                continue
            if c.value > best_val:
                best_val = c.value
                best_idx = i
        if best_idx >= 0:
            c = p.hand.pop(best_idx)
            p.rituals.append(c.value)
            ritual_played = True

    # One noble
    if not noble_played:
        for i, c in enumerate(p.hand):
            if c.type != CardType.NOBLE:
                continue
            cost = noble_cost(c.noble_id)
            if cost <= 0 or has_lane(p.rituals, cost):
                p.hand.pop(i)
                p.nobles.append(c)
                noble_played = True
                break

    # Noble activations (spell-like)
    for n in list(p.nobles):
        if not can_activate_noble(n, p):
            continue
        activate_noble(n, p, opp, rng)
        noble_activations += 1

    # Incantations and dethrone as long as possible
    while True:
        playable_indices: List[int] = []
        priorities: List[int] = []  # lower is higher priority

        for idx, c in enumerate(p.hand):
            if c.type == CardType.DETHRONE:
                if not opp.nobles:
                    continue
                cost = c.value
                if has_lane(p.rituals, cost) or can_sacrifice(p.rituals, cost):
                    playable_indices.append(idx)
                    priorities.append(0)
            elif c.type == CardType.INCANTATION:
                n = c.value
                if n < 1:
                    continue
                lane_ok = has_active_incantation_lane(p, n)
                need_sac = not lane_ok
                if need_sac and not can_sacrifice(p.rituals, n):
                    continue
                v = (c.verb or "").lower()
                if v == "wrath" and not opp.rituals:
                    continue
                if v == "woe" and not opp.hand:
                    continue
                if v == "burn" and not opp.deck:
                    continue
                if v == "revive" and not p.crypt:
                    continue
                if v == "seek":
                    prio = 2
                elif v == "insight":
                    prio = 4
                elif v == "burn":
                    prio = 1
                elif v == "woe":
                    prio = 1
                elif v == "wrath":
                    prio = 0
                elif v == "revive":
                    prio = 3
                else:
                    prio = 5
                playable_indices.append(idx)
                priorities.append(prio)

        if not playable_indices:
            break

        # Choose best priority, then random among equals
        best_prio = min(priorities)
        cand = [i for i, p_ in zip(playable_indices, priorities) if p_ == best_prio]
        play_idx = rng.choice(cand)
        card = p.hand.pop(play_idx)

        if card.type == CardType.DETHRONE:
            cost = card.value
            if not has_lane(p.rituals, cost) and can_sacrifice(p.rituals, cost):
                sac_idxs = greedy_sacrifice_indices(p.rituals, cost)
                apply_sacrifice(p, sac_idxs)
            tgt = choose_dethrone_target(opp, rng)
            if tgt is not None:
                destroy_noble(opp, tgt)
            p.crypt.append(card)
        elif card.type == CardType.INCANTATION:
            n = card.value
            lane_ok = has_active_incantation_lane(p, n)
            if not lane_ok:
                sac_idxs = greedy_sacrifice_indices(p.rituals, n)
                apply_sacrifice(p, sac_idxs)
            v = (card.verb or "").lower()
            apply_incantation(v, n, p, opp, rng)
            p.crypt.append(card)

    # Optional discard-for-draw (50/50)
    if not discard_draw_used and p.hand and rng.random() < 0.5:
        di = rng.randrange(len(p.hand))
        p.crypt.append(p.hand.pop(di))
        draw_one(p)
        discard_draw_used = True

    # End-of-turn discard to 7
    if len(p.hand) > MAX_HAND_END:
        extra = len(p.hand) - MAX_HAND_END
        # discard highest-value cards first
        idxs = list(range(len(p.hand)))
        idxs.sort(key=lambda i: (p.hand[i].value if p.hand[i].type != CardType.NOBLE else 0), reverse=True)
        for i in idxs[:extra]:
            # recompute index each time because we mutate
            if not p.hand:
                break
            j = min(i, len(p.hand) - 1)
            p.crypt.append(p.hand.pop(j))

    return ritual_played, noble_played, noble_activations


# --------- Single game simulation ---------

@dataclass
class GameStats:
    winner: int  # 0, 1, or -1 draw
    starting_player: int
    turns: int
    end_reason: str  # "power", "deck", "draw"
    power_history: List[Tuple[int, int, int]]  # (turn_no, p0_power, p1_power)
    p0_crypt_end: int
    p1_crypt_end: int
    p0_abyss_end: int
    p1_abyss_end: int
    total_noble_activations: int


def simulate_single_game(
    decks: List[List[Card]],
    rng: random.Random,
) -> GameStats:
    deck0 = [Card(**vars(c)) for c in rng.choice(decks)]
    deck1 = [Card(**vars(c)) for c in rng.choice(decks)]

    rng.shuffle(deck0)
    rng.shuffle(deck1)

    p0 = PlayerState(deck=deck0)
    p1 = PlayerState(deck=deck1)

    for _ in range(START_HAND):
        draw_one(p0)
        draw_one(p1)

    do_london_mulligan(p0, rng)
    do_london_mulligan(p1, rng)

    starting_player = rng.randrange(2)
    current = starting_player

    winner = -1
    end_reason = "draw"
    turns = 0
    power_history: List[Tuple[int, int, int]] = []
    total_noble_activations = 0

    discard_draw_used = False

    while True:
        turns += 1
        for player_idx in (current, 1 - current):
            p = p0 if player_idx == 0 else p1
            opp = p1 if player_idx == 0 else p0

            if not draw_one(p):
                pw0 = ritual_power(p0.rituals)
                pw1 = ritual_power(p1.rituals)
                if pw0 > pw1:
                    winner = 0
                    end_reason = "deck"
                elif pw1 > pw0:
                    winner = 1
                    end_reason = "deck"
                else:
                    winner = -1
                    end_reason = "deck"
                power_history.append((turns, pw0, pw1))
                return GameStats(
                    winner=winner,
                    starting_player=starting_player,
                    turns=turns,
                    end_reason=end_reason,
                    power_history=power_history,
                    p0_crypt_end=len(p0.crypt),
                    p1_crypt_end=len(p1.crypt),
                    p0_abyss_end=len(p0.inc_abyss),
                    p1_abyss_end=len(p1.inc_abyss),
                    total_noble_activations=total_noble_activations,
                )

            p.reset_turn_flags()
            discard_draw_used = False

            _, _, noble_acts = ai_play_turn(p, opp, rng, discard_draw_used)
            total_noble_activations += noble_acts

            pw0 = ritual_power(p0.rituals)
            pw1 = ritual_power(p1.rituals)
            power_history.append((turns if player_idx == 0 else turns + 0, pw0, pw1))

            if pw0 >= WIN_POWER or pw1 >= WIN_POWER:
                if pw0 >= WIN_POWER and pw1 >= WIN_POWER:
                    winner = -1
                    end_reason = "power"
                elif pw0 >= WIN_POWER:
                    winner = 0
                    end_reason = "power"
                else:
                    winner = 1
                    end_reason = "power"
                return GameStats(
                    winner=winner,
                    starting_player=starting_player,
                    turns=turns,
                    end_reason=end_reason,
                    power_history=power_history,
                    p0_crypt_end=len(p0.crypt),
                    p1_crypt_end=len(p1.crypt),
                    p0_abyss_end=len(p0.inc_abyss),
                    p1_abyss_end=len(p1.inc_abyss),
                    total_noble_activations=total_noble_activations,
                )

        current = 1 - current

        if turns > 200:
            pw0 = ritual_power(p0.rituals)
            pw1 = ritual_power(p1.rituals)
            if pw0 > pw1:
                winner = 0
                end_reason = "timeout_power"
            elif pw1 > pw0:
                winner = 1
                end_reason = "timeout_power"
            else:
                winner = -1
                end_reason = "timeout_draw"
            return GameStats(
                winner=winner,
                starting_player=starting_player,
                turns=turns,
                end_reason=end_reason,
                power_history=power_history,
                p0_crypt_end=len(p0.crypt),
                p1_crypt_end=len(p1.crypt),
                p0_abyss_end=len(p0.inc_abyss),
                p1_abyss_end=len(p1.inc_abyss),
                total_noble_activations=total_noble_activations,
            )


# --------- Worker and aggregation ---------

def worker_task(args: Tuple[int, int, str]) -> List[GameStats]:
    worker_id, n_games, base_dir_str = args
    base_dir = Path(base_dir_str)
    decks = load_decks(base_dir)
    rng = random.Random(123456 + worker_id * 7919)
    out: List[GameStats] = []
    for _ in range(n_games):
        out.append(simulate_single_game(decks, rng))
    return out


def aggregate_results(all_games: List[GameStats]) -> None:
    total_games = len(all_games)
    wins_first = 0
    wins_second = 0
    games_first = 0
    games_second = 0
    turns_list: List[int] = []
    end_reasons: Dict[str, int] = {}
    total_noble_acts = 0
    crypt_sizes_p0: List[int] = []
    crypt_sizes_p1: List[int] = []
    abyss_sizes_p0: List[int] = []
    abyss_sizes_p1: List[int] = []

    max_turns_seen = max((g.turns for g in all_games), default=0)
    power_sums_p0 = [0.0] * (max_turns_seen + 1)
    power_sums_p1 = [0.0] * (max_turns_seen + 1)
    power_counts = [0] * (max_turns_seen + 1)

    for g in all_games:
        turns_list.append(g.turns)
        end_reasons[g.end_reason] = end_reasons.get(g.end_reason, 0) + 1
        total_noble_acts += g.total_noble_activations
        crypt_sizes_p0.append(g.p0_crypt_end)
        crypt_sizes_p1.append(g.p1_crypt_end)
        abyss_sizes_p0.append(g.p0_abyss_end)
        abyss_sizes_p1.append(g.p1_abyss_end)
        if g.starting_player == 0:
            games_first += 1
            if g.winner == 0:
                wins_first += 1
        else:
            games_second += 1
            if g.winner == 1:
                wins_second += 1
        for t, p0p, p1p in g.power_history:
            if 0 <= t <= max_turns_seen:
                power_sums_p0[t] += p0p
                power_sums_p1[t] += p1p
                power_counts[t] += 1

    print(f"Total games: {total_games}")
    if games_first > 0:
        print(f"P(win | go first):  {wins_first / games_first:.3f}  ({wins_first}/{games_first})")
    if games_second > 0:
        print(f"P(win | go second): {wins_second / games_second:.3f}  ({wins_second}/{games_second})")

    print()
    print(f"Average game length (turns): {statistics.mean(turns_list):.2f}")
    print(f"Median game length (turns):  {statistics.median(turns_list):.2f}")

    print()
    print("Win conditions / end reasons:")
    for k, v in sorted(end_reasons.items(), key=lambda kv: kv[0]):
        print(f"  {k}: {v} ({v / total_games:.3%})")

    print()
    print(f"Average noble activations per game: {total_noble_acts / total_games:.2f}")
    print(f"Average crypt size P0: {statistics.mean(crypt_sizes_p0):.2f}")
    print(f"Average crypt size P1: {statistics.mean(crypt_sizes_p1):.2f}")
    print(f"Average abyss size  P0: {statistics.mean(abyss_sizes_p0):.2f}")
    print(f"Average abyss size  P1: {statistics.mean(abyss_sizes_p1):.2f}")

    print()
    print("Average ritual power per turn (P0, P1) for early turns:")
    max_report_turn = min(20, max_turns_seen)
    for t in range(1, max_report_turn + 1):
        if power_counts[t] == 0:
            continue
        avg0 = power_sums_p0[t] / power_counts[t]
        avg1 = power_sums_p1[t] / power_counts[t]
        print(f"  Turn {t:2d}: P0={avg0:5.2f}, P1={avg1:5.2f}")


def main() -> None:
    base_dir = Path(__file__).resolve().parent
    total_games = 100_000
    n_workers = cpu_count()
    games_per_worker = total_games // n_workers
    extra = total_games % n_workers

    tasks: List[Tuple[int, int, str]] = []
    wid = 0
    for i in range(n_workers):
        n = games_per_worker + (1 if i < extra else 0)
        if n <= 0:
            continue
        tasks.append((wid, n, str(base_dir)))
        wid += 1

    print(f"Running {total_games} games across {len(tasks)} workers...")

    with Pool(processes=len(tasks)) as pool:
        results = pool.map(worker_task, tasks)

    all_games: List[GameStats] = [g for sub in results for g in sub]
    aggregate_results(all_games)


if __name__ == "__main__":
    main()