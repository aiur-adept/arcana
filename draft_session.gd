extends Node

var active: bool = false
var pool_by_key: Dictionary = {}


func begin() -> void:
	clear()
	active = true


func clear() -> void:
	active = false
	pool_by_key.clear()


func merge_pack(entries: Array) -> void:
	active = true
	var DeckEditor := load("res://deck_editor.gd") as GDScript
	var de: Control = DeckEditor.new()
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var key: String = de.catalog_entry_key(e as Dictionary)
		pool_by_key[key] = int(pool_by_key.get(key, 0)) + 1
	de.queue_free()
