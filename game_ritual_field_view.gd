extends RefCounted
class_name GameRitualFieldView

const CARD_SCALE := 1.618
const HAND_CARD_W := 72.0 * CARD_SCALE
const HAND_CARD_H := 102.0 * CARD_SCALE
const HAND_CARD_FONT_SIZE := 26
const FIELD_CARD_SCALE := 0.8
const FIELD_CARD_W := HAND_CARD_W * FIELD_CARD_SCALE
const FIELD_CARD_H := HAND_CARD_H * FIELD_CARD_SCALE
const FIELD_CARD_FONT_SIZE := int(round(HAND_CARD_FONT_SIZE * FIELD_CARD_SCALE))
const CARD_TEXT_FONT: Font = preload("res://fonts/Macondo-Regular.ttf")

const INC_PICK_SAC := 1
const INC_PICK_WRATH := 2
const INC_PICK_DETHRONE := 3
const INC_PICK_SMRSK := 9
const INC_PICK_BIRD_ATTACK := 11
const INC_PICK_BIRD_TARGET := 12
const INC_PICK_NEST_BIRD := 13
const INC_PICK_NEST_TEMPLE := 14
const INC_PICK_RING_TARGET := 15
const INC_PICK_DELPHA := 16

var game: Control

func _init(p_game: Control) -> void:
	game = p_game


func stylebox_field_hover_glow(base: StyleBoxFlat) -> StyleBoxFlat:
	var h := base.duplicate() as StyleBoxFlat
	var c := base.border_color
	h.shadow_size = 12
	h.shadow_offset = Vector2.ZERO
	h.shadow_color = Color(c.r, c.g, c.b, 0.48)
	return h


func rebuild_ritual_field(row: HBoxContainer, field: Variant, ours: bool) -> void:
	for c in row.get_children():
		c.queue_free()
	var no_rituals: bool = typeof(field) != TYPE_ARRAY or field.is_empty()
	if no_rituals:
		var empty := Label.new()
		empty.text = "—"
		empty.modulate = Color(0.45, 0.45, 0.5)
		row.add_child(empty)
		return
	var act: Array = ArcanaMatchState.active_mask_for_field(field)
	var by_value: Dictionary = {}
	for i in field.size():
		var v: int = int(field[i].get("value", 0))
		if not by_value.has(v):
			by_value[v] = []
		var arr: Array = by_value[v]
		arr.append({
			"value": v,
			"mid": int(field[i].get("mid", 0)),
			"active": i < act.size() and bool(act[i])
		})
		by_value[v] = arr
	var values: Array = by_value.keys()
	values.sort()
	for v in values:
		var pick_mode := 0
		if ours and game._sacrifice_selecting and game._inc_pick_phase == INC_PICK_SAC:
			pick_mode = 1
		elif ours and game._sacrifice_selecting and (game._inc_pick_phase == INC_PICK_SMRSK or game._inc_pick_phase == INC_PICK_DELPHA):
			pick_mode = 1
		elif not ours and game._sacrifice_selecting and game._inc_pick_phase == INC_PICK_WRATH:
			pick_mode = 2
		row.add_child(make_ritual_stack(by_value[v], ours, pick_mode))


func rebuild_noble_field(row: HBoxContainer, nobles: Variant, ours: bool) -> void:
	for c in row.get_children():
		c.queue_free()
	if typeof(nobles) != TYPE_ARRAY:
		return
	for noble in nobles as Array:
		if typeof(noble) != TYPE_DICTIONARY:
			continue
		row.add_child(make_noble_card(noble as Dictionary, ours))


func _flush_bird_buffer(row: HBoxContainer, buffer: Array, ours: bool) -> void:
	if buffer.is_empty():
		return
	var order: Array = []
	var groups: Dictionary = {}
	for bd in buffer:
		var key := str((bd as Dictionary).get("name", "Bird"))
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(bd)
	for key in order:
		var grp: Array = groups[key] as Array
		row.add_child(make_bird_stack(grp, ours))
	buffer.clear()


func rebuild_bird_field(row: HBoxContainer, birds: Variant, ours: bool) -> void:
	for c in row.get_children():
		c.queue_free()
	if typeof(birds) != TYPE_ARRAY:
		return
	var buffer: Array = []
	for bird in birds as Array:
		if typeof(bird) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = bird as Dictionary
		if int(bd.get("nest_temple_mid", -1)) >= 0:
			continue
		var has_rings: bool = not (bd.get("rings", []) as Array).is_empty()
		if has_rings:
			_flush_bird_buffer(row, buffer, ours)
			row.add_child(make_bird_stack([bd], ours))
		else:
			buffer.append(bd)
	_flush_bird_buffer(row, buffer, ours)
	if row.get_child_count() == 0:
		var empty_b := Label.new()
		empty_b.text = "—"
		empty_b.modulate = Color(0.45, 0.45, 0.5)
		row.add_child(empty_b)


func make_bird_stack(birds: Array, ours: bool) -> Control:
	var shift := 12.0 * CARD_SCALE
	var w := FIELD_CARD_W
	var h := FIELD_CARD_H
	var count := birds.size()
	var stack := Control.new()
	var extra: float = shift if count > 1 else 0.0
	var front_bd_for_size: Dictionary = birds[count - 1] as Dictionary
	var has_rings: bool = not (front_bd_for_size.get("rings", []) as Array).is_empty()
	var stack_h: float = h + (3.0 + 22.0) if has_rings else h
	stack.custom_minimum_size = Vector2(w + extra, stack_h)
	if count > 1:
		var back := Panel.new()
		back.custom_minimum_size = Vector2(w, h)
		back.set_size(Vector2(w, h))
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bsb := StyleBoxFlat.new()
		bsb.set_corner_radius_all(4)
		bsb.set_border_width_all(2)
		bsb.bg_color = Color(1.0, 1.0, 1.0)
		bsb.border_color = Color(0.05, 0.05, 0.05)
		back.add_theme_stylebox_override("panel", bsb)
		back.position = Vector2(0, 0)
		back.z_index = 0
		stack.add_child(back)
	var front_bd: Dictionary = birds[count - 1] as Dictionary
	var front_card := make_bird_card(front_bd, ours)
	front_card.position = Vector2(extra, 0)
	front_card.z_index = 1
	stack.add_child(front_card)
	if count > 1:
		var badge := Label.new()
		badge.text = "x%d" % count
		badge.position = Vector2(extra + w - 52, 2)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.custom_minimum_size = Vector2(44, 22)
		badge.add_theme_font_override("font", CARD_TEXT_FONT)
		badge.add_theme_font_size_override("font_size", maxi(12, FIELD_CARD_FONT_SIZE - 6))
		badge.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.z_index = 2
		stack.add_child(badge)
	return stack


func make_ritual_stack(cards: Array, ours: bool, pick_mode: int) -> Control:
	var shift := 12.0 * CARD_SCALE
	var w := FIELD_CARD_W
	var h := FIELD_CARD_H
	var count := cards.size()
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(w + shift * maxi(0, count - 1), h)
	for i in count:
		var d: Dictionary = cards[i]
		var mid: int = int(d.get("mid", -1))
		var picked: bool = (pick_mode == 1 and (game._sacrifice_selected_mids.has(mid) or game._single_ritual_pick_mid == mid)) or (pick_mode == 2 and game._wrath_selected_mids.has(mid))
		var card := make_ritual_card(
			int(d.get("value", 0)),
			ours,
			bool(d.get("active", true)),
			mid,
			pick_mode,
			picked
		)
		card.position = Vector2(shift * i, 0)
		card.z_index = i
		stack.add_child(card)
	return stack


func make_ritual_card(value: int, _ours: bool, active: bool, ritual_mid: int = -1, pick_mode: int = 0, picked: bool = false, dim_when_inactive: bool = true) -> Control:
	var w := FIELD_CARD_W
	var h := FIELD_CARD_H
	var ritual_gold := Color(0.95, 0.78, 0.24)
	var ritual_gold_strong := Color(1.0, 0.86, 0.35)
	var sacrifice_outline := Color(0.28, 0.92, 0.52)
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(3 if picked else 2)
	sb.bg_color = Color(0.04, 0.04, 0.06)
	if pick_mode == 1:
		sb.border_color = sacrifice_outline if picked else ritual_gold
	elif pick_mode == 2:
		sb.border_color = ritual_gold_strong if picked else ritual_gold
	else:
		sb.border_color = ritual_gold
	panel.add_theme_stylebox_override("panel", sb)
	var sb_hover := stylebox_field_hover_glow(sb)
	if pick_mode == 1 and ritual_mid >= 0:
		var mid_cap := ritual_mid
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb := ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
					game._on_sacrifice_field_clicked(mid_cap)
		)
	if pick_mode == 2 and ritual_mid >= 0:
		var mid_w := ritual_mid
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb := ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
					game._on_wrath_field_clicked(mid_w)
		)
	var rv := value
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", sb_hover)
		game._show_card_hover_preview({"type": "ritual", "value": rv})
	)
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", sb)
		game._hide_card_hover_preview()
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
	lbl.add_theme_color_override("font_color", ritual_gold_strong if picked else ritual_gold)
	lbl.add_theme_font_size_override("font_size", FIELD_CARD_FONT_SIZE)
	cc.add_child(lbl)
	if not active and dim_when_inactive:
		panel.modulate = Color(0.58, 0.58, 0.62)
	return panel


func _make_rings_tab(host_kind: String, host_mid: int, ring_count: int, ours: bool) -> Button:
	var tab := Button.new()
	tab.text = str(ring_count)
	tab.custom_minimum_size = Vector2(FIELD_CARD_W, 22)
	tab.add_theme_font_override("font", CARD_TEXT_FONT)
	tab.add_theme_font_size_override("font_size", maxi(12, FIELD_CARD_FONT_SIZE - 4))
	var rsb := StyleBoxFlat.new()
	rsb.set_corner_radius_all(3)
	rsb.set_border_width_all(2)
	rsb.bg_color = Color(0.14, 0.16, 0.19)
	rsb.border_color = Color(0.82, 0.85, 0.92)
	tab.add_theme_stylebox_override("normal", rsb)
	tab.add_theme_stylebox_override("hover", stylebox_field_hover_glow(rsb))
	tab.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	tab.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	tab.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	var k_cap := host_kind
	var mid_cap := host_mid
	var host_is_opp := not ours
	tab.pressed.connect(func() -> void:
		game.show_host_rings_modal(k_cap, mid_cap, host_is_opp)
	)
	return tab


func make_noble_card(noble: Dictionary, ours: bool) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(FIELD_CARD_W, FIELD_CARD_H)
	var noble_name: String = game._short_noble_name(str(noble.get("name", "Noble")))
	var used_turn := int(noble.get("used_turn", -1))
	var exhausted := used_turn == int(game._last_snap.get("turn_number", -999))
	btn.text = noble_name
	btn.add_theme_font_override("font", CARD_TEXT_FONT)
	btn.add_theme_font_size_override("font_size", FIELD_CARD_FONT_SIZE)
	var noble_bg := Color(0.13, 0.1, 0.18)
	var noble_border := Color(0.84, 0.7, 1.0)
	var noble_fg := Color(0.96, 0.93, 1.0)
	var noble_bg_used := Color(0.07, 0.055, 0.11)
	var noble_border_used := Color(0.48, 0.38, 0.62)
	var noble_fg_used := Color(0.65, 0.58, 0.78)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(2)
	sb.bg_color = noble_bg_used if exhausted else noble_bg
	sb.border_color = noble_border_used if exhausted else noble_border
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_color_override("font_color", noble_fg_used if exhausted else noble_fg)
	var sb_dis := sb.duplicate()
	btn.add_theme_stylebox_override("disabled", sb_dis)
	btn.add_theme_color_override("font_disabled_color", noble_fg_used if exhausted else noble_fg)
	var mid := int(noble.get("mid", -1))
	var noble_hid := str(noble.get("noble_id", ""))
	var can_pick_dethrone: bool = not ours and game._sacrifice_selecting and game._inc_pick_phase == INC_PICK_DETHRONE
	var can_pick_ring: bool = ours and game._sacrifice_selecting and game._inc_pick_phase == INC_PICK_RING_TARGET
	var can_activate: bool = ours and not exhausted and not game._sacrifice_selecting and not game._insight_open and int(game._last_snap.get("current", -1)) == int(game._last_snap.get("you", -2))
	if noble_hid == "aeoiu_rituals":
		var cr: Array = game._last_snap.get("your_ritual_crypt_cards", []) as Array
		can_activate = can_activate and cr.size() > 0
	btn.disabled = false
	if can_pick_ring:
		btn.pressed.connect(func() -> void:
			game._on_ring_target_clicked("noble", mid)
		)
	elif can_pick_dethrone:
		btn.pressed.connect(func() -> void:
			game._on_dethrone_field_clicked(mid)
		)
	elif can_activate:
		btn.pressed.connect(func() -> void:
			game._on_noble_activate_pressed(mid)
		)
	else:
		btn.disabled = true
	var normal_sb: StyleBoxFlat = sb
	if can_pick_dethrone and game._dethrone_selected_mid == mid:
		var sb_sel := sb.duplicate()
		sb_sel.border_color = Color(1.0, 0.45, 0.45)
		sb_sel.set_border_width_all(3)
		normal_sb = sb_sel
		btn.add_theme_stylebox_override("normal", sb_sel)
		btn.add_theme_stylebox_override("disabled", sb_sel)
	if can_pick_ring:
		var sb_ring := sb.duplicate()
		sb_ring.border_color = Color(0.92, 0.94, 1.0)
		sb_ring.set_border_width_all(3)
		normal_sb = sb_ring
		btn.add_theme_stylebox_override("normal", sb_ring)
		btn.add_theme_stylebox_override("disabled", sb_ring)
	var sb_hover := stylebox_field_hover_glow(normal_sb)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_stylebox_override("hover_pressed", sb_hover)
	btn.add_theme_stylebox_override("focus", normal_sb)
	var noble_view := noble.duplicate(true)
	noble_view["type"] = "noble"
	btn.mouse_entered.connect(func() -> void:
		game._show_card_hover_preview(noble_view)
	)
	btn.mouse_exited.connect(func() -> void:
		game._hide_card_hover_preview()
	)
	var rings: Array = (noble.get("rings", []) as Array)
	if rings.is_empty():
		return btn
	var noble_wrap := Control.new()
	noble_wrap.custom_minimum_size = Vector2(FIELD_CARD_W, FIELD_CARD_H + 3 + 22)
	noble_wrap.size = noble_wrap.custom_minimum_size
	noble_wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.position = Vector2.ZERO
	btn.size = Vector2(FIELD_CARD_W, FIELD_CARD_H)
	btn.custom_minimum_size = Vector2(FIELD_CARD_W, FIELD_CARD_H)
	noble_wrap.add_child(btn)
	var noble_tab := _make_rings_tab("noble", mid, rings.size(), ours)
	noble_tab.position = Vector2(0, FIELD_CARD_H + 3)
	noble_tab.size = Vector2(FIELD_CARD_W, 22)
	noble_wrap.add_child(noble_tab)
	return noble_wrap


func make_bird_card(bird: Dictionary, ours: bool) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(FIELD_CARD_W, FIELD_CARD_H)
	btn.text = str(bird.get("name", "Bird"))
	btn.add_theme_font_override("font", CARD_TEXT_FONT)
	btn.add_theme_font_size_override("font_size", FIELD_CARD_FONT_SIZE)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(2)
	sb.bg_color = Color(1.0, 1.0, 1.0)
	sb.border_color = Color(0.05, 0.05, 0.05)
	var mid := int(bird.get("mid", -1))
	var nest_tm := int(bird.get("nest_temple_mid", -1))
	var bird_rings: Array = (bird.get("rings", []) as Array)
	var is_attack_pick: bool = ours and game._sacrifice_selecting and game._inc_pick_phase == INC_PICK_BIRD_ATTACK and nest_tm < 0
	var is_target_pick: bool = (not ours) and game._sacrifice_selecting and game._inc_pick_phase == INC_PICK_BIRD_TARGET and nest_tm < 0
	var is_nest_picker: bool = ours and game._sacrifice_selecting and game._inc_pick_phase == INC_PICK_NEST_TEMPLE and int(game._nest_pick_bird_mid) == mid
	var is_ring_pick: bool = ours and game._sacrifice_selecting and game._inc_pick_phase == INC_PICK_RING_TARGET and nest_tm < 0
	var can_start_nest: bool = false
	if ours and not game._sacrifice_selecting and nest_tm < 0 and bird_rings.is_empty():
		var snap: Dictionary = game._last_snap
		var mine := int(snap.get("current", -1)) == int(snap.get("you", -2))
		can_start_nest = mine and game._temple_field_input_ok() and game._has_nest_action_available(snap)
	if is_attack_pick and game._bird_attack_selected.has(mid):
		sb.set_border_width_all(3)
		sb.border_color = Color(0.05, 0.05, 0.05)
	if is_target_pick and game._bird_defender_mid == mid:
		sb.set_border_width_all(3)
		sb.border_color = Color(1.0, 0.58, 0.58)
	if is_nest_picker:
		sb.set_border_width_all(4)
		sb.border_color = Color(0.45, 0.92, 0.82)
		btn.z_index = 60
	if is_ring_pick:
		sb.set_border_width_all(3)
		sb.border_color = Color(0.92, 0.94, 1.0)
	btn.add_theme_stylebox_override("normal", sb)
	var hover := stylebox_field_hover_glow(sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("hover_pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	var sb_dis := sb.duplicate()
	btn.add_theme_stylebox_override("disabled", sb_dis)
	var bird_fg := Color(0.05, 0.05, 0.05)
	btn.add_theme_color_override("font_color", bird_fg)
	btn.add_theme_color_override("font_disabled_color", bird_fg)
	btn.add_theme_color_override("font_hover_color", bird_fg)
	btn.add_theme_color_override("font_pressed_color", bird_fg)
	btn.add_theme_color_override("font_hover_pressed_color", bird_fg)
	btn.add_theme_color_override("font_focus_color", bird_fg)
	if is_ring_pick:
		btn.pressed.connect(func() -> void:
			game._on_ring_target_clicked("bird", mid)
		)
	elif is_attack_pick:
		btn.pressed.connect(func() -> void:
			game._on_bird_attacker_clicked(mid)
		)
	elif is_target_pick:
		btn.pressed.connect(func() -> void:
			game._on_bird_target_clicked(mid)
		)
	elif can_start_nest:
		btn.pressed.connect(func() -> void:
			game._start_nest_from_bird(mid)
		)
	else:
		btn.disabled = true
	var v := bird.duplicate(true)
	v["type"] = "bird"
	btn.mouse_entered.connect(func() -> void:
		game._show_card_hover_preview(v)
	)
	btn.mouse_exited.connect(func() -> void:
		game._hide_card_hover_preview()
	)
	var power_count := int(bird.get("power", 0))
	if power_count > 0:
		var power_icon: TextureRect = game._make_corner_pip_icon(power_count, true, Color(0.82, 0.1, 0.1, 0.98))
		power_icon.position = Vector2(FIELD_CARD_W - power_icon.custom_minimum_size.x - 4, 4)
		btn.add_child(power_icon)
	if bird_rings.is_empty():
		return btn
	var bwrap := Control.new()
	bwrap.custom_minimum_size = Vector2(FIELD_CARD_W, FIELD_CARD_H + 3 + 22)
	bwrap.size = bwrap.custom_minimum_size
	bwrap.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.position = Vector2.ZERO
	btn.size = Vector2(FIELD_CARD_W, FIELD_CARD_H)
	btn.custom_minimum_size = Vector2(FIELD_CARD_W, FIELD_CARD_H)
	bwrap.add_child(btn)
	var bird_tab := _make_rings_tab("bird", mid, bird_rings.size(), ours)
	bird_tab.position = Vector2(0, FIELD_CARD_H + 3)
	bird_tab.size = Vector2(FIELD_CARD_W, 22)
	bwrap.add_child(bird_tab)
	return bwrap


func rebuild_temple_field(row: HBoxContainer, temples: Variant, ours: bool) -> void:
	for c in row.get_children():
		c.queue_free()
	var arr: Array = temples if typeof(temples) == TYPE_ARRAY else []
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "—"
		empty.modulate = Color(0.45, 0.45, 0.5)
		row.add_child(empty)
		return
	for t in arr:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		row.add_child(make_temple_card(t as Dictionary, ours))


func make_temple_card(temple: Dictionary, ours: bool) -> Control:
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var mid := int(temple.get("mid", -1))
	var nest_mids: Array = temple.get("nested_bird_mids", []) as Array
	var nest_n := nest_mids.size()
	var has_nest_tab: bool = nest_n > 0
	var total_h: float = FIELD_CARD_H + (3.0 + 22.0) if has_nest_tab else FIELD_CARD_H
	row.custom_minimum_size = Vector2(FIELD_CARD_W, total_h)
	row.size = row.custom_minimum_size
	var nest_tab: Button = null
	if has_nest_tab:
		nest_tab = Button.new()
		nest_tab.text = str(nest_n)
		nest_tab.custom_minimum_size = Vector2(FIELD_CARD_W, 22)
		nest_tab.size = nest_tab.custom_minimum_size
		nest_tab.position = Vector2(0, FIELD_CARD_H + 3)
		nest_tab.add_theme_font_override("font", CARD_TEXT_FONT)
		nest_tab.add_theme_font_size_override("font_size", maxi(12, FIELD_CARD_FONT_SIZE - 4))
		var nsb := StyleBoxFlat.new()
		nsb.set_corner_radius_all(3)
		nsb.set_border_width_all(2)
		nsb.bg_color = Color(0.1, 0.14, 0.18)
		nsb.border_color = Color(1.0, 1.0, 1.0)
		nest_tab.add_theme_stylebox_override("normal", nsb)
		nest_tab.add_theme_stylebox_override("hover", stylebox_field_hover_glow(nsb))
		nest_tab.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		nest_tab.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		nest_tab.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
		var mid_cap := mid
		var ours_cap := ours
		nest_tab.pressed.connect(func() -> void:
			game.show_temple_nest_modal(mid_cap, not ours_cap)
		)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(FIELD_CARD_W, FIELD_CARD_H)
	btn.size = Vector2(FIELD_CARD_W, FIELD_CARD_H)
	btn.position = Vector2.ZERO
	var shown: String = game._short_noble_name(str(temple.get("name", "Temple")))
	var used_turn := int(temple.get("used_turn", -1))
	var exhausted := used_turn == int(game._last_snap.get("turn_number", -999))
	btn.text = shown
	btn.add_theme_font_override("font", CARD_TEXT_FONT)
	btn.add_theme_font_size_override("font_size", FIELD_CARD_FONT_SIZE)
	var temple_bg := Color(0.06, 0.11, 0.11)
	var temple_border := Color(0.32, 0.78, 0.74)
	var temple_fg := Color(0.85, 0.97, 0.94)
	var temple_bg_used := Color(0.045, 0.07, 0.07)
	var temple_border_used := Color(0.22, 0.48, 0.46)
	var temple_fg_used := Color(0.55, 0.72, 0.7)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(2)
	sb.bg_color = temple_bg_used if exhausted else temple_bg
	sb.border_color = temple_border_used if exhausted else temple_border
	var snap: Dictionary = game._last_snap
	var is_nest_temple_pick: bool = ours and game._sacrifice_selecting and game._inc_pick_phase == INC_PICK_NEST_TEMPLE
	var has_nest_room: bool = game._temple_has_nest_room(snap, temple)
	if is_nest_temple_pick and has_nest_room:
		sb.set_border_width_all(3)
		sb.border_color = Color(0.45, 0.92, 0.82)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_color_override("font_color", temple_fg_used if exhausted else temple_fg)
	var sb_dis := sb.duplicate()
	btn.add_theme_stylebox_override("disabled", sb_dis)
	btn.add_theme_color_override("font_disabled_color", temple_fg_used if exhausted else temple_fg)
	var tid := str(temple.get("temple_id", ""))
	var can_activate: bool = ours and not exhausted and game._temple_field_input_ok()
	if tid == "delpha_oracles":
		var cr: Array = game._last_snap.get("your_ritual_crypt_cards", []) as Array
		can_activate = can_activate and cr.size() > 0
	if tid == "ytria_cycles":
		var hand_n := (game._last_snap.get("your_hand", []) as Array).size()
		can_activate = can_activate and hand_n > 0
	if tid == "eyrie_feathers":
		can_activate = false
	if is_nest_temple_pick:
		if has_nest_room:
			btn.set_meta("nest_valid_temple", true)
			row.z_index = 60
			btn.pressed.connect(func() -> void:
				game._on_nest_temple_chosen(mid)
			)
		else:
			btn.disabled = true
	elif can_activate:
		btn.pressed.connect(func() -> void:
			game._on_temple_activate_pressed(mid)
		)
	else:
		btn.disabled = true
	var sb_hover := stylebox_field_hover_glow(sb)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_stylebox_override("hover_pressed", sb_hover)
	btn.add_theme_stylebox_override("focus", sb)
	var tview := temple.duplicate(true)
	tview["type"] = "temple"
	btn.mouse_entered.connect(func() -> void:
		game._show_card_hover_preview(tview)
	)
	btn.mouse_exited.connect(func() -> void:
		game._hide_card_hover_preview()
	)
	row.add_child(btn)
	if nest_tab != null:
		row.add_child(nest_tab)
	return row
