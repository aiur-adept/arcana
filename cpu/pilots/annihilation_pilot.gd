extends ArcanaCpuBase
class_name ArcanaAnnihilationPilot

# Port of sim/pilots/annihilation.py

func _init() -> void:
	W_NOBLE_BIG_TRIPLET = 55.0
	W_EFFECT_WOE_PER_DISCARD = 4.5
	W_EFFECT_WRATH_PER_KILLED = 3.2


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
	if not vals.has(3) and not vals.has(4) and hand.size() <= 5:
		return true
	return false


func adjust_ring_score(card: Dictionary, score: float) -> float:
	if str(card.get("ring_id", "")) == "celadon_annihilation":
		return score + 20.0
	return score


func wrath_score_adjust(snap: Dictionary, base: float) -> float:
	if _has_noble_on_field(snap.get("your_nobles", []) as Array, "zytzr_annihilation"):
		return base + 10.0
	return base


func scion_response(host: Node, snap: Dictionary) -> void:
	var st := str(snap.get("scion_pending_type", ""))
	var sid := int(snap.get("scion_pending_id", -1))
	if st == "tmrsk_woe":
		if int(snap.get("opp_hand", 0)) > 0:
			if not host._try_submit_scion_trigger(1, "accept", {"scion_id": sid, "woe_target": 0}, false):
				host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		else:
			host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
		return
	super(host, snap)
