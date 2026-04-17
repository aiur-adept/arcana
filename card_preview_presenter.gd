extends RefCounted
class_name CardPreviewPresenter

const CardTraits = preload("res://card_traits.gd")
const CARD_TEXT_FONT: Font = preload("res://fonts/Macondo-Regular.ttf")
const PREVIEW_SCALE := 1.618

const PREVIEW_RITUAL_BORDER := Color(0.95, 0.78, 0.24)
const PREVIEW_RITUAL_TEXT := Color(1.0, 0.86, 0.35)
const PREVIEW_NOBLE_BORDER := Color(0.84, 0.7, 1.0)
const PREVIEW_NOBLE_TEXT := Color(0.96, 0.93, 1.0)
const PREVIEW_TEMPLE_BORDER := Color(0.35, 0.82, 0.78)
const PREVIEW_TEMPLE_TEXT := Color(0.88, 0.98, 0.95)
const PREVIEW_NEUTRAL_BORDER := Color(0.8, 0.83, 0.9)
const PREVIEW_NEUTRAL_TEXT := Color(0.92, 0.92, 0.96)


static func build_preview_panel(host: Control, config: Dictionary = {}) -> Dictionary:
	var mode := str(config.get("mode", "corner"))
	var root := Panel.new()
	root.name = str(config.get("name", "CardHoverPreview"))
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var z_index := int(config.get("z_index", 100))
	root.z_index = z_index
	var ui := float(config.get("ui_scale", PREVIEW_SCALE))
	var pad_lr := int(round(10.0 * ui))
	var pad_tb := int(round(8.0 * ui))
	var sep := maxi(1, int(round(4.0 * ui)))
	var corner := int(round(8.0 * ui))
	var border_w := maxi(1, int(round(2.0 * ui)))
	var edge := roundf(18.0 * ui)
	if mode == "corner":
		root.anchor_left = 1.0
		root.anchor_top = 1.0
		root.anchor_right = 1.0
		root.anchor_bottom = 1.0
		var card_scale := float(config.get("card_scale", PREVIEW_SCALE))
		var card_aspect := float(config.get("card_aspect", 0.7))
		var card_h := 210.0 * card_scale * 1.41421356
		var card_w := card_h * card_aspect
		root.offset_left = -edge - card_w
		root.offset_top = -edge - card_h
		root.offset_right = -edge
		root.offset_bottom = -edge
		root.custom_minimum_size = Vector2(card_w, card_h)
	else:
		root.custom_minimum_size = Vector2(float(config.get("width", 240.0 * ui)), 0.0)

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(corner)
	sb.set_border_width_all(border_w)
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.95)
	sb.border_color = Color(0.8, 0.83, 0.9)
	root.add_theme_stylebox_override("panel", sb)
	host.add_child(root)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", pad_lr)
	pad.add_theme_constant_override("margin_top", pad_tb)
	pad.add_theme_constant_override("margin_right", pad_lr)
	pad.add_theme_constant_override("margin_bottom", pad_tb)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", sep)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	var title_sz := int(round(15.0 * ui))
	var type_sz := int(round(13.0 * ui))
	var body_sz := int(round(16.0 * ui))

	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font", CARD_TEXT_FONT)
	title.add_theme_font_size_override("font_size", title_sz)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	var type_line := Label.new()
	type_line.add_theme_font_override("font", CARD_TEXT_FONT)
	type_line.add_theme_font_size_override("font_size", type_sz)
	type_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(type_line)

	var body := RichTextLabel.new()
	body.add_theme_font_override("normal_font", CARD_TEXT_FONT)
	body.add_theme_font_size_override("normal_font_size", body_sz)
	body.fit_content = true
	body.scroll_active = false
	body.bbcode_enabled = false
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	return {
		"mode": mode,
		"root": root,
		"panel_sb": sb,
		"title": title,
		"type_line": type_line,
		"body": body
	}


static func show_preview(preview: Dictionary, card: Dictionary, mouse_position: Vector2 = Vector2.ZERO) -> void:
	var root: Panel = preview.get("root")
	if root == null:
		return
	var title: Label = preview.get("title")
	var type_line: Label = preview.get("type_line")
	var body: RichTextLabel = preview.get("body")
	title.text = card_title(card)
	type_line.text = card_type_line(card)
	body.text = card_rules_text(card)
	var panel_sb: StyleBoxFlat = preview.get("panel_sb") as StyleBoxFlat
	var kind := _card_type(card)
	var border_c: Color
	var text_c: Color
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
		_:
			border_c = PREVIEW_NEUTRAL_BORDER
			text_c = PREVIEW_NEUTRAL_TEXT
	if panel_sb != null:
		panel_sb.border_color = border_c
	title.add_theme_color_override("font_color", text_c)
	type_line.add_theme_color_override("font_color", text_c)
	body.add_theme_color_override("default_color", text_c)
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
		return "%d-Ritual" % int(card.get("value", 0))
	if t == "noble":
		return str(card.get("name", "Noble"))
	if t == "temple":
		var nm: Variant = card.get("name", null)
		if nm == null:
			return "Temple"
		var ts := str(nm).strip_edges()
		return ts if not ts.is_empty() else "Temple"
	if t == "dethrone":
		return "Dethrone 4"
	return "%s %d" % [str(card.get("verb", "")).capitalize(), int(card.get("value", 0))]


static func card_type_line(card: Dictionary) -> String:
	var t := _card_type(card)
	if t == "ritual":
		return "Ritual"
	if t == "noble":
		var cost := _noble_cost_for_id(str(card.get("noble_id", "")))
		return "Noble%s" % (" (cost %d)" % cost if cost > 0 else "")
	if t == "temple":
		var raw_cost := int(card.get("cost", 0))
		if raw_cost <= 0:
			raw_cost = _temple_cost_for_id(str(card.get("temple_id", "")))
		return "Temple (cost %d)" % raw_cost
	return "Incantation"


static func card_rules_text(card: Dictionary) -> String:
	var t := _card_type(card)
	if t == "ritual":
		var v := int(card.get("value", 0))
		return "Play one ritual per turn. This allows you to play Incantations and Nobles of power %d if active. Activation requires a complete active chain (1..N)." % [v]
	if t == "noble":
		return _noble_preview_text(str(card.get("noble_id", "")))
	if t == "temple":
		return _temple_preview_text(str(card.get("temple_id", "")))
	if t == "dethrone":
		return "Dethrone 4: destroy 1 opponent noble."
	var n := int(card.get("value", 0))
	var verb := str(card.get("verb", "")).to_lower()
	match verb:
		"seek":
			var noun := "card" if n == 1 else "cards"
			return "Seek %d: draw %d %s." % [n, n, noun]
		"insight":
			return "Insight %d: rearrange the top %d card(s) of a chosen deck and/or put any to the bottom." % [n, n]
		"burn":
			return "Burn %d: discard the top %d card(s) of a chosen player's deck." % [n, n * 2]
		"woe":
			return "Woe %d: a chosen player discards %d chosen card(s) from hand." % [n, n]
		"revive":
			return "Revive %d: you may cast %d incantation(s) from your crypt (chosen; no ritual cost)." % [n, n]
		"wrath":
			return "Wrath %d: destroy %d opponent ritual(s)." % [n, _wrath_destroy_count(n)]
		_:
			return "Incantation %d." % n


static func _card_type(card: Dictionary) -> String:
	return CardTraits.effective_kind(card)


static func _wrath_destroy_count(value: int) -> int:
	if value == 4:
		return 2
	return 0


static func _temple_preview_text(temple_id: String) -> String:
	match temple_id:
		"phaedra_illusion":
			return "Once per turn: Insight 1, then draw a card."
		"delpha_oracles":
			return "Once per turn: Send a Ritual of power X to the abyss to Burn yourself X (mill 2X from your deck), then play an additional Ritual from your crypt."
		"gotha_illness":
			return "Skip your draw step. Once per turn: discard a card, then draw cards equal to its power/cost."
		"ytria_cycles":
			return "Once per turn: discard your hand, then draw that many cards."
		_:
			return "Temple — sacrifice 7 to play from hand."


static func _temple_cost_for_id(temple_id: String) -> int:
	match temple_id:
		"ytria_cycles":
			return 9
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
			return "Activate (once per turn): Seek 1."
		"wndrr_incantation":
			return "Activate (once per turn): Woe 1."
		"bndrr_incantation":
			return "Activate (once per turn): Burn 1."
		"rndrr_incantation":
			return "Activate (once per turn): Revive 1."
		"indrr_incantation":
			return "Activate (once per turn): Insight 2."
		"xytzr_emanation":
			return "Whenever you Seek, draw an additional card. Whenever you Insight, look at an additional card."
		"yytzr_occultation":
			return "Whenever you Burn, add 3 to the number discarded. Whenever you Revive, you may sacrifice 2+ ritual power for an extra crypt cast."
		"zytzr_annihilation":
			return "Whenever you Wrath, destroy an extra ritual. Whenever you Woe, the victim discards an additional card."
		"aeoiu_rituals":
			return "Activate (once per turn): play a Ritual from your crypt."
		"rmrsk_emanation":
			return "Whenever you Insight, you may then draw a card."
		"smrsk_occultation":
			return "Whenever you Burn or Revive, you may sacrifice a Ritual of power X to Burn yourself X."
		"tmrsk_annihilation":
			return "Whenever you Wrath, Woe 1."
		_:
			return "Noble effect."


static func _noble_cost_for_id(nid: String) -> int:
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
