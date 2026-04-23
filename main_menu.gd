extends Control

const IncludedDecks = preload("res://included_decks.gd")

const DECK_DIR := "user://decks"
const DECK_EXT := ".json"
const DECK_EXPORT_PREFIX := "decks_export_"
const SELECTED_DECK_PATH_FILE := "user://selected_deck_path.txt"
const SELECTED_OPPONENT_DECK_PATH_FILE := "user://selected_opponent_deck_path.txt"
const PLAY_MODE_FILE := "user://arcana_play_mode.txt"
const LAN_JOIN_FILE := "user://arcana_lan_join.txt"
const LAN_LAST_JOIN_FILE := "user://arcana_lan_last_join.txt"
const DEFAULT_LAN_PORT := 17777

const _PICKER_STEP_YOURS := "yours"
const _PICKER_STEP_OPPONENT := "opponent"

@onready var play_button: Button = %PlayLink
@onready var campaign_button: Button = %CampaignLink
@onready var goldfish_button: Button = %GoldfishLink
@onready var lan_host_button: Button = %LanHostLink
@onready var lan_join_button: Button = %LanJoinLink
@onready var deck_editor_button: Button = %DeckEditorLink
@onready var draft_deck_button: Button = %DraftDeckLink
@onready var how_to_play_button: Button = %HowToPlayLink
@onready var exit_button: Button = %ExitButton
@onready var draft_session: Node = get_node("/root/DraftSession")
@onready var deck_picker_overlay: Control = %DeckPickerOverlay
@onready var deck_picker_title: Label = %DeckPickerTitle
@onready var deck_picker_list: ItemList = %DeckPickerList
@onready var deck_picker_status: Label = %DeckPickerStatus
@onready var deck_picker_confirm_button: Button = %DeckPickerConfirmButton
@onready var deck_picker_cancel_button: Button = %DeckPickerCancelButton
@onready var lan_join_overlay: Control = %LanJoinOverlay
@onready var lan_join_host_edit: LineEdit = %LanJoinHostEdit
@onready var lan_join_port_edit: LineEdit = %LanJoinPortEdit
@onready var lan_join_deck_list: ItemList = %LanJoinDeckList
@onready var lan_join_status: Label = %LanJoinStatus
@onready var lan_join_cancel_button: Button = %LanJoinCancelButton
@onready var lan_join_connect_button: Button = %LanJoinConnectButton

var _deck_paths: Array[String] = []
var _deck_picker_for_goldfish: bool = false
var _deck_picker_for_lan_host: bool = false
var _deck_picker_step: String = _PICKER_STEP_YOURS
var _your_deck_path: String = ""


func _ready() -> void:
	_double_button_padding(play_button)
	_double_button_padding(campaign_button)
	_double_button_padding(goldfish_button)
	_double_button_padding(lan_host_button)
	_double_button_padding(lan_join_button)
	_double_button_padding(deck_editor_button)
	_double_button_padding(draft_deck_button)
	_double_button_padding(how_to_play_button)
	_double_button_padding(exit_button)
	%PlayLink.pressed.connect(_on_play_pressed)
	%CampaignLink.pressed.connect(_on_campaign_pressed)
	%GoldfishLink.pressed.connect(_on_goldfish_pressed)
	%LanHostLink.pressed.connect(_on_lan_host_pressed)
	%LanJoinLink.pressed.connect(_on_lan_join_pressed)
	%DeckEditorLink.pressed.connect(_on_deck_editor_pressed)
	%DraftDeckLink.pressed.connect(_on_draft_deck_pressed)
	%HowToPlayLink.pressed.connect(_on_how_to_play_pressed)
	%ExitButton.pressed.connect(_on_exit_pressed)
	deck_picker_list.item_selected.connect(_on_deck_picker_item_selected)
	deck_picker_list.item_activated.connect(_on_deck_picker_item_activated)
	deck_picker_confirm_button.pressed.connect(_on_deck_picker_confirm_pressed)
	deck_picker_cancel_button.pressed.connect(_hide_deck_picker)
	deck_picker_overlay.visible = false
	deck_picker_confirm_button.disabled = true
	lan_join_overlay.visible = false
	lan_join_connect_button.pressed.connect(_on_lan_join_connect_pressed)
	lan_join_cancel_button.pressed.connect(_hide_lan_join_overlay)
	lan_join_deck_list.item_selected.connect(_on_lan_join_deck_selected)
	lan_join_deck_list.item_activated.connect(_on_lan_join_deck_activated)


func _double_button_padding(btn: Button) -> void:
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := btn.get_theme_stylebox(style_name)
		if style == null:
			continue
		var padded := style.duplicate()
		padded.content_margin_left *= 2.0
		padded.content_margin_right *= 2.0
		padded.content_margin_top *= 2.0
		padded.content_margin_bottom *= 2.0
		btn.add_theme_stylebox_override(style_name, padded)

func _on_play_pressed() -> void:
	_deck_picker_for_goldfish = false
	_deck_picker_for_lan_host = false
	_your_deck_path = ""
	_deck_picker_step = _PICKER_STEP_YOURS
	_show_deck_picker()


func _on_goldfish_pressed() -> void:
	_deck_picker_for_goldfish = true
	_deck_picker_for_lan_host = false
	_your_deck_path = ""
	_deck_picker_step = _PICKER_STEP_YOURS
	_show_deck_picker()


func _on_campaign_pressed() -> void:
	get_tree().change_scene_to_file("res://campaign.tscn")


func _on_lan_host_pressed() -> void:
	_deck_picker_for_goldfish = false
	_deck_picker_for_lan_host = true
	_your_deck_path = ""
	_deck_picker_step = _PICKER_STEP_YOURS
	_show_deck_picker()


func _on_lan_join_pressed() -> void:
	_refresh_deck_paths()
	lan_join_deck_list.clear()
	lan_join_status.text = ""
	for path in _deck_paths:
		lan_join_deck_list.add_item(IncludedDecks.list_row_text(path))
	if _deck_paths.is_empty():
		lan_join_status.text = "No deck files found. Build and save one first."
		lan_join_connect_button.disabled = true
	else:
		lan_join_connect_button.disabled = true
	_load_lan_join_defaults_into_fields()
	lan_join_overlay.visible = true
	lan_join_host_edit.grab_focus()


func _load_lan_join_defaults_into_fields() -> void:
	if not FileAccess.file_exists(LAN_LAST_JOIN_FILE):
		lan_join_host_edit.text = ""
		lan_join_port_edit.text = str(DEFAULT_LAN_PORT)
		return
	var f := FileAccess.open(LAN_LAST_JOIN_FILE, FileAccess.READ)
	if f == null:
		lan_join_host_edit.text = ""
		lan_join_port_edit.text = str(DEFAULT_LAN_PORT)
		return
	var raw := f.get_as_text().strip_edges()
	if raw.is_empty():
		lan_join_host_edit.text = ""
		lan_join_port_edit.text = str(DEFAULT_LAN_PORT)
		return
	var lines := raw.split("\n", false)
	if lines.size() >= 2:
		lan_join_host_edit.text = lines[0].strip_edges()
		var pi := int(lines[1].strip_edges())
		lan_join_port_edit.text = str(pi if pi > 0 else DEFAULT_LAN_PORT)
		return
	var one := lines[0].strip_edges()
	if ":" in one:
		var idx := one.rfind(":")
		lan_join_host_edit.text = one.substr(0, idx).strip_edges()
		var ps := int(one.substr(idx + 1).strip_edges())
		lan_join_port_edit.text = str(ps if ps > 0 else DEFAULT_LAN_PORT)
	else:
		lan_join_host_edit.text = one
		lan_join_port_edit.text = str(DEFAULT_LAN_PORT)


func _hide_lan_join_overlay() -> void:
	lan_join_overlay.visible = false


func _on_lan_join_deck_selected(_index: int) -> void:
	lan_join_connect_button.disabled = lan_join_deck_list.get_selected_items().is_empty()


func _on_lan_join_deck_activated(index: int) -> void:
	lan_join_deck_list.select(index)
	_on_lan_join_connect_pressed()


func _on_lan_join_connect_pressed() -> void:
	var selected := lan_join_deck_list.get_selected_items()
	if selected.is_empty():
		lan_join_status.text = "Select a deck."
		return
	var host := lan_join_host_edit.text.strip_edges()
	if host.is_empty():
		lan_join_status.text = "Enter the host's LAN address."
		return
	var port := int(lan_join_port_edit.text.strip_edges())
	if port <= 0 or port >= 65536:
		lan_join_status.text = "Invalid port."
		return
	var deck_path := _deck_paths[int(selected[0])]
	var jf := FileAccess.open(LAN_JOIN_FILE, FileAccess.WRITE)
	if jf == null:
		lan_join_status.text = "Could not store join info."
		return
	jf.store_string("%s\n%d" % [host, port])
	var lf := FileAccess.open(LAN_LAST_JOIN_FILE, FileAccess.WRITE)
	if lf != null:
		lf.store_string("%s\n%d" % [host, port])
	var df := FileAccess.open(SELECTED_DECK_PATH_FILE, FileAccess.WRITE)
	if df == null:
		lan_join_status.text = "Could not store selected deck."
		return
	df.store_string(deck_path)
	DirAccess.remove_absolute(SELECTED_OPPONENT_DECK_PATH_FILE)
	var mf := FileAccess.open(PLAY_MODE_FILE, FileAccess.WRITE)
	if mf != null:
		mf.store_string("lan_client")
	_hide_lan_join_overlay()
	get_tree().change_scene_to_file("res://game.tscn")


func _show_deck_picker() -> void:
	_refresh_deck_paths()
	deck_picker_list.clear()
	deck_picker_confirm_button.disabled = true
	for path in _deck_paths:
		deck_picker_list.add_item(IncludedDecks.list_row_text(path))
	if _deck_paths.is_empty():
		deck_picker_title.text = "No decks"
		deck_picker_status.text = "No deck files found. Build and save one first."
		deck_picker_overlay.visible = true
		return
	_apply_picker_step_labels()
	deck_picker_overlay.visible = true
	deck_picker_list.grab_focus()


func _apply_picker_step_labels() -> void:
	if _deck_picker_for_lan_host:
		deck_picker_title.text = "LAN host — your deck"
		deck_picker_status.text = "Choose your deck, then start; a friend joins your LAN address."
		deck_picker_confirm_button.text = "Host"
		return
	if _deck_picker_for_goldfish:
		deck_picker_title.text = "Select your deck (goldfish)"
		deck_picker_status.text = "Choose a deck for goldfish (solo), then confirm."
		deck_picker_confirm_button.text = "Play"
		return
	if _deck_picker_step == _PICKER_STEP_YOURS:
		deck_picker_title.text = "Select your deck"
		deck_picker_status.text = "Step 1 of 2: choose your deck, then press Next."
		deck_picker_confirm_button.text = "Next"
	else:
		deck_picker_title.text = "Select opponent deck"
		deck_picker_status.text = "Step 2 of 2: choose the CPU's deck, then press Play."
		deck_picker_confirm_button.text = "Play"


func _hide_deck_picker() -> void:
	deck_picker_overlay.visible = false


func _refresh_deck_paths() -> void:
	_deck_paths.clear()
	for slug in IncludedDecks.slug_list():
		_deck_paths.append(IncludedDecks.token(slug))
	DirAccess.make_dir_recursive_absolute(DECK_DIR)
	var dir := DirAccess.open(DECK_DIR)
	if dir != null:
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


func _on_deck_picker_item_selected(_index: int) -> void:
	deck_picker_confirm_button.disabled = deck_picker_list.get_selected_items().is_empty()


func _on_deck_picker_item_activated(index: int) -> void:
	_advance_picker(index)


func _on_deck_picker_confirm_pressed() -> void:
	var selected := deck_picker_list.get_selected_items()
	if selected.is_empty():
		return
	_advance_picker(int(selected[0]))


func _advance_picker(index: int) -> void:
	if index < 0 or index >= _deck_paths.size():
		return
	var selected_path := _deck_paths[index]
	if _deck_picker_for_lan_host:
		_launch_lan_host(selected_path)
		return
	if _deck_picker_for_goldfish:
		_launch_match(selected_path, "")
		return
	if _deck_picker_step == _PICKER_STEP_OPPONENT:
		_launch_match(_your_deck_path, selected_path)
		return
	_your_deck_path = selected_path
	_deck_picker_step = _PICKER_STEP_OPPONENT
	deck_picker_list.deselect_all()
	deck_picker_confirm_button.disabled = true
	_apply_picker_step_labels()


func _launch_lan_host(your_path: String) -> void:
	if your_path.is_empty():
		deck_picker_status.text = "Could not resolve your deck selection."
		return
	var f := FileAccess.open(SELECTED_DECK_PATH_FILE, FileAccess.WRITE)
	if f == null:
		deck_picker_status.text = "Could not store selected deck. Try again."
		return
	f.store_string(your_path)
	DirAccess.remove_absolute(SELECTED_OPPONENT_DECK_PATH_FILE)
	var mf := FileAccess.open(PLAY_MODE_FILE, FileAccess.WRITE)
	if mf != null:
		mf.store_string("lan_host")
	_hide_deck_picker()
	get_tree().change_scene_to_file("res://game.tscn")


func _launch_match(your_path: String, opponent_path: String) -> void:
	if your_path.is_empty():
		deck_picker_status.text = "Could not resolve your deck selection."
		return
	var f := FileAccess.open(SELECTED_DECK_PATH_FILE, FileAccess.WRITE)
	if f == null:
		deck_picker_status.text = "Could not store selected deck. Try again."
		return
	f.store_string(your_path)
	if _deck_picker_for_goldfish:
		DirAccess.remove_absolute(SELECTED_OPPONENT_DECK_PATH_FILE)
	else:
		var of := FileAccess.open(SELECTED_OPPONENT_DECK_PATH_FILE, FileAccess.WRITE)
		if of == null:
			deck_picker_status.text = "Could not store opponent deck. Try again."
			return
		of.store_string(opponent_path)
	var mf := FileAccess.open(PLAY_MODE_FILE, FileAccess.WRITE)
	if mf != null:
		mf.store_string("goldfish" if _deck_picker_for_goldfish else "versus")
	_hide_deck_picker()
	get_tree().change_scene_to_file("res://game.tscn")

func _on_deck_editor_pressed() -> void:
	draft_session.clear()
	get_tree().change_scene_to_file("res://deck_editor.tscn")


func _on_draft_deck_pressed() -> void:
	get_tree().change_scene_to_file("res://draft_packs.tscn")


func _on_how_to_play_pressed() -> void:
	get_tree().change_scene_to_file("res://how_to_play.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
