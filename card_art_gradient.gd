extends RefCounted
class_name CardArtGradient

const BORDER_NEUTRAL := Color(0.8, 0.83, 0.9)
const BORDER_NOBLE := Color(0.84, 0.7, 1.0)
const BORDER_BIRD := Color(0.05, 0.05, 0.05)
const BORDER_TEMPLE_A := Color(0.22, 0.68, 0.64)
const BORDER_TEMPLE_B := Color(0.55, 0.96, 0.90)
const GOLD_A := Color(0.92, 0.72, 0.18)
const GOLD_B := Color(1.0, 0.92, 0.42)
const TEAL_NOBLE_A := Color(0.2, 0.72, 0.66)
const TEAL_NOBLE_B := Color(0.48, 0.94, 0.88)
const PURPLE_NOBLE_A := Color(0.72, 0.55, 0.92)
const PURPLE_NOBLE_B := Color(0.94, 0.84, 1.0)
const RING_TEAL_A := Color(0.06, 0.42, 0.38)
const RING_TEAL_B := Color(0.10, 0.58, 0.52)
const RING_GOLD_A := Color(0.52, 0.36, 0.04)
const RING_GOLD_B := Color(0.72, 0.52, 0.10)
const RING_PURPLE_A := Color(0.32, 0.12, 0.48)
const RING_PURPLE_B := Color(0.46, 0.22, 0.62)

const INC_SEEK_A := Color(0.10, 0.62, 0.58)
const INC_SEEK_B := Color(0.96, 0.99, 0.99)
const INC_INSIGHT_A := Color(0.08, 0.54, 0.56)
const INC_INSIGHT_B := Color(0.18, 0.42, 0.92)
const INC_BURN_A := Color(0.92, 0.64, 0.12)
const INC_BURN_B := Color(0.98, 0.46, 0.10)
const INC_REVIVE_A := Color(0.88, 0.70, 0.18)
const INC_REVIVE_B := Color(0.98, 0.97, 0.93)
const INC_RENEW_A := Color(0.98, 0.97, 0.93)
const INC_RENEW_B := Color(0.88, 0.70, 0.18)
const INC_WOE_A := Color(0.48, 0.20, 0.78)
const INC_WOE_B := Color(0.50, 0.07, 0.54)
const INC_WRATH_A := Color(0.24, 0.07, 0.36)
const INC_WRATH_B := Color(0.03, 0.78, 0.04)
const INC_TEARS_A := Color(0.96, 0.86, 0.22)
const INC_TEARS_B := Color(0.99, 0.99, 0.96)

const NOBLE_BLACK_A := Color(0.05, 0.05, 0.07)


static func gradient_endpoints_for_card(card: Dictionary) -> PackedColorArray:
	var kind := CardTraits.effective_kind(card)
	match kind:
		"incantation":
			return _incantation_endpoints(str(card.get("verb", "")).to_lower().strip_edges())
		"noble":
			return _noble_endpoints(str(card.get("noble_id", "")))
		"temple":
			return _temple_endpoints()
		"bird":
			return _bird_endpoints()
		"ring":
			return _ring_endpoints(str(card.get("ring_id", "")).strip_edges())
		_:
			var a := BORDER_NEUTRAL.darkened(0.12)
			var b := BORDER_NEUTRAL.lightened(0.15)
			return PackedColorArray([a, b])


static func to_bbcode_centered_colored_lines(plain: String, c0: Color, c1: Color) -> String:
	var lines := plain.split("\n")
	var n := lines.size()
	if n == 0:
		return ""
	var parts: PackedStringArray = []
	parts.append("[center]")
	for i in n:
		var t := 0.0 if n <= 1 else float(i) / float(n - 1)
		var col := c0.lerp(c1, t)
		var line := _escape_bbcode_line(lines[i])
		parts.append("[color=%s]%s[/color]" % [_color_hex_rgb(col), line])
		if i < n - 1:
			parts.append("\n")
	parts.append("[/center]")
	return "".join(parts)


static func _u32(h: int) -> int:
	return h & 0x7FFFFFFF


static func _incantation_endpoints(verb: String) -> PackedColorArray:
	var v := verb.to_lower().strip_edges()
	match v:
		"seek":
			return PackedColorArray([INC_SEEK_A, INC_SEEK_B])
		"insight":
			return PackedColorArray([INC_INSIGHT_A, INC_INSIGHT_B])
		"burn":
			return PackedColorArray([INC_BURN_A, INC_BURN_B])
		"revive":
			return PackedColorArray([INC_REVIVE_A, INC_REVIVE_B])
		"renew":
			return PackedColorArray([INC_RENEW_A, INC_RENEW_B])
		"woe":
			return PackedColorArray([INC_WOE_A, INC_WOE_B])
		"wrath":
			return PackedColorArray([INC_WRATH_A, INC_WRATH_B])
		"tears":
			return PackedColorArray([INC_TEARS_A, INC_TEARS_B])
		_:
			pass
	var key := "incantation:" + v if not v.is_empty() else "incantation:_"
	var h := _u32(hash(key))
	var hue := float(h % 360) / 360.0
	var c0 := Color.from_hsv(hue, 0.48, 0.90)
	var c1 := Color.from_hsv(fmod(hue + 0.085, 1.0), 0.55, 0.97)
	return PackedColorArray([c0, c1])


static func _noble_endpoints(noble_id: String) -> PackedColorArray:
	var nid := noble_id.to_lower()
	if nid.contains("_annihilation"):
		return PackedColorArray([PURPLE_NOBLE_A, PURPLE_NOBLE_B])
	if nid.contains("_occultation"):
		return PackedColorArray([GOLD_A, GOLD_B])
	if nid.contains("_emanation"):
		return PackedColorArray([TEAL_NOBLE_A, TEAL_NOBLE_B])
	if nid.ends_with("_power"):
		return PackedColorArray([GOLD_A, _noble_hash_accent("pw:" + noble_id)])
	if nid.ends_with("_incantation"):
		return PackedColorArray([NOBLE_BLACK_A, _noble_hash_accent("in:" + noble_id)])
	var h := _u32(hash("noble:" + noble_id))
	var hue := float(h % 360) / 360.0
	var c0 := Color.from_hsv(hue, 0.42, 0.88)
	var c1 := Color.from_hsv(fmod(hue + 0.09, 1.0), 0.50, 0.94)
	return PackedColorArray([c0, c1])


static func _noble_hash_accent(salt: String) -> Color:
	var h := _u32(hash("noble_accent:" + salt))
	var hue := float(h % 360) / 360.0
	return Color.from_hsv(hue, 0.50, 0.91)


static func _temple_endpoints() -> PackedColorArray:
	return PackedColorArray([BORDER_TEMPLE_A, BORDER_TEMPLE_B])


static func _bird_endpoints() -> PackedColorArray:
	return PackedColorArray([Color(0.07, 0.07, 0.07), Color(0.02, 0.02, 0.02)])


static func _ring_endpoints(ring_id: String) -> PackedColorArray:
	if ring_id.is_empty():
		return _single_hue_pair(BORDER_NEUTRAL)
	var rid := ring_id.to_lower()
	if rid.contains("_annihilation"):
		return PackedColorArray([RING_PURPLE_A, RING_PURPLE_B])
	if rid.contains("_occultation"):
		return PackedColorArray([RING_GOLD_A, RING_GOLD_B])
	if rid.contains("_emanation"):
		return PackedColorArray([RING_TEAL_A, RING_TEAL_B])
	var def: Variant = ArcanaMatchState.RING_DEFS.get(ring_id, null)
	if def == null or not def is Dictionary:
		return _single_hue_pair(BORDER_NEUTRAL)
	var red: Variant = def.get("reductions", {})
	if typeof(red) != TYPE_DICTIONARY:
		return _single_hue_pair(BORDER_NEUTRAL)
	var keys: Array = (red as Dictionary).keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a).to_lower() < str(b).to_lower()
	)
	var uniq: Array = []
	for k in keys:
		var c := _reduction_key_to_border_color(str(k))
		var dup := false
		for u in uniq:
			if (u as Color).is_equal_approx(c):
				dup = true
				break
		if not dup:
			uniq.append(c)
	if uniq.is_empty():
		return _single_hue_pair(BORDER_NEUTRAL)
	if uniq.size() == 1:
		return _single_hue_pair(uniq[0] as Color)
	return PackedColorArray([uniq[0] as Color, uniq[uniq.size() - 1] as Color])


static func _single_hue_pair(base: Color) -> PackedColorArray:
	return PackedColorArray([base.darkened(0.22), base.lightened(0.28)])


static func _reduction_key_to_border_color(key: String) -> Color:
	var k := key.strip_edges().to_lower()
	if k == "noble":
		return BORDER_NOBLE
	if k == "bird":
		return BORDER_BIRD
	return BORDER_NEUTRAL


static func _color_hex_rgb(c: Color) -> String:
	return "#%02x%02x%02x" % [clampi(int(c.r * 255.0), 0, 255), clampi(int(c.g * 255.0), 0, 255), clampi(int(c.b * 255.0), 0, 255)]


static func _escape_bbcode_line(s: String) -> String:
	return s.replace("[", "[lb]")

