extends Control

const IncludedDecks = preload("res://included_decks.gd")

const DECK_DIR := "user://decks"
const DECK_EXT := ".json"
const DECK_EXPORT_PREFIX := "decks_export_"
const SELECTED_DECK_PATH_FILE := "user://selected_deck_path.txt"

@onready var deck_picker_overlay: Control = %DeckPickerOverlay
@onready var deck_picker_list: ItemList = %DeckPickerList
@onready var deck_picker_status: Label = %DeckPickerStatus
@onready var deck_picker_confirm_button: Button = %DeckPickerConfirmButton
@onready var deck_picker_cancel_button: Button = %DeckPickerCancelButton

var _deck_paths: Array[String] = []


func _ready() -> void:
	%PlayLink.pressed.connect(_on_play_pressed)
	%DeckEditorLink.pressed.connect(_on_deck_editor_pressed)
	%HowToPlayLink.pressed.connect(_on_how_to_play_pressed)
	%ExitButton.pressed.connect(_on_exit_pressed)
	deck_picker_list.item_selected.connect(_on_deck_picker_item_selected)
	deck_picker_list.item_activated.connect(_on_deck_picker_item_activated)
	deck_picker_confirm_button.pressed.connect(_on_deck_picker_confirm_pressed)
	deck_picker_cancel_button.pressed.connect(_hide_deck_picker)
	deck_picker_overlay.visible = false
	deck_picker_confirm_button.disabled = true

func _on_play_pressed() -> void:
	_show_deck_picker()


func _show_deck_picker() -> void:
	_refresh_deck_paths()
	deck_picker_list.clear()
	deck_picker_confirm_button.disabled = true
	for path in _deck_paths:
		deck_picker_list.add_item(IncludedDecks.list_row_text(path))
	if _deck_paths.is_empty():
		deck_picker_status.text = "No deck files found. Build and save one first."
		return
	deck_picker_status.text = "Choose a deck, then press Play."
	deck_picker_overlay.visible = true
	deck_picker_list.grab_focus()


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
	_play_with_selected_deck(index)


func _on_deck_picker_confirm_pressed() -> void:
	var selected := deck_picker_list.get_selected_items()
	if selected.is_empty():
		return
	_play_with_selected_deck(int(selected[0]))


func _play_with_selected_deck(index: int) -> void:
	if index < 0 or index >= _deck_paths.size():
		return
	var selected_path := _deck_paths[index]
	var f := FileAccess.open(SELECTED_DECK_PATH_FILE, FileAccess.WRITE)
	if f == null:
		deck_picker_status.text = "Could not store selected deck. Try again."
		return
	f.store_string(selected_path)
	_hide_deck_picker()
	get_tree().change_scene_to_file("res://game.tscn")

func _on_deck_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://deck_editor.tscn")


func _on_how_to_play_pressed() -> void:
	get_tree().change_scene_to_file("res://how_to_play.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
