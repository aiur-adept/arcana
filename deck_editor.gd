extends Control

const IncludedDecks = preload("res://included_decks.gd")

const RITUAL_VALUES: Array[int] = [1, 2, 3, 4]
const INCANTATION_VERBS: Array[String] = ["seek", "insight", "burn", "woe", "revive", "wrath", "dethrone"]
const INCANTATION_VALUES: Array[int] = [1, 2, 3, 4]
const TARGET_RITUAL_COUNT := 19
const TARGET_NON_RITUAL_COUNT := 21
const MAX_RITUAL_COPIES := 9
const MAX_INCANTATION_COPIES := 4
const MAX_NOBLE_FIRSTNAME_COPIES := 4
const DECK_DIR := "user://decks"
const DECK_EXT := ".json"
const DECK_EXPORT_PREFIX := "decks_export_"
const NOBLE_DEFS := [
	{"id": "krss_power", "name": "Krss, Noble of Power"},
	{"id": "trss_power", "name": "Trss, Noble of Power"},
	{"id": "yrss_power", "name": "Yrss, Noble of Power"},
	{"id": "xytzr_emanation", "name": "Xytzr, Noble of Emanation"},
	{"id": "yytzr_occultation", "name": "Yytzr, Noble of Occultation"},
	{"id": "zytzr_annihilation", "name": "Zytzr, Noble of Annihilation"},
	{"id": "aeoiu_rituals", "name": "Aeoiu, Noble of Rituals"},
	{"id": "sndrr_incantation", "name": "Sndrr, Noble of Incantation"},
	{"id": "indrr_incantation", "name": "Indrr, Noble of Incantation"},
	{"id": "bndrr_incantation", "name": "Bndrr, Noble of Incantation"},
	{"id": "wndrr_incantation", "name": "Wndrr, Noble of Incantation"},
	{"id": "rndrr_incantation", "name": "Rndrr, Noble of Incantation"}
]

@onready var deck_list: ItemList = %DeckList
@onready var deck_name_edit: LineEdit = %DeckNameEdit
@onready var reload_decks_button: Button = %ReloadDecksButton
@onready var new_deck_button: Button = %NewDeckButton
@onready var export_decks_button: Button = %ExportDecksButton
@onready var delete_deck_button: Button = %DeleteDeckButton
@onready var delete_deck_confirm_dialog: ConfirmationDialog = %DeleteDeckConfirmDialog
@onready var add_type_button: Button = %AddTypeButton
@onready var add_kind_option: OptionButton = %AddKindOption
@onready var add_verb_option: OptionButton = %AddVerbOption
@onready var add_value_option: OptionButton = %AddValueOption
@onready var deck_cards_list: VBoxContainer = %DeckCardsList
@onready var totals_label: Label = %TotalsLabel
@onready var status_label: Label = %StatusLabel
@onready var save_button: Button = %SaveButton
@onready var back_button: Button = %BackButton

var _deck_paths: Array[String] = []
var _selected_deck_path := ""
var _entries: Dictionary = {}
var _preview_popup: PanelContainer
var _preview_label: Label


func _ready() -> void:
	_init_preview_popup()
	_configure_add_controls()
	deck_list.item_selected.connect(_on_deck_selected)
	reload_decks_button.pressed.connect(_refresh_deck_list)
	new_deck_button.pressed.connect(_on_new_deck_pressed)
	export_decks_button.pressed.connect(_on_export_decks_button_pressed)
	delete_deck_button.pressed.connect(_on_delete_deck_button_pressed)
	delete_deck_confirm_dialog.confirmed.connect(_on_delete_deck_confirmed)
	add_type_button.pressed.connect(_on_add_type_pressed)
	add_kind_option.mouse_entered.connect(_on_add_hovered)
	add_verb_option.mouse_entered.connect(_on_add_hovered)
	add_value_option.mouse_entered.connect(_on_add_hovered)
	add_type_button.mouse_entered.connect(_on_add_hovered)
	add_kind_option.mouse_exited.connect(_hide_preview)
	add_verb_option.mouse_exited.connect(_hide_preview)
	add_value_option.mouse_exited.connect(_hide_preview)
	add_type_button.mouse_exited.connect(_hide_preview)
	add_kind_option.item_selected.connect(func(_idx: int) -> void:
		_refresh_add_verb_options()
		_refresh_add_verb_visibility()
		_refresh_add_value_options()
	)
	add_verb_option.item_selected.connect(func(_idx: int) -> void:
		_refresh_add_value_options()
	)
	save_button.pressed.connect(_on_save_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	_refresh_add_verb_options()
	_refresh_add_verb_visibility()
	_refresh_add_value_options()
	_refresh_deck_list()
	if _deck_paths.is_empty():
		_start_new_deck("default_deck")
	else:
		_load_deck_path(_deck_paths[0])
	_update_validation()


func _configure_add_controls() -> void:
	add_kind_option.clear()
	add_kind_option.add_item("Ritual")
	add_kind_option.add_item("Incantation")
	add_kind_option.add_item("Noble")
	add_verb_option.clear()
	for verb in INCANTATION_VERBS:
		add_verb_option.add_item(verb.capitalize())
	add_value_option.clear()
	for value in RITUAL_VALUES:
		add_value_option.add_item(str(value))


func _init_preview_popup() -> void:
	_preview_popup = PanelContainer.new()
	_preview_popup.visible = false
	_preview_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_popup.z_index = 100
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.11, 0.15, 0.97)
	sb.border_color = Color(0.55, 0.63, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	_preview_popup.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_preview_popup.add_child(margin)
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.custom_minimum_size = Vector2(220, 0)
	margin.add_child(_preview_label)
	add_child(_preview_popup)


func _refresh_add_verb_options() -> void:
	var kind := add_kind_option.get_item_text(add_kind_option.selected)
	add_verb_option.clear()
	if kind == "Noble":
		for n in NOBLE_DEFS:
			add_verb_option.add_item(str(n.get("name", "")))
	else:
		for verb in INCANTATION_VERBS:
			add_verb_option.add_item(verb.capitalize())


func _refresh_add_verb_visibility() -> void:
	var kind := add_kind_option.get_item_text(add_kind_option.selected)
	add_verb_option.visible = kind == "Incantation" or kind == "Noble"
	add_value_option.visible = kind == "Ritual" or kind == "Incantation"


func _refresh_add_value_options() -> void:
	var kind := add_kind_option.get_item_text(add_kind_option.selected)
	add_value_option.clear()
	var values: Array[int] = []
	if kind == "Ritual":
		values = RITUAL_VALUES
	elif kind == "Incantation":
		if add_verb_option.selected < 0 or add_verb_option.selected >= INCANTATION_VERBS.size():
			return
		values = _incantation_values_for_verb(INCANTATION_VERBS[add_verb_option.selected])
	else:
		return
	for v in values:
		add_value_option.add_item(str(v))
	if add_value_option.item_count > 0:
		add_value_option.select(0)


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
	if verb == "dethrone":
		return [4]
	return INCANTATION_VALUES


func _entry_key_ritual(value: int) -> String:
	return "r_%d" % value


func _entry_key_incantation(verb: String, value: int) -> String:
	return "i_%s_%d" % [verb, value]


func _entry_key_noble(noble_id: String) -> String:
	return "n_%s" % noble_id


func _entry_display_name(entry: Dictionary) -> String:
	if str(entry.get("kind", "")) == "ritual":
		return "%d-Ritual" % int(entry.get("value", 0))
	if str(entry.get("kind", "")) == "noble":
		return str(entry.get("name", "Noble"))
	if str(entry.get("kind", "")) == "dethrone":
		return "Dethrone 4"
	return "%s %d" % [str(entry.get("verb", "")).capitalize(), int(entry.get("value", 0))]


func _entry_preview_text(entry: Dictionary) -> String:
	var kind := str(entry.get("kind", ""))
	if kind == "ritual":
		var v := int(entry.get("value", 0))
		return "Ritual %d\nProvides ritual value %d on your field." % [v, v]
	if kind == "incantation":
		var verb := str(entry.get("verb", "")).to_lower()
		var v := int(entry.get("value", 0))
		match verb:
			"seek":
				return "Seek %d\nDraw %d card(s)." % [v, v]
			"insight":
				return "Insight %d\nReorder the top %d card(s) of a chosen player's deck." % [v, v]
			"burn":
				return "Burn %d\nDiscard the top %d card(s) of a chosen player's deck." % [v, v * 2]
			"woe":
				return "Woe %d\nA chosen player discards %d chosen card(s)." % [v, v]
			"revive":
				return "Revive %d\nYou may cast %d incantation(s) from your crypt (chosen)." % [v, v]
			"wrath":
				return "Wrath %d\nDestroy %d opponent ritual(s)." % [v, _wrath_destroy_count(v)]
			"dethrone":
				return "Dethrone 4\nChoose and destroy an opponent noble."
		return "%s %d" % [verb.capitalize(), v]
	if kind == "noble":
		var nid := str(entry.get("noble_id", ""))
		return "%s\n%s" % [str(entry.get("name", "Noble")), _noble_preview_text(nid)]
	if kind == "dethrone":
		return "Dethrone 4\nChoose and destroy an opponent noble."
	return _entry_display_name(entry)


func _noble_preview_text(noble_id: String) -> String:
	match noble_id:
		"krss_power":
			return "Passive: grants access to 1-cost incantations."
		"trss_power":
			return "Passive: grants access to 2-cost incantations."
		"yrss_power":
			return "Passive: grants access to 3-cost incantations."
		"sndrr_incantation":
			return "Activate once per turn: Seek 1."
		"indrr_incantation":
			return "Activate once per turn: Insight 2."
		"bndrr_incantation":
			return "Activate once per turn: Burn 1."
		"wndrr_incantation":
			return "Activate once per turn: Woe 1."
		"rndrr_incantation":
			return "Activate once per turn: Revive 1."
		"xytzr_emanation":
			return "Whenever you Seek, draw an additional card. Whenever you Insight, look at an additional card."
		"yytzr_occultation":
			return "Whenever you Burn, add 3 to cards milled. Whenever you Revive, you may sacrifice 2+ ritual power for an extra crypt cast."
		"zytzr_annihilation":
			return "Whenever you Wrath, destroy an extra ritual. Whenever you Woe, the victim discards an additional card."
		"aeoiu_rituals":
			return "Activate once per turn: play a Ritual from your crypt."
	return "Noble."


func _wrath_destroy_count(value: int) -> int:
	if value == 4:
		return 2
	return 0


func _show_preview(text: String) -> void:
	if text.is_empty():
		return
	_preview_label.text = text
	_preview_popup.reset_size()
	var mouse := get_global_mouse_position()
	_preview_popup.global_position = mouse + Vector2(18, 18)
	_preview_popup.visible = true


func _hide_preview() -> void:
	if _preview_popup != null:
		_preview_popup.visible = false


func _add_selection_entry() -> Dictionary:
	if add_kind_option.selected < 0:
		return {}
	var kind := add_kind_option.get_item_text(add_kind_option.selected)
	if kind == "Ritual":
		if add_value_option.selected < 0:
			return {}
		var ritual_value := int(add_value_option.get_item_text(add_value_option.selected))
		return {"kind": "ritual", "value": ritual_value}
	if kind == "Incantation":
		if add_verb_option.selected < 0 or add_verb_option.selected >= INCANTATION_VERBS.size():
			return {}
		var sel_verb := INCANTATION_VERBS[add_verb_option.selected]
		if sel_verb == "dethrone":
			return {"kind": "dethrone", "value": 4}
		if add_value_option.selected < 0:
			return {}
		var ivalue := int(add_value_option.get_item_text(add_value_option.selected))
		return {"kind": "incantation", "verb": sel_verb, "value": ivalue}
	if kind == "Noble":
		if add_verb_option.selected >= 0 and add_verb_option.selected < NOBLE_DEFS.size():
			var noble: Dictionary = NOBLE_DEFS[add_verb_option.selected]
			return {"kind": "noble", "noble_id": str(noble.get("id", "")), "name": str(noble.get("name", ""))}
		return {"kind": "noble", "name": "Noble"}
	return {"kind": "dethrone", "value": 4}


func _on_add_hovered() -> void:
	_show_preview(_entry_preview_text(_add_selection_entry()))


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
				_add_or_increment_entry(_entry_key_noble(nid), {"kind": "noble", "noble_id": nid, "name": nname})
		elif kind == "dethrone":
			if int(card.get("value", 4)) == 4:
				_add_or_increment_entry("dethrone", {"kind": "dethrone", "value": 4})


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


func _deck_readonly() -> bool:
	return IncludedDecks.is_token(_selected_deck_path)


func _apply_readonly_ui() -> void:
	var ro := _deck_readonly()
	add_type_button.disabled = ro
	add_kind_option.disabled = ro
	add_verb_option.disabled = ro
	add_value_option.disabled = ro
	deck_name_edit.editable = not ro
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
	sb.bg_color = Color(0.15, 0.17, 0.22)
	sb.border_color = Color(0.45, 0.5, 0.62)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	bg.add_theme_stylebox_override("panel", sb)
	row.add_child(bg)
	var preview_text := _entry_preview_text(entry)
	bg.mouse_entered.connect(func() -> void:
		_show_preview(preview_text)
	)
	bg.mouse_exited.connect(_hide_preview)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	bg.add_child(inner)

	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.text = "%s x%d" % [_entry_display_name(entry), int(entry.get("count", 0))]
	inner.add_child(lbl)

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


func _on_add_type_pressed() -> void:
	if _deck_readonly():
		return
	var kind := add_kind_option.get_item_text(add_kind_option.selected)
	var value := int(add_value_option.get_item_text(add_value_option.selected))
	if kind == "Ritual":
		var key_r := _entry_key_ritual(value)
		if _entries.has(key_r):
			_increment_entry(key_r)
			return
		var entry_r := {"kind": "ritual", "value": value, "count": 0}
		if not _can_increase_entry(entry_r):
			_show_cannot_add_status(entry_r)
			return
		entry_r["count"] = 1
		_entries[key_r] = entry_r
	elif kind == "Incantation":
		var verb := INCANTATION_VERBS[add_verb_option.selected]
		if verb == "dethrone":
			if _entries.has("dethrone"):
				_increment_entry("dethrone")
				return
			var entry_d := {"kind": "dethrone", "value": 4, "count": 0}
			if not _can_increase_entry(entry_d):
				_show_cannot_add_status(entry_d)
				return
			entry_d["count"] = 1
			_entries["dethrone"] = entry_d
			_render_entries()
			_update_validation()
			return
		if not _incantation_values_for_verb(verb).has(value):
			var legal_values: Array[int] = _incantation_values_for_verb(verb)
			var legal_text := ",".join(PackedStringArray(legal_values.map(func(v: int) -> String:
				return str(v)
			)))
			status_label.text = "%s only supports values %s." % [verb.capitalize(), legal_text]
			status_label.modulate = Color(1, 0.95, 0.6)
			return
		var key_i := _entry_key_incantation(verb, value)
		if _entries.has(key_i):
			_increment_entry(key_i)
			return
		var entry_i := {"kind": "incantation", "verb": verb, "value": value, "count": 0}
		if not _can_increase_entry(entry_i):
			_show_cannot_add_status(entry_i)
			return
		entry_i["count"] = 1
		_entries[key_i] = entry_i
	elif kind == "Noble":
		if add_verb_option.selected < 0 or add_verb_option.selected >= NOBLE_DEFS.size():
			return
		var noble: Dictionary = NOBLE_DEFS[add_verb_option.selected]
		var nid := str(noble.get("id", ""))
		var key_n := _entry_key_noble(nid)
		if _entries.has(key_n):
			_increment_entry(key_n)
			return
		var entry_n := {"kind": "noble", "noble_id": nid, "name": str(noble.get("name", "")), "count": 0}
		if not _can_increase_entry(entry_n):
			_show_cannot_add_status(entry_n)
			return
		entry_n["count"] = 1
		_entries[key_n] = entry_n
	else:
		if _entries.has("dethrone"):
			_increment_entry("dethrone")
			return
		var entry_d := {"kind": "dethrone", "value": 4, "count": 0}
		if not _can_increase_entry(entry_d):
			_show_cannot_add_status(entry_d)
			return
		entry_d["count"] = 1
		_entries["dethrone"] = entry_d
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
	if kind == "incantation" or kind == "dethrone":
		if count >= MAX_INCANTATION_COPIES:
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
		elif kind == "dethrone":
			dethrone_total += count
	return {
		"rituals": ritual_total,
		"incantations": incantation_total,
		"nobles": noble_total,
		"dethrones": dethrone_total,
		"non_ritual": incantation_total + noble_total + dethrone_total
	}


func _update_validation() -> void:
	var totals := _totals()
	var total_cards := int(totals["rituals"]) + int(totals["non_ritual"])
	totals_label.text = "Rituals %d/%d   Non-Ritual %d/%d   Total %d/40" % [
		totals["rituals"],
		TARGET_RITUAL_COUNT,
		totals["non_ritual"],
		TARGET_NON_RITUAL_COUNT,
		total_cards
	]
	var copies_ok := _incantation_copy_limit_ok()
	var noble_ok := _noble_copy_limit_ok()
	var is_valid: bool = totals["rituals"] == TARGET_RITUAL_COUNT and totals["non_ritual"] == TARGET_NON_RITUAL_COUNT and copies_ok and noble_ok
	var ro := _deck_readonly()
	save_button.disabled = not is_valid or ro
	if ro:
		if is_valid:
			status_label.text = "Included deck (read-only; cannot delete or overwrite)."
			status_label.modulate = Color(0.72, 0.88, 1.0)
		else:
			status_label.text = "Included deck data looks invalid."
			status_label.modulate = Color(1, 0.55, 0.55)
	elif is_valid:
		status_label.text = "Deck is legal. Save is enabled."
		status_label.modulate = Color(0.65, 1, 0.65)
	elif not copies_ok:
		status_label.text = "Adjust counts: max %d copies of each incantation variant." % MAX_INCANTATION_COPIES
		status_label.modulate = Color(1, 0.95, 0.6)
	elif not noble_ok:
		status_label.text = "Adjust counts: max %d nobles of the same first name." % MAX_NOBLE_FIRSTNAME_COPIES
		status_label.modulate = Color(1, 0.95, 0.6)
	else:
		status_label.text = "Adjust counts to a legal 40-card deck."
		status_label.modulate = Color(1, 0.95, 0.6)


func _build_deck_payload() -> Dictionary:
	var cards: Array[Dictionary] = []
	var ritual_counts: Dictionary = {}
	var incantation_counts: Dictionary = {}
	var noble_counts: Dictionary = {}
	var dethrone_count := 0
	for value in RITUAL_VALUES:
		ritual_counts[str(value)] = 0
	for verb in INCANTATION_VERBS:
		for value in _incantation_values_for_verb(verb):
			incantation_counts["%s_%d" % [verb, value]] = 0
	for n in NOBLE_DEFS:
		noble_counts[str(n.get("id", ""))] = 0

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
			if str(entry.get("kind", "")) == "dethrone":
				dethrone_count = count
				for _m in count:
					cards.append({"type": "Dethrone", "value": 4})
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
			"dethrones": dethrone_count
		},
		"rules_snapshot": {
			"total_cards": 40,
			"ritual_target": TARGET_RITUAL_COUNT,
			"non_ritual_target": TARGET_NON_RITUAL_COUNT,
			"max_ritual_copies": MAX_RITUAL_COPIES
		}
	}


func _write_json(path: String, payload: Dictionary) -> int:
	_ensure_deck_dir()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	return OK


func _load_deck_payload(path: String) -> Dictionary:
	if IncludedDecks.is_token(path):
		return IncludedDecks.payload_for_slug(IncludedDecks.slug_from_token(path))
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func _export_path() -> String:
	var stamp := Time.get_datetime_string_from_system(false).replace(":", "-").replace(" ", "_")
	return "%s/%s%s%s" % [DECK_DIR, DECK_EXPORT_PREFIX, stamp, DECK_EXT]


func _build_decks_export_payload() -> Dictionary:
	var exported_decks: Array[Dictionary] = []
	for path in _deck_paths:
		if IncludedDecks.is_token(path):
			continue
		var payload := _load_deck_payload(path)
		if payload.is_empty():
			continue
		exported_decks.append({
			"file_name": path.get_file(),
			"deck_name": str(payload.get("deck_name", path.get_file().trim_suffix(DECK_EXT))),
			"payload": payload
		})
	return {
		"schema_version": 1,
		"exported_at": Time.get_datetime_string_from_system(true),
		"deck_count": exported_decks.size(),
		"decks": exported_decks
	}


func _on_export_decks_button_pressed() -> void:
	_refresh_deck_list()
	var export_payload := _build_decks_export_payload()
	var export_count := int(export_payload.get("deck_count", 0))
	if export_count <= 0:
		status_label.text = "No saved deck files found to export."
		status_label.modulate = Color(1, 0.95, 0.6)
		return
	var path := _export_path()
	var result := _write_json(path, export_payload)
	if result != OK:
		status_label.text = "Failed to export decks to %s (error %d)." % [path, result]
		status_label.modulate = Color(1, 0.55, 0.55)
		return
	status_label.text = "Exported %d deck(s): %s" % [export_count, path]
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
	if totals["rituals"] != TARGET_RITUAL_COUNT or totals["non_ritual"] != TARGET_NON_RITUAL_COUNT:
		status_label.text = "Deck is invalid. Rituals must be %d and non-ritual cards must be %d." % [TARGET_RITUAL_COUNT, TARGET_NON_RITUAL_COUNT]
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
