extends ArcanaCpuBase
class_name ArcanaOccultationPilot

# Port of sim/pilots/occultation.py

func _init() -> void:
	W_NOBLE_BIG_TRIPLET = 55.0
	W_EFFECT_BURN_BASE = 4.0
	W_EFFECT_BURN_VALUE = 2.0
	W_REVIVE_PRIO_BURN = 8.0
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
	var has_aeoiu := _has_noble_on_field(snap.get("your_nobles", []) as Array, "aeoiu_rituals")
	var deck_len := int(snap.get("your_deck", 0))
	if has_aeoiu and rit_count < 3 and deck_len > 2 * val + 3:
		return you
	return opp


func adjust_ring_score(card: Dictionary, score: float) -> float:
	if str(card.get("ring_id", "")) == "cymbil_occultation":
		return score + 15.0
	return score


func score_noble_play(card: Dictionary, eff_cost: int, sac: Array, active_lanes: Array, snap: Dictionary = {}) -> Variant:
	var base: Variant = super(card, eff_cost, sac, active_lanes, snap)
	if base == null:
		return null
	var score := float(base)
	if str(card.get("noble_id", "")) == "aeoiu_rituals":
		score += 30.0
	return score
