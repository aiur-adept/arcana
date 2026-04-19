extends ArcanaCpuBase
class_name ArcanaEmanationPilot

# Port of sim/pilots/emanation.py

func _init() -> void:
	W_EFFECT_SEEK_VALUE = 4.0
	W_EFFECT_INSIGHT_VALUE = 2.0


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


func adjust_ring_score(card: Dictionary, score: float) -> float:
	if str(card.get("ring_id", "")) == "sybiline_emanation":
		return score + 25.0
	return score


func score_dethrone(card: Dictionary, sac: Array, target: Dictionary, snap: Dictionary = {}) -> Variant:
	if target.is_empty():
		return null
	var tcost: int = _GameSnapshotUtils.noble_cost_for_id(str(target.get("noble_id", "")))
	if tcost < 6:
		return null
	return super(card, sac, target, snap)


func scion_response(host: Node, snap: Dictionary) -> void:
	var st := str(snap.get("scion_pending_type", ""))
	var sid := int(snap.get("scion_pending_id", -1))
	if st == "rmrsk_draw":
		if not host._try_submit_scion_trigger(1, "accept", {"scion_id": sid}, false):
			host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		return
	super(host, snap)
