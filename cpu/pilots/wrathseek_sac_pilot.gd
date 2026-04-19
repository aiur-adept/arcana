extends ArcanaCpuBase
class_name ArcanaWrathseekSacPilot

# Port of sim/pilots/wrathseek_sac.py

func _init() -> void:
	REVIVE_VERB_PRIORITY = {
		VERB_WRATH: 10,
		VERB_WOE: 5,
		VERB_SEEK: 3,
		VERB_INSIGHT: 2,
		VERB_BURN: 1,
	}
	SAC_PENALTY_PER_RITUAL = 1.0


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
	if not vals.has(3) and hand.size() <= 5:
		return true
	return false


func adjust_incantation_score(card: Dictionary, _sac: Array, score: float) -> Variant:
	if str(card.get("verb", "")).to_lower() == VERB_WRATH:
		return score + 12.0
	return score


func wrath_score_adjust(_snap: Dictionary, base: float) -> float:
	return base + 6.0
