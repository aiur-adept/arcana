extends ArcanaCpuBase
class_name ArcanaRitualReanimatorPilot

# Port of sim/pilots/ritual_reanimator.py

func _init() -> void:
	W_AEOIU_ACTIVATION_BASE = 70.0
	W_TEMPLE_BASE = 65.0
	W_NOBLE_BIG_TRIPLET = 25.0
	W_REVIVE_PRIO_RENEW = 30.0
	W_REVIVE_PRIO_BURN = 18.0
	W_REVIVE_PRIO_INSIGHT = 11.0
	W_REVIVE_PRIO_SEEK = 6.0
	W_REVIVE_PRIO_WOE = 2.0
	W_REVIVE_PRIO_WRATH = 0.0


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
	var you := int(snap.get("you", 0))
	var opp := 1 - you
	var your_crypt: Array = snap.get("your_crypt_cards", []) as Array
	var rit_count := 0
	for c in your_crypt:
		if _card_kind(c) == "ritual":
			rit_count += 1
	var deck_len := int(snap.get("your_deck", 0))
	var has_aeoiu := _has_noble_on_field(snap.get("your_nobles", []) as Array, "aeoiu_rituals")
	var ymp := int(snap.get("your_match_power", 0))
	var omp := int(snap.get("opp_match_power", 0))
	if deck_len <= 2 * val + 1:
		return opp
	if rit_count < 3 and deck_len > 2 * val + 2:
		return you
	if has_aeoiu and rit_count < 4 and deck_len > 2 * val + 2:
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


func adjust_incantation_score(snap: Dictionary, card: Dictionary, sac: Array, score: float) -> Variant:
	var b: Variant = super.adjust_incantation_score(snap, card, sac, score)
	if b == null:
		return null
	var out := float(b)
	var v := str(card.get("verb", "")).to_lower()
	if v == VERB_REVIVE:
		out += 6.0
	elif v == VERB_RENEW:
		out += 10.0
	return out


func score_noble_play(card: Dictionary, eff_cost: int, sac: Array, active_lanes: Array, snap: Dictionary = {}) -> Variant:
	var base: Variant = super(card, eff_cost, sac, active_lanes, snap)
	if base == null:
		return null
	var sc := float(base)
	if str(card.get("noble_id", "")) == "aeoiu_rituals":
		sc += 50.0
	return sc


func score_temple_play(card: Dictionary, sac: Array, lanes_after_sac: Array, snap: Dictionary) -> Variant:
	var base: Variant = super(card, sac, lanes_after_sac, snap)
	if base == null:
		return null
	var sc := float(base)
	if str(card.get("temple_id", "")) == "phaedra_illusion":
		var hand: Array = snap.get("your_hand", []) as Array
		if hand.size() >= 4:
			sc += 15.0
	return sc
