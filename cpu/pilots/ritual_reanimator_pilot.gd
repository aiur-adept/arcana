extends ArcanaCpuBase
class_name ArcanaRitualReanimatorPilot

# Port of sim/pilots/ritual_reanimator.py

func _init() -> void:
	W_AEOIU_ACTIVATION_BASE = 70.0
	W_TEMPLE_BASE = 65.0
	W_NOBLE_BIG_TRIPLET = 25.0


func mulligan(_host: Node, snap: Dictionary) -> bool:
	var hand: Array = snap.get("your_hand", [])
	if hand.is_empty():
		return false
	var rituals: Array = []
	var has_action := false
	for c in hand:
		var k := _card_kind(c)
		if k == "ritual":
			rituals.append(c)
		elif k == "incantation":
			has_action = true
	if rituals.is_empty() or rituals.size() == hand.size():
		return true
	var vals: Dictionary = {}
	for r in rituals:
		vals[int((r as Dictionary).get("value", 0))] = true
	if not vals.has(1):
		return true
	if not has_action and rituals.size() >= 3:
		return true
	return false


func choose_burn_target(snap: Dictionary, val: int) -> int:
	var your_crypt: Array = snap.get("your_crypt_cards", []) as Array
	var rit_count := 0
	for c in your_crypt:
		if _card_kind(c) == "ritual":
			rit_count += 1
	var has_aeoiu := _has_noble_on_field(snap.get("your_nobles", []) as Array, "aeoiu_rituals")
	var deck_len := int(snap.get("your_deck", 0))
	if has_aeoiu and rit_count < 3 and deck_len > 2 * val + 3:
		return 1
	return 0


func score_noble_play(card: Dictionary, eff_cost: int, sac: Array, active_lanes: Array, snap: Dictionary = {}) -> Variant:
	var base: Variant = super(card, eff_cost, sac, active_lanes, snap)
	if base == null:
		return null
	var score := float(base)
	if str(card.get("noble_id", "")) == "aeoiu_rituals":
		score += 50.0
	return score


func score_temple_play(card: Dictionary, sac: Array, lanes_after_sac: Array, snap: Dictionary) -> Variant:
	var base: Variant = super(card, sac, lanes_after_sac, snap)
	if base == null:
		return null
	var score := float(base)
	if str(card.get("temple_id", "")) == "phaedra_illusion":
		var hand: Array = snap.get("your_hand", []) as Array
		if hand.size() >= 4:
			score += 15.0
	return score
