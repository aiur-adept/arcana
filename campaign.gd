extends Control

const IncludedDecks = preload("res://included_decks.gd")
const GalleryCatalog = preload("res://gallery_catalog.gd")
const ScalableCardBack = preload("res://scalable_card_back.gd")

const SELECTED_DECK_PATH_FILE := "user://selected_deck_path.txt"
const SELECTED_OPPONENT_DECK_PATH_FILE := "user://selected_opponent_deck_path.txt"
const PLAY_MODE_FILE := "user://arcana_play_mode.txt"
const CAMPAIGN_PROGRESS_FILE := "user://arcana_campaign_progress.json"
const CAMPAIGN_CHALLENGER_FILE := "user://arcana_campaign_challenger.txt"
const CAMPAIGN_SERIES_FILE := "user://arcana_campaign_series.json"
const CAMPAIGN_SELECTED_DECK_FILE := "user://arcana_campaign_selected_deck.txt"
const CAMPAIGN_PLAYER_DECK_FILE := "user://arcana_campaign_player_deck.txt"

const CAMPAIGN_ORDER: Array[String] = [
	"emanation",
	"occultation",
	"annihilation",
	"ritual_reanimator",
	"void_temples",
	"bird_flock"
]

const TRACK_LINE_COLOR := Color(0.52, 0.56, 0.68, 0.92)
const NODE_LOCKED_COLOR := Color(0.38, 0.42, 0.50, 1.0)
const NODE_CURRENT_COLOR := Color(0.96, 0.78, 0.26, 1.0)
const NODE_DONE_COLOR := Color(0.28, 0.82, 0.64, 1.0)
const PREVIEW_SCALE := 1.38

@onready var back_button: Button = %BackButton
@onready var progress_label: Label = %ProgressLabel
@onready var campaign_deck_label: Label = %CampaignDeckLabel
@onready var campaign_deck_button: Button = %CampaignDeckButton
@onready var node_track: Control = %NodeTrack
@onready var node_hbox: HBoxContainer = %NodeHBox
@onready var challenge_dialog: ConfirmationDialog = %ChallengeDialog
@onready var deck_picker_overlay: Control = %DeckPickerOverlay
@onready var deck_picker_list: ItemList = %DeckPickerList
@onready var deck_picker_status: Label = %DeckPickerStatus
@onready var deck_picker_confirm_button: Button = %DeckPickerConfirmButton
@onready var deck_picker_cancel_button: Button = %DeckPickerCancelButton

var _campaign_progress: int = 0
var _pending_challenge_slug: String = ""
var _campaign_deck_path: String = ""
var _deck_paths: Array[String] = []
var _preview_buttons: Array[Button] = []
var _node_markers: Array[Control] = []
var _lock_overlays: Array[ColorRect] = []
var _cardback_overlays: Array[Control] = []
var _slug_labels: Array[Label] = []
var _lock_label_questions: Array[Label] = []
var _track_line: ColorRect


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	campaign_deck_button.pressed.connect(_on_campaign_deck_button_pressed)
	challenge_dialog.confirmed.connect(_on_challenge_confirmed)
	deck_picker_list.item_selected.connect(_on_deck_picker_item_selected)
	deck_picker_list.item_activated.connect(_on_deck_picker_item_activated)
	deck_picker_confirm_button.pressed.connect(_on_deck_picker_confirm_pressed)
	deck_picker_cancel_button.pressed.connect(_hide_deck_picker)
	node_track.resized.connect(_refresh_track_visuals)
	node_hbox.resized.connect(_refresh_track_visuals)
	deck_picker_overlay.visible = false
	_refresh_deck_paths()
	_campaign_deck_path = _load_selected_campaign_deck_path()
	if _campaign_deck_path.is_empty():
		_show_deck_picker(true)
	else:
		_reload_campaign_state_for_selected_deck()
	_build_track_ui()
	_update_unlock_states()


func _build_track_ui() -> void:
	for child in node_hbox.get_children():
		child.queue_free()
	_preview_buttons.clear()
	_node_markers.clear()
	_lock_overlays.clear()
	_cardback_overlays.clear()
	_slug_labels.clear()
	_lock_label_questions.clear()
	for child in node_track.get_children():
		child.queue_free()
	_track_line = ColorRect.new()
	_track_line.color = TRACK_LINE_COLOR
	_track_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node_track.add_child(_track_line)
	for i in CAMPAIGN_ORDER.size():
		var slug := CAMPAIGN_ORDER[i]
		var card := _representative_preview_card(slug)
		var holder := VBoxContainer.new()
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.alignment = BoxContainer.ALIGNMENT_CENTER
		holder.add_theme_constant_override("separation", 10)
		node_hbox.add_child(holder)

		var preview_size := CardPreviewPresenter.preview_pixel_size({"card_scale": PREVIEW_SCALE})
		var top_block := Control.new()
		top_block.custom_minimum_size = Vector2(preview_size.x, preview_size.y + 50.0)
		top_block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		holder.add_child(top_block)

		var top_vbox := VBoxContainer.new()
		top_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		top_vbox.add_theme_constant_override("separation", 6)
		top_block.add_child(top_vbox)

		var preview_button := Button.new()
		preview_button.text = ""
		preview_button.custom_minimum_size = preview_size
		preview_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		preview_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		preview_button.focus_mode = Control.FOCUS_NONE
		preview_button.tooltip_text = ""
		preview_button.flat = true
		preview_button.clip_contents = true
		preview_button.pressed.connect(_on_preview_pressed.bind(slug, i))
		top_vbox.add_child(preview_button)

		var preview := CardPreviewPresenter.build_preview_panel(self, {
			"parent_slot": preview_button,
			"mode": "slot",
			"ui_scale": PREVIEW_SCALE,
			"card_scale": PREVIEW_SCALE,
			"name": "CampaignPreview_%s" % slug,
			"z_index": 2
		})
		CardPreviewPresenter.show_preview(preview, card)
		var cardback := Control.new()
		cardback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cardback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cardback.z_index = 60
		cardback.script = ScalableCardBack
		cardback.visible = false
		preview_button.add_child(cardback)

		var node_marker := PanelContainer.new()
		node_marker.custom_minimum_size = Vector2(24, 24)
		node_marker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		node_marker.focus_mode = Control.FOCUS_NONE
		holder.add_child(node_marker)

		var slug_label := Label.new()
		slug_label.text = slug
		slug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slug_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_vbox.add_child(slug_label)
		var lock_label_q := Label.new()
		lock_label_q.text = "?"
		lock_label_q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label_q.add_theme_font_size_override("font_size", 34)
		lock_label_q.visible = false
		top_vbox.add_child(lock_label_q)

		var lock_overlay := ColorRect.new()
		lock_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_overlay.color = Color(0, 0, 0, 0.50)
		lock_overlay.z_index = 50
		lock_overlay.visible = false
		top_block.add_child(lock_overlay)

		_preview_buttons.append(preview_button)
		_node_markers.append(node_marker)
		_lock_overlays.append(lock_overlay)
		_cardback_overlays.append(cardback)
		_slug_labels.append(slug_label)
		_lock_label_questions.append(lock_label_q)
	_update_unlock_states()
	call_deferred("_refresh_track_visuals")


func _on_campaign_deck_button_pressed() -> void:
	_show_deck_picker(false)


func _show_deck_picker(force_pick: bool) -> void:
	_refresh_deck_paths()
	deck_picker_list.clear()
	deck_picker_status.text = ""
	deck_picker_confirm_button.disabled = true
	for path in _deck_paths:
		deck_picker_list.add_item(IncludedDecks.list_row_text(path))
	if force_pick:
		deck_picker_status.text = "Select a campaign deck to begin."
	if _deck_paths.is_empty():
		deck_picker_status.text = "No deck files found."
		deck_picker_confirm_button.disabled = true
	deck_picker_cancel_button.disabled = force_pick and _campaign_deck_path.is_empty()
	deck_picker_overlay.visible = true
	deck_picker_overlay.move_to_front()
	deck_picker_list.grab_focus()


func _hide_deck_picker() -> void:
	deck_picker_overlay.visible = false


func _on_deck_picker_item_selected(_index: int) -> void:
	deck_picker_confirm_button.disabled = deck_picker_list.get_selected_items().is_empty()


func _on_deck_picker_item_activated(index: int) -> void:
	deck_picker_list.select(index)
	_apply_campaign_deck_selection()


func _on_deck_picker_confirm_pressed() -> void:
	_apply_campaign_deck_selection()


func _apply_campaign_deck_selection() -> void:
	var selected := deck_picker_list.get_selected_items()
	if selected.is_empty():
		return
	var idx := int(selected[0])
	if idx < 0 or idx >= _deck_paths.size():
		return
	_campaign_deck_path = _deck_paths[idx]
	_store_selected_campaign_deck_path(_campaign_deck_path)
	_reload_campaign_state_for_selected_deck()
	_hide_deck_picker()


func _refresh_deck_paths() -> void:
	_deck_paths.clear()
	for slug in IncludedDecks.slug_list():
		_deck_paths.append(IncludedDecks.token(slug))
	DirAccess.make_dir_recursive_absolute("user://decks")
	var dir := DirAccess.open("user://decks")
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var fn := dir.get_next()
		if fn == "":
			break
		if dir.current_is_dir() or not fn.ends_with(".json") or fn.begins_with("decks_export_"):
			continue
		_deck_paths.append("user://decks/%s" % fn)
	dir.list_dir_end()
	_deck_paths.sort()


func _load_selected_campaign_deck_path() -> String:
	if FileAccess.file_exists(CAMPAIGN_SELECTED_DECK_FILE):
		var f := FileAccess.open(CAMPAIGN_SELECTED_DECK_FILE, FileAccess.READ)
		if f != null:
			var saved := f.get_as_text().strip_edges()
			if not saved.is_empty() and _deck_paths.has(saved):
				return saved
	return ""


func _store_selected_campaign_deck_path(path: String) -> void:
	var f := FileAccess.open(CAMPAIGN_SELECTED_DECK_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(path)


func _reload_campaign_state_for_selected_deck() -> void:
	_campaign_progress = clampi(_load_campaign_progress_for_selected_deck(), 0, CAMPAIGN_ORDER.size())
	campaign_deck_label.text = "Deck: %s" % IncludedDecks.list_row_text(_campaign_deck_path)
	_update_progress_label()
	_update_unlock_states()


func _update_unlock_states() -> void:
	for i in _preview_buttons.size():
		var btn := _preview_buttons[i]
		var is_current := i == _campaign_progress and _campaign_progress < CAMPAIGN_ORDER.size()
		btn.disabled = not is_current
		btn.modulate = Color(1, 1, 1, 1.0)
		if i < _lock_overlays.size():
			_lock_overlays[i].visible = i > _campaign_progress
		if i < _cardback_overlays.size():
			_cardback_overlays[i].visible = i > _campaign_progress
		if i < _slug_labels.size():
			_slug_labels[i].visible = i <= _campaign_progress
		if i < _lock_label_questions.size():
			_lock_label_questions[i].visible = i > _campaign_progress
		if i < _node_markers.size():
			_apply_node_style(_node_markers[i], i < _campaign_progress)
	_refresh_track_visuals()


func _apply_node_style(node_marker: Control, filled: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(999)
	sb.set_border_width_all(2)
	sb.border_color = NODE_LOCKED_COLOR
	sb.bg_color = NODE_DONE_COLOR if filled else Color(0, 0, 0, 0)
	node_marker.add_theme_stylebox_override("panel", sb)


func _refresh_track_visuals() -> void:
	if _track_line == null or _node_markers.size() < 2:
		return
	var first: Control = _node_markers[0]
	var last: Control = _node_markers[_node_markers.size() - 1]
	if first == null or last == null:
		return
	var first_center := first.global_position + first.size * 0.5
	var last_center := last.global_position + last.size * 0.5
	var y := first_center.y - node_track.global_position.y
	var left := first_center.x - node_track.global_position.x
	var right := last_center.x - node_track.global_position.x
	_track_line.position = Vector2(minf(left, right), y - 2.0)
	_track_line.size = Vector2(absf(right - left), 4.0)


func _update_progress_label() -> void:
	if _campaign_deck_path.is_empty():
		progress_label.text = "Select a campaign deck."
		return
	if _campaign_progress >= CAMPAIGN_ORDER.size():
		progress_label.text = "Deck %s - campaign complete (6/6)" % IncludedDecks.list_row_text(_campaign_deck_path)
		return
	var next_slug := CAMPAIGN_ORDER[_campaign_progress]
	var series := _load_series_state_for_selected_deck()
	var wins := 0
	var losses := 0
	if str(series.get("slug", "")) == next_slug:
		wins = int(series.get("wins", 0))
		losses = int(series.get("losses", 0))
	progress_label.text = "Deck %s - progress: %d/6 - next: %s (set: %d-%d)" % [IncludedDecks.list_row_text(_campaign_deck_path), _campaign_progress, next_slug, wins, losses]


func _representative_preview_card(slug: String) -> Dictionary:
	if slug == "bird_flock":
		return GalleryCatalog.entry_to_preview_card({
			"kind": "temple",
			"type": "temple",
			"temple_id": "eyrie_feathers",
			"name": "Eyrie, Temple of Feathers",
			"cost": 6
		})
	var payload := IncludedDecks.payload_for_slug(slug)
	var cards_variant: Variant = payload.get("cards", [])
	if typeof(cards_variant) != TYPE_ARRAY:
		return {"kind": "temple", "type": "temple", "name": slug, "temple_id": "phaedra_illusion", "cost": 7}
	var cards := cards_variant as Array
	for card in cards:
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var c := card as Dictionary
		var ctype := str(c.get("type", "")).to_lower()
		if ctype == "noble" or ctype == "temple":
			return _deck_card_to_preview(c)
	for card in cards:
		if typeof(card) != TYPE_DICTIONARY:
			continue
		return _deck_card_to_preview(card as Dictionary)
	return {"kind": "temple", "type": "temple", "name": slug, "temple_id": "phaedra_illusion", "cost": 7}


func _deck_card_to_preview(card: Dictionary) -> Dictionary:
	var c := card.duplicate(true)
	var kind := str(c.get("type", "")).to_lower()
	c["kind"] = kind
	if kind == "noble":
		var id := str(c.get("noble_id", ""))
		if c.get("name", "") == "":
			c["name"] = _name_for_noble(id)
	if kind == "temple":
		var tid := str(c.get("temple_id", ""))
		if c.get("name", "") == "":
			c["name"] = _name_for_temple(tid)
		if int(c.get("cost", 0)) <= 0:
			c["cost"] = _cost_for_temple(tid)
	return GalleryCatalog.entry_to_preview_card(c)


func _name_for_noble(noble_id: String) -> String:
	for defn in GalleryCatalog.NOBLE_DEFS:
		if str(defn.get("id", "")) == noble_id:
			return str(defn.get("name", "Noble"))
	return "Noble"


func _name_for_temple(temple_id: String) -> String:
	for defn in GalleryCatalog.TEMPLE_DEFS:
		if str(defn.get("id", "")) == temple_id:
			return str(defn.get("name", "Temple"))
	return "Temple"


func _cost_for_temple(temple_id: String) -> int:
	for defn in GalleryCatalog.TEMPLE_DEFS:
		if str(defn.get("id", "")) == temple_id:
			return int(defn.get("cost", 7))
	return 7


func _on_preview_pressed(slug: String, index: int) -> void:
	if index != _campaign_progress:
		return
	_pending_challenge_slug = slug
	challenge_dialog.dialog_text = "challenge %s? (best of 3, play this deck)" % slug
	challenge_dialog.popup_centered()


func _on_challenge_confirmed() -> void:
	if _pending_challenge_slug.is_empty():
		return
	_launch_campaign_match()


func _launch_campaign_match() -> void:
	if _pending_challenge_slug.is_empty():
		return
	if _campaign_deck_path.is_empty():
		return
	var your_path := _campaign_deck_path
	var your_file := FileAccess.open(SELECTED_DECK_PATH_FILE, FileAccess.WRITE)
	if your_file == null:
		return
	your_file.store_string(your_path)

	var opp_file := FileAccess.open(SELECTED_OPPONENT_DECK_PATH_FILE, FileAccess.WRITE)
	if opp_file == null:
		return
	opp_file.store_string(IncludedDecks.token(_pending_challenge_slug))

	var mode_file := FileAccess.open(PLAY_MODE_FILE, FileAccess.WRITE)
	if mode_file != null:
		mode_file.store_string("campaign")
	var challenge_file := FileAccess.open(CAMPAIGN_CHALLENGER_FILE, FileAccess.WRITE)
	if challenge_file != null:
		challenge_file.store_string(_pending_challenge_slug)
	var player_deck_file := FileAccess.open(CAMPAIGN_PLAYER_DECK_FILE, FileAccess.WRITE)
	if player_deck_file != null:
		player_deck_file.store_string(_campaign_deck_path)
	get_tree().change_scene_to_file("res://game.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _campaign_deck_key(path: String) -> String:
	var p := path.strip_edges()
	if IncludedDecks.is_token(p):
		return p
	return p.replace("\\", "/").to_lower()


func _load_campaign_progress_for_selected_deck() -> int:
	if _campaign_deck_path.is_empty():
		return 0
	if not FileAccess.file_exists(CAMPAIGN_PROGRESS_FILE):
		return 0
	var f := FileAccess.open(CAMPAIGN_PROGRESS_FILE, FileAccess.READ)
	if f == null:
		return 0
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	var data := parsed as Dictionary
	var key := _campaign_deck_key(_campaign_deck_path)
	var by_deck_var: Variant = data.get("completed_by_deck", null)
	if typeof(by_deck_var) == TYPE_DICTIONARY:
		var by_deck := by_deck_var as Dictionary
		return int(by_deck.get(key, 0))
	return int(data.get("completed", 0))


func _load_series_state_for_selected_deck() -> Dictionary:
	if _campaign_deck_path.is_empty():
		return {}
	if not FileAccess.file_exists(CAMPAIGN_SERIES_FILE):
		return {}
	var f := FileAccess.open(CAMPAIGN_SERIES_FILE, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data := parsed as Dictionary
	var key := _campaign_deck_key(_campaign_deck_path)
	var by_deck_var: Variant = data.get("series_by_deck", null)
	if typeof(by_deck_var) == TYPE_DICTIONARY:
		var by_deck := by_deck_var as Dictionary
		var deck_series_var: Variant = by_deck.get(key, null)
		if typeof(deck_series_var) == TYPE_DICTIONARY:
			return deck_series_var as Dictionary
	if data.has("slug"):
		return data
	return {}
