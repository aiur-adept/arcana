extends RefCounted
class_name CardPreviewPresenter

const CornerPipDraw = preload("res://corner_pip_draw.gd")
const CARD_TEXT_FONT: Font = preload("res://fonts/Macondo-Regular.ttf")
const PREVIEW_SCALE := 1.618

const PREVIEW_RITUAL_BORDER := Color(0.95, 0.78, 0.24)
const PREVIEW_RITUAL_TEXT := Color(1.0, 0.86, 0.35)
const PREVIEW_NOBLE_BORDER := Color(0.84, 0.7, 1.0)
const PREVIEW_NOBLE_TEXT := Color(0.96, 0.93, 1.0)
const PREVIEW_TEMPLE_BORDER := Color(0.35, 0.82, 0.78)
const PREVIEW_TEMPLE_TEXT := Color(0.88, 0.98, 0.95)
const PREVIEW_BIRD_BORDER := Color(0.05, 0.05, 0.05)
const PREVIEW_BIRD_TEXT := Color(0.05, 0.05, 0.05)
const PREVIEW_RING_BORDER := Color(0.12, 0.12, 0.14)
const PREVIEW_RING_TEXT := Color(0.05, 0.05, 0.05)
const PREVIEW_NEUTRAL_BORDER := Color(0.8, 0.83, 0.9)
const PREVIEW_NEUTRAL_TEXT := Color(0.92, 0.92, 0.96)

const RITUAL_BIG_COLOR := Color(0.95, 0.78, 0.24)
const POWER_PIP_COLOR := Color(0.82, 0.1, 0.1, 0.98)
const COST_PIP_DARK := Color(0.05, 0.05, 0.05, 0.98)
const COST_PIP_LIGHT := Color(1, 1, 1, 0.98)


static func preview_pixel_size(config: Dictionary = {}) -> Vector2:
	var card_scale := float(config.get("card_scale", PREVIEW_SCALE))
	var card_aspect := float(config.get("card_aspect", 0.7))
	var card_h := 210.0 * card_scale * 1.41421356
	var card_w := card_h * card_aspect
	return Vector2(card_w, card_h)


static func build_preview_panel(host: Control, config: Dictionary = {}) -> Dictionary:
	var mode := str(config.get("mode", "corner"))
	var slot_parent: Control = config.get("parent_slot", null) as Control
	if slot_parent != null:
		mode = "slot"
	var root := Panel.new()
	root.name = str(config.get("name", "CardHoverPreview"))
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = int(config.get("z_index", 100))
	var ui := float(config.get("ui_scale", PREVIEW_SCALE))
	var pad_lr := int(round(10.0 * ui))
	var pad_tb := int(round(8.0 * ui))
	var sep := maxi(1, int(round(4.0 * ui)))
	var corner := int(round(8.0 * ui))
	var border_w := maxi(1, int(round(2.0 * ui)))
	var edge := roundf(18.0 * ui)
	var sz := preview_pixel_size(config)
	var card_w := sz.x
	var card_h := sz.y
	if mode == "corner":
		root.anchor_left = 1.0
		root.anchor_top = 1.0
		root.anchor_right = 1.0
		root.anchor_bottom = 1.0
		root.offset_left = -edge - card_w
		root.offset_top = -edge - card_h
		root.offset_right = -edge
		root.offset_bottom = -edge
	elif mode == "slot":
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.offset_left = 0
		root.offset_top = 0
		root.offset_right = 0
		root.offset_bottom = 0
	root.custom_minimum_size = Vector2(card_w, card_h)

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(corner)
	sb.set_border_width_all(border_w)
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.95)
	sb.border_color = Color(0.8, 0.83, 0.9)
	root.add_theme_stylebox_override("panel", sb)
	var attach_parent: Control = slot_parent if slot_parent != null else host
	attach_parent.add_child(root)

	var title_sz := int(round(12.0 * ui))
	var type_sz := int(round(10.4 * ui))
	var body_sz := int(round(12.8 * 0.9 * ui))
	var big_sz := int(round(48.0 * ui))
	var body_right_reserve := int(round(44.0 * ui))

	var top_row := HBoxContainer.new()
	top_row.set_anchors_preset(Control.PRESET_TOP_WIDE, false)
	top_row.offset_left = pad_lr
	top_row.offset_top = pad_tb
	top_row.offset_right = -pad_lr
	top_row.add_theme_constant_override("separation", sep)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_row)

	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font", CARD_TEXT_FONT)
	title.add_theme_font_size_override("font_size", title_sz)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	var power_pips := CenterContainer.new()
	power_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_pips.size_flags_horizontal = Control.SIZE_SHRINK_END
	power_pips.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top_row.add_child(power_pips)

	var ritual_big := Label.new()
	ritual_big.set_anchors_preset(Control.PRESET_TOP_WIDE, false)
	ritual_big.anchor_bottom = 0.4
	ritual_big.offset_top = 0
	ritual_big.offset_bottom = 0
	ritual_big.offset_left = pad_lr
	ritual_big.offset_right = -pad_lr
	ritual_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ritual_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ritual_big.add_theme_font_override("font", CARD_TEXT_FONT)
	ritual_big.add_theme_font_size_override("font_size", big_sz)
	ritual_big.add_theme_color_override("font_color", RITUAL_BIG_COLOR)
	ritual_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ritual_big.visible = false
	root.add_child(ritual_big)

	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	info.anchor_top = 0.5
	info.offset_top = 0
	info.offset_left = pad_lr
	info.offset_right = -pad_lr
	info.offset_bottom = -pad_tb
	info.add_theme_constant_override("separation", sep)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(info)

	var type_line := Label.new()
	type_line.add_theme_font_override("font", CARD_TEXT_FONT)
	type_line.add_theme_font_size_override("font_size", type_sz)
	type_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(type_line)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, body_sz)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(gap)

	var body_wrap := MarginContainer.new()
	body_wrap.add_theme_constant_override("margin_right", body_right_reserve)
	body_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(body_wrap)

	var body := RichTextLabel.new()
	body.add_theme_font_override("normal_font", CARD_TEXT_FONT)
	body.add_theme_font_size_override("normal_font_size", body_sz)
	body.fit_content = true
	body.scroll_active = false
	body.bbcode_enabled = false
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_wrap.add_child(body)

	var footer_h := int(round(60.0 * ui))
	var footer := HBoxContainer.new()
	footer.anchor_left = 0.0
	footer.anchor_right = 1.0
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = pad_lr
	footer.offset_right = -pad_lr
	footer.offset_top = -footer_h
	footer.offset_bottom = -pad_tb
	footer.add_theme_constant_override("separation", sep)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(footer)

	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(footer_spacer)

	var cost_col := VBoxContainer.new()
	cost_col.add_theme_constant_override("separation", maxi(1, int(round(2.0 * ui))))
	cost_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_col.size_flags_horizontal = Control.SIZE_SHRINK_END
	cost_col.alignment = BoxContainer.ALIGNMENT_END
	footer.add_child(cost_col)

	var cost_pips := CenterContainer.new()
	cost_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cost_col.add_child(cost_pips)

	var cost_number := Label.new()
	cost_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_number.add_theme_font_override("font", CARD_TEXT_FONT)
	cost_number.add_theme_font_size_override("font_size", int(round(9.0 * ui)))
	cost_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_number.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cost_number.visible = false
	cost_col.add_child(cost_number)

	return {
		"mode": mode,
		"embed": slot_parent != null,
		"root": root,
		"panel_sb": sb,
		"title": title,
		"type_line": type_line,
		"body": body,
		"ritual_big": ritual_big,
		"power_pips": power_pips,
		"cost_pips": cost_pips,
		"cost_number": cost_number,
		"ui": ui
	}


static func show_preview(preview: Dictionary, card: Dictionary, mouse_position: Vector2 = Vector2.ZERO) -> void:
	var root: Panel = preview.get("root")
	if root == null:
		return
	var title: Label = preview.get("title")
	var type_line: Label = preview.get("type_line")
	var body: RichTextLabel = preview.get("body")
	var ritual_big: Label = preview.get("ritual_big")
	var power_pips: Container = preview.get("power_pips")
	var cost_pips: Container = preview.get("cost_pips")
	var cost_number: Label = preview.get("cost_number")
	var ui := float(preview.get("ui", PREVIEW_SCALE))

	title.text = card_title(card)
	type_line.text = card_type_line(card)
	body.text = card_rules_text(card)

	var panel_sb: StyleBoxFlat = preview.get("panel_sb") as StyleBoxFlat
	var kind := _card_type(card)
	var border_c: Color
	var text_c: Color
	var bg_c := Color(0.03, 0.03, 0.05, 0.95)
	var is_bird := kind == "bird"
	var is_ring := kind == "ring"
	match kind:
		"ritual":
			border_c = PREVIEW_RITUAL_BORDER
			text_c = PREVIEW_RITUAL_TEXT
		"noble":
			border_c = PREVIEW_NOBLE_BORDER
			text_c = PREVIEW_NOBLE_TEXT
		"temple":
			border_c = PREVIEW_TEMPLE_BORDER
			text_c = PREVIEW_TEMPLE_TEXT
		"bird":
			border_c = PREVIEW_BIRD_BORDER
			text_c = PREVIEW_BIRD_TEXT
			bg_c = Color(0.97, 0.97, 0.97, 0.98)
		"ring":
			border_c = PREVIEW_RING_BORDER
			text_c = PREVIEW_RING_TEXT
			bg_c = Color(0.86, 0.88, 0.91, 0.98)
		_:
			border_c = PREVIEW_NEUTRAL_BORDER
			text_c = PREVIEW_NEUTRAL_TEXT
	if panel_sb != null:
		panel_sb.border_color = border_c
		panel_sb.bg_color = bg_c
	title.add_theme_color_override("font_color", text_c)
	type_line.add_theme_color_override("font_color", text_c)
	body.add_theme_color_override("default_color", text_c)

	if ritual_big != null:
		if kind == "ritual":
			ritual_big.text = str(int(card.get("value", 0)))
			ritual_big.visible = true
		else:
			ritual_big.visible = false

	_clear_children(power_pips)
	if is_bird:
		var power := int(card.get("power", 0))
		if power > 0:
			power_pips.add_child(_make_pip_icon(power, true, POWER_PIP_COLOR, ui))

	_clear_children(cost_pips)
	var cost_count := 0
	match kind:
		"bird":
			cost_count = int(card.get("cost", 0))
		"noble":
			cost_count = _noble_cost_for_id(str(card.get("noble_id", "")))
		"temple":
			cost_count = int(card.get("cost", 0))
			if cost_count <= 0:
				cost_count = _temple_cost_for_id(str(card.get("temple_id", "")))
		"incantation":
			cost_count = int(card.get("value", 0))
		"ring":
			cost_count = 2
	if cost_count > 0:
		var pip_color: Color = COST_PIP_DARK if (is_bird or is_ring) else COST_PIP_LIGHT
		cost_pips.add_child(_make_pip_icon(cost_count, false, pip_color, ui))
	if cost_number != null:
		if cost_count > 0:
			cost_number.text = str(cost_count)
			cost_number.add_theme_color_override("font_color", text_c)
			cost_number.visible = true
		else:
			cost_number.visible = false

	if not preview.get("embed", false):
		if str(preview.get("mode", "corner")) != "corner":
			root.global_position = mouse_position + Vector2(18, 18)
	root.visible = true
	root.move_to_front()


static func hide_preview(preview: Dictionary) -> void:
	var root: Panel = preview.get("root")
	if root != null:
		root.visible = false


static func card_title(card: Dictionary) -> String:
	var t := _card_type(card)
	if t == "ritual":
		return "Ritual"
	if t == "noble":
		return str(card.get("name", "Noble"))
	if t == "temple":
		var nm: Variant = card.get("name", null)
		if nm == null:
			return "Temple"
		var ts := str(nm).strip_edges()
		return ts if not ts.is_empty() else "Temple"
	if t == "bird":
		return str(card.get("name", "Bird"))
	if t == "ring":
		return str(card.get("name", "Ring"))
	var verb := str(card.get("verb", ""))
	if verb.to_lower() == "void":
		return "Void"
	return "%s %d" % [verb.capitalize(), int(card.get("value", 0))]


static func card_type_line(card: Dictionary) -> String:
	var t := _card_type(card)
	if t == "ritual":
		return "Ritual"
	if t == "noble":
		return "Noble"
	if t == "bird":
		return "Bird"
	if t == "temple":
		return "Temple"
	if t == "ring":
		return "Ring"
	return "Incantation"


static func card_rules_text(card: Dictionary) -> String:
	var t := _card_type(card)
	if t == "ritual":
		var v := int(card.get("value", 0))
		return "Play one ritual per turn. This allows you to play cards of cost %d if active. Activation requires a complete active chain (1..N)." % [v]
	if t == "noble":
		return _noble_preview_text(str(card.get("noble_id", "")))
	if t == "bird":
		return "Each bird adds +1 to match power. Nest: place a bird under your temple (at most temple-cost birds per temple); nested birds add an additional +1 match power and cannot be involved in combat."
	if t == "temple":
		return _temple_preview_text(str(card.get("temple_id", "")))
	if t == "ring":
		return _ring_preview_text(str(card.get("ring_id", "")))
	var n := int(card.get("value", 0))
	var verb := str(card.get("verb", "")).to_lower()
	match verb:
		"dethrone":
			return "Dethrone 4: destroy 1 opponent noble."
		"seek":
			var noun := "card" if n == 1 else "cards"
			return "Seek %d: draw %d %s." % [n, n, noun]
		"insight":
			return "Insight %d: rearrange the top %d card(s) of a chosen deck and/or put any to the bottom." % [n, n]
		"burn":
			return "Burn %d: discard the top %d card(s) of a chosen player's deck." % [n, n * 2]
		"woe":
			return "Woe %d: a chosen player discards %d chosen card(s) from hand." % [n, maxi(n - 2, 0)]
		"revive":
			return "Revive %d: you may cast %d incantation from your crypt (chosen; no ritual cost)." % [n, n]
		"wrath":
			return "Wrath 4: destroy 1 opponent ritual."
		"deluge":
			return "Deluge %d: destroy all wild (non-nested) birds with power %d or less, then all nested birds become wild again." % [n, n - 1]
		"tears":
			return "Tears %d: return a Bird from your crypt to your field." % n
		"void":
			return "Void: during the opponent's turn, discard one card from your hand to nullify a non-ritual card they just played (it goes to their crypt with no effect). Void can nullify another Void. 10-second response window."
		_:
			return "Incantation %d." % n


static func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func _make_pip_icon(count: int, filled: bool, color: Color, ui: float) -> TextureRect:
	var n := clampi(count, 0, 24)
	var dot_r: int = maxi(1, int(round(4.0 * ui)))
	var step: float = 6.0 * ui
	var icon_size: int = maxi(1, int(round(28.0 * ui)))
	if n > 1:
		var remaining: int = n
		var ring: int = 1
		var max_ring_radius: int = 0
		while remaining > 0:
			var cap: int = ring * 6
			var take: int = mini(remaining, cap)
			var radius: int = int(round(ring * step))
			max_ring_radius = maxi(max_ring_radius, radius)
			remaining -= take
			ring += 1
		icon_size = maxi(icon_size, 2 * (max_ring_radius + dot_r) + 2)
	var center := Vector2i(icon_size >> 1, icon_size >> 1)
	var image := Image.create(icon_size, icon_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if n == 1:
		CornerPipDraw.draw_dot_on_image(image, center, dot_r, filled, color)
	elif n > 1:
		var remaining2: int = n
		var ring2: int = 1
		while remaining2 > 0:
			var cap2: int = ring2 * 6
			var take2: int = mini(remaining2, cap2)
			var radius2: int = int(round(ring2 * step))
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


static func _card_type(card: Dictionary) -> String:
	return CardTraits.effective_kind(card)


static func _ring_preview_text(ring_id: String) -> String:
	match ring_id:
		"sybiline_emanation":
			return "Attach to a Noble or un-nested Bird. While on the field, your Seek and Insight cost 1 less to play (minimum 0)."
		"cymbil_occultation":
			return "Attach to a Noble or un-nested Bird. While on the field, your Burn and Revive cost 1 less to play (minimum 0)."
		"celadon_annihilation":
			return "Attach to a Noble or un-nested Bird. While on the field, your Woe and Wrath cost 1 less to play (minimum 0)."
		"serraf_nobles":
			return "Attach to a Noble or un-nested Bird. While on the field, your Nobles cost 1 less to play (minimum 0)."
		"sinofia_feathers":
			return "Attach to a Noble or un-nested Bird. While on the field, your Birds and your Tears cost 1 less to play (minimum 0)."
		_:
			return "Ring — attach to a Noble or un-nested Bird."


static func _temple_preview_text(temple_id: String) -> String:
	match temple_id:
		"phaedra_illusion":
			return "Activate (once per turn): look at the top card of a chosen deck and keep it on top or place it on the bottom, then draw a card."
		"delpha_oracles":
			return "Activate (once per turn): send a Ritual of power X to the abyss, then discard the top 2X cards of your own deck, then play a Ritual from your crypt."
		"gotha_illness":
			return "Skip your draw step. Activate (once per turn): discard a non-temple card, then draw cards equal to its power/cost."
		"ytria_cycles":
			return "Activate (once per turn): discard your hand, then draw that many cards."
		"eyrie_feathers":
			return "When this Temple enters, search your deck for a Bird card and put it onto your field, then shuffle your deck."
		_:
			return "Temple — sacrifice 7 to play from hand."


static func _temple_cost_for_id(temple_id: String) -> int:
	match temple_id:
		"ytria_cycles":
			return 9
		"eyrie_feathers":
			return 6
		"phaedra_illusion", "delpha_oracles", "gotha_illness":
			return 7
		_:
			return 7


static func _noble_preview_text(noble_id: String) -> String:
	match noble_id:
		"krss_power":
			return "Passive: grants access to 1-cost incantations."
		"trss_power":
			return "Passive: grants access to 2-cost incantations."
		"yrss_power":
			return "Passive: grants access to 3-cost incantations."
		"sndrr_incantation":
			return "Activate (once per turn): discard a card, then draw a card."
		"wndrr_incantation":
			return "Activate (once per turn): discard a card, then the opponent discards a chosen card from hand."
		"bndrr_incantation":
			return "Activate (once per turn): discard the top 4 cards of a chosen player's deck."
		"rndrr_incantation":
			return "Activate (once per turn): cast one incantation from your crypt; the cast card goes to the abyss."
		"indrr_incantation":
			return "Activate (once per turn): look at the top card of a chosen deck; keep it on top or place it on the bottom."
		"xytzr_emanation":
			return "Whenever you Seek, draw an additional card. Whenever you Insight, look at one additional card."
		"yytzr_occultation":
			return "Whenever you Burn, 3 additional cards are discarded from the top of that deck. Whenever you Revive, you may sacrifice rituals totaling at least 2 to cast one additional incantation from your crypt."
		"zytzr_annihilation":
			return "Whenever you Wrath, destroy one additional opponent ritual. Whenever you Woe, the victim discards one additional card."
		"aeoiu_rituals":
			return "Activate (once per turn): play a Ritual from your crypt."
		"rmrsk_emanation":
			return "Whenever you Insight, you may then draw a card."
		"smrsk_occultation":
			return "Whenever you Burn or Revive, you may sacrifice a Ritual of power X, then discard the top 2X cards of your own deck."
		"tmrsk_annihilation":
			return "Whenever you Wrath, the opponent discards a chosen card from hand."
		_:
			return "Noble effect."


static func _noble_cost_for_id(nid: String) -> int:
	return GameSnapshotUtils.noble_cost_for_id(nid)
