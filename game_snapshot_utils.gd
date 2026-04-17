extends RefCounted
class_name GameSnapshotUtils

const CardTraits = preload("res://card_traits.gd")

static func your_crypt_cards_from_snap(snap: Dictionary) -> Array:
	return (snap.get("your_crypt_cards", []) as Array).duplicate(true)


static func opp_crypt_cards_from_snap(snap: Dictionary) -> Array:
	return (snap.get("opp_crypt_cards", []) as Array).duplicate(true)


static func your_abyss_cards_from_snap(snap: Dictionary) -> Array:
	return (snap.get("your_inc_abyss_cards", []) as Array).duplicate(true)


static func opp_abyss_cards_from_snap(snap: Dictionary) -> Array:
	return (snap.get("opp_inc_abyss_cards", []) as Array).duplicate(true)


static func filtered_crypt_cards(cards: Array, kinds: Array) -> Array:
	var out: Array = []
	for card in cards:
		if kinds.has(card_type(card)):
			out.append(card)
	return out


static func crypt_stack_entries(cards: Array) -> Array:
	var by_key: Dictionary = {}
	for c in cards:
		var key := hand_card_stack_key(c)
		if not by_key.has(key):
			by_key[key] = {"card": c, "count": 0}
		var row: Dictionary = by_key[key]
		row["count"] = int(row.get("count", 0)) + 1
		by_key[key] = row
	var keys: Array = by_key.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		var da: Dictionary = by_key[a]
		var db: Dictionary = by_key[b]
		return card_label(da.get("card", {})) < card_label(db.get("card", {}))
	)
	var out: Array = []
	for k in keys:
		out.append(by_key[k])
	return out


static func short_noble_name(full_name: String) -> String:
	var idx := full_name.find(",")
	if idx <= 0:
		return full_name
	return full_name.substr(0, idx).strip_edges()


static func card_type(card: Variant) -> String:
	if typeof(card) != TYPE_DICTIONARY:
		return ""
	return CardTraits.effective_kind(card as Dictionary)


static func card_label(card: Variant) -> String:
	var t := card_type(card)
	if t == "ritual":
		return "%d-R" % int(card.get("value", 0))
	if t == "bird":
		return str(card.get("name", "Bird"))
	if t == "noble":
		return short_noble_name(str(card.get("name", "Noble")))
	if t == "temple":
		return short_noble_name(str(card.get("name", "Temple")))
	if t == "dethrone":
		return "Dethrone 4"
	return "%s %d" % [str(card.get("verb", "")), int(card.get("value", 0))]


static func hand_card_stack_key(card: Variant) -> String:
	var t := card_type(card)
	if t == "ritual":
		return "r:%d" % int(card.get("value", 0))
	if t == "bird":
		return "b:%s" % str(card.get("bird_id", ""))
	if t == "noble":
		return "n:%s" % str(card.get("noble_id", ""))
	if t == "temple":
		return "t:%s" % str(card.get("temple_id", ""))
	if t == "dethrone":
		return "dethrone"
	return "i:%s:%d" % [str(card.get("verb", "")).to_lower(), int(card.get("value", 0))]


static func noble_cost_for_id(nid: String) -> int:
	match nid:
		"krss_power":
			return 2
		"rmrsk_emanation", "smrsk_occultation", "tmrsk_annihilation":
			return 2
		"trss_power":
			return 3
		"yrss_power":
			return 4
		"xytzr_emanation", "yytzr_occultation", "zytzr_annihilation", "aeoiu_rituals":
			return 4
		"sndrr_incantation", "wndrr_incantation", "bndrr_incantation", "rndrr_incantation", "indrr_incantation":
			return 3
		_:
			return 0


static func temple_cost_for_id(tid: String) -> int:
	match tid:
		"ytria_cycles":
			return 9
		"phaedra_illusion", "delpha_oracles", "gotha_illness":
			return 7
		_:
			return 7


static func card_corner_pip_spec(card: Variant) -> Dictionary:
	var t := card_type(card)
	if t == "ritual":
		return {"count": max(0, int(card.get("value", 0))), "filled": true}
	if t == "bird":
		return {"count": max(0, int(card.get("cost", 0))), "filled": false}
	if t == "incantation":
		return {"count": max(0, int(card.get("value", 0))), "filled": false}
	if t == "noble":
		return {"count": noble_cost_for_id(str(card.get("noble_id", ""))), "filled": false}
	if t == "temple":
		var raw := int(card.get("cost", 0))
		if raw <= 0:
			raw = temple_cost_for_id(str(card.get("temple_id", "")))
		return {"count": max(0, raw), "filled": false}
	return {"count": 0, "filled": false}
