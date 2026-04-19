extends ArcanaCpuBase
class_name ArcanaIncantationsPilot

# Port of sim/pilots/incantations.py

func _init() -> void:
	REVIVE_VERB_PRIORITY = {
		VERB_WOE: 7,
		VERB_BURN: 5,
		VERB_WRATH: 9,
		VERB_SEEK: 3,
		VERB_INSIGHT: 2,
	}


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
	if not vals.has(2) and hand.size() <= 5:
		return true
	return false


func wrath_score_adjust(snap: Dictionary, base: float) -> float:
	var opp_field: Array = snap.get("opp_field", []) as Array
	var rit_power := 0
	for r in opp_field:
		rit_power += int((r as Dictionary).get("value", 0))
	if opp_field.size() < 2 and rit_power < 5:
		return base - 20.0
	return base + 4.0
