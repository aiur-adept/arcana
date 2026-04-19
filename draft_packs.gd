extends Control

const ScalableCardBack = preload("res://scalable_card_back.gd")
const DeckEditorScr = preload("res://deck_editor.gd")
const CardPreviewScr = preload("res://card_preview_presenter.gd")
const CardRarityScr = preload("res://card_rarity.gd")

const PACKS_TARGET := 10
const CARDS_PER_PACK := 10

var _de: Control
var _catalog: Array = []
var _pool_bronze: Array = []
var _pool_silver: Array = []
var _pool_gold: Array = []

var _rng := RandomNumberGenerator.new()

var _packs_opened: int = 0
var _busy: bool = false
var _intro_visible: bool = true

var _open_another: Button
var _draft_btn: Button
var _back_btn: Button

@onready var draft_session: Node = get_node("/root/DraftSession")

var _intro_host: Control
var _open_pack_button: Button
var _intro_back: Control
var _grid_host: Control
var _grid: GridContainer

var _slot_pivots: Array[Control] = []
var _slot_backs: Array[Control] = []
var _slot_preview_hosts: Array[Control] = []
var _slot_preview_state: Array[Dictionary] = []

var _current_pack: Array = []


func _ready() -> void:
	draft_session.begin()
	_rng.randomize()
	_de = DeckEditorScr.new()
	_catalog.clear()
	_pool_bronze.clear()
	_pool_silver.clear()
	_pool_gold.clear()
	for e in _de._build_gallery_entries():
		if str(e.get("kind", "")) == "ritual":
			continue
		_catalog.append(e)
		match CardRarityScr.rarity(e):
			"bronze":
				_pool_bronze.append(e)
			"silver":
				_pool_silver.append(e)
			"gold":
				_pool_gold.append(e)

	var sz: Vector2 = CardPreviewScr.preview_pixel_size({})

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.08, 0.1, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_grid_host = CenterContainer.new()
	_grid_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid_host.offset_top = 56.0
	_grid_host.visible = false
	_grid_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid_host)

	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid_host.add_child(_grid)
	_build_slots(sz)

	_intro_host = CenterContainer.new()
	_intro_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_host.offset_top = 56.0
	_intro_host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_intro_host)

	var intro_v := VBoxContainer.new()
	intro_v.add_theme_constant_override("separation", 14)
	intro_v.alignment = BoxContainer.ALIGNMENT_CENTER
	intro_v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	intro_v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_intro_host.add_child(intro_v)

	_open_pack_button = Button.new()
	_open_pack_button.flat = true
	_open_pack_button.focus_mode = Control.FOCUS_NONE
	_open_pack_button.custom_minimum_size = sz
	_open_pack_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_open_pack_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_open_pack_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_open_pack_button.pressed.connect(_on_open_pack_pressed)
	intro_v.add_child(_open_pack_button)

	_intro_back = ScalableCardBack.new()
	_intro_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open_pack_button.add_child(_intro_back)

	var hint := Label.new()
	hint.text = "Click to open pack."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intro_v.add_child(hint)

	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 12.0
	top.offset_bottom = 56.0
	top.add_theme_constant_override("margin_left", 16)
	top.add_theme_constant_override("margin_right", 16)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_child(top_row)

	_back_btn = Button.new()
	_back_btn.text = "Main menu"
	_back_btn.pressed.connect(_on_main_menu_pressed)
	top_row.add_child(_back_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)

	_open_another = Button.new()
	_open_another.text = "Open another pack"
	_open_another.disabled = true
	_open_another.pressed.connect(_on_open_another_pressed)
	top_row.add_child(_open_another)

	_draft_btn = Button.new()
	_draft_btn.disabled = true
	_draft_btn.pressed.connect(_on_draft_deck_pressed)
	top_row.add_child(_draft_btn)

	_refresh_top_bar()


func _exit_tree() -> void:
	if _de != null:
		_de.queue_free()
		_de = null


func _fit_grid_scale() -> float:
	var vp: Vector2 = get_viewport_rect().size
	var sz: Vector2 = CardPreviewScr.preview_pixel_size({})
	var gap := 8.0
	var avail_w: float = vp.x - 40.0
	var avail_h: float = vp.y - 100.0
	var gw: float = 5.0 * sz.x + 4.0 * gap
	var gh: float = 2.0 * sz.y + gap
	return minf(minf(avail_w / gw, avail_h / gh), 1.0)


func _build_slots(base_sz: Vector2) -> void:
	for i in CARDS_PER_PACK:
		var cell := MarginContainer.new()
		cell.add_theme_constant_override("margin_right", 0)
		cell.add_theme_constant_override("margin_bottom", 0)

		var pivot := Control.new()
		pivot.custom_minimum_size = base_sz
		pivot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pivot.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var back := ScalableCardBack.new()
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var ph := Control.new()
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE

		pivot.add_child(back)
		pivot.add_child(ph)
		cell.add_child(pivot)
		_grid.add_child(cell)

		_slot_pivots.append(pivot)
		_slot_backs.append(back)
		_slot_preview_hosts.append(ph)
		_slot_preview_state.append({})


func _on_open_pack_pressed() -> void:
	if _busy:
		return
	_begin_first_pack()


func _begin_first_pack() -> void:
	_busy = true
	_intro_visible = false
	_intro_host.visible = false
	_grid_host.visible = true
	await get_tree().process_frame
	_grid.scale = Vector2(_fit_grid_scale(), _fit_grid_scale())
	await _roll_and_reveal_pack()


func _on_open_another_pressed() -> void:
	if _busy or _packs_opened >= PACKS_TARGET:
		return
	_prepare_new_pack_visuals()
	await _roll_and_reveal_pack()


func _prepare_new_pack_visuals() -> void:
	_busy = true
	for i in CARDS_PER_PACK:
		var st: Dictionary = _slot_preview_state[i]
		var root: Control = st.get("root") as Control
		if root != null and is_instance_valid(root):
			root.queue_free()
		_slot_preview_state[i] = {}
		var pivot: Control = _slot_pivots[i]
		pivot.scale = Vector2.ONE
		pivot.pivot_offset = pivot.size * 0.5
		_slot_backs[i].visible = true
	_current_pack.clear()


func _tier_for_pack_slot(slot_i: int) -> String:
	if slot_i <= 6:
		return "bronze"
	if slot_i <= 8:
		return "silver"
	return "gold"


func _pick_entry_for_tier(tier: String) -> Dictionary:
	var pool: Array = _pool_bronze
	if tier == "silver":
		pool = _pool_silver
	elif tier == "gold":
		pool = _pool_gold
	if pool.is_empty():
		pool = _catalog
	if pool.is_empty():
		return {}
	var row: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)] as Dictionary
	return row.duplicate(true)


func _roll_and_reveal_pack() -> void:
	_current_pack.clear()
	for slot_i in CARDS_PER_PACK:
		var tier := _tier_for_pack_slot(slot_i)
		_current_pack.append(_pick_entry_for_tier(tier))
	draft_session.merge_pack(_current_pack)
	_packs_opened += 1
	await _reveal_sequence_async()
	_busy = false
	_refresh_top_bar()


func _reveal_sequence_async() -> void:
	for i in CARDS_PER_PACK:
		await _flip_slot_async(i, _current_pack[i])


func _flip_slot_async(slot_i: int, entry: Dictionary) -> void:
	var pivot: Control = _slot_pivots[slot_i]
	var back: Control = _slot_backs[slot_i]
	var ph: Control = _slot_preview_hosts[slot_i]
	pivot.pivot_offset = pivot.size * 0.5

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pivot, "scale:x", 0.0, 0.11)
	await tw.finished

	back.visible = false
	var card: Dictionary = _de._entry_to_preview_card(entry)
	var prev: Dictionary = CardPreviewPresenter.build_preview_panel(ph, {
		"parent_slot": ph,
		"z_index": 2,
		"name": "DraftSlotPreview_%d" % slot_i
	})
	_slot_preview_state[slot_i] = prev
	CardPreviewPresenter.show_preview(prev, card)
	var root_panel: Control = prev.get("root") as Control
	if root_panel != null:
		root_panel.visible = true

	tw = create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pivot, "scale:x", 1.0, 0.11)
	await tw.finished


func _refresh_top_bar() -> void:
	_open_another.disabled = _busy or _packs_opened >= PACKS_TARGET or _intro_visible
	if _packs_opened >= PACKS_TARGET:
		_draft_btn.disabled = false
		_draft_btn.text = "Draft deck"
	else:
		_draft_btn.disabled = true
		_draft_btn.text = "Draft now (%d/%d)" % [_packs_opened, PACKS_TARGET]


func _on_draft_deck_pressed() -> void:
	if _packs_opened < PACKS_TARGET:
		return
	get_tree().change_scene_to_file("res://deck_editor.tscn")


func _on_main_menu_pressed() -> void:
	draft_session.clear()
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _grid_host != null and _grid_host.visible:
		_grid.scale = Vector2(_fit_grid_scale(), _fit_grid_scale())
