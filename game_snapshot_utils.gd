extends RefCounted
class_name GameSnapshotUtils

const _NOBLES_DIR := "res://nobles"
static var _noble_cost_cache: Dictionary = {}
static var _noble_cost_cache_built: bool = false


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
	if t == "ring":
		return short_noble_name(str(card.get("name", "Ring")))
	var verb := str(card.get("verb", ""))
	var vl := verb.to_lower()
	if vl == "void":
		return "Void"
	if vl == "wrath":
		return "Wrath"
	return "%s %d" % [verb, int(card.get("value", 0))]


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
	if t == "ring":
		return "rg:%s" % str(card.get("ring_id", ""))
	return "i:%s:%d" % [str(card.get("verb", "")).to_lower(), int(card.get("value", 0))]


static func noble_cost_for_id(nid: String) -> int:
	if not _noble_cost_cache_built:
		_build_noble_cost_cache()
	return int(_noble_cost_cache.get(nid, 0))


static func refresh_noble_cost_cache() -> void:
	_noble_cost_cache.clear()
	_noble_cost_cache_built = false
	_build_noble_cost_cache()


static func _build_noble_cost_cache() -> void:
	_noble_cost_cache_built = true
	var fns: Array[String] = []
	if ResourceLoader.has_method(&"list_directory"):
		for fn in ResourceLoader.list_directory(_NOBLES_DIR):
			var s := str(fn)
			if s.ends_with("/") or not s.ends_with(".gd"):
				continue
			fns.append(s)
	if fns.is_empty():
		var dir := DirAccess.open(_NOBLES_DIR)
		if dir == null:
			return
		dir.list_dir_begin()
		while true:
			var fn2 := dir.get_next()
			if fn2 == "":
				break
			if dir.current_is_dir() or not fn2.ends_with(".gd"):
				continue
			fns.append(fn2)
		dir.list_dir_end()
	var seen: Dictionary = {}
	for fn in fns:
		if seen.has(fn):
			continue
		seen[fn] = true
		var script := load("%s/%s" % [_NOBLES_DIR, fn])
		if script == null:
			continue
		var hook: Variant = script.new()
		if hook == null or not hook.has_method("build_definition"):
			continue
		var def: Variant = hook.call("build_definition")
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var d := def as Dictionary
		var nid := str(d.get("id", ""))
		if nid.is_empty():
			continue
		_noble_cost_cache[nid] = int(d.get("cost", 0))


static func temple_cost_for_id(tid: String) -> int:
	match tid:
		"ytria_cycles":
			return 9
		"eyrie_feathers":
			return 6
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
		if str(card.get("verb", "")).to_lower() == "wrath":
			return {"count": 0, "filled": false}
		return {"count": max(0, int(card.get("value", 0))), "filled": false}
	if t == "noble":
		return {"count": noble_cost_for_id(str(card.get("noble_id", ""))), "filled": false}
	if t == "temple":
		var raw := int(card.get("cost", 0))
		if raw <= 0:
			raw = temple_cost_for_id(str(card.get("temple_id", "")))
		return {"count": max(0, raw), "filled": false}
	if t == "ring":
		return {"count": 2, "filled": false}
	return {"count": 0, "filled": false}
