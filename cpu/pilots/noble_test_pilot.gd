extends ArcanaCpuBase
class_name ArcanaNobleTestPilot

# Port of sim/pilots/noble_test.py

const POWER_NOBLES := ["krss_power", "trss_power", "yrss_power"]


func _init() -> void:
	W_NOBLE_BASE = 75.0
	W_NOBLE_GRANT_NEW_LANE = 55.0
	W_DETHRONE_PER_COST = 5.0


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
	var has_serraf := false
	var cheap_noble := false
	var has_one := false
	for c in hand:
		var cd := c as Dictionary
		var k := _card_kind(cd)
		if k == "ring" and str(cd.get("ring_id", "")) == "serraf_nobles":
			has_serraf = true
		elif k == "noble":
			var cost: int = _GameSnapshotUtils.noble_cost_for_id(str(cd.get("noble_id", "")))
			if cost <= 3:
				cheap_noble = true
		elif k == "ritual" and int(cd.get("value", 0)) == 1:
			has_one = true
	if has_serraf and cheap_noble:
		return false
	if not has_one and rituals.size() >= 3:
		return true
	return false


func score_noble_play(card: Dictionary, eff_cost: int, sac: Array, active_lanes: Array, snap: Dictionary = {}) -> Variant:
	var base: Variant = super(card, eff_cost, sac, active_lanes, snap)
	if base == null:
		return null
	var score := float(base)
	if POWER_NOBLES.has(str(card.get("noble_id", ""))):
		score += 25.0
	return score


func adjust_ring_score(card: Dictionary, score: float) -> float:
	if str(card.get("ring_id", "")) == "serraf_nobles":
		return score + 25.0
	return score
