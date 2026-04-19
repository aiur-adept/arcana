extends RefCounted
class_name ArcanaPilotWeightsLoader

const WEIGHTS_PATH := "res://data/pilot_weights.json"
static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func _get_root() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(WEIGHTS_PATH):
		return {}
	var f := FileAccess.open(WEIGHTS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return {}
	var d: Variant = j.data
	if d is Dictionary:
		_cache = d
		return d
	return {}


static func apply_saved_weights(pilot: ArcanaCpuBase, slug: String) -> void:
	var root := _get_root()
	var by_slug: Variant = root.get("weights_by_slug", {})
	if not by_slug is Dictionary:
		return
	var w: Variant = by_slug.get(slug, {})
	if not w is Dictionary or w.is_empty():
		return
	for k in w:
		var key := str(k)
		if key.is_empty():
			continue
		var vv: Variant = w[k]
		if typeof(vv) != TYPE_FLOAT and typeof(vv) != TYPE_INT:
			continue
		pilot.set(key, float(vv))
