extends Control

const CARD_SCALE := 1.618
const HAND_CARD_W := 72.0 * CARD_SCALE
const HAND_CARD_H := 102.0 * CARD_SCALE
const CARD_TEXT_FONT: Font = preload("res://fonts/Macondo-Regular.ttf")
const CornerPipDraw = preload("res://corner_pip_draw.gd")
const HAND_CARD_FONT_SIZE := 21

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
	_build_temple_pay_example()
	_build_bird_fight_example()
	_build_bird_fight_example_multi()
	_build_nest_example()
	_build_ring_example()


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
	row.add_child(_spacer(14.0))
	row.add_child(_caption("Temple"))
	row.add_child(_make_temple_card(_delpha_temple()))
	row.add_child(_spacer(14.0))
	row.add_child(_caption("Bird"))
	row.add_child(_make_bird_card({
		"type": "bird",
		"bird_id": "wren",
		"name": "Wren",
		"cost": 2,
		"power": 1
	}))
	row.add_child(_spacer(14.0))
	row.add_child(_caption("Ring"))
	row.add_child(_make_hand_card_widget({
		"type": "ring",
		"ring_id": "sybiline_emanation",
		"name": "Sybiline, Ring of Emanation",
		"cost": 2
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


func _build_temple_pay_example() -> void:
	var row: HBoxContainer = %ExampleTempleRow
	row.add_child(_caption("Sacrifice"))
	row.add_child(_make_ritual_card(4, true))
	row.add_child(_make_ritual_card(2, true))
	row.add_child(_make_ritual_card(1, true))
	row.add_child(_caption("total 7 -> play"))
	row.add_child(_make_temple_card(_delpha_temple()))


func _delpha_temple() -> Dictionary:
	return {
		"type": "temple",
		"name": "Delpha, Temple of Oracles",
		"temple_id": "delpha_oracles",
		"cost": 7
	}


func _build_bird_fight_example() -> void:
	var finch := {
		"type": "bird",
		"bird_id": "finch",
		"name": "Finch",
		"cost": 2,
		"power": 1
	}
	var sparrow := {
		"type": "bird",
		"bird_id": "sparrow",
		"name": "Sparrow",
		"cost": 2,
		"power": 1
	}
	var setup: HBoxContainer = %ExampleBirdFightSetupRow
	setup.add_child(_caption("Setup"))
	setup.add_child(_make_bird_card(finch, false))
	setup.add_child(_caption("attacks"))
	setup.add_child(_make_bird_card(sparrow, false))
	setup.add_child(_caption("(defender)"))
	var outcome: HBoxContainer = %ExampleBirdFightOutcomeRow
	outcome.add_child(_caption("Outcome"))
	outcome.add_child(_make_bird_card(finch, true))
	outcome.add_child(_caption("and"))
	outcome.add_child(_make_bird_card(sparrow, true))
	outcome.add_child(_caption("→ crypt"))


func _build_bird_fight_example_multi() -> void:
	var kestrel := {
		"type": "bird",
		"bird_id": "kestrel",
		"name": "Kestrel",
		"cost": 3,
		"power": 2
	}
	var shrike := {
		"type": "bird",
		"bird_id": "shrike",
		"name": "Shrike",
		"cost": 3,
		"power": 2
	}
	var hawk := {
		"type": "bird",
		"bird_id": "hawk",
		"name": "Hawk",
		"cost": 4,
		"power": 3
	}
	var setup2: HBoxContainer = %ExampleBirdFight2SetupRow
	setup2.add_child(_caption("Setup"))
	setup2.add_child(_make_bird_card(kestrel, false))
	setup2.add_child(_caption("+"))
	setup2.add_child(_make_bird_card(shrike, false))
	setup2.add_child(_caption("attack"))
	setup2.add_child(_make_bird_card(hawk, false))
	setup2.add_child(_caption("(defender)"))
	var outcome2: HBoxContainer = %ExampleBirdFight2OutcomeRow
	outcome2.add_child(_caption("Outcome"))
	outcome2.add_child(_caption("Kestrel → crypt"))
	outcome2.add_child(_make_bird_card(kestrel, true))
	outcome2.add_child(_caption("Shrike stays"))
	outcome2.add_child(_make_bird_card(shrike, false))
	outcome2.add_child(_caption("Hawk → crypt"))
	outcome2.add_child(_make_bird_card(hawk, true))


func _build_nest_example() -> void:
	var wren := {
		"type": "bird",
		"bird_id": "wren",
		"name": "Wren",
		"cost": 2,
		"power": 1
	}
	var temple := _delpha_temple()
	var before: HBoxContainer = %ExampleBirdNestBeforeRow
	before.add_child(_caption("Before"))
	before.add_child(_make_bird_card(wren, false))
	before.add_child(_caption("+"))
	before.add_child(_make_temple_card(temple))
	var after: HBoxContainer = %ExampleBirdNestAfterRow
	after.add_child(_caption("After"))
	after.add_child(_make_temple_with_nest_stack(1, temple))


func _build_ring_example() -> void:
	var sybiline := {
		"type": "ring",
		"ring_id": "sybiline_emanation",
		"name": "Sybiline, Ring of Emanation",
		"cost": 2
	}
	var serraf := {
		"type": "ring",
		"ring_id": "serraf_nobles",
		"name": "Serraf, Ring of Nobles",
		"cost": 2
	}
	var card_row: HBoxContainer = %ExampleRingCardRow
	card_row.add_child(_caption("Ring card"))
	card_row.add_child(_make_hand_card_widget(sybiline))
	card_row.add_child(_spacer(14.0))
	card_row.add_child(_caption("Seek / Insight now cost 1 less"))

	var attach_row: HBoxContainer = %ExampleRingAttachRow
	attach_row.add_child(_caption("Before"))
	attach_row.add_child(_make_noble_card({
		"type": "noble",
		"name": "Trss, Noble of Power",
		"noble_id": "trss_power"
	}))
	attach_row.add_child(_caption("+"))
	attach_row.add_child(_make_hand_card_widget(serraf))
	attach_row.add_child(_spacer(20.0))
	attach_row.add_child(_caption("After"))
	attach_row.add_child(_make_noble_with_ring_stack(1, {
		"type": "noble",
		"name": "Trss, Noble of Power",
		"noble_id": "trss_power"
	}))
	attach_row.add_child(_caption("Nobles now cost 1 less"))


func _make_noble_with_ring_stack(ring_count: int, noble: Dictionary) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	var ring_tab := Button.new()
	ring_tab.text = str(ring_count)
	ring_tab.disabled = true
	ring_tab.custom_minimum_size = Vector2(HAND_CARD_W, 20)
	ring_tab.add_theme_font_override("font", CARD_TEXT_FONT)
	ring_tab.add_theme_font_size_override("font_size", maxi(12, HAND_CARD_FONT_SIZE - 4))
	var rsb := StyleBoxFlat.new()
	rsb.set_corner_radius_all(3)
	rsb.set_border_width_all(2)
	rsb.bg_color = Color(0.12, 0.13, 0.16)
	rsb.border_color = Color(0.86, 0.88, 0.92)
	ring_tab.add_theme_stylebox_override("normal", rsb)
	ring_tab.add_theme_stylebox_override("disabled", rsb)
	ring_tab.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
	ring_tab.add_theme_color_override("font_disabled_color", Color(0.86, 0.88, 0.92))
	vbox.add_child(_make_noble_card(noble))
	vbox.add_child(ring_tab)
	return vbox


func _make_temple_with_nest_stack(nest_count: int, temple: Dictionary) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	var nest_tab := Button.new()
	nest_tab.text = str(nest_count)
	nest_tab.disabled = true
	nest_tab.custom_minimum_size = Vector2(HAND_CARD_W, 20)
	nest_tab.add_theme_font_override("font", CARD_TEXT_FONT)
	nest_tab.add_theme_font_size_override("font_size", maxi(12, HAND_CARD_FONT_SIZE - 4))
	var nsb := StyleBoxFlat.new()
	nsb.set_corner_radius_all(3)
	nsb.set_border_width_all(2)
	nsb.bg_color = Color(0.1, 0.14, 0.18)
	nsb.border_color = Color(1.0, 1.0, 1.0)
	nest_tab.add_theme_stylebox_override("normal", nsb)
	nest_tab.add_theme_stylebox_override("disabled", nsb)
	nest_tab.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	nest_tab.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(_make_temple_card(temple))
	vbox.add_child(nest_tab)
	return vbox


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


func _make_bird_card(bird: Dictionary, dimmed: bool = false) -> Control:
	var w := HAND_CARD_W
	var h := HAND_CARD_H
	var shell := Control.new()
	shell.custom_minimum_size = Vector2(w, h)
	shell.mouse_filter = Control.MOUSE_FILTER_PASS
	var btn := Button.new()
	btn.disabled = true
	btn.custom_minimum_size = Vector2(w, h)
	btn.text = str(bird.get("name", "Bird"))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(2)
	sb.bg_color = Color(1.0, 1.0, 1.0)
	sb.border_color = Color(0.05, 0.05, 0.05)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_font_override("font", CARD_TEXT_FONT)
	btn.add_theme_font_size_override("font_size", HAND_CARD_FONT_SIZE)
	btn.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	btn.add_theme_color_override("font_disabled_color", Color(0.05, 0.05, 0.05))
	btn.position = Vector2.ZERO
	btn.size = Vector2(w, h)
	var bird_view := bird.duplicate(true)
	bird_view["type"] = "bird"
	shell.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(bird_view)
	)
	shell.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	btn.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(bird_view)
	)
	btn.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	shell.add_child(btn)
	var pip_spec := _card_corner_pip_spec(bird_view)
	if int(pip_spec.get("count", 0)) > 0:
		var pip_icon := _make_corner_pip_icon(int(pip_spec.get("count", 0)), bool(pip_spec.get("filled", false)), Color(0.05, 0.05, 0.05, 0.98))
		pip_icon.position = Vector2(w - pip_icon.custom_minimum_size.x - 4, h - pip_icon.custom_minimum_size.y - 4)
		shell.add_child(pip_icon)
	var bird_power := int(bird.get("power", 0))
	if bird_power > 0:
		var power_icon := _make_corner_pip_icon(bird_power, true, Color(0.82, 0.1, 0.1, 0.98))
		power_icon.position = Vector2(w - power_icon.custom_minimum_size.x - 4, 26)
		shell.add_child(power_icon)
	if dimmed:
		shell.modulate = Color(0.52, 0.52, 0.56)
	return shell


func _make_noble_card(noble: Dictionary) -> Control:
	var w := HAND_CARD_W
	var h := HAND_CARD_H
	var shell := Control.new()
	shell.custom_minimum_size = Vector2(w, h)
	shell.mouse_filter = Control.MOUSE_FILTER_PASS
	var btn := Button.new()
	btn.disabled = true
	btn.custom_minimum_size = Vector2(w, h)
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
	btn.position = Vector2.ZERO
	btn.size = Vector2(w, h)
	var noble_view := noble.duplicate(true)
	noble_view["type"] = "noble"
	shell.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(noble_view)
	)
	shell.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	btn.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(noble_view)
	)
	btn.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	shell.add_child(btn)
	var pip_spec := _card_corner_pip_spec(noble_view)
	if int(pip_spec.get("count", 0)) > 0:
		var pip_icon := _make_corner_pip_icon(int(pip_spec.get("count", 0)), bool(pip_spec.get("filled", false)), Color(1, 1, 1, 0.98))
		pip_icon.position = Vector2(w - pip_icon.custom_minimum_size.x - 4, h - pip_icon.custom_minimum_size.y - 4)
		shell.add_child(pip_icon)
	return shell


func _make_hand_card_widget(card: Dictionary) -> Control:
	var w := HAND_CARD_W
	var h := HAND_CARD_H
	var shell := Control.new()
	shell.custom_minimum_size = Vector2(w, h)
	shell.mouse_filter = Control.MOUSE_FILTER_PASS
	var tap := Button.new()
	tap.text = str(int(card.get("value", 0))) if _card_type(card) == "ritual" else _card_label(card)
	tap.position = Vector2.ZERO
	tap.size = Vector2(w, h)
	tap.disabled = true
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(2)
	sb.bg_color = Color(0.04, 0.04, 0.06)
	var t := _card_type(card)
	if t == "temple":
		sb.border_color = Color(0.2, 0.84, 0.84)
	elif t == "ring":
		sb.bg_color = Color(0.12, 0.13, 0.16)
		sb.border_color = Color(0.86, 0.88, 0.92)
	else:
		sb.border_color = Color(0.92, 0.92, 0.95)
	tap.add_theme_stylebox_override("normal", sb)
	tap.add_theme_stylebox_override("disabled", sb)
	var font_color: Color = Color(0.86, 0.88, 0.92) if t == "ring" else Color(0.98, 0.98, 0.98)
	tap.add_theme_color_override("font_color", font_color)
	tap.add_theme_color_override("font_disabled_color", font_color)
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
	var ct := _card_type(card)
	if int(pip_spec.get("count", 0)) > 0:
		var cost_color := Color(0.05, 0.05, 0.05, 0.98) if ct == "bird" else Color(1, 1, 1, 0.98)
		var pip_icon := _make_corner_pip_icon(int(pip_spec.get("count", 0)), bool(pip_spec.get("filled", false)), cost_color)
		pip_icon.position = Vector2(w - pip_icon.custom_minimum_size.x - 4, h - pip_icon.custom_minimum_size.y - 4)
		shell.add_child(pip_icon)
	if ct == "bird":
		var bird_power := int(card.get("power", 0))
		if bird_power > 0:
			var power_icon := _make_corner_pip_icon(bird_power, true, Color(0.82, 0.1, 0.1, 0.98))
			power_icon.position = Vector2(w - power_icon.custom_minimum_size.x - 4, 26)
			shell.add_child(power_icon)
	return shell


func _card_corner_pip_spec(card: Dictionary) -> Dictionary:
	var t := _card_type(card)
	if t == "ritual":
		return {"count": max(0, int(card.get("value", 0))), "filled": true}
	if t == "bird":
		return {"count": max(0, int(card.get("cost", 0))), "filled": false}
	if t == "incantation":
		return {"count": max(0, int(card.get("value", 0))), "filled": false}
	if t == "noble":
		return {"count": _noble_cost_for_id(str(card.get("noble_id", ""))), "filled": false}
	if t == "temple":
		var cost := int(card.get("cost", 0))
		if cost <= 0:
			cost = _temple_cost_for_id(str(card.get("temple_id", "")))
		return {"count": max(0, cost), "filled": false}
	if t == "ring":
		return {"count": 2, "filled": false}
	return {"count": 0, "filled": false}


func _make_corner_pip_icon(count: int, filled: bool, color: Color = Color(1, 1, 1, 0.98)) -> TextureRect:
	var n := clampi(count, 0, 24)
	var dot_r: int = 4
	var icon_size: int = 28
	if n > 1:
		var remaining: int = n
		var ring: int = 1
		var step: float = 6.0
		var max_ring_radius: int = 0
		while remaining > 0:
			var cap: int = ring * 6
			var take: int = mini(remaining, cap)
			var radius: int = int(round(ring * step))
			max_ring_radius = maxi(max_ring_radius, radius)
			remaining -= take
			ring += 1
		icon_size = maxi(28, 2 * (max_ring_radius + dot_r) + 2)
	var center := Vector2i(icon_size >> 1, icon_size >> 1)
	var image := Image.create(icon_size, icon_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if n == 1:
		CornerPipDraw.draw_dot_on_image(image, center, dot_r, filled, color)
	else:
		var remaining2: int = n
		var ring2: int = 1
		var step2: float = 6.0
		while remaining2 > 0:
			var cap2: int = ring2 * 6
			var take2: int = mini(remaining2, cap2)
			var radius2: int = int(round(ring2 * step2))
			for i in take2:
				var ang := TAU * (float(i) / float(take2)) - PI / 2.0
				var px := center.x + int(round(cos(ang) * radius2))
				var py := center.y + int(round(sin(ang) * radius2))
				CornerPipDraw.draw_dot_on_image(image, Vector2i(px, py), dot_r, filled, color)
			remaining2 -= take2
			ring2 += 1
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
	if t == "bird":
		return str(card.get("name", "Bird"))
	if t == "noble":
		return _short_noble_name(str(card.get("name", "Noble")))
	if t == "temple":
		return _short_temple_name(str(card.get("name", "Temple")))
	if t == "ring":
		return _short_noble_name(str(card.get("name", "Ring")))
	var verb := str(card.get("verb", ""))
	if verb.to_lower() == "void":
		return "Void"
	return "%s %d" % [verb, int(card.get("value", 0))]


func _short_noble_name(full_name: String) -> String:
	var idx := full_name.find(",")
	if idx <= 0:
		return full_name
	return full_name.substr(0, idx).strip_edges()


func _short_temple_name(full_name: String) -> String:
	var idx := full_name.find(",")
	if idx < 0:
		return full_name
	return full_name.substr(0, idx).strip_edges()


func _make_temple_card(temple: Dictionary) -> Control:
	return _make_hand_card_widget(temple)


func _noble_cost_for_id(nid: String) -> int:
	return GameSnapshotUtils.noble_cost_for_id(nid)


func _temple_cost_for_id(tid: String) -> int:
	if tid == "ytria_cycles":
		return 9
	if tid == "eyrie_feathers":
		return 6
	return 7
