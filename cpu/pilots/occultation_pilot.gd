extends ArcanaCpuBase
class_name ArcanaOccultationPilot

# Port of sim/pilots/occultation.py — ramp via self-mill, Revive→Renew, Renew.

var W_REVIVE_PLAY_BIAS_BURN: float = 16.0
var W_REVIVE_PLAY_BIAS_CRYPT_RENEW_NO_HAND_RENEW: float = 18.0
var W_REVIVE_PLAY_ELIG_MISC: float = 4.0

func _init() -> void:
	W_NOBLE_BIG_TRIPLET = 55.0
	W_EFFECT_BURN_BASE = 4.0
	W_EFFECT_BURN_VALUE = 2.0
	W_REVIVE_PRIO_RENEW = 30.0
	W_REVIVE_PRIO_BURN = 18.0
	W_REVIVE_PRIO_WOE = 4.0
	W_REVIVE_PRIO_SEEK = 3.0
	W_REVIVE_PRIO_INSIGHT = 2.0
	W_REVIVE_PRIO_WRATH = 0.0


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
	var vals: Dictionary = {}
	for r in rituals:
		vals[int((r as Dictionary).get("value", 0))] = true
	if not vals.has(1):
		return true
	return false


func choose_burn_target(snap: Dictionary, val: int) -> int:
	var you := int(snap.get("you", 0))
	var opp := 1 - you
	var your_crypt: Array = snap.get("your_crypt_cards", []) as Array
	var rit_count := 0
	for c in your_crypt:
		if _card_kind(c) == "ritual":
			rit_count += 1
	var deck_len := int(snap.get("your_deck", 0))
	var has_aeoiu := _has_noble_on_field(snap.get("your_nobles", []) as Array, "aeoiu_rituals")
	var yyt := _has_noble_on_field(snap.get("your_nobles", []) as Array, "yytzr_occultation")
	var ymp := int(snap.get("your_match_power", 0))
	var omp := int(snap.get("opp_match_power", 0))
	if deck_len <= 2 * val + 1:
		return opp
	if rit_count < 3 and deck_len > 2 * val + 2:
		return you
	if yyt and rit_count < 5 and deck_len > 2 * val + 2:
		return you
	if has_aeoiu and rit_count < 3 and deck_len > 2 * val + 3:
		return you
	if omp > ymp + 2 and rit_count < 3:
		return you
	return opp


func amend_revive_ctx(snap: Dictionary, your_crypt: Array, global_pick: int, ctx: Dictionary) -> void:
	if global_pick < 0 or global_pick >= your_crypt.size():
		return
	var c := your_crypt[global_pick] as Dictionary
	if _card_kind(c) != "incantation":
		return
	if str(c.get("verb", "")).to_lower() != VERB_BURN:
		return
	var val := int(c.get("value", 0))
	var you := int(snap.get("you", 0))
	if choose_burn_target(snap, val) != you:
		return
	var steps: Array = ctx.get("revive_steps", []) as Array
	if steps.is_empty():
		return
	var s0: Dictionary = (steps[0] as Dictionary).duplicate(true)
	var nested: Dictionary = s0.get("nested", {}) as Dictionary
	nested = nested.duplicate(true) if not nested.is_empty() else {}
	nested["mill_target"] = you
	s0["nested"] = nested
	steps[0] = s0
	ctx["revive_steps"] = steps


func _hand_has_renew(snap: Dictionary) -> bool:
	var hand: Array = snap.get("your_hand", []) as Array
	for c in hand:
		var d := c as Dictionary
		if _card_kind(d) != "incantation":
			continue
		if str(d.get("verb", "")).to_lower() == VERB_RENEW:
			return true
	return false


func _revive_play_crypt_bias(snap: Dictionary) -> float:
	var crypt: Array = snap.get("your_crypt_cards", []) as Array
	var elig: Array = []
	for i in crypt.size():
		var c := crypt[i] as Dictionary
		if _card_kind(c) != "incantation":
			continue
		var pv := str(c.get("verb", "")).to_lower()
		if pv == VERB_REVIVE or pv == VERB_TEARS or pv == VERB_DETHRONE:
			continue
		elig.append(i)
	if elig.is_empty():
		return 0.0
	var pick := choose_revive_target(crypt, elig)
	if pick < 0:
		return 0.0
	var cc := crypt[pick] as Dictionary
	var vv := str(cc.get("verb", "")).to_lower()
	if vv == VERB_RENEW:
		if _hand_has_renew(snap):
			return 0.0
		return W_REVIVE_PLAY_BIAS_CRYPT_RENEW_NO_HAND_RENEW
	if vv == VERB_BURN:
		return W_REVIVE_PLAY_BIAS_BURN
	return W_REVIVE_PLAY_ELIG_MISC


func adjust_incantation_score(snap: Dictionary, card: Dictionary, sac: Array, score: float) -> Variant:
	var b: Variant = super.adjust_incantation_score(snap, card, sac, score)
	if b == null:
		return null
	var out := float(b)
	var v := str(card.get("verb", "")).to_lower()
	if v == VERB_REVIVE:
		out += 6.0 + _revive_play_crypt_bias(snap)
	elif v == VERB_RENEW:
		out += 14.0
	return out


func adjust_ring_score(card: Dictionary, score: float) -> float:
	if str(card.get("ring_id", "")) == "cymbil_occultation":
		return score + 15.0
	return score


func score_noble_play(card: Dictionary, eff_cost: int, sac: Array, active_lanes: Array, snap: Dictionary = {}) -> Variant:
	var base: Variant = super(card, eff_cost, sac, active_lanes, snap)
	if base == null:
		return null
	var sc := float(base)
	if str(card.get("noble_id", "")) == "aeoiu_rituals":
		sc += 30.0
	return sc
