extends Control

const IncludedDecks = preload("res://included_decks.gd")

const RITUAL_VALUES: Array[int] = [1, 2, 3, 4]
const INCANTATION_VERBS: Array[String] = ["seek", "insight", "burn", "woe", "revive", "wrath", "deluge", "tears", "dethrone"]
const INCANTATION_VALUES: Array[int] = [1, 2, 3, 4]
const TARGET_RITUAL_COUNT := 19
const TARGET_NON_RITUAL_COUNT := 21
const MIN_DECK_SIZE := 40
const MAX_DECK_SIZE := 50
const MAX_RITUAL_COPIES := 9
const MAX_INCANTATION_COPIES := 4
const MAX_NOBLE_FIRSTNAME_COPIES := 4
const MAX_BIRD_COPIES := 4
const DECK_DIR := "user://decks"
const DECK_EXT := ".json"
const DECK_EXPORT_PREFIX := "decks_export_"
const EXPORT_DIALOG_CONFIG_PATH := "user://deck_export_dir.txt"
const NOBLE_DEFS := [
	{"id": "krss_power", "name": "Krss, Noble of Power"},
	{"id": "rmrsk_emanation", "name": "Rmrsk, Scion of Emanation"},
	{"id": "smrsk_occultation", "name": "Smrsk, Scion of Occultation"},
	{"id": "tmrsk_annihilation", "name": "Tmrsk, Scion of Annihilation"},
	{"id": "trss_power", "name": "Trss, Noble of Power"},
	{"id": "yrss_power", "name": "Yrss, Noble of Power"},
	{"id": "xytzr_emanation", "name": "Xytzr, Noble of Emanation"},
	{"id": "yytzr_occultation", "name": "Yytzr, Noble of Occultation"},
	{"id": "zytzr_annihilation", "name": "Zytzr, Noble of Annihilation"},
	{"id": "aeoiu_rituals", "name": "Aeoiu, Scion of Rituals"},
	{"id": "sndrr_incantation", "name": "Sndrr, Noble of Incantation"},
	{"id": "indrr_incantation", "name": "Indrr, Noble of Incantation"},
	{"id": "bndrr_incantation", "name": "Bndrr, Noble of Incantation"},
	{"id": "wndrr_incantation", "name": "Wndrr, Noble of Incantation"},
	{"id": "rndrr_incantation", "name": "Rndrr, Noble of Incantation"}
]
const TEMPLE_DEFS := [
	{"id": "phaedra_illusion", "name": "Phaedra, Temple of Illusion", "cost": 7},
	{"id": "delpha_oracles", "name": "Delpha, Temple of Oracles", "cost": 7},
	{"id": "gotha_illness", "name": "Gotha, Temple of Illness", "cost": 7},
	{"id": "eyrie_feathers", "name": "Eyrie, Temple of Feathers", "cost": 6},
	{"id": "ytria_cycles", "name": "Ytria, Temple of Cycles", "cost": 9}
]
const MAX_TEMPLE_COPIES := 3
const BIRD_DEFS := [
	{"id": "wren", "name": "Wren", "cost": 2, "power": 1},
	{"id": "sparrow", "name": "Sparrow", "cost": 2, "power": 1},
	{"id": "finch", "name": "Finch", "cost": 2, "power": 1},
	{"id": "kestrel", "name": "Kestrel", "cost": 3, "power": 2},
	{"id": "shrike", "name": "Shrike", "cost": 3, "power": 2},
	{"id": "gull", "name": "Gull", "cost": 3, "power": 2},
	{"id": "hawk", "name": "Hawk", "cost": 4, "power": 3},
	{"id": "eagle", "name": "Eagle", "cost": 4, "power": 3},
	{"id": "raven", "name": "Raven", "cost": 4, "power": 3}
]

@onready var deck_list: ItemList = %DeckList
@onready var deck_name_edit: LineEdit = %DeckNameEdit
@onready var reload_decks_button: Button = %ReloadDecksButton
@onready var new_deck_button: Button = %NewDeckButton
@onready var export_decks_button: Button = %ExportDecksButton
@onready var copy_deck_json_button: Button = %CopyDeckJsonButton
@onready var delete_deck_button: Button = %DeleteDeckButton
@onready var delete_deck_confirm_dialog: ConfirmationDialog = %DeleteDeckConfirmDialog
@onready var card_gallery: GridContainer = %CardGallery
@onready var deck_cards_list: VBoxContainer = %DeckCardsList
@onready var totals_label: Label = %TotalsLabel
@onready var status_label: Label = %StatusLabel
@onready var save_button: Button = %SaveButton
@onready var back_button: Button = %BackButton

var _deck_paths: Array[String] = []
var _selected_deck_path := ""
var _entries: Dictionary = {}
var _hover_preview: Dictionary = {}
var _gallery_entries: Array[Dictionary] = []
var _export_dialog: FileDialog = null


func _ready() -> void:
	_hover_preview = CardPreviewPresenter.build_preview_panel(self, {
		"mode": "corner",
		"name": "DeckCardHoverPreview",
		"z_index": 4096
	})
	_gallery_entries = _build_gallery_entries()
	_render_gallery()
	deck_list.item_selected.connect(_on_deck_selected)
	reload_decks_button.pressed.connect(_refresh_deck_list)
	new_deck_button.pressed.connect(_on_new_deck_pressed)
	export_decks_button.pressed.connect(_on_export_decks_button_pressed)
	copy_deck_json_button.pressed.connect(_on_copy_deck_json_button_pressed)
	delete_deck_button.pressed.connect(_on_delete_deck_button_pressed)
	delete_deck_confirm_dialog.confirmed.connect(_on_delete_deck_confirmed)
	save_button.pressed.connect(_on_save_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	_refresh_deck_list()
	if _deck_paths.is_empty():
		_start_new_deck("default_deck")
	else:
		_load_deck_path(_deck_paths[0])
	_update_validation()


func _build_gallery_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value in RITUAL_VALUES:
		out.append({"kind": "ritual", "value": value})
	for verb in INCANTATION_VERBS:
		for value in _incantation_values_for_verb(verb):
			if verb == "dethrone":
				out.append({"kind": "dethrone", "value": 4})
			else:
				out.append({"kind": "incantation", "verb": verb, "value": value})
	for noble in NOBLE_DEFS:
		out.append({"kind": "noble", "noble_id": str(noble.get("id", "")), "name": str(noble.get("name", ""))})
	for tm in TEMPLE_DEFS:
		out.append({"kind": "temple", "temple_id": str(tm.get("id", "")), "name": str(tm.get("name", "")), "cost": int(tm.get("cost", 7))})
	for bird in BIRD_DEFS:
		out.append({
			"kind": "bird",
			"bird_id": str(bird.get("id", "")),
			"name": str(bird.get("name", "")),
			"cost": int(bird.get("cost", 0)),
			"power": int(bird.get("power", 0))
		})
	return out


func _render_gallery() -> void:
	for c in card_gallery.get_children():
		c.queue_free()
	var readonly := _deck_readonly()
	for entry in _gallery_entries:
		card_gallery.add_child(_build_gallery_card(entry, readonly))


func _ensure_deck_dir() -> void:
	var dir_result := DirAccess.make_dir_recursive_absolute(DECK_DIR)
	if dir_result != OK and dir_result != ERR_ALREADY_EXISTS:
		push_warning("Could not create deck dir: %s" % DECK_DIR)


func _refresh_deck_list() -> void:
	_ensure_deck_dir()
	_deck_paths.clear()
	deck_list.clear()
	for slug in IncludedDecks.slug_list():
		_deck_paths.append(IncludedDecks.token(slug))
	var dir := DirAccess.open(DECK_DIR)
	if dir == null:
		status_label.text = "Could not open %s (included decks still listed)." % DECK_DIR
		status_label.modulate = Color(1, 0.95, 0.6)
	else:
		dir.list_dir_begin()
		while true:
			var fn := dir.get_next()
			if fn == "":
				break
			if dir.current_is_dir() or not fn.ends_with(DECK_EXT) or fn.begins_with(DECK_EXPORT_PREFIX):
				continue
			_deck_paths.append("%s/%s" % [DECK_DIR, fn])
		dir.list_dir_end()
	_deck_paths.sort()
	for path in _deck_paths:
		deck_list.add_item(IncludedDecks.list_row_text(path))


func _on_deck_selected(index: int) -> void:
	if index < 0 or index >= _deck_paths.size():
		return
	_load_deck_path(_deck_paths[index])


func _on_new_deck_pressed() -> void:
	_start_new_deck("new_deck")


func _start_new_deck(deck_name_seed: String) -> void:
	_selected_deck_path = ""
	deck_name_edit.text = _sanitize_deck_name(deck_name_seed)
	_entries.clear()
	_render_entries()
	_update_validation()
	_apply_readonly_ui()


func _sanitize_deck_name(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	if s.is_empty():
		return ""
	var out := ""
	for ch in s:
		var c := str(ch)
		var ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		out += c if ok else "_"
	return out.strip_edges()


func _current_deck_path() -> String:
	var deck_name := _sanitize_deck_name(deck_name_edit.text)
	if deck_name.is_empty():
		deck_name = "deck"
		deck_name_edit.text = deck_name
	if _selected_deck_path.is_empty():
		_selected_deck_path = "%s/%s%s" % [DECK_DIR, deck_name, DECK_EXT]
	return _selected_deck_path


func _incantation_values_for_verb(verb: String) -> Array[int]:
	if verb == "revive":
		return [1]
	if verb == "wrath":
		return [4]
	if verb == "deluge":
		return [2, 3, 4]
	if verb == "tears":
		return [3]
	if verb == "dethrone":
		return [4]
	return INCANTATION_VALUES


func _entry_key_ritual(value: int) -> String:
	return "r_%d" % value


func _entry_key_incantation(verb: String, value: int) -> String:
	return "i_%s_%d" % [verb, value]


func _entry_key_noble(noble_id: String) -> String:
	return "n_%s" % noble_id


func _entry_key_temple(temple_id: String) -> String:
	return "tm_%s" % temple_id


func _entry_key_bird(bird_id: String) -> String:
	return "b_%s" % bird_id


func _canonical_noble_name(noble_id: String, fallback_name: String = "") -> String:
	for noble in NOBLE_DEFS:
		if str(noble.get("id", "")) == noble_id:
			return str(noble.get("name", fallback_name))
	return fallback_name


func _entry_display_name(entry: Dictionary) -> String:
	if str(entry.get("kind", "")) == "ritual":
		return "%d-Ritual" % int(entry.get("value", 0))
	if str(entry.get("kind", "")) == "noble":
		return str(entry.get("name", "Noble"))
	if str(entry.get("kind", "")) == "temple":
		return str(entry.get("name", "Temple"))
	if str(entry.get("kind", "")) == "bird":
		return str(entry.get("name", "Bird"))
	if str(entry.get("kind", "")) == "dethrone":
		return "Dethrone 4"
	return "%s %d" % [str(entry.get("verb", "")).capitalize(), int(entry.get("value", 0))]


func _entry_to_preview_card(entry: Dictionary) -> Dictionary:
	var out := entry.duplicate(true)
	out["type"] = str(entry.get("kind", ""))
	return out


func _entry_key(entry: Dictionary) -> String:
	var kind := str(entry.get("kind", ""))
	if kind == "ritual":
		return _entry_key_ritual(int(entry.get("value", 0)))
	if kind == "noble":
		return _entry_key_noble(str(entry.get("noble_id", "")))
	if kind == "temple":
		return _entry_key_temple(str(entry.get("temple_id", "")))
	if kind == "bird":
		return _entry_key_bird(str(entry.get("bird_id", "")))
	if kind == "dethrone":
		return "dethrone"
	return _entry_key_incantation(str(entry.get("verb", "")), int(entry.get("value", 0)))


func _build_gallery_card(entry: Dictionary, readonly: bool) -> Control:
	var card_slot := MarginContainer.new()
	card_slot.custom_minimum_size = Vector2(160, 74)
	card_slot.add_theme_constant_override("margin_right", 6)
	card_slot.add_theme_constant_override("margin_bottom", 6)

	var btn := Button.new()
	btn.text = _entry_display_name(entry)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(150, 68)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var key := _entry_key(entry)
	var count := int((_entries.get(key, {}) as Dictionary).get("count", 0))
	var probe := entry.duplicate(true)
	probe["count"] = count
	btn.disabled = readonly or not _can_increase_entry(probe)
	if count > 0:
		btn.text = "%s  x%d" % [btn.text, count]
	btn.pressed.connect(func() -> void:
		_add_entry_from_gallery(entry)
	)
	btn.mouse_entered.connect(func() -> void:
		CardPreviewPresenter.show_preview(_hover_preview, _entry_to_preview_card(entry))
	)
	btn.mouse_exited.connect(func() -> void:
		CardPreviewPresenter.hide_preview(_hover_preview)
	)

	var kind := str(entry.get("kind", ""))
	var base_bg := Color(0.13, 0.16, 0.21)
	var base_border := Color(0.42, 0.5, 0.64)
	var hover_border := Color(0.8, 0.88, 1.0)
	var disabled_bg := Color(0.1, 0.11, 0.14)
	var disabled_border := Color(0.3, 0.32, 0.38)
	var font_color := Color(0.96, 0.96, 0.98)
	var font_hover_color := Color(0.98, 0.98, 1.0)
	var font_disabled_color := Color(0.62, 0.66, 0.74)
	if kind == "ritual":
		base_border = Color(0.95, 0.78, 0.24)
		hover_border = Color(1.0, 0.88, 0.42)
		disabled_border = Color(0.56, 0.5, 0.32)
		font_color = Color(0.95, 0.78, 0.24)
		font_hover_color = Color(1.0, 0.88, 0.42)
		font_disabled_color = Color(0.62, 0.56, 0.38)
	elif kind == "noble":
		base_bg = Color(0.13, 0.1, 0.18)
		base_border = Color(0.84, 0.7, 1.0)
		hover_border = Color(0.92, 0.82, 1.0)
		disabled_bg = Color(0.11, 0.09, 0.14)
		disabled_border = Color(0.46, 0.4, 0.58)
		font_color = Color(0.96, 0.93, 1.0)
		font_hover_color = Color(0.99, 0.96, 1.0)
		font_disabled_color = Color(0.69, 0.64, 0.78)
	elif kind == "temple":
		base_bg = Color(0.07, 0.11, 0.11)
		base_border = Color(0.32, 0.78, 0.74)
		hover_border = Color(0.5, 0.95, 0.9)
		disabled_bg = Color(0.06, 0.09, 0.09)
		disabled_border = Color(0.22, 0.45, 0.42)
		font_color = Color(0.85, 0.97, 0.94)
		font_hover_color = Color(0.75, 1.0, 0.96)
		font_disabled_color = Color(0.5, 0.62, 0.6)
	elif kind == "bird":
		base_bg = Color(0.97, 0.97, 0.97)
		base_border = Color(0.08, 0.08, 0.08)
		hover_border = Color(0.0, 0.0, 0.0)
		disabled_bg = Color(0.9, 0.9, 0.9)
		disabled_border = Color(0.35, 0.35, 0.35)
		font_color = Color(0.05, 0.05, 0.05)
		font_hover_color = Color(0.0, 0.0, 0.0)
		font_disabled_color = Color(0.3, 0.3, 0.3)

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.bg_color = base_bg
	sb.border_color = base_border
	sb.content_margin_left = 10
	sb.content_margin_top = 10
	sb.content_margin_right = 10
	sb.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.border_color = hover_border
	btn.add_theme_stylebox_override("hover", sb_hover)
	var sb_disabled := sb.duplicate()
	sb_disabled.bg_color = disabled_bg
	sb_disabled.border_color = disabled_border
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_hover_color)
	btn.add_theme_color_override("font_disabled_color", font_disabled_color)

	card_slot.add_child(btn)
	return card_slot


func _add_or_increment_entry(key: String, base_data: Dictionary) -> void:
	if not _entries.has(key):
		var d := base_data.duplicate(true)
		d["count"] = 0
		_entries[key] = d
	var e: Dictionary = _entries[key]
	e["count"] = int(e.get("count", 0)) + 1
	_entries[key] = e


func _ingest_deck_dictionary(parsed_dict: Dictionary) -> void:
	var cards: Array = parsed_dict.get("cards", []) as Array
	for card in cards:
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var kind := str(card.get("type", "")).to_lower()
		if kind == "ritual":
			var rv := int(card.get("value", 0))
			if RITUAL_VALUES.has(rv):
				_add_or_increment_entry(_entry_key_ritual(rv), {"kind": "ritual", "value": rv})
		elif kind == "incantation":
			var verb := str(card.get("verb", "")).to_lower()
			var iv := int(card.get("value", 0))
			if INCANTATION_VERBS.has(verb) and _incantation_values_for_verb(verb).has(iv):
				_add_or_increment_entry(_entry_key_incantation(verb, iv), {"kind": "incantation", "verb": verb, "value": iv})
		elif kind == "noble":
			var nid := str(card.get("noble_id", ""))
			var nname := str(card.get("name", ""))
			if not nid.is_empty():
				_add_or_increment_entry(_entry_key_noble(nid), {
					"kind": "noble",
					"noble_id": nid,
					"name": _canonical_noble_name(nid, nname)
				})
		elif kind == "dethrone":
			if int(card.get("value", 4)) == 4:
				_add_or_increment_entry("dethrone", {"kind": "dethrone", "value": 4})
		elif kind == "temple":
			var tid := str(card.get("temple_id", ""))
			var tname := str(card.get("name", ""))
			if not tid.is_empty():
				_add_or_increment_entry(_entry_key_temple(tid), {
					"kind": "temple",
					"temple_id": tid,
					"name": _canonical_temple_name(tid, tname),
					"cost": int(card.get("cost", 7))
				})
		elif kind == "bird":
			var bid := str(card.get("bird_id", ""))
			var bname := str(card.get("name", "Bird"))
			if not bid.is_empty():
				_add_or_increment_entry(_entry_key_bird(bid), {
					"kind": "bird",
					"bird_id": bid,
					"name": bname,
					"cost": int(card.get("cost", 0)),
					"power": int(card.get("power", 0))
				})


func _canonical_temple_name(temple_id: String, fallback_name: String = "") -> String:
	for tm in TEMPLE_DEFS:
		if str(tm.get("id", "")) == temple_id:
			return str(tm.get("name", fallback_name))
	return fallback_name


func _load_deck_path(path: String) -> void:
	_selected_deck_path = path
	_entries.clear()
	var parsed_dict: Dictionary = {}
	if IncludedDecks.is_token(path):
		var slug := IncludedDecks.slug_from_token(path)
		parsed_dict = IncludedDecks.payload_for_slug(slug)
		if parsed_dict.is_empty():
			status_label.text = "Missing included deck: %s" % slug
			status_label.modulate = Color(1, 0.55, 0.55)
			deck_name_edit.text = slug
			_render_entries()
			_update_validation()
			_apply_readonly_ui()
			return
		deck_name_edit.text = str(parsed_dict.get("deck_name", slug))
	else:
		deck_name_edit.text = path.get_file().trim_suffix(DECK_EXT)
		if not FileAccess.file_exists(path):
			_render_entries()
			_update_validation()
			_apply_readonly_ui()
			return
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			status_label.text = "Failed to read %s." % path
			status_label.modulate = Color(1, 0.55, 0.55)
			_render_entries()
			_update_validation()
			_apply_readonly_ui()
			return
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			_render_entries()
			_update_validation()
			_apply_readonly_ui()
			return
		parsed_dict = parsed as Dictionary
	_ingest_deck_dictionary(parsed_dict)
	_render_entries()
	_update_validation()
	_apply_readonly_ui()


func _render_entries() -> void:
	for c in deck_cards_list.get_children():
		c.queue_free()
	var keys: Array = _entries.keys()
	keys.sort()
	for key in keys:
		deck_cards_list.add_child(_build_entry_pill(key, _entries[key], _deck_readonly()))
	_render_gallery()


func _deck_readonly() -> bool:
	return IncludedDecks.is_token(_selected_deck_path)


func _apply_readonly_ui() -> void:
	deck_name_edit.editable = not _deck_readonly()
	_render_gallery()
	_update_delete_deck_button()


func _update_delete_deck_button() -> void:
	var p := _selected_deck_path
	var can_delete := not IncludedDecks.is_token(p) and not p.is_empty() and FileAccess.file_exists(p)
	delete_deck_button.disabled = not can_delete


func _build_entry_pill(key: String, entry: Dictionary, readonly: bool) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var bg := PanelContainer.new()
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	var kind := str(entry.get("kind", ""))
	var base_bg := Color(0.15, 0.17, 0.22)
	var border := Color(0.45, 0.5, 0.62)
	if kind == "ritual":
		base_bg = Color(0.17, 0.14, 0.08)
		border = Color(0.95, 0.78, 0.24)
	elif kind == "noble":
		base_bg = Color(0.13, 0.1, 0.18)
		border = Color(0.84, 0.7, 1.0)
	elif kind == "temple":
		base_bg = Color(0.07, 0.11, 0.11)
		border = Color(0.32, 0.78, 0.74)
	elif kind == "bird":
		base_bg = Color(0.97, 0.97, 0.97)
		border = Color(0.08, 0.08, 0.08)
	sb.bg_color = base_bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	bg.add_theme_stylebox_override("panel", sb)
	row.add_child(bg)
	var preview_card := _entry_to_preview_card(entry)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	bg.add_child(inner)

	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lbl.text = "%s x%d" % [_entry_display_name(entry), int(entry.get("count", 0))]
	if kind == "bird":
		lbl.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	lbl.mouse_entered.connect(func() -> void:
		CardPreviewPresenter.show_preview(_hover_preview, preview_card)
	)
	lbl.mouse_exited.connect(func() -> void:
		CardPreviewPresenter.hide_preview(_hover_preview)
	)
	inner.add_child(lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(spacer)

	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(32, 28)
	minus.disabled = readonly
	minus.pressed.connect(func() -> void:
		_decrement_entry(key)
	)
	inner.add_child(minus)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(32, 28)
	plus.disabled = readonly
	plus.pressed.connect(func() -> void:
		_increment_entry(key)
	)
	inner.add_child(plus)

	var remove := Button.new()
	remove.text = "X"
	remove.custom_minimum_size = Vector2(36, 28)
	remove.disabled = readonly
	remove.pressed.connect(func() -> void:
		_entries.erase(key)
		_render_entries()
		_update_validation()
	)
	row.add_child(remove)
	return row


func _increment_entry(key: String) -> void:
	if not _entries.has(key):
		return
	var e: Dictionary = _entries[key]
	if not _can_increase_entry(e):
		_show_cannot_add_status(e)
		return
	var next_count := int(e.get("count", 0)) + 1
	e["count"] = next_count
	_entries[key] = e
	_render_entries()
	_update_validation()


func _decrement_entry(key: String) -> void:
	if not _entries.has(key):
		return
	var e: Dictionary = _entries[key]
	var next_count := int(e.get("count", 0)) - 1
	if next_count <= 0:
		_entries.erase(key)
	else:
		e["count"] = next_count
		_entries[key] = e
	_render_entries()
	_update_validation()


func _add_entry_from_gallery(base_entry: Dictionary) -> void:
	if _deck_readonly():
		return
	var key := _entry_key(base_entry)
	if _entries.has(key):
		_increment_entry(key)
		return
	var entry := base_entry.duplicate(true)
	entry["count"] = 0
	if not _can_increase_entry(entry):
		_show_cannot_add_status(entry)
		return
	entry["count"] = 1
	_entries[key] = entry
	_render_entries()
	_update_validation()


func _can_increase_entry(entry: Dictionary) -> bool:
	var totals := _totals()
	var kind := str(entry.get("kind", ""))
	var count := int(entry.get("count", 0))
	if kind == "ritual":
		if count >= MAX_RITUAL_COPIES:
			return false
		return int(totals.get("rituals", 0)) < TARGET_RITUAL_COUNT
	if kind == "noble":
		var fname := _noble_first_name(entry)
		if fname.is_empty():
			return false
		if _noble_first_name_total(fname) >= MAX_NOBLE_FIRSTNAME_COPIES:
			return false
		return int(totals.get("non_ritual", 0)) < TARGET_NON_RITUAL_COUNT
	if kind == "bird":
		if count >= MAX_BIRD_COPIES:
			return false
		return int(totals.get("non_ritual", 0)) < TARGET_NON_RITUAL_COUNT
	if kind == "incantation" or kind == "dethrone":
		if count >= MAX_INCANTATION_COPIES:
			return false
		return int(totals.get("non_ritual", 0)) < TARGET_NON_RITUAL_COUNT
	if kind == "temple":
		if count >= MAX_TEMPLE_COPIES:
			return false
		return int(totals.get("non_ritual", 0)) < TARGET_NON_RITUAL_COUNT
	return false


func _show_cannot_add_status(entry: Dictionary) -> void:
	var kind := str(entry.get("kind", ""))
	if kind == "ritual":
		if int(entry.get("count", 0)) >= MAX_RITUAL_COPIES:
			status_label.text = "Cannot add: max %d copies of that ritual." % MAX_RITUAL_COPIES
		else:
			status_label.text = "Cannot add: ritual cap is %d." % TARGET_RITUAL_COUNT
	elif kind == "noble":
		var fname := _noble_first_name(entry)
		if not fname.is_empty() and _noble_first_name_total(fname) >= MAX_NOBLE_FIRSTNAME_COPIES:
			status_label.text = "Cannot add: max %d nobles named %s." % [MAX_NOBLE_FIRSTNAME_COPIES, fname]
		else:
			status_label.text = "Cannot add: non-ritual cap is %d." % TARGET_NON_RITUAL_COUNT
	elif kind == "bird":
		if int(entry.get("count", 0)) >= MAX_BIRD_COPIES:
			status_label.text = "Cannot add: max %d copies of that bird." % MAX_BIRD_COPIES
		else:
			status_label.text = "Cannot add: non-ritual cap is %d." % TARGET_NON_RITUAL_COUNT
	else:
		if int(entry.get("count", 0)) >= MAX_INCANTATION_COPIES:
			status_label.text = "Cannot add: max %d copies of a given incantation." % MAX_INCANTATION_COPIES
		else:
			status_label.text = "Cannot add: non-ritual cap is %d." % TARGET_NON_RITUAL_COUNT
	status_label.modulate = Color(1, 0.95, 0.6)


func _incantation_copy_limit_ok() -> bool:
	for entry in _entries.values():
		var kind := str(entry.get("kind", ""))
		if kind != "incantation" and kind != "dethrone":
			continue
		if int(entry.get("count", 0)) > MAX_INCANTATION_COPIES:
			return false
	return true


func _noble_first_name(entry: Dictionary) -> String:
	var noble_name := str(entry.get("name", "")).strip_edges()
	if noble_name.is_empty():
		var nid := str(entry.get("noble_id", ""))
		if nid.is_empty():
			return ""
		var sid := nid.get_slice("_", 0)
		return sid.capitalize()
	var comma := noble_name.find(",")
	if comma > 0:
		return noble_name.substr(0, comma).strip_edges()
	return noble_name.get_slice(" ", 0).strip_edges()


func _noble_first_name_total(first_name: String) -> int:
	var total := 0
	for entry in _entries.values():
		if str(entry.get("kind", "")) != "noble":
			continue
		if _noble_first_name(entry) == first_name:
			total += int(entry.get("count", 0))
	return total


func _bird_copy_limit_ok() -> bool:
	for entry in _entries.values():
		if str(entry.get("kind", "")) != "bird":
			continue
		if int(entry.get("count", 0)) > MAX_BIRD_COPIES:
			return false
	return true


func _noble_copy_limit_ok() -> bool:
	var counts: Dictionary = {}
	for entry in _entries.values():
		if str(entry.get("kind", "")) != "noble":
			continue
		var fname := _noble_first_name(entry)
		if fname.is_empty():
			return false
		counts[fname] = int(counts.get(fname, 0)) + int(entry.get("count", 0))
	for k in counts.keys():
		if int(counts[k]) > MAX_NOBLE_FIRSTNAME_COPIES:
			return false
	return true


func _totals() -> Dictionary:
	var ritual_total := 0
	var incantation_total := 0
	var noble_total := 0
	var temple_total := 0
	var bird_total := 0
	var dethrone_total := 0
	for entry in _entries.values():
		var count := int(entry.get("count", 0))
		if count <= 0:
			continue
		var kind := str(entry.get("kind", ""))
		if kind == "ritual":
			ritual_total += count
		elif kind == "incantation":
			incantation_total += count
		elif kind == "noble":
			noble_total += count
		elif kind == "temple":
			temple_total += count
		elif kind == "bird":
			bird_total += count
		elif kind == "dethrone":
			dethrone_total += count
	return {
		"rituals": ritual_total,
		"incantations": incantation_total,
		"nobles": noble_total,
		"temples": temple_total,
		"birds": bird_total,
		"dethrones": dethrone_total,
		"non_ritual": incantation_total + noble_total + temple_total + dethrone_total + bird_total
	}


func _update_validation() -> void:
	var totals := _totals()
	var total_cards := int(totals["rituals"]) + int(totals["non_ritual"])
	totals_label.text = "Rituals %d/%d   Non-Ritual %d/%d   Total %d (%d-%d)" % [
		totals["rituals"],
		TARGET_RITUAL_COUNT,
		totals["non_ritual"],
		TARGET_NON_RITUAL_COUNT,
		total_cards,
		MIN_DECK_SIZE,
		MAX_DECK_SIZE
	]
	var copies_ok := _incantation_copy_limit_ok()
	var noble_ok := _noble_copy_limit_ok()
	var bird_ok := _bird_copy_limit_ok()
	var is_valid: bool = totals["rituals"] == TARGET_RITUAL_COUNT and totals["non_ritual"] == TARGET_NON_RITUAL_COUNT and total_cards >= MIN_DECK_SIZE and total_cards <= MAX_DECK_SIZE and copies_ok and noble_ok and bird_ok
	var ro := _deck_readonly()
	if ro:
		is_valid = true
	save_button.disabled = not is_valid or ro
	if ro:
		status_label.text = "Included deck (read-only; cannot delete or overwrite)."
		status_label.modulate = Color(0.72, 0.88, 1.0)
	elif is_valid:
		status_label.text = "Deck is legal. Save is enabled."
		status_label.modulate = Color(0.65, 1, 0.65)
	elif not copies_ok:
		status_label.text = "Adjust counts: max %d copies of each incantation variant." % MAX_INCANTATION_COPIES
		status_label.modulate = Color(1, 0.95, 0.6)
	elif not noble_ok:
		status_label.text = "Adjust counts: max %d nobles of the same first name." % MAX_NOBLE_FIRSTNAME_COPIES
		status_label.modulate = Color(1, 0.95, 0.6)
	elif not bird_ok:
		status_label.text = "Adjust counts: max %d copies of each bird." % MAX_BIRD_COPIES
		status_label.modulate = Color(1, 0.95, 0.6)
	else:
		status_label.text = "Adjust counts to a legal 40 card deck."
		status_label.modulate = Color(1, 0.95, 0.6)


func _build_deck_payload() -> Dictionary:
	var cards: Array[Dictionary] = []
	var ritual_counts: Dictionary = {}
	var incantation_counts: Dictionary = {}
	var noble_counts: Dictionary = {}
	var temple_counts: Dictionary = {}
	var bird_counts: Dictionary = {}
	var dethrone_count := 0
	for value in RITUAL_VALUES:
		ritual_counts[str(value)] = 0
	for verb in INCANTATION_VERBS:
		for value in _incantation_values_for_verb(verb):
			incantation_counts["%s_%d" % [verb, value]] = 0
	for n in NOBLE_DEFS:
		noble_counts[str(n.get("id", ""))] = 0
	for tm in TEMPLE_DEFS:
		temple_counts[str(tm.get("id", ""))] = 0
	for bd in BIRD_DEFS:
		bird_counts[str(bd.get("id", ""))] = 0

	for entry in _entries.values():
		var count := int(entry.get("count", 0))
		if count <= 0:
			continue
		if str(entry.get("kind", "")) == "ritual":
			var rv := int(entry.get("value", 0))
			ritual_counts[str(rv)] = count
			for _i in count:
				cards.append({"type": "Ritual", "value": rv})
		else:
			if str(entry.get("kind", "")) == "noble":
				var nid := str(entry.get("noble_id", ""))
				var nname := str(entry.get("name", ""))
				noble_counts[nid] = count
				for _k in count:
					cards.append({"type": "Noble", "noble_id": nid, "name": nname})
				continue
			if str(entry.get("kind", "")) == "temple":
				var tid2 := str(entry.get("temple_id", ""))
				var tnam := str(entry.get("name", ""))
				var tcost := int(entry.get("cost", 7))
				temple_counts[tid2] = count
				for _ti in count:
					cards.append({"type": "Temple", "temple_id": tid2, "name": tnam, "cost": tcost})
				continue
			if str(entry.get("kind", "")) == "dethrone":
				dethrone_count = count
				for _m in count:
					cards.append({"type": "Dethrone", "value": 4})
				continue
			if str(entry.get("kind", "")) == "bird":
				var bid := str(entry.get("bird_id", ""))
				var bname := str(entry.get("name", "Bird"))
				var bcost := int(entry.get("cost", 0))
				var bpower := int(entry.get("power", 0))
				bird_counts[bid] = count
				for _bi in count:
					cards.append({"type": "Bird", "bird_id": bid, "name": bname, "cost": bcost, "power": bpower})
				continue
			var verb := str(entry.get("verb", ""))
			var iv := int(entry.get("value", 0))
			incantation_counts["%s_%d" % [verb, iv]] = count
			for _j in count:
				cards.append({"type": "Incantation", "verb": verb, "value": iv})

	return {
		"schema_version": 1,
		"deck_name": deck_name_edit.text.strip_edges(),
		"cards": cards,
		"counts": {
			"rituals": ritual_counts,
			"incantations": incantation_counts,
			"nobles": noble_counts,
			"temples": temple_counts,
			"birds": bird_counts,
			"dethrones": dethrone_count
		},
		"rules_snapshot": {
			"total_cards_min": 40,
			"total_cards_max": 50,
			"ritual_target": TARGET_RITUAL_COUNT,
			"non_ritual_target": TARGET_NON_RITUAL_COUNT,
			"max_ritual_copies": MAX_RITUAL_COPIES,
			"max_bird_copies": MAX_BIRD_COPIES
		}
	}


func _write_json(path: String, payload: Dictionary) -> int:
	_ensure_deck_dir()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	return OK


func _export_filename_for_current_deck(payload: Dictionary) -> String:
	var deck_name := str(payload.get("deck_name", "")).strip_edges()
	var slug := _sanitize_deck_name(deck_name)
	if slug.is_empty():
		if IncludedDecks.is_token(_selected_deck_path):
			slug = IncludedDecks.slug_from_token(_selected_deck_path)
		elif not _selected_deck_path.is_empty():
			slug = _selected_deck_path.get_file().trim_suffix(DECK_EXT)
	if slug.is_empty():
		slug = "deck"
	return slug + DECK_EXT


func _load_last_export_dir() -> String:
	if not FileAccess.file_exists(EXPORT_DIALOG_CONFIG_PATH):
		return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var f := FileAccess.open(EXPORT_DIALOG_CONFIG_PATH, FileAccess.READ)
	if f == null:
		return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var dir := f.get_as_text().strip_edges()
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return dir


func _save_last_export_dir(path: String) -> void:
	var dir := path.get_base_dir()
	if dir.is_empty():
		return
	var f := FileAccess.open(EXPORT_DIALOG_CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(dir)


func _ensure_export_dialog() -> FileDialog:
	if _export_dialog != null and is_instance_valid(_export_dialog):
		return _export_dialog
	_export_dialog = FileDialog.new()
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.use_native_dialog = true
	_export_dialog.filters = PackedStringArray(["*.json ; Deck JSON"])
	_export_dialog.title = "Export Deck"
	_export_dialog.file_selected.connect(_on_export_dialog_file_selected)
	add_child(_export_dialog)
	return _export_dialog


func _on_export_decks_button_pressed() -> void:
	var payload := _build_deck_payload()
	if payload.is_empty() or (payload.get("cards", []) as Array).is_empty():
		status_label.text = "Nothing to export: current deck is empty."
		status_label.modulate = Color(1, 0.95, 0.6)
		return
	var deck_name := str(payload.get("deck_name", "")).strip_edges()
	if deck_name.is_empty():
		status_label.text = "Set a deck name before exporting."
		status_label.modulate = Color(1, 0.95, 0.6)
		return
	var dialog := _ensure_export_dialog()
	dialog.current_dir = _load_last_export_dir()
	dialog.current_file = _export_filename_for_current_deck(payload)
	dialog.popup_centered_ratio(0.6)


func _on_export_dialog_file_selected(path: String) -> void:
	var payload := _build_deck_payload()
	if payload.is_empty():
		status_label.text = "Nothing to export."
		status_label.modulate = Color(1, 0.95, 0.6)
		return
	if not path.to_lower().ends_with(DECK_EXT):
		path += DECK_EXT
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status_label.text = "Failed to export to %s (error %d)." % [path, FileAccess.get_open_error()]
		status_label.modulate = Color(1, 0.55, 0.55)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	_save_last_export_dir(path)
	var deck_name := str(payload.get("deck_name", "deck"))
	status_label.text = "Exported '%s' to %s" % [deck_name, path]
	status_label.modulate = Color(0.65, 1, 0.65)


func _on_copy_deck_json_button_pressed() -> void:
	var payload := _build_deck_payload()
	var deck_name := str(payload.get("deck_name", "")).strip_edges()
	if deck_name.is_empty():
		status_label.text = "Set a deck name before copying JSON."
		status_label.modulate = Color(1, 0.95, 0.6)
		return
	var cards := payload.get("cards", []) as Array
	if cards.is_empty():
		status_label.text = "Deck has no cards to copy."
		status_label.modulate = Color(1, 0.95, 0.6)
		return
	DisplayServer.clipboard_set(JSON.stringify(payload, "\t"))
	status_label.text = "Copied deck JSON to clipboard."
	status_label.modulate = Color(0.65, 1, 0.65)


func _on_save_button_pressed() -> void:
	if _deck_readonly():
		status_label.text = "Cannot save over an included deck."
		status_label.modulate = Color(1, 0.95, 0.6)
		return
	var totals := _totals()
	if not _incantation_copy_limit_ok():
		status_label.text = "Deck is invalid. You may only have %d copies of each incantation variant." % MAX_INCANTATION_COPIES
		status_label.modulate = Color(1, 0.55, 0.55)
		return
	if not _bird_copy_limit_ok():
		status_label.text = "Deck is invalid. You may only have %d copies of each bird." % MAX_BIRD_COPIES
		status_label.modulate = Color(1, 0.55, 0.55)
		return
	var total_cards := int(totals["rituals"]) + int(totals["non_ritual"])
	if totals["rituals"] != TARGET_RITUAL_COUNT or totals["non_ritual"] != TARGET_NON_RITUAL_COUNT or total_cards < MIN_DECK_SIZE or total_cards > MAX_DECK_SIZE:
		status_label.text = "Deck is invalid. Rituals=%d, non-ritual=%d, total 40." % [TARGET_RITUAL_COUNT, TARGET_NON_RITUAL_COUNT]
		status_label.modulate = Color(1, 0.55, 0.55)
		return
	var path := _current_deck_path()
	var result := _write_json(path, _build_deck_payload())
	if result != OK:
		status_label.text = "Failed to save deck to %s (error %d)." % [path, result]
		status_label.modulate = Color(1, 0.55, 0.55)
		return
	status_label.text = "Deck saved: %s" % path
	status_label.modulate = Color(0.65, 1, 0.65)
	_refresh_deck_list()
	_select_deck_path(path)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _on_delete_deck_button_pressed() -> void:
	if delete_deck_button.disabled:
		return
	var path := _selected_deck_path
	if IncludedDecks.is_token(path) or path.is_empty() or not FileAccess.file_exists(path):
		return
	var display := path.get_file().get_basename()
	delete_deck_confirm_dialog.dialog_text = "Delete \"%s\" permanently? This cannot be undone." % display
	delete_deck_confirm_dialog.popup_centered()


func _on_delete_deck_confirmed() -> void:
	var path := _selected_deck_path
	if IncludedDecks.is_token(path) or path.is_empty():
		return
	if not FileAccess.file_exists(path):
		_update_delete_deck_button()
		return
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		status_label.text = "Could not delete deck (error %d)." % err
		status_label.modulate = Color(1, 0.55, 0.55)
		return
	status_label.text = "Deleted: %s" % path.get_file()
	status_label.modulate = Color(0.65, 1, 0.65)
	_refresh_deck_list()
	if _deck_paths.is_empty():
		_start_new_deck("new_deck")
	else:
		_load_deck_path(_deck_paths[0])
		deck_list.select(0)


func _select_deck_path(path: String) -> void:
	for i in deck_list.item_count:
		if i < _deck_paths.size() and _deck_paths[i] == path:
			deck_list.select(i)
			return
