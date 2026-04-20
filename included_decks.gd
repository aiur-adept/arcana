extends Object

const BUNDLE_DIR := "res://included_decks"
const MANIFEST_PATH := "res://included_decks/index.json"
const LEGACY_BUNDLE_PATH := "res://included_decks.json"
const TOKEN_PREFIX := "included:"
static var _issues_logged := false
static var _cache: Dictionary = {}
static var _cache_slugs: Array[String] = []
static var _cache_built := false


static func _normalize_slug(file_name: String) -> String:
	var fn := file_name.strip_edges()
	if fn.to_lower().ends_with(".json"):
		return fn.substr(0, fn.length() - 5)
	return fn


static func is_token(path: String) -> bool:
	return path.begins_with(TOKEN_PREFIX)


static func token(slug: String) -> String:
	return TOKEN_PREFIX + slug


static func slug_from_token(path: String) -> String:
	if not is_token(path):
		return ""
	return path.substr(TOKEN_PREFIX.length())


static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var p: Variant = JSON.parse_string(f.get_as_text())
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	return p as Dictionary


static func _manifest_slugs() -> Array[String]:
	var out: Array[String] = []
	var manifest := _read_json_dict(MANIFEST_PATH)
	var slugs_variant: Variant = manifest.get("slugs", null)
	if typeof(slugs_variant) == TYPE_ARRAY:
		for s in (slugs_variant as Array):
			var slug := _normalize_slug(str(s))
			if not slug.is_empty():
				out.append(slug)
	if out.is_empty():
		var dir := DirAccess.open(BUNDLE_DIR)
		if dir != null:
			dir.list_dir_begin()
			while true:
				var fn := dir.get_next()
				if fn == "":
					break
				if dir.current_is_dir():
					continue
				if not fn.to_lower().ends_with(".json"):
					continue
				if fn == "index.json":
					continue
				out.append(_normalize_slug(fn))
			dir.list_dir_end()
			out.sort()
	return out


static func _build_cache() -> void:
	if _cache_built:
		return
	_cache_built = true
	_cache.clear()
	_cache_slugs.clear()
	for slug in _manifest_slugs():
		var path := "%s/%s.json" % [BUNDLE_DIR, slug]
		var payload := _read_json_dict(path)
		if payload.is_empty():
			continue
		_cache[slug] = payload
		_cache_slugs.append(slug)
	if _cache_slugs.is_empty():
		_load_legacy_bundle_into_cache()
	_log_data_issues_once()


static func _load_legacy_bundle_into_cache() -> void:
	var bundle := _read_json_dict(LEGACY_BUNDLE_PATH)
	var decks_variant: Variant = bundle.get("decks", null)
	if typeof(decks_variant) != TYPE_ARRAY:
		return
	var decks := decks_variant as Array
	for i in decks.size():
		var item: Variant = decks[i]
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry := item as Dictionary
		var payload := _entry_payload(entry)
		var slug := _entry_slug(entry)
		if slug.is_empty():
			slug = "deck_%d" % (i + 1)
		if _cache.has(slug):
			continue
		_cache[slug] = payload
		_cache_slugs.append(slug)


static func reload() -> void:
	_cache_built = false
	_issues_logged = false
	_cache.clear()
	_cache_slugs.clear()


static func slug_list() -> Array[String]:
	_build_cache()
	return _cache_slugs.duplicate()


static func payload_for_slug(slug: String) -> Dictionary:
	_build_cache()
	var p: Variant = _cache.get(slug, null)
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	return (p as Dictionary).duplicate(true)


static func _entry_slug(entry: Dictionary) -> String:
	var file_name := _normalize_slug(str(entry.get("file_name", "")))
	if not file_name.is_empty():
		return file_name
	var payload := _entry_payload(entry)
	var deck_name := str(payload.get("deck_name", "")).strip_edges()
	if deck_name.is_empty():
		deck_name = str(entry.get("deck_name", "")).strip_edges()
	return deck_name


static func _entry_payload(entry: Dictionary) -> Dictionary:
	if entry.has("payload"):
		var payload: Variant = entry.get("payload")
		if typeof(payload) == TYPE_DICTIONARY:
			return payload as Dictionary
	return entry


static func _log_data_issues_once() -> void:
	if _issues_logged:
		return
	_issues_logged = true
	for slug in _cache_slugs:
		var payload_variant: Variant = _cache.get(slug, null)
		if typeof(payload_variant) != TYPE_DICTIONARY:
			print("INFO: included_decks data issue: deck '%s' payload is not a dictionary." % slug)
			continue
		var payload := payload_variant as Dictionary
		var cards_variant: Variant = payload.get("cards", null)
		if typeof(cards_variant) != TYPE_ARRAY:
			print("INFO: included_decks data issue: deck '%s' missing cards array." % slug)
			continue
		var cards := cards_variant as Array
		for j in cards.size():
			var card: Variant = cards[j]
			if typeof(card) != TYPE_DICTIONARY:
				print("INFO: included_decks data issue: deck '%s' card[%d] is not a dictionary." % [slug, j])
				continue
			var c := card as Dictionary
			var ctype := str(c.get("type", "")).to_lower()
			var value := int(c.get("value", 0))
			if ctype == "ritual":
				if value < 1 or value > 4:
					print("INFO: included_decks data issue: deck '%s' ritual card[%d] has invalid value %d." % [slug, j, value])
			elif ctype == "incantation":
				var verb := str(c.get("verb", "")).to_lower()
				if verb.is_empty():
					print("INFO: included_decks data issue: deck '%s' incantation card[%d] missing verb." % [slug, j])
				var ok_value := value >= 1 and value <= 4
				if verb == "revive":
					ok_value = value == 1
				elif verb == "renew":
					ok_value = value == 2
				elif verb == "wrath":
					ok_value = value == 4
				elif verb == "deluge":
					ok_value = value >= 2 and value <= 4
				elif verb == "tears":
					ok_value = value == 3
				elif verb == "void":
					ok_value = value == 0
				elif verb == "dethrone":
					ok_value = value == 4
				if not ok_value:
					print("INFO: included_decks data issue: deck '%s' incantation card[%d] has invalid value %d for verb '%s'." % [slug, j, value, verb])
			elif ctype == "noble":
				var noble_id := str(c.get("noble_id", "")).strip_edges()
				if noble_id.is_empty():
					print("INFO: included_decks data issue: deck '%s' noble card[%d] missing noble_id." % [slug, j])
			elif ctype == "temple":
				var temple_id := str(c.get("temple_id", "")).strip_edges()
				if temple_id.is_empty():
					print("INFO: included_decks data issue: deck '%s' temple card[%d] missing temple_id." % [slug, j])
			elif ctype == "ring":
				var ring_id := str(c.get("ring_id", "")).strip_edges()
				if ring_id.is_empty():
					print("INFO: included_decks data issue: deck '%s' ring card[%d] missing ring_id." % [slug, j])
			elif ctype == "bird":
				var bird_id := str(c.get("bird_id", "")).strip_edges()
				if bird_id.is_empty():
					print("INFO: included_decks data issue: deck '%s' bird card[%d] missing bird_id." % [slug, j])
				var cost := int(c.get("cost", 0))
				var power := int(c.get("power", 0))
				if cost < 2 or cost > 4:
					print("INFO: included_decks data issue: deck '%s' bird card[%d] has invalid cost %d." % [slug, j, cost])
				if power != cost - 1:
					print("INFO: included_decks data issue: deck '%s' bird card[%d] has invalid power %d for cost %d." % [slug, j, power, cost])
			else:
				print("INFO: included_decks data issue: deck '%s' card[%d] has unknown type '%s'." % [slug, j, ctype])


static func list_row_text(path: String) -> String:
	if is_token(path):
		return "[Included] %s" % slug_from_token(path)
	return path.get_file().get_basename()


static func default_play_path() -> String:
	if not payload_for_slug("default_deck").is_empty():
		return token("default_deck")
	return "user://decks/default_deck.json"
