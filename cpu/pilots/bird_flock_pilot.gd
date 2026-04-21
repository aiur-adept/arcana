extends ArcanaCpuBase
class_name ArcanaBirdTestPilot

# Port of sim/pilots/bird_flock.py

const UNNEST_BIRDS := ["raven", "hawk", "eagle"]


func _init() -> void:
	W_TEMPLE_EYRIE_BONUS = 50.0
	W_BIRD_POWER_BONUS = 2.0


func mulligan(_host: Node, snap: Dictionary) -> bool:
	var hand: Array = snap.get("your_hand", [])
	if hand.is_empty():
		return false
	var rituals: Array = []
	var has_bird := false
	for c in hand:
		var k := _card_kind(c)
		if k == "ritual":
			rituals.append(c)
		elif k == "bird":
			has_bird = true
	if rituals.is_empty() or rituals.size() == hand.size():
		return true
	var vals: Dictionary = {}
	for r in rituals:
		vals[int((r as Dictionary).get("value", 0))] = true
	if not vals.has(1):
		return true
	if not has_bird and rituals.size() >= 3:
		return true
	return false


func should_nest(bird: Dictionary, _temple: Dictionary) -> bool:
	var bid := str(bird.get("bird_id", ""))
	if UNNEST_BIRDS.has(bid):
		return false
	return true


func _pick_ring_host(card: Dictionary, hosts: Array, your_nobles: Array, your_birds: Array) -> Dictionary:
	if str(card.get("ring_id", "")) == "sinofia_feathers":
		# Prefer a raven that is wild
		for b in your_birds:
			var bd := b as Dictionary
			if str(bd.get("bird_id", "")) != "raven":
				continue
			if int(bd.get("nest_temple_mid", -1)) >= 0:
				continue
			var mid := int(bd.get("mid", -1))
			for h in hosts:
				if h["kind"] == "bird" and int(h["mid"]) == mid:
					return h
		# Otherwise the highest-power unnested bird
		var best_mid := -1
		var best_pow := -1
		for b in your_birds:
			var bd2 := b as Dictionary
			if int(bd2.get("nest_temple_mid", -1)) >= 0:
				continue
			var p := int(bd2.get("power", 0))
			if p > best_pow:
				best_pow = p
				best_mid = int(bd2.get("mid", -1))
		if best_mid >= 0:
			for h in hosts:
				if h["kind"] == "bird" and int(h["mid"]) == best_mid:
					return h
	return super(card, hosts, your_nobles, your_birds)
