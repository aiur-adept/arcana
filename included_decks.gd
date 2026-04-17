extends Object

const BUNDLE_PATH := "res://included_decks.json"
const TOKEN_PREFIX := "included:"
static var _issues_logged := false


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


static func load_bundle() -> Dictionary:
	if not FileAccess.file_exists(BUNDLE_PATH):
		return {}
	var f := FileAccess.open(BUNDLE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var p: Variant = JSON.parse_string(f.get_as_text())
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	var bundle := p as Dictionary
	_log_data_issues_once(bundle)
	return bundle


static func slug_list() -> Array[String]:
	var out: Array[String] = []
	for e in load_bundle().get("decks", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var slug := _entry_slug(e as Dictionary)
		if not slug.is_empty():
			out.append(slug)
	return out


static func payload_for_slug(slug: String) -> Dictionary:
	for e in load_bundle().get("decks", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var entry := e as Dictionary
		if _entry_slug(entry) != slug:
			continue
		return _entry_payload(entry)
	return {}


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


static func _log_data_issues_once(bundle: Dictionary) -> void:
	if _issues_logged:
		return
	_issues_logged = true
	var decks_variant: Variant = bundle.get("decks", [])
	if typeof(decks_variant) != TYPE_ARRAY:
		print("INFO: included_decks data issue: 'decks' is not an array.")
		return
	var decks := decks_variant as Array
	var declared_count := int(bundle.get("deck_count", -1))
	if declared_count >= 0 and declared_count != decks.size():
		print("INFO: included_decks data issue: deck_count=%d but decks has %d entries." % [declared_count, decks.size()])
	for i in decks.size():
		var item: Variant = decks[i]
		if typeof(item) != TYPE_DICTIONARY:
			print("INFO: included_decks data issue: deck[%d] is not a dictionary." % i)
			continue
		var entry := item as Dictionary
		var payload := _entry_payload(entry)
		var slug := _entry_slug(entry)
		if slug.is_empty():
			print("INFO: included_decks data issue: deck[%d] has empty slug/deck_name." % i)
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
				elif verb == "wrath":
					ok_value = value == 4
				if verb == "dethrone":
					ok_value = value == 4
				if not ok_value:
					print("INFO: included_decks data issue: deck '%s' incantation card[%d] has invalid value %d for verb '%s'." % [slug, j, value, verb])
			elif ctype == "dethrone":
				if value != 4:
					print("INFO: included_decks data issue: deck '%s' dethrone card[%d] has invalid value %d." % [slug, j, value])
			elif ctype == "noble":
				var noble_id := str(c.get("noble_id", "")).strip_edges()
				if noble_id.is_empty():
					print("INFO: included_decks data issue: deck '%s' noble card[%d] missing noble_id." % [slug, j])
			elif ctype == "temple":
				var temple_id := str(c.get("temple_id", "")).strip_edges()
				if temple_id.is_empty():
					print("INFO: included_decks data issue: deck '%s' temple card[%d] missing temple_id." % [slug, j])
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
