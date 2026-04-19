extends ArcanaCpuBase
class_name ArcanaRevivePilot

# Port of sim/pilots/revive.py

func _init() -> void:
	REVIVE_VERB_PRIORITY = {
		VERB_SEEK: 10,
		VERB_INSIGHT: 6,
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
	if not vals.has(2) and rituals.size() >= 3:
		return true
	return false


func score_noble_play(card: Dictionary, eff_cost: int, sac: Array, active_lanes: Array) -> Variant:
	var base: Variant = super(card, eff_cost, sac, active_lanes)
	if base == null:
		return null
	var score := float(base)
	if str(card.get("noble_id", "")) == "rndrr_incantation":
		score += 30.0
	return score
