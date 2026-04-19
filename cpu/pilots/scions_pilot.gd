extends ArcanaCpuBase
class_name ArcanaScionsPilot

# Port of sim/pilots/scions.py

const SCION_IDS := ["rmrsk_emanation", "smrsk_occultation", "tmrsk_annihilation"]


func _init() -> void:
	W_NOBLE_BASE = 70.0


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


func score_noble_play(card: Dictionary, eff_cost: int, sac: Array, active_lanes: Array) -> Variant:
	var base: Variant = super(card, eff_cost, sac, active_lanes)
	if base == null:
		return null
	var score := float(base)
	if SCION_IDS.has(str(card.get("noble_id", ""))):
		score += 15.0
	return score


func adjust_ring_score(card: Dictionary, score: float) -> float:
	if str(card.get("ring_id", "")) == "serraf_nobles":
		return score + 22.0
	return score


func scion_response(host: Node, snap: Dictionary) -> void:
	var st := str(snap.get("scion_pending_type", ""))
	var sid := int(snap.get("scion_pending_id", -1))
	if st == "rmrsk_draw":
		if not host._try_submit_scion_trigger(1, "accept", {"scion_id": sid}, false):
			host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		return
	if st == "smrsk_burn":
		host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		return
	if st == "tmrsk_woe":
		if int(snap.get("opp_hand", 0)) > 0:
			if not host._try_submit_scion_trigger(1, "accept", {"scion_id": sid, "woe_target": 0}, false):
				host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		else:
			host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		return
	host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
