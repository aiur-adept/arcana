extends RefCounted
class_name ArcanaCpuBase

# GDScript port of sim/ai.py GreedyAI. Subclassed per-deck in cpu/pilots/*.gd.
# Void-response is Godot-only (sim does not model VERB_VOID); the default
# implementation stays on this base class and pilots do not override it.

const CPU_ACTION_SEC := 1.618
const _GameSnapshotUtils = preload("res://game_snapshot_utils.gd")
const _CardTraits = preload("res://card_traits.gd")

const VERB_SEEK := "seek"
const VERB_INSIGHT := "insight"
const VERB_BURN := "burn"
const VERB_WOE := "woe"
const VERB_WRATH := "wrath"
const VERB_REVIVE := "revive"
const VERB_RENEW := "renew"
const VERB_DELUGE := "deluge"
const VERB_TEARS := "tears"
const VERB_VOID := "void"
const VERB_DETHRONE := "dethrone"

const LANE_GRANTS := {
	"krss_power": 1,
	"trss_power": 2,
	"yrss_power": 3,
}

const NOBLE_DEFS := {
	"krss_power":          {"grants_lane": 1},
	"trss_power":          {"grants_lane": 2},
	"yrss_power":          {"grants_lane": 3},
	"xytzr_emanation":     {},
	"yytzr_occultation":   {},
	"zytzr_annihilation":  {},
	"aeoiu_rituals":       {},
	"sndrr_incantation":   {"activated_verb": VERB_SEEK,    "activated_value": 1, "activation_discard": true},
	"indrr_incantation":   {"activated_verb": VERB_INSIGHT, "activated_value": 1},
	"bndrr_incantation":   {"activated_verb": VERB_BURN,    "activated_value": 2},
	"wndrr_incantation":   {"activated_verb": VERB_WOE,     "activated_value": 3, "activation_discard": true},
	"rndrr_incantation":   {"activated_verb": VERB_REVIVE,  "activated_value": 2},
	"rmrsk_emanation":     {},
	"smrsk_occultation":   {},
	"tmrsk_annihilation":  {},
}

const RING_DEFS := {
	"sybiline_emanation":   {"reductions": {"seek": 1, "insight": 1}},
	"cymbil_occultation":   {"reductions": {"burn": 1, "revive": 1, "renew": 1}},
	"celadon_annihilation": {"reductions": {"woe": 1, "wrath": 1}},
	"serraf_nobles":        {"reductions": {"noble": 1}},
	"sinofia_feathers":     {"reductions": {"bird": 1, "tears": 1}},
}

const RING_COST := 2
const BIG_TRIPLET := ["xytzr_emanation", "yytzr_occultation", "zytzr_annihilation"]

# -------------------------------------------------------------- weights
var W_RITUAL_BASE: float = 10.0
var W_RITUAL_VALUE_BONUS: float = 1.0
var W_RITUAL_NEW_LANE: float = 60.0
var W_RITUAL_DUP_LANE_1: float = -4.0

var W_NOBLE_BASE: float = 60.0
var W_NOBLE_COST_BONUS: float = 1.0
var W_NOBLE_GRANT_NEW_LANE: float = 40.0
var W_NOBLE_BIG_TRIPLET: float = 20.0

var W_BIRD_BASE: float = 15.0
var W_BIRD_POWER_BONUS: float = 1.0

var W_TEMPLE_BASE: float = 55.0
var W_TEMPLE_COST_BONUS: float = 1.0
var W_TEMPLE_EYRIE_BONUS: float = 30.0

var W_RING_BASE: float = 18.0

var W_DETHRONE_BASE: float = 40.0
var W_DETHRONE_PER_COST: float = 3.0

var SAC_PENALTY_PER_RITUAL: float = 2.0
var SAC_W_FIELD_POWER: float = 0.0
var SAC_W_HIGH_RITUAL: float = 0.0
var INC_BASE_BONUS: float = 5.0

var W_NOBLE_ACTIVATION: float = 30.0
var W_NOBLE_ACTIVATION_DISCARD_PENALTY: float = 8.0
var W_AEOIU_ACTIVATION_BASE: float = 45.0

var W_TEMPLE_PHAEDRA_ACT: float = 38.0
var W_TEMPLE_DELPHA_ACT_BASE: float = 25.0
var W_TEMPLE_GOTHA_ACT_BASE: float = 20.0
var W_TEMPLE_YTRIA_ACT_BASE: float = 25.0

var W_NEST_BASE: float = 8.0
var W_FIGHT_KILL_BASE: float = 4.0
var W_DISCARD_DRAW: float = 3.0
var DD_W_FIELD_CONTRIB: float = 0.0
var DD_W_CARD_COST: float = 0.0

var DD_W_RITUAL_BASE: float = 1.0
var DD_W_RITUAL_PER_VALUE: float = 0.3
var DD_W_INC_BASE: float = 2.0
var DD_W_INC_PER_VALUE: float = 0.4
var DD_W_INC_DETHRONE: float = 5.0
var DD_W_INC_WRATH: float = 5.0
var DD_W_NOBLE_BASE: float = 4.0
var DD_W_NOBLE_PER_COST: float = 0.5
var DD_W_TEMPLE_BASE: float = 6.0
var DD_W_TEMPLE_PER_COST: float = 0.2
var DD_W_BIRD_BASE: float = 3.0
var DD_W_BIRD_PER_POWER: float = 0.3
var DD_W_RING: float = 4.0

var W_RING_SAVE_INC: float = 2.0
var W_RING_SAVE_NOBLE: float = 1.5
var W_RING_SAVE_BIRD: float = 1.0

var W_NEST_POWER_BONUS: float = 1.0
var W_AEOIU_RITUAL_VALUE: float = 1.0
var W_TEMPLE_DELPHA_PER_DELTA: float = 10.0
var W_TEMPLE_GOTHA_PER_DRAW: float = 3.0
var W_TEMPLE_YTRIA_PER_HAND: float = 2.0

var W_REVIVE_PRIO_WRATH: float = 6.0
var W_REVIVE_PRIO_SEEK: float = 5.0
var W_REVIVE_PRIO_WOE: float = 4.0
var W_REVIVE_PRIO_BURN: float = 3.0
var W_REVIVE_PRIO_INSIGHT: float = 2.0
var W_REVIVE_PRIO_RENEW: float = 0.0

var W_SF_RITUAL_MP_PUSH: float = 0.0
var W_SF_INC_BEHIND: float = 0.0
var W_SF_RING_OPP_BOARD: float = 0.0
var W_SF_DISCARD_FLOOD: float = 0.0

var W_EFFECT_SEEK_BASE: float = 8.0
var W_EFFECT_SEEK_VALUE: float = 3.0
var W_EFFECT_INSIGHT_BASE: float = 4.0
var W_EFFECT_INSIGHT_VALUE: float = 1.0
var W_EFFECT_BURN_BASE: float = 2.0
var W_EFFECT_BURN_VALUE: float = 1.0
var W_EFFECT_WOE_BASE: float = 5.0
var W_EFFECT_WOE_PER_DISCARD: float = 3.0
var W_EFFECT_WRATH_BASE: float = 10.0
var W_EFFECT_WRATH_PER_KILLED: float = 2.5
var W_EFFECT_REVIVE_BASE: float = 12.0
var W_EFFECT_RENEW_BASE: float = 12.0
var W_EFFECT_DELUGE_BASE: float = 5.0
var W_EFFECT_DELUGE_PER_NET: float = 4.0
var W_EFFECT_TEARS_BASE: float = 10.0

# =========================================================================
# Top-level orchestration
# =========================================================================

func run_turn(host: Node) -> void:
	if host._match == null:
		return
	var guard := 400
	while guard > 0:
		guard -= 1
		await host.get_tree().create_timer(CPU_ACTION_SEC).timeout
		if host._match == null:
			return
		var snap: Dictionary = host._match.snapshot(1)
		if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
			return
		if bool(snap.get("void_pending_you_respond", false)):
			_cpu_decide_void_response(host, snap, false)
			continue
		if bool(snap.get("void_pending_waiting", false)):
			continue
		if bool(snap.get("woe_pending_you_respond", false)):
			_respond_woe(host, snap)
			continue
		if bool(snap.get("eyrie_pending_you_respond", false)):
			_respond_eyrie(host, snap)
			continue
		if bool(snap.get("scion_pending_you_respond", false)):
			scion_response(host, snap)
			continue
		if int(snap.get("current", -1)) != 1:
			return
		var best: Variant = _enumerate_best(host, snap)
		if best == null:
			break
		var ok := _execute_action(host, snap, best)
		if not ok:
			break
	_end_turn(host)


func run_mulligan_step(host: Node) -> void:
	if host._match == null:
		return
	var snap: Dictionary = host._match.snapshot(1)
	if not bool(snap.get("mulligan_active", false)):
		return
	if int(snap.get("current", -1)) != 1:
		return
	var bottom_needed := int(snap.get("your_mulligan_bottom_needed", 0))
	if bottom_needed > 0:
		var hand: Array = snap.get("your_hand", [])
		if hand.is_empty():
			return
		var worst := _pick_worst_hand_index(hand)
		host._try_mulligan_bottom(1, worst, true)
		return
	var can_take := bool(snap.get("your_can_mulligan", false))
	var take := false
	if can_take:
		take = mulligan(host, snap)
	host._try_choose_mulligan(1, take, true)


# -------- overridable per-pilot mulligan --------

func mulligan(_host: Node, snap: Dictionary) -> bool:
	var hand: Array = snap.get("your_hand", [])
	if hand.is_empty():
		return false
	var rituals: Array = []
	for c in hand:
		if _card_kind(c) == "ritual":
			rituals.append(c)
	if rituals.is_empty() or rituals.size() == hand.size():
		return true
	var low := false
	for r in rituals:
		if int((r as Dictionary).get("value", 0)) == 1:
			low = true
			break
	if not low and rituals.size() >= 3:
		return true
	return false


# =========================================================================
# Response handlers
# =========================================================================

func _respond_woe(host: Node, snap: Dictionary) -> void:
	var hand: Array = snap.get("your_hand", [])
	var need := int(snap.get("woe_pending_amount", 0))
	var indices: Array = woe_response(snap, hand, need)
	host._try_submit_woe_discard(1, indices, true)


func woe_response(_snap: Dictionary, hand: Array, need: int) -> Array:
	var scored: Array = []
	for i in hand.size():
		scored.append({"i": i, "s": _card_discard_score(hand[i])})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["s"]) < float(b["s"])
	)
	var out: Array = []
	for j in mini(need, scored.size()):
		out.append(int((scored[j] as Dictionary)["i"]))
	return out


func _respond_eyrie(host: Node, snap: Dictionary) -> void:
	var picks: Array = []
	var cands: Array = snap.get("eyrie_bird_candidates", []) as Array
	var rem := int(snap.get("eyrie_pending_remaining", 0))
	for ci in mini(rem, cands.size()):
		picks.append(int((cands[ci] as Dictionary).get("deck_idx", -1)))
	if host._match.apply_eyrie_submit(1, picks) == "ok":
		host._broadcast_sync(false)


func scion_response(host: Node, snap: Dictionary) -> void:
	var st := str(snap.get("scion_pending_type", ""))
	var sid := int(snap.get("scion_pending_id", -1))
	if st == "rmrsk_draw":
		if not host._try_submit_scion_trigger(1, "accept", {"scion_id": sid}, false):
			host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		return
	if st == "smrsk_burn":
		# base ai.py scion_response declines smrsk
		host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		return
	if st == "tmrsk_woe":
		if int(snap.get("opp_hand", 0)) > 0:
			if not host._try_submit_scion_trigger(1, "accept", {"scion_id": sid, "woe_target": 0}, false):
				host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		else:
			host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		return
	host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)


# =========================================================================
# Void reaction (Godot-only; sim doesn't model Void)
# =========================================================================

func _cpu_decide_void_response(host: Node, snap: Dictionary, trigger_cpu_check: bool = true) -> void:
	var hand: Array = snap.get("your_hand", []) as Array
	var void_idx := -1
	for i in hand.size():
		var c: Dictionary = hand[i] as Dictionary
		if _card_kind(c) == "incantation" and str(c.get("verb", "")).to_lower() == "void":
			void_idx = i
			break
	if void_idx < 0 or hand.size() < 2:
		if host._match != null and host._match.submit_void_skip(1) == "ok":
			host._broadcast_sync(trigger_cpu_check)
		return
	var cost := int(snap.get("void_pending_cost", 0))
	var prob := clampf(float(cost) / 10.0, 0.0, 1.0)
	if cost <= 0 or randf() >= prob:
		if host._match.submit_void_skip(1) == "ok":
			host._broadcast_sync(trigger_cpu_check)
		return
	var discard_idx := _cpu_pick_void_discard(hand, void_idx)
	if discard_idx < 0:
		if host._match.submit_void_skip(1) == "ok":
			host._broadcast_sync(trigger_cpu_check)
		return
	if host._match.submit_void_react(1, void_idx, discard_idx) == "ok":
		host._broadcast_sync(trigger_cpu_check)


func _cpu_pick_void_discard(hand: Array, void_idx: int) -> int:
	var best_idx := -1
	var best_score: float = 9999.0
	for i in hand.size():
		if i == void_idx:
			continue
		var score := _card_discard_score(hand[i])
		if score < best_score:
			best_score = score
			best_idx = i
	return best_idx


# =========================================================================
# Enumeration + scoring
# =========================================================================

func _enumerate_best(host: Node, snap: Dictionary) -> Variant:
	var actions: Array = []
	var hand: Array = snap.get("your_hand", []) as Array
	var your_field: Array = snap.get("your_field", []) as Array
	var your_nobles: Array = snap.get("your_nobles", []) as Array
	var your_birds: Array = snap.get("your_birds", []) as Array
	var your_temples: Array = snap.get("your_temples", []) as Array
	var opp_nobles: Array = snap.get("opp_nobles", []) as Array
	var active_lanes: Array = _active_lanes(your_field, your_nobles)

	var ritual_played := bool(snap.get("your_ritual_played", false))
	var noble_played := bool(snap.get("your_noble_played", false))
	var bird_played := bool(snap.get("your_bird_played", false))
	var temple_played := bool(snap.get("your_temple_played", false))

	for i in hand.size():
		var c: Dictionary = hand[i] as Dictionary
		var kind := _card_kind(c)
		if kind == "ritual":
			if ritual_played:
				continue
			if not host._match.can_play_ritual(1, i):
				continue
			var v := int(c.get("value", 0))
			var unlocked := _count_new_lanes_if_ritual(your_field, your_nobles, v)
			var ymp := int(snap.get("your_match_power", 0))
			var score := score_ritual_play(c, active_lanes, unlocked, ymp)
			actions.append({"score": score, "kind": "ritual", "hand_idx": i})
		elif kind == "noble":
			if noble_played:
				continue
			if not host._match.can_play_noble(1, i):
				continue
			var base_cost: int = _GameSnapshotUtils.noble_cost_for_id(str(c.get("noble_id", "")))
			var eff: int = host._match.effective_noble_cost(1, base_cost)
			var sac: Array = []
			if eff > 0 and (eff > 4 or not _lane_in_set(active_lanes, eff)):
				sac = _greedy_sac_min(your_field, eff)
				if sac.is_empty() and eff > 0:
					continue
			var nscore: Variant = score_noble_play(c, eff, sac, active_lanes, snap)
			if nscore == null:
				continue
			actions.append({"score": float(nscore), "kind": "noble", "hand_idx": i, "sac": sac})
		elif kind == "bird":
			if bird_played:
				continue
			if not host._match.can_play_bird(1, i):
				continue
			var bscore := score_bird_play(c)
			actions.append({"score": bscore, "kind": "bird", "hand_idx": i})
		elif kind == "ring":
			if not host._match.can_play_ring(1, i):
				continue
			var ra: Variant = _score_ring_action(host, snap, c, i, your_nobles, your_birds, hand)
			if ra != null:
				actions.append(ra)
		elif kind == "temple":
			if temple_played:
				continue
			if not host._match.can_play_temple(1, i):
				continue
			var tcost: int = _GameSnapshotUtils.temple_cost_for_id(str(c.get("temple_id", "")))
			var tsac := _greedy_sac_min(your_field, tcost)
			if tsac.is_empty() and tcost > 0:
				continue
			var lanes_after := _lanes_after_sac(your_field, your_nobles, tsac)
			var tscore: Variant = score_temple_play(c, tsac, lanes_after, snap)
			if tscore == null:
				continue
			actions.append({"score": float(tscore), "kind": "temple", "hand_idx": i, "sac": tsac})
		elif kind == "incantation":
			if _CardTraits.is_dethrone(c):
				if opp_nobles.is_empty():
					continue
				var dsac: Array = []
				if not host._match.has_active_ritual_lane(1, 4):
					dsac = _greedy_sac_min(your_field, 4)
					if dsac.is_empty():
						continue
				var target := choose_dethrone_target(snap)
				if target.is_empty():
					continue
				var dscore: Variant = score_dethrone(c, dsac, target, snap)
				if dscore == null:
					continue
				actions.append({"score": float(dscore), "kind": "dethrone", "hand_idx": i, "sac": dsac, "target_mid": int(target.get("mid", -1))})
				continue
			var ia: Variant = _score_incantation(host, snap, c, i, active_lanes, your_field)
			if ia != null:
				actions.append(ia)

	for n in your_nobles:
		var nd := n as Dictionary
		var nmid := int(nd.get("mid", -1))
		if not host._match.can_activate_noble(1, nmid):
			continue
		if int(nd.get("used_turn", -1)) == int(snap.get("turn_number", 0)):
			continue
		var nid := str(nd.get("noble_id", ""))
		if nid == "aeoiu_rituals":
			var your_crypt: Array = snap.get("your_crypt_cards", []) as Array
			var best_ci := -1
			var best_v := -1
			for ci in your_crypt.size():
				var cc := your_crypt[ci] as Dictionary
				if _card_kind(cc) != "ritual":
					continue
				var vv := int(cc.get("value", 0))
				if vv > best_v:
					best_v = vv
					best_ci = ci
			if best_ci < 0:
				continue
			var ritual_filtered_idx := _ritual_crypt_index(your_crypt, best_ci)
			if ritual_filtered_idx < 0:
				continue
			var ascore := W_AEOIU_ACTIVATION_BASE + float(best_v) * W_AEOIU_RITUAL_VALUE
			actions.append({"score": ascore, "kind": "activate_aeoiu", "noble_mid": nmid, "ritual_crypt_idx": ritual_filtered_idx})
			continue
		var info: Dictionary = NOBLE_DEFS.get(nid, {}) as Dictionary
		var verb := str(info.get("activated_verb", ""))
		if verb.is_empty():
			continue
		var val := int(info.get("activated_value", 0))
		if bool(info.get("activation_discard", false)) and hand.is_empty():
			continue
		var eff_res: Variant = _score_effect(host, snap, verb, val)
		if eff_res == null:
			continue
		var eff_score := float((eff_res as Dictionary)["score"])
		var eff_ctx: Dictionary = ((eff_res as Dictionary)["ctx"] as Dictionary).duplicate(true)
		eff_score += W_NOBLE_ACTIVATION
		if bool(info.get("activation_discard", false)):
			var worst_i := _pick_worst_hand_index(hand)
			eff_ctx["discard_hand_idx"] = worst_i
			eff_score -= W_NOBLE_ACTIVATION_DISCARD_PENALTY
		actions.append({"score": eff_score, "kind": "activate_noble", "noble_mid": nmid, "noble_id": nid, "verb": verb, "value": val, "ctx": eff_ctx})

	for t in your_temples:
		var td := t as Dictionary
		var tmid := int(td.get("mid", -1))
		if int(td.get("used_turn", -1)) == int(snap.get("turn_number", 0)):
			continue
		if not host._match.can_activate_temple(1, tmid):
			continue
		var ta: Variant = _score_temple_activation(host, snap, td)
		if ta != null:
			actions.append(ta)

	for b in your_birds:
		var bd := b as Dictionary
		if int(bd.get("nest_temple_mid", -1)) >= 0:
			continue
		for t2 in your_temples:
			var td2 := t2 as Dictionary
			var cap: int = _GameSnapshotUtils.temple_cost_for_id(str(td2.get("temple_id", "")))
			var nested: Array = td2.get("nested", []) as Array
			if nested.size() >= cap:
				continue
			if should_nest(bd, td2):
				var nscore := W_NEST_BASE + float(bd.get("power", 0)) * W_NEST_POWER_BONUS
				actions.append({"score": nscore, "kind": "nest", "bird_mid": int(bd.get("mid", -1)), "temple_mid": int(td2.get("mid", -1))})
			break

	if not bool(snap.get("your_bird_fight_used", false)):
		var fight: Variant = _best_fight(snap)
		if fight != null:
			actions.append(fight)

	if not bool(snap.get("discard_draw_used", true)) and not hand.is_empty():
		var worst_dd := _pick_worst_hand_index(hand)
		var worst_c: Dictionary = hand[worst_dd] as Dictionary
		var dd_score := _discard_draw_action_score(snap, worst_c)
		actions.append({"score": dd_score, "kind": "discard_draw", "hand_idx": worst_dd})

	if actions.is_empty():
		return null
	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	var top := actions[0] as Dictionary
	if float(top["score"]) <= 0.0:
		return null
	return top


# -------- scoring hooks (per-play) --------

func score_ritual_play(card: Dictionary, before_lanes: Array, lanes_unlocked: int, your_mp: int) -> float:
	var score := W_RITUAL_BASE + float(card.get("value", 0)) * W_RITUAL_VALUE_BONUS + W_RITUAL_NEW_LANE * float(lanes_unlocked)
	if int(card.get("value", 0)) == 1 and _lane_in_set(before_lanes, 1):
		score += W_RITUAL_DUP_LANE_1
	var deficit := maxi(0, 18 - your_mp)
	score += W_SF_RITUAL_MP_PUSH * float(deficit) * float(lanes_unlocked)
	return score


func score_noble_play(card: Dictionary, _eff_cost: int, sac: Array, active_lanes: Array, snap: Dictionary = {}) -> Variant:
	var score := W_NOBLE_BASE + float(_GameSnapshotUtils.noble_cost_for_id(str(card.get("noble_id", "")))) * W_NOBLE_COST_BONUS
	var nid := str(card.get("noble_id", ""))
	var info: Dictionary = NOBLE_DEFS.get(nid, {}) as Dictionary
	var grant := int(info.get("grants_lane", 0))
	if grant > 0 and not _lane_in_set(active_lanes, grant):
		score += W_NOBLE_GRANT_NEW_LANE
	if BIG_TRIPLET.has(nid):
		score += W_NOBLE_BIG_TRIPLET
	if not sac.is_empty():
		score -= _sac_penalty(sac, snap)
	return score


func score_bird_play(card: Dictionary) -> float:
	return W_BIRD_BASE + float(card.get("power", 0)) * W_BIRD_POWER_BONUS


func score_temple_play(card: Dictionary, sac: Array, lanes_after_sac: Array, _snap: Dictionary) -> Variant:
	if lanes_after_sac.size() < 2:
		return null
	var score := W_TEMPLE_BASE + float(_GameSnapshotUtils.temple_cost_for_id(str(card.get("temple_id", "")))) * W_TEMPLE_COST_BONUS
	if str(card.get("temple_id", "")) == "eyrie_feathers":
		# Approximate the Python "any bird in deck" check via crypt_cards + birds already in play.
		# Eyrie's own ETB-search is what makes this valuable; we unconditionally give the bonus.
		score += W_TEMPLE_EYRIE_BONUS
	if not sac.is_empty():
		score -= _sac_penalty(sac, _snap)
	return score


func score_dethrone(_card: Dictionary, sac: Array, target: Dictionary, snap: Dictionary = {}) -> Variant:
	var score := W_DETHRONE_BASE + float(target.get("cost", 0)) * W_DETHRONE_PER_COST
	if not sac.is_empty():
		score -= _sac_penalty(sac, snap)
	return score


func choose_dethrone_target(snap: Dictionary) -> Dictionary:
	var opp: Array = snap.get("opp_nobles", []) as Array
	if opp.is_empty():
		return {}
	var best: Dictionary = {}
	var best_cost := -1
	for n in opp:
		var nd := n as Dictionary
		var c: int = _GameSnapshotUtils.noble_cost_for_id(str(nd.get("noble_id", "")))
		if c > best_cost:
			best_cost = c
			best = nd
	if not best.is_empty() and not best.has("cost"):
		best["cost"] = best_cost
	return best


func should_nest(_bird: Dictionary, _temple: Dictionary) -> bool:
	return true


# -------- ring --------

func _score_ring_action(_host: Node, snap: Dictionary, card: Dictionary, hand_idx: int, your_nobles: Array, your_birds: Array, hand_full: Array) -> Variant:
	var rid := str(card.get("ring_id", ""))
	var hosts: Array = _ring_hosts(your_nobles, your_birds)
	if hosts.is_empty():
		return null
	for n in your_nobles:
		var rings: Array = (n as Dictionary).get("rings", []) as Array
		for r in rings:
			if str((r as Dictionary).get("ring_id", "")) == rid:
				return null
	for b in your_birds:
		var rings2: Array = (b as Dictionary).get("rings", []) as Array
		for r in rings2:
			if str((r as Dictionary).get("ring_id", "")) == rid:
				return null
	var reductions: Dictionary = (RING_DEFS.get(rid, {}) as Dictionary).get("reductions", {}) as Dictionary
	var savings: float = 0.0
	for c in hand_full:
		var cd := c as Dictionary
		var k := _card_kind(cd)
		if k == "incantation":
			var v := str(cd.get("verb", "")).to_lower()
			if reductions.has(v):
				savings += W_RING_SAVE_INC
		elif k == "noble" and reductions.has("noble"):
			savings += W_RING_SAVE_NOBLE
		elif k == "bird" and reductions.has("bird"):
			savings += W_RING_SAVE_BIRD
	var crypt: Array = snap.get("your_crypt_cards", []) as Array
	for c in crypt:
		var cd2 := c as Dictionary
		var k2 := _card_kind(cd2)
		if k2 == "incantation":
			var v2 := str(cd2.get("verb", "")).to_lower()
			if reductions.has(v2):
				savings += W_RING_SAVE_INC
		elif k2 == "noble" and reductions.has("noble"):
			savings += W_RING_SAVE_NOBLE
		elif k2 == "bird" and reductions.has("bird"):
			savings += W_RING_SAVE_BIRD
	var score := W_RING_BASE + savings
	score = adjust_ring_score(card, score)
	var opp_field_sz: int = (snap.get("opp_field", []) as Array).size()
	var opp_bird_sz: int = (snap.get("opp_birds", []) as Array).size()
	score += W_SF_RING_OPP_BOARD * float(opp_field_sz + opp_bird_sz)
	var pick := _pick_ring_host(card, hosts, your_nobles, your_birds)
	return {"score": score, "kind": "ring", "hand_idx": hand_idx, "host_kind": pick["kind"], "host_mid": pick["mid"]}


func adjust_ring_score(_card: Dictionary, score: float) -> float:
	return score


func _pick_ring_host(_card: Dictionary, hosts: Array, your_nobles: Array, _your_birds: Array) -> Dictionary:
	for h in hosts:
		if h["kind"] == "noble":
			for n in your_nobles:
				var nd := n as Dictionary
				if int(nd.get("mid", -1)) == int(h["mid"]):
					var info: Dictionary = NOBLE_DEFS.get(str(nd.get("noble_id", "")), {}) as Dictionary
					if int(info.get("grants_lane", 0)) > 0:
						return h
					break
	for h in hosts:
		if h["kind"] == "noble":
			return h
	return hosts[0]


func _ring_hosts(your_nobles: Array, your_birds: Array) -> Array:
	var out: Array = []
	for n in your_nobles:
		out.append({"kind": "noble", "mid": int((n as Dictionary).get("mid", -1))})
	for b in your_birds:
		var bd := b as Dictionary
		if int(bd.get("nest_temple_mid", -1)) >= 0:
			continue
		out.append({"kind": "bird", "mid": int(bd.get("mid", -1))})
	return out


# -------- incantation --------

func _score_incantation(host: Node, snap: Dictionary, card: Dictionary, hand_idx: int, active_lanes: Array, your_field: Array) -> Variant:
	var verb := str(card.get("verb", "")).to_lower()
	var val := int(card.get("value", 0))
	if verb == VERB_VOID:
		return null
	var eff_val: int = host._match.effective_incantation_cost(1, verb, val)
	var sac: Array = []
	if verb == VERB_WRATH:
		var w0 := choose_wrath_instigator_sac_from_snap(snap)
		if w0 < 0:
			return null
		sac = [w0]
	elif eff_val > 0 and not _lane_in_set(active_lanes, eff_val):
		sac = _greedy_sac_min(your_field, eff_val)
		if sac.is_empty():
			return null
		var lanes_after := _lanes_after_sac(your_field, snap.get("your_nobles", []) as Array, sac)
		if lanes_after.is_empty():
			return null
	var eff: Variant = _score_effect(host, snap, verb, val)
	if eff == null:
		return null
	var score := float((eff as Dictionary)["score"])
	var ctx: Dictionary = ((eff as Dictionary)["ctx"] as Dictionary).duplicate(true)
	score += INC_BASE_BONUS
	if not sac.is_empty():
		score -= _sac_penalty(sac, snap)
	var adj: Variant = adjust_incantation_score(snap, card, sac, score)
	if adj == null:
		return null
	var fadj := float(adj)
	var ymp2 := int(snap.get("your_match_power", 0))
	var omp2 := int(snap.get("opp_match_power", 0))
	var gap := maxi(0, omp2 - ymp2)
	fadj += W_SF_INC_BEHIND * float(gap) * float(val) * 0.1
	return {"score": fadj, "kind": "incantation", "hand_idx": hand_idx, "sac": sac, "ctx": ctx, "verb": verb, "value": val}


func adjust_incantation_score(_snap: Dictionary, _card: Dictionary, _sac: Array, score: float) -> Variant:
	return score


# -------- temple activation --------

func _score_temple_activation(_host: Node, snap: Dictionary, temple: Dictionary) -> Variant:
	var tmid := int(temple.get("mid", -1))
	var tid := str(temple.get("temple_id", ""))
	if tid == "phaedra_illusion":
		return {"score": W_TEMPLE_PHAEDRA_ACT, "kind": "activate_temple_phaedra", "temple_mid": tmid}
	if tid == "delpha_oracles":
		var your_field: Array = snap.get("your_field", []) as Array
		var crypt: Array = snap.get("your_crypt_cards", []) as Array
		if your_field.is_empty():
			return null
		var min_val := 9
		var min_mid := -1
		for r in your_field:
			var v := int((r as Dictionary).get("value", 0))
			if v < min_val:
				min_val = v
				min_mid = int((r as Dictionary).get("mid", -1))
		if min_mid < 0:
			return null
		# choose best ritual in crypt with value > min_val
		var best_ci := -1
		var best_v := -1
		var rit_idx := 0
		var rit_filtered := -1
		for ci in crypt.size():
			var cc := crypt[ci] as Dictionary
			if _card_kind(cc) != "ritual":
				continue
			var v2 := int(cc.get("value", 0))
			if v2 > best_v:
				best_v = v2
				best_ci = ci
				rit_filtered = rit_idx
			rit_idx += 1
		if best_ci < 0:
			return null
		if best_v <= min_val:
			return null
		if int(snap.get("your_deck", 0)) < 2 * min_val:
			return null
		var score := W_TEMPLE_DELPHA_ACT_BASE + float(best_v - min_val) * W_TEMPLE_DELPHA_PER_DELTA
		return {"score": score, "kind": "activate_temple_delpha", "temple_mid": tmid, "ritual_mid": min_mid, "ritual_crypt_idx": rit_filtered}
	if tid == "gotha_illness":
		var hand: Array = snap.get("your_hand", []) as Array
		var best_i := -1
		var best_draw := 0
		for i in hand.size():
			var c := hand[i] as Dictionary
			var k := _card_kind(c)
			if k == "temple":
				continue
			if not gotha_hand_allowed(c):
				continue
			var draw_n := 0
			if k == "ritual" or k == "incantation":
				draw_n = int(c.get("value", 0))
			elif k == "noble":
				draw_n = _GameSnapshotUtils.noble_cost_for_id(str(c.get("noble_id", "")))
			elif k == "bird" or k == "ring":
				draw_n = int(c.get("cost", 0))
			if _CardTraits.is_dethrone(c):
				draw_n = 4
			if draw_n > best_draw:
				best_draw = draw_n
				best_i = i
		if best_i >= 0 and best_draw >= 2:
			var score := W_TEMPLE_GOTHA_ACT_BASE + float(best_draw) * W_TEMPLE_GOTHA_PER_DRAW
			return {"score": score, "kind": "activate_temple_gotha", "temple_mid": tmid, "hand_idx": best_i}
		return null
	if tid == "ytria_cycles":
		var hand2: Array = snap.get("your_hand", []) as Array
		if hand2.size() >= ytria_min_hand():
			var score := W_TEMPLE_YTRIA_ACT_BASE + float(hand2.size()) * W_TEMPLE_YTRIA_PER_HAND
			return {"score": score, "kind": "activate_temple_ytria", "temple_mid": tmid}
		return null
	return null


func gotha_hand_allowed(_card: Dictionary) -> bool:
	return true


func ytria_min_hand() -> int:
	return 4


# -------- effect scoring --------

func _score_effect(host: Node, snap: Dictionary, verb: String, val: int) -> Variant:
	var opp_field: Array = snap.get("opp_field", []) as Array
	var your_birds: Array = snap.get("your_birds", []) as Array
	var opp_birds: Array = snap.get("opp_birds", []) as Array
	var opp_hand_size := int(snap.get("opp_hand", 0))
	var your_crypt: Array = snap.get("your_crypt_cards", []) as Array
	var v := verb.to_lower()
	if v == VERB_SEEK:
		return {"score": W_EFFECT_SEEK_BASE + float(val) * W_EFFECT_SEEK_VALUE, "ctx": {}}
	if v == VERB_INSIGHT:
		var bot := choose_insight_bottom(val)
		var take: int = host._match.insight_effective_n(1, val)
		var opp_deck_n := int(snap.get("opp_deck", 0))
		take = mini(take, opp_deck_n)
		var top: Array = []
		var bottom: Array = []
		if bot <= 0:
			for i in take:
				top.append(i)
		elif bot >= take:
			for i in take:
				bottom.append(i)
		else:
			for i in range(take - bot):
				top.append(i)
			for i in range(take - bot, take):
				bottom.append(i)
		return {"score": W_EFFECT_INSIGHT_BASE + float(val) * W_EFFECT_INSIGHT_VALUE, "ctx": {"insight_target": 0, "insight_top": top, "insight_bottom": bottom}}
	if v == VERB_BURN:
		var target := choose_burn_target(snap, val)
		return {"score": W_EFFECT_BURN_BASE + float(val) * W_EFFECT_BURN_VALUE, "ctx": {"mill_target": target}}
	if v == VERB_WOE:
		if opp_hand_size <= 0:
			return null
		var discards := maxi(val - 2, 0)
		if _has_noble_on_field(snap.get("your_nobles", []) as Array, "zytzr_annihilation"):
			discards += 1
		if discards <= 0:
			return null
		return {"score": W_EFFECT_WOE_BASE + float(discards) * W_EFFECT_WOE_PER_DISCARD, "ctx": {"woe_target": 0}}
	if v == VERB_WRATH:
		if opp_field.is_empty():
			return null
		var killcount: int = host._match.effective_wrath_destroy_count(1, val)
		killcount = mini(killcount, opp_field.size())
		var sorted_vals: Array = []
		for r in opp_field:
			sorted_vals.append(int((r as Dictionary).get("value", 0)))
		sorted_vals.sort()
		sorted_vals.reverse()
		var killed_val := 0
		for i in killcount:
			killed_val += int(sorted_vals[i])
		var base: float = W_EFFECT_WRATH_BASE + float(killed_val) * W_EFFECT_WRATH_PER_KILLED
		var adj := wrath_score_adjust(snap, base)
		return {"score": adj, "ctx": {}}
	if v == VERB_REVIVE:
		var elig := _revive_eligible_indices(your_crypt)
		if elig.is_empty():
			return null
		return {"score": W_EFFECT_REVIVE_BASE, "ctx": {}}
	if v == VERB_RENEW:
		var r_crypt: Array = snap.get("your_ritual_crypt_cards", []) as Array
		if r_crypt.is_empty():
			return null
		var best_rf := 0
		var best_val := -1
		for ri in r_crypt.size():
			var rv := int((r_crypt[ri] as Dictionary).get("value", 0))
			if rv > best_val:
				best_val = rv
				best_rf = ri
		return {"score": W_EFFECT_RENEW_BASE, "ctx": {"renew_ritual_crypt_idx": best_rf}}
	if v == VERB_DELUGE:
		var threshold := val - 1
		var opp_hit := 0
		var me_hit := 0
		var opp_unnest := 0
		var me_unnest := 0
		for b in opp_birds:
			var bd := b as Dictionary
			if int(bd.get("nest_temple_mid", -1)) < 0 and int(bd.get("power", 0)) <= threshold:
				opp_hit += 1
			if int(bd.get("nest_temple_mid", -1)) >= 0:
				opp_unnest += 1
		for b in your_birds:
			var bd2 := b as Dictionary
			if int(bd2.get("nest_temple_mid", -1)) < 0 and int(bd2.get("power", 0)) <= threshold:
				me_hit += 1
			if int(bd2.get("nest_temple_mid", -1)) >= 0:
				me_unnest += 1
		var net := (opp_hit - me_hit) + (opp_unnest - me_unnest)
		if net <= 0:
			return null
		return {"score": W_EFFECT_DELUGE_BASE + float(net) * W_EFFECT_DELUGE_PER_NET, "ctx": {}}
	if v == VERB_TEARS:
		var bird_filtered := _GameSnapshotUtils.filtered_crypt_cards(your_crypt, ["bird"])
		if bird_filtered.is_empty():
			return null
		return {"score": W_EFFECT_TEARS_BASE, "ctx": {"tears_crypt_idx": 0}}
	return null


func wrath_score_adjust(_snap: Dictionary, base: float) -> float:
	return base


func choose_burn_target(_snap: Dictionary, _val: int) -> int:
	return 0


func choose_insight_bottom(val: int) -> int:
	return val


# -------- bird fight --------

func _best_fight(snap: Dictionary) -> Variant:
	var your_birds: Array = snap.get("your_birds", []) as Array
	var opp_birds: Array = snap.get("opp_birds", []) as Array
	var best: Dictionary = {}
	var best_score := 0.0
	for a in your_birds:
		var ad := a as Dictionary
		if int(ad.get("nest_temple_mid", -1)) >= 0:
			continue
		for d in opp_birds:
			var dd := d as Dictionary
			if int(dd.get("nest_temple_mid", -1)) >= 0:
				continue
			var ap := int(ad.get("power", 0))
			var dp := int(dd.get("power", 0))
			var atk_dies := ap <= dp
			var def_dies := dp <= ap
			var s: float = 0.0
			if def_dies:
				s += W_FIGHT_KILL_BASE + float(dp)
			if atk_dies:
				s -= W_FIGHT_KILL_BASE + float(ap)
			if s > best_score:
				best_score = s
				best = {"score": s, "kind": "fight", "atk_mid": int(ad.get("mid", -1)), "def_mid": int(dd.get("mid", -1)), "def_power": dp}
	if best.is_empty() or best_score <= 0.0:
		return null
	return best


# -------- wrath / revive target helpers --------

func choose_wrath_targets(snap: Dictionary, count: int) -> Array:
	var opp_field: Array = snap.get("opp_field", []) as Array
	var sorted_field: Array = opp_field.duplicate()
	sorted_field.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("value", 0)) > int(b.get("value", 0))
	)
	var out: Array = []
	for i in mini(count, sorted_field.size()):
		out.append(int((sorted_field[i] as Dictionary).get("mid", -1)))
	return out


func choose_wrath_instigator_sac_from_snap(snap: Dictionary) -> int:
	var your_field: Array = snap.get("your_field", []) as Array
	if your_field.is_empty():
		return -1
	var best_mid := -1
	var best_val := 999999
	for r in your_field:
		var d := r as Dictionary
		var mid := int(d.get("mid", -1))
		if mid < 0:
			continue
		var vm := int(d.get("value", 0))
		if vm < best_val or (vm == best_val and (best_mid < 0 or mid < best_mid)):
			best_val = vm
			best_mid = mid
	return best_mid


func _revive_verb_prio_bonus(verb: String) -> float:
	var v := verb.to_lower()
	if v == VERB_WRATH:
		return W_REVIVE_PRIO_WRATH
	if v == VERB_SEEK:
		return W_REVIVE_PRIO_SEEK
	if v == VERB_WOE:
		return W_REVIVE_PRIO_WOE
	if v == VERB_BURN:
		return W_REVIVE_PRIO_BURN
	if v == VERB_INSIGHT:
		return W_REVIVE_PRIO_INSIGHT
	if v == VERB_RENEW:
		return W_REVIVE_PRIO_RENEW
	return 0.0


func choose_revive_target(your_crypt: Array, elig_indices: Array) -> int:
	var best := -1
	var best_score := -1000000.0
	for i in elig_indices:
		var c := your_crypt[int(i)] as Dictionary
		var verb := str(c.get("verb", "")).to_lower()
		var score := float(c.get("value", 0)) + _revive_verb_prio_bonus(verb)
		if score > best_score:
			best_score = score
			best = int(i)
	return best


func choose_aeoiu_crypt_ritual(_snap: Dictionary, default_filtered_idx: int) -> int:
	return default_filtered_idx


func amend_revive_ctx(_snap: Dictionary, _your_crypt: Array, _global_pick: int, _ctx: Dictionary) -> void:
	pass


# =========================================================================
# Execution
# =========================================================================

func _execute_action(host: Node, snap: Dictionary, action: Dictionary) -> bool:
	var kind := str(action.get("kind", ""))
	match kind:
		"ritual":
			if not host._try_play_ritual(1, int(action["hand_idx"]), false):
				return false
		"noble":
			if not host._try_play_noble(1, int(action["hand_idx"]), action.get("sac", []) as Array, false):
				return false
		"bird":
			if not host._try_play_bird(1, int(action["hand_idx"]), false):
				return false
		"ring":
			if not host._try_play_ring(1, int(action["hand_idx"]), str(action["host_kind"]), int(action["host_mid"]), false):
				return false
		"temple":
			if not host._try_play_temple(1, int(action["hand_idx"]), action.get("sac", []) as Array, false):
				return false
		"incantation":
			var verb := str(action.get("verb", ""))
			var val := int(action.get("value", 0))
			var ctx: Dictionary = (action.get("ctx", {}) as Dictionary).duplicate(true)
			var wrath_mids: Array = []
			if verb == VERB_WRATH:
				var killcount: int = host._match.effective_wrath_destroy_count(1, val)
				wrath_mids = choose_wrath_targets(snap, killcount)
			if verb == VERB_REVIVE:
				var your_crypt: Array = snap.get("your_crypt_cards", []) as Array
				var elig := _revive_eligible_indices(your_crypt)
				var pick := choose_revive_target(your_crypt, elig)
				if pick >= 0:
					# convert global crypt idx to incantation-filtered idx
					var inc_filtered := -1
					var running := 0
					for ci in your_crypt.size():
						var cc := your_crypt[ci] as Dictionary
						if _card_kind(cc) != "incantation":
							continue
						var v2 := str(cc.get("verb", "")).to_lower()
						if v2 == VERB_REVIVE or v2 == VERB_TEARS:
							running += 1
							continue
						if ci == pick:
							inc_filtered = running
							break
						running += 1
					if inc_filtered >= 0:
						ctx["revive_steps"] = [{"revive_crypt_idx": inc_filtered}]
						amend_revive_ctx(snap, your_crypt, pick, ctx)
					else:
						ctx["revive_steps"] = [{"revive_skip": true}]
				else:
					ctx["revive_steps"] = [{"revive_skip": true}]
			if verb == VERB_INSIGHT and not ctx.has("insight_target"):
				ctx["insight_target"] = 0
			host._try_play_inc(1, int(action["hand_idx"]), action.get("sac", []) as Array, wrath_mids, ctx, false)
		"dethrone":
			host._try_play_dethrone(1, int(action["hand_idx"]), [int(action["target_mid"])], action.get("sac", []) as Array, false)
		"activate_aeoiu":
			var filtered_idx := int(action.get("ritual_crypt_idx", 0))
			filtered_idx = choose_aeoiu_crypt_ritual(snap, filtered_idx)
			if host._match.apply_aeoiu_ritual_from_crypt(1, int(action["noble_mid"]), filtered_idx) != "ok":
				return false
			host._broadcast_sync(false)
		"activate_noble":
			var nid := str(action.get("noble_id", ""))
			var verb2 := str(action.get("verb", ""))
			var val2 := int(action.get("value", 0))
			var ctx2: Dictionary = (action.get("ctx", {}) as Dictionary).duplicate(true)
			if nid == "indrr_incantation":
				var tgt: int = int(ctx2.get("insight_target", 0))
				var eff: int = host._match.insight_effective_n(1, val2)
				var top_list: Array = ctx2.get("insight_top", []) as Array
				var bot_list: Array = ctx2.get("insight_bottom", []) as Array
				if top_list.is_empty() and bot_list.is_empty():
					for i in mini(eff, int(snap.get("opp_deck", 0))):
						top_list.append(i)
				if host._match.activate_noble_with_insight(1, int(action["noble_mid"]), tgt, top_list, bot_list) != "ok":
					return false
				host._broadcast_sync(false)
			elif nid == "rndrr_incantation":
				var steps_ctx := {"revive_steps": [{"revive_skip": true}]}
				var your_crypt: Array = snap.get("your_crypt_cards", []) as Array
				var elig := _revive_eligible_indices(your_crypt)
				if not elig.is_empty():
					var pick := choose_revive_target(your_crypt, elig)
					if pick >= 0:
						var inc_filtered := -1
						var running := 0
						for ci in your_crypt.size():
							var cc := your_crypt[ci] as Dictionary
							if _card_kind(cc) != "incantation":
								continue
							var vv := str(cc.get("verb", "")).to_lower()
							if vv == VERB_REVIVE or vv == VERB_TEARS:
								running += 1
								continue
							if ci == pick:
								inc_filtered = running
								break
							running += 1
						if inc_filtered >= 0:
							steps_ctx = {"revive_steps": [{"revive_crypt_idx": inc_filtered}]}
				if host._match.apply_noble_revive_from_crypt(1, int(action["noble_mid"]), steps_ctx) != "ok":
					return false
				host._broadcast_sync(false)
			else:
				if verb2 == VERB_WRATH:
					var killcount: int = host._match.effective_wrath_destroy_count(1, val2)
					var wm := choose_wrath_targets(snap, killcount)
					if host._match.apply_noble_spell_like(1, int(action["noble_mid"]), verb2, val2, wm, ctx2) != "ok":
						return false
				else:
					if host._match.apply_noble_spell_like(1, int(action["noble_mid"]), verb2, val2, [], ctx2) != "ok":
						return false
				host._broadcast_sync(false)
		"activate_temple_phaedra":
			if host._match.apply_temple_phaedra_insight(1, int(action["temple_mid"]), 0, [], [1]) != "ok":
				return false
			host._broadcast_sync(false)
		"activate_temple_delpha":
			if host._match.apply_temple_delpha(1, int(action["temple_mid"]), int(action["ritual_mid"]), int(action["ritual_crypt_idx"])) != "ok":
				return false
			host._broadcast_sync(false)
		"activate_temple_gotha":
			if host._match.apply_temple_gotha(1, int(action["temple_mid"]), int(action["hand_idx"])) != "ok":
				return false
			host._broadcast_sync(false)
		"activate_temple_ytria":
			if host._match.apply_temple_ytria(1, int(action["temple_mid"])) != "ok":
				return false
			host._broadcast_sync(false)
		"nest":
			if host._match.nest_bird(1, int(action["bird_mid"]), int(action["temple_mid"])) != "ok":
				return false
			host._broadcast_sync(false)
		"fight":
			var atk: int = int(action["atk_mid"])
			var dp: int = int(action.get("def_power", 0))
			host._try_resolve_bird_fight(1, [atk], int(action["def_mid"]), {atk: dp}, false)
		"discard_draw":
			host._try_discard_draw(1, int(action["hand_idx"]), false)
		_:
			return false
	return true


func _end_turn(host: Node) -> void:
	if host._match == null:
		return
	var snap: Dictionary = host._match.snapshot(1)
	if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
		return
	if int(snap.get("current", -1)) != 1:
		return
	if bool(snap.get("woe_pending_you_respond", false)) or bool(snap.get("scion_pending_you_respond", false)) or bool(snap.get("eyrie_pending_you_respond", false)):
		return
	var hand: Array = snap.get("your_hand", []) as Array
	var indices := end_turn_discards(hand)
	host._try_end_turn(1, indices, true)


func end_turn_discards(hand: Array) -> Array:
	if hand.size() <= 7:
		return []
	var need := hand.size() - 7
	var scored: Array = []
	for i in hand.size():
		scored.append({"i": i, "s": _card_discard_score(hand[i])})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["s"]) < float(b["s"])
	)
	var out: Array = []
	for j in need:
		out.append(int((scored[j] as Dictionary)["i"]))
	return out


# =========================================================================
# Helpers
# =========================================================================

func _card_kind(c: Variant) -> String:
	return _GameSnapshotUtils.card_type(c)


func _card_discard_score(c: Variant) -> float:
	if typeof(c) != TYPE_DICTIONARY:
		return 0.0
	var cd := c as Dictionary
	var k := _card_kind(cd)
	if k == "ritual":
		return DD_W_RITUAL_BASE + float(cd.get("value", 0)) * DD_W_RITUAL_PER_VALUE
	if k == "incantation":
		var v := str(cd.get("verb", "")).to_lower()
		if v == "wrath":
			return DD_W_INC_WRATH
		if _CardTraits.is_dethrone(cd):
			return DD_W_INC_DETHRONE
		return DD_W_INC_BASE + float(cd.get("value", 0)) * DD_W_INC_PER_VALUE
	if k == "noble":
		return DD_W_NOBLE_BASE + float(_GameSnapshotUtils.noble_cost_for_id(str(cd.get("noble_id", "")))) * DD_W_NOBLE_PER_COST
	if k == "temple":
		return DD_W_TEMPLE_BASE + float(_GameSnapshotUtils.temple_cost_for_id(str(cd.get("temple_id", "")))) * DD_W_TEMPLE_PER_COST
	if k == "bird":
		return DD_W_BIRD_BASE + float(cd.get("power", 0)) * DD_W_BIRD_PER_POWER
	if k == "ring":
		return DD_W_RING
	return 0.0


func _pick_worst_hand_index(hand: Array) -> int:
	if hand.is_empty():
		return -1
	var best_i := 0
	var best_score: float = _card_discard_score(hand[0])
	for i in range(1, hand.size()):
		var s := _card_discard_score(hand[i])
		if s < best_score:
			best_score = s
			best_i = i
	return best_i


func _sac_field_stats(snap: Dictionary) -> Vector2:
	var your_field: Array = snap.get("your_field", []) as Array
	var field_power := 0.0
	var highest := 0.0
	for r in your_field:
		var v := float((r as Dictionary).get("value", 0))
		field_power += v
		if v > highest:
			highest = v
	return Vector2(field_power, highest)


func _sac_penalty(sac: Array, snap: Dictionary) -> float:
	if sac.is_empty():
		return 0.0
	var fs := _sac_field_stats(snap)
	return SAC_PENALTY_PER_RITUAL * float(sac.size()) + SAC_W_FIELD_POWER * fs.x + SAC_W_HIGH_RITUAL * fs.y


func _card_dd_cost(cd: Dictionary) -> float:
	var k := _card_kind(cd)
	if k == "ritual":
		return float(cd.get("value", 0))
	if k == "incantation":
		return float(cd.get("value", 0))
	if k == "noble":
		return float(_GameSnapshotUtils.noble_cost_for_id(str(cd.get("noble_id", ""))))
	if k == "temple":
		return float(_GameSnapshotUtils.temple_cost_for_id(str(cd.get("temple_id", ""))))
	if k == "bird":
		return float(cd.get("cost", 0))
	if k == "ring":
		return float(RING_COST)
	return 0.0


func _discard_draw_action_score(snap: Dictionary, card: Dictionary) -> float:
	var contrib := _card_discard_score(card)
	var cost := _card_dd_cost(card)
	var hand: Array = snap.get("your_hand", []) as Array
	var flood := maxi(0, hand.size() - 6)
	return W_DISCARD_DRAW + DD_W_FIELD_CONTRIB * contrib + DD_W_CARD_COST * cost + W_SF_DISCARD_FLOOD * float(flood)


func _active_lanes(your_field: Array, your_nobles: Array) -> Array:
	var out: Dictionary = {}
	for r in your_field:
		var v := int((r as Dictionary).get("value", 0))
		if v >= 1 and v <= 4:
			out[v] = true
	for n in your_nobles:
		var nid := str((n as Dictionary).get("noble_id", ""))
		if LANE_GRANTS.has(nid):
			out[int(LANE_GRANTS[nid])] = true
	var arr: Array = []
	for k in out.keys():
		arr.append(int(k))
	arr.sort()
	return arr


func _lane_in_set(lanes: Array, n: int) -> bool:
	for x in lanes:
		if int(x) == n:
			return true
	return false


func _count_new_lanes_if_ritual(your_field: Array, your_nobles: Array, value: int) -> int:
	var before := _active_lanes(your_field, your_nobles)
	var synthetic_field: Array = your_field.duplicate()
	synthetic_field.append({"mid": -999, "value": value})
	var after := _active_lanes(synthetic_field, your_nobles)
	return maxi(0, after.size() - before.size())


func _lanes_after_sac(your_field: Array, your_nobles: Array, sac_mids: Array) -> Array:
	var skip: Dictionary = {}
	for m in sac_mids:
		skip[int(m)] = true
	var kept: Array = []
	for r in your_field:
		var mid := int((r as Dictionary).get("mid", -1))
		if skip.has(mid):
			continue
		kept.append(r)
	return _active_lanes(kept, your_nobles)


func _greedy_sac_min(your_field: Array, target: int) -> Array:
	if target <= 0:
		return []
	var items: Array = []
	for r in your_field:
		items.append({"mid": int((r as Dictionary).get("mid", -1)), "v": int((r as Dictionary).get("value", 0))})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["v"]) < int(b["v"])
	)
	var total := 0
	var out: Array = []
	for it in items:
		out.append(int((it as Dictionary)["mid"]))
		total += int((it as Dictionary)["v"])
		if total >= target:
			return out
	return []


func _greedy_sac_high(your_field: Array, target: int) -> Array:
	if target <= 0:
		return []
	var items: Array = []
	for r in your_field:
		items.append({"mid": int((r as Dictionary).get("mid", -1)), "v": int((r as Dictionary).get("value", 0))})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["v"]) > int(b["v"])
	)
	var total := 0
	var out: Array = []
	for it in items:
		out.append(int((it as Dictionary)["mid"]))
		total += int((it as Dictionary)["v"])
		if total >= target:
			return out
	return []


func _has_noble_on_field(nobles: Array, noble_id: String) -> bool:
	for n in nobles:
		if str((n as Dictionary).get("noble_id", "")) == noble_id:
			return true
	return false


func _revive_eligible_indices(your_crypt: Array) -> Array:
	var out: Array = []
	for i in your_crypt.size():
		var c := your_crypt[i] as Dictionary
		if _card_kind(c) != "incantation":
			continue
		var v := str(c.get("verb", "")).to_lower()
		if v == VERB_REVIVE or v == VERB_TEARS or v == VERB_VOID:
			continue
		if _CardTraits.is_dethrone(c):
			continue
		out.append(i)
	return out


func _ritual_crypt_index(your_crypt: Array, global_idx: int) -> int:
	var running := -1
	for i in your_crypt.size():
		var c := your_crypt[i] as Dictionary
		if _card_kind(c) != "ritual":
			continue
		running += 1
		if i == global_idx:
			return running
	return -1
