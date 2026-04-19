extends ArcanaCpuBase
class_name ArcanaTemplesPilot

# Port of sim/pilots/temples.py

const TEMPLE_PLAY_PRIORITY := {
	"phaedra_illusion": 30.0,
	"delpha_oracles":   25.0,
	"gotha_illness":    15.0,
	"eyrie_feathers":   20.0,
	"ytria_cycles":     0.0,
}


func _init() -> void:
	W_TEMPLE_BASE = 55.0
	W_TEMPLE_COST_BONUS = 0.0


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


func score_temple_play(card: Dictionary, sac: Array, lanes_after_sac: Array, snap: Dictionary) -> Variant:
	var base: Variant = super(card, sac, lanes_after_sac, snap)
	if base == null:
		return null
	var score := float(base)
	var tid := str(card.get("temple_id", ""))
	score += float(TEMPLE_PLAY_PRIORITY.get(tid, 0.0))
	return score


func ytria_min_hand() -> int:
	return 5
