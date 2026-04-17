extends Control

const CARD_SCALE := 1.618
const HAND_CARD_W := 72.0 * CARD_SCALE
const HAND_CARD_H := 102.0 * CARD_SCALE
const CARD_TEXT_FONT: Font = preload("res://fonts/Macondo-Regular.ttf")
const CornerPipDraw = preload("res://corner_pip_draw.gd")
const HAND_CARD_FONT_SIZE := 26

var _hover_preview: Dictionary = {}


func _ready() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	_build_hover_preview_panel()
	_build_examples()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _build_hover_preview_panel() -> void:
	_hover_preview = CardPreviewPresenter.build_preview_panel(self, {
		"mode": "corner",
		"z_index": 4096
	})


func _show_card_hover_preview(card: Dictionary) -> void:
	CardPreviewPresenter.show_preview(_hover_preview, card)


func _hide_card_hover_preview() -> void:
	CardPreviewPresenter.hide_preview(_hover_preview)


func _build_examples() -> void:
	_build_type_examples()
	_build_active_vs_inactive_examples()
	_build_pay_examples()


func _build_type_examples() -> void:
	var row: HBoxContainer = %ExampleTypeRow
	row.add_child(_caption("Ritual"))
	row.add_child(_make_ritual_card(2, true))
	row.add_child(_spacer(14.0))
	row.add_child(_caption("Noble"))
	row.add_child(_make_noble_card({
		"type": "noble",
		"name": "Trss, Noble of Power",
		"noble_id": "trss_power"
	}))
	row.add_child(_spacer(14.0))
	row.add_child(_caption("Incantation"))
	row.add_child(_make_hand_card_widget({
		"type": "incantation",
		"verb": "Seek",
		"value": 2
	}))


func _build_active_vs_inactive_examples() -> void:
	var row: HBoxContainer = %ExampleComboRow
	row.add_child(_caption("Active chain"))
	row.add_child(_make_ritual_card(1, true))
	row.add_child(_make_ritual_card(2, true))
	row.add_child(_make_ritual_card(3, true))
	row.add_child(_spacer(20.0))
	row.add_child(_caption("Broken chain (4 inactive)"))
	row.add_child(_make_ritual_card(1, true))
	row.add_child(_make_ritual_card(2, true))
	row.add_child(_make_ritual_card(4, false))


func _build_pay_examples() -> void:
	var row: HBoxContainer = %ExamplePayRow
	row.add_child(_caption("Active rituals"))
	row.add_child(_make_ritual_card(1, true))
	row.add_child(_make_ritual_card(2, true))
	row.add_child(_make_ritual_card(3, true))
	row.add_child(_caption("can cast"))
	row.add_child(_make_hand_card_widget({
		"type": "incantation",
		"verb": "Woe",
		"value": 3
	}))
	row.add_child(_make_noble_card({
		"type": "noble",
		"name": "Trss, Noble of Power",
		"noble_id": "trss_power"
	}))


func _caption(text_value: String) -> Label:
	var lbl := Label.new()
	lbl.text = text_value
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.9, 0.94))
	return lbl


func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 1.0)
	return c


func _make_ritual_card(value: int, active: bool) -> Control:
	var w := HAND_CARD_W
	var h := HAND_CARD_H
	var ritual_gold := Color(0.95, 0.78, 0.24)
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(2)
	sb.bg_color = Color(0.04, 0.04, 0.06)
	sb.border_color = ritual_gold
	panel.add_theme_stylebox_override("panel", sb)
	var rv := value
	panel.mouse_entered.connect(func() -> void:
		_show_card_hover_preview({"type": "ritual", "value": rv})
	)
	panel.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(cc)
	var lbl := Label.new()
	lbl.text = str(value)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", CARD_TEXT_FONT)
	lbl.add_theme_color_override("font_color", ritual_gold)
	lbl.add_theme_font_size_override("font_size", HAND_CARD_FONT_SIZE)
	cc.add_child(lbl)
	if not active:
		panel.modulate = Color(0.58, 0.58, 0.62)
	return panel


func _make_noble_card(noble: Dictionary) -> Control:
	var btn := Button.new()
	btn.disabled = true
	btn.custom_minimum_size = Vector2(HAND_CARD_W, HAND_CARD_H)
	btn.text = _short_noble_name(str(noble.get("name", "Noble")))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(2)
	sb.bg_color = Color(0.13, 0.1, 0.18)
	sb.border_color = Color(0.84, 0.7, 1.0)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_font_override("font", CARD_TEXT_FONT)
	btn.add_theme_font_size_override("font_size", HAND_CARD_FONT_SIZE)
	btn.add_theme_color_override("font_color", Color(0.96, 0.93, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.96, 0.93, 1.0))
	var noble_view := noble.duplicate(true)
	noble_view["type"] = "noble"
	btn.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(noble_view)
	)
	btn.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	return btn


func _make_hand_card_widget(card: Dictionary) -> Control:
	var w := HAND_CARD_W
	var h := HAND_CARD_H
	var shell := Control.new()
	shell.custom_minimum_size = Vector2(w, h)
	shell.mouse_filter = Control.MOUSE_FILTER_PASS
	var tap := Button.new()
	tap.text = _card_label(card)
	tap.position = Vector2.ZERO
	tap.size = Vector2(w, h)
	tap.disabled = true
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(2)
	sb.bg_color = Color(0.04, 0.04, 0.06)
	sb.border_color = Color(0.92, 0.92, 0.95)
	tap.add_theme_stylebox_override("normal", sb)
	tap.add_theme_stylebox_override("disabled", sb)
	tap.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	tap.add_theme_color_override("font_disabled_color", Color(0.98, 0.98, 0.98))
	tap.add_theme_font_override("font", CARD_TEXT_FONT)
	tap.add_theme_font_size_override("font_size", HAND_CARD_FONT_SIZE)
	var hover_card: Dictionary = card.duplicate(true)
	shell.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(hover_card)
	)
	shell.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	tap.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(hover_card)
	)
	tap.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	shell.add_child(tap)
	var pip_spec := _card_corner_pip_spec(card)
	if int(pip_spec.get("count", 0)) > 0:
		var pip_icon := _make_corner_pip_icon(int(pip_spec.get("count", 0)), bool(pip_spec.get("filled", false)))
		pip_icon.position = Vector2(w - pip_icon.custom_minimum_size.x - 4, h - pip_icon.custom_minimum_size.y - 4)
		shell.add_child(pip_icon)
	return shell


func _card_corner_pip_spec(card: Dictionary) -> Dictionary:
	var t := _card_type(card)
	if t == "ritual":
		return {"count": max(0, int(card.get("value", 0))), "filled": true}
	if t == "incantation":
		return {"count": max(0, int(card.get("value", 0))), "filled": false}
	if t == "noble":
		return {"count": _noble_cost_for_id(str(card.get("noble_id", ""))), "filled": false}
	return {"count": 0, "filled": false}


func _make_corner_pip_icon(count: int, filled: bool) -> TextureRect:
	var n := clampi(count, 0, 24)
	var icon_size: int = 28
	var center := Vector2i(icon_size >> 1, icon_size >> 1)
	var image := Image.create(icon_size, icon_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var dot_r: int = 4
	if n == 1:
		CornerPipDraw.draw_dot_on_image(image, center, dot_r, filled)
	else:
		var remaining: int = n
		var ring: int = 1
		var step: float = 6.0
		while remaining > 0:
			var cap: int = ring * 6
			var take: int = mini(remaining, cap)
			var radius: int = int(round(ring * step))
			for i in take:
				var ang := TAU * (float(i) / float(take)) - PI / 2.0
				var px := center.x + int(round(cos(ang) * radius))
				var py := center.y + int(round(sin(ang) * radius))
				CornerPipDraw.draw_dot_on_image(image, Vector2i(px, py), dot_r, filled)
			remaining -= take
			ring += 1
	var tex := ImageTexture.create_from_image(image)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP
	rect.custom_minimum_size = Vector2(icon_size, icon_size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _card_type(card: Dictionary) -> String:
	return str(card.get("type", "")).to_lower()


func _card_label(card: Dictionary) -> String:
	var t := _card_type(card)
	if t == "ritual":
		return "%d-R" % int(card.get("value", 0))
	if t == "noble":
		return _short_noble_name(str(card.get("name", "Noble")))
	if t == "dethrone":
		return "Dethrone 4"
	return "%s %d" % [str(card.get("verb", "")), int(card.get("value", 0))]


func _short_noble_name(full_name: String) -> String:
	var idx := full_name.find(",")
	if idx <= 0:
		return full_name
	return full_name.substr(0, idx).strip_edges()


func _noble_cost_for_id(nid: String) -> int:
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
