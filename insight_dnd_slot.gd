extends Panel
class_name InsightDnDSlot

const CARD_SCALE := 1.618
const HAND_CARD_H := 102.0 * CARD_SCALE

var slot_index: int = 0
var insight_zone: String = "top"
var can_drag: bool = true
var game: Control

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not can_drag:
		return null
	var px := ColorRect.new()
	px.custom_minimum_size = Vector2(50.0 * CARD_SCALE, HAND_CARD_H)
	px.color = Color(0.25, 0.4, 0.65, 0.92)
	set_drag_preview(px)
	return {"insight_slot": slot_index, "insight_zone": insight_zone}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return game != null and typeof(data) == TYPE_DICTIONARY and data.has("insight_slot") and data.has("insight_zone")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if game != null and typeof(data) == TYPE_DICTIONARY:
		game._insight_handle_drop(str(data.get("insight_zone", "")), int(data["insight_slot"]), insight_zone, slot_index)
