extends RefCounted
class_name CardPreviewPresenter


static func build_preview_panel(host: Control, config: Dictionary = {}) -> Dictionary:
	var mode := str(config.get("mode", "corner"))
	var root := Panel.new()
	root.name = str(config.get("name", "CardHoverPreview"))
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var z_index := int(config.get("z_index", 100))
	root.z_index = z_index
	if mode == "corner":
		root.anchor_left = 1.0
		root.anchor_top = 1.0
		root.anchor_right = 1.0
		root.anchor_bottom = 1.0
		var card_scale := float(config.get("card_scale", 1.0))
		var card_aspect := float(config.get("card_aspect", 0.7))
		var card_h := 210.0 * card_scale * 1.41421356
		var card_w := card_h * card_aspect
		root.offset_left = -18.0 - card_w
		root.offset_top = -18.0 - card_h
		root.offset_right = -18.0
		root.offset_bottom = -18.0
		root.custom_minimum_size = Vector2(card_w, card_h)
	else:
		root.custom_minimum_size = Vector2(float(config.get("width", 240.0)), 0.0)

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.95)
	sb.border_color = Color(0.8, 0.83, 0.9)
	root.add_theme_stylebox_override("panel", sb)
	host.add_child(root)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 15)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	var type_line := Label.new()
	type_line.add_theme_font_size_override("font_size", 13)
	type_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(type_line)

	var body := RichTextLabel.new()
	body.fit_content = true
	body.scroll_active = false
	body.bbcode_enabled = false
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	return {
		"mode": mode,
		"root": root,
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
	if str(preview.get("mode", "corner")) != "corner":
		root.global_position = mouse_position + Vector2(18, 18)
	root.visible = true


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
	return "Incantation"


static func card_rules_text(card: Dictionary) -> String:
	var t := _card_type(card)
	if t == "ritual":
		var v := int(card.get("value", 0))
		return "Play one ritual per turn. This allows you to play Incantations and Nobles of power %d if active. Activation requires a complete active chain (1..N)." % [v]
	if t == "noble":
		return _noble_preview_text(str(card.get("noble_id", "")))
	if t == "dethrone":
		return "Dethrone 4: destroy 1 opponent noble."
	var n := int(card.get("value", 0))
	var verb := str(card.get("verb", "")).to_lower()
	match verb:
		"seek":
			var noun := "card" if n == 1 else "cards"
			return "Seek %d: draw %d %s." % [n, n, noun]
		"insight":
			return "Insight %d: reorder the top %d card(s) of either deck." % [n, n]
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
	var t := str(card.get("type", card.get("kind", ""))).to_lower()
	if t == "dethrone":
		return "dethrone"
	if t == "incantation":
		if str(card.get("verb", "")).to_lower() == "dethrone":
			return "dethrone"
		return "incantation"
	if t == "ritual":
		return "ritual"
	if t == "noble":
		return "noble"
	return t


static func _wrath_destroy_count(value: int) -> int:
	if value == 4:
		return 2
	return 0


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
			return "Whenever you Seek or Insight, you may draw a card."
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
