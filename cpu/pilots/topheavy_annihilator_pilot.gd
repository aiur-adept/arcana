extends ArcanaCpuBase
class_name ArcanaTopheavyAnnihilatorPilot

# Port of sim/pilots/topheavy_annihilator.py

func _init() -> void:
	W_NOBLE_BIG_TRIPLET = 40.0


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
	var has_big_play := false
	for c in hand:
		var cd := c as Dictionary
		var k := _card_kind(cd)
		if k == "incantation" and str(cd.get("verb", "")).to_lower() == VERB_WRATH:
			has_big_play = true
			break
		if k == "ritual" and int(cd.get("value", 0)) == 4:
			has_big_play = true
			break
	if not has_big_play and rituals.size() >= 3:
		return true
	return false


func _score_incantation(host: Node, snap: Dictionary, card: Dictionary, hand_idx: int, active_lanes: Array, your_field: Array) -> Variant:
	var verb := str(card.get("verb", "")).to_lower()
	var val := int(card.get("value", 0))
	if verb == VERB_VOID:
		return null
	var eff_val: int = host._match.effective_incantation_cost(1, verb, val)
	if eff_val > 0 and not _lane_in_set(active_lanes, eff_val):
		# Topheavy refuses to sac for incantations with one exception.
		if verb == VERB_WRATH and _has_noble_on_field(snap.get("your_nobles", []) as Array, "zytzr_annihilation"):
			var sac := _greedy_sac_high(your_field, eff_val)
			if sac.is_empty():
				return null
			var lanes_after := _lanes_after_sac(your_field, snap.get("your_nobles", []) as Array, sac)
			if lanes_after.is_empty():
				return null
			var eff: Variant = _score_effect(host, snap, verb, val)
			if eff == null:
				return null
			var score := float((eff as Dictionary)["score"]) + INC_BASE_BONUS - _sac_penalty(sac)
			var ctx: Dictionary = ((eff as Dictionary)["ctx"] as Dictionary).duplicate(true)
			return {"score": score, "kind": "incantation", "hand_idx": hand_idx, "sac": sac, "ctx": ctx, "verb": verb, "value": val}
		return null
	var eff2: Variant = _score_effect(host, snap, verb, val)
	if eff2 == null:
		return null
	var score2 := float((eff2 as Dictionary)["score"]) + INC_BASE_BONUS
	var ctx2: Dictionary = ((eff2 as Dictionary)["ctx"] as Dictionary).duplicate(true)
	return {"score": score2, "kind": "incantation", "hand_idx": hand_idx, "sac": [], "ctx": ctx2, "verb": verb, "value": val}
