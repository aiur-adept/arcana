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


func _score_incantation(host: Node, snap: Dictionary, card: Dictionary, hand_idx: int, active_lanes: Array, _your_field: Array) -> Variant:
	var verb := str(card.get("verb", "")).to_lower()
	var val := int(card.get("value", 0))
	if verb == VERB_VOID:
		return null
	if verb == VERB_WRATH:
		var wrath_sac := _pick_wrath_sacrifice_from_snap(snap)
		if wrath_sac.is_empty():
			return null
		var eff_wrath: Variant = _score_effect(host, snap, verb, val)
		if eff_wrath == null:
			return null
		var score_wrath := float((eff_wrath as Dictionary)["score"]) + INC_BASE_BONUS - _sac_penalty(wrath_sac, snap)
		var kill_val := _wrath_expected_killed_value_local(host, snap, val)
		var self_sac_val := _sac_total_value_local(snap.get("your_field", []) as Array, wrath_sac)
		if kill_val <= self_sac_val:
			return null
		var adj_wrath: Variant = adjust_incantation_score(snap, card, wrath_sac, score_wrath)
		if adj_wrath == null:
			return null
		var fadj := float(adj_wrath)
		var ymp2 := int(snap.get("your_match_power", 0))
		var omp2 := int(snap.get("opp_match_power", 0))
		var gap := maxi(0, omp2 - ymp2)
		fadj += W_SF_INC_BEHIND * float(gap) * float(val) * 0.1
		var ctx_wrath: Dictionary = ((eff_wrath as Dictionary)["ctx"] as Dictionary).duplicate(true)
		return {"score": fadj, "kind": "incantation", "hand_idx": hand_idx, "sac": wrath_sac, "ctx": ctx_wrath, "verb": verb, "value": val}
	var eff_val: int = host._match.effective_incantation_cost(1, verb, val)
	if eff_val > 0 and not _lane_in_set(active_lanes, eff_val):
		# Topheavy refuses to sac for non-Wrath incantations.
		return null
	var eff2: Variant = _score_effect(host, snap, verb, val)
	if eff2 == null:
		return null
	var score2 := float((eff2 as Dictionary)["score"]) + INC_BASE_BONUS
	var ctx2: Dictionary = ((eff2 as Dictionary)["ctx"] as Dictionary).duplicate(true)
	return {"score": score2, "kind": "incantation", "hand_idx": hand_idx, "sac": [], "ctx": ctx2, "verb": verb, "value": val}


func _pick_wrath_sacrifice_from_snap(snap: Dictionary) -> Array:
	var your_field: Array = snap.get("your_field", []) as Array
	if your_field.is_empty():
		return []
	var sorted_field: Array = your_field.duplicate()
	sorted_field.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var av := int(a.get("value", 0))
		var bv := int(b.get("value", 0))
		if av == bv:
			return int(a.get("mid", -1)) < int(b.get("mid", -1))
		return av > bv
	)
	for r in sorted_field:
		var mid := int((r as Dictionary).get("mid", -1))
		if mid < 0:
			continue
		var lanes_after := _lanes_after_sac(your_field, snap.get("your_nobles", []) as Array, [mid])
		if lanes_after.size() >= 1:
			return [mid]
	var fallback_mid := choose_wrath_instigator_sac_from_snap(snap)
	if fallback_mid < 0:
		return []
	return [fallback_mid]


func _wrath_expected_killed_value_local(host: Node, snap: Dictionary, val: int) -> int:
	var opp_field: Array = snap.get("opp_field", []) as Array
	if opp_field.is_empty():
		return 0
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
	return killed_val


func _sac_total_value_local(field: Array, sac_mids: Array) -> int:
	var total := 0
	for mid_v in sac_mids:
		var mid := int(mid_v)
		for r in field:
			var d := r as Dictionary
			if int(d.get("mid", -1)) == mid:
				total += int(d.get("value", 0))
				break
	return total
