extends Control

const CornerPipDraw = preload("res://corner_pip_draw.gd")

const COLOR_TEAL := Color("#3ec4b0")
const COLOR_PURPLE := Color("#b565d8")
const COLOR_GOLD := Color("#e8c547")
const COLOR_WHITE := Color("#f5f5f5")
const COLOR_SILVER := Color("#8c919a")
const GROUP_COLORS: Array[Color] = [COLOR_WHITE, COLOR_SILVER, COLOR_TEAL, COLOR_PURPLE, COLOR_GOLD]

const PIP_COUNT := 15
const GROUP_SIZE := 3

var _panel: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = StyleBoxFlat.new()
	_panel.bg_color = Color(0, 0, 0, 1)
	_panel.set_corner_radius_all(5)
	_panel.set_border_width_all(2)
	_panel.border_color = Color(0.22, 0.22, 0.3)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_panel, r)
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return
	var center := Vector2(w * 0.5, h * 0.5)
	var min_dim := minf(w, h)
	var step := min_dim * 0.17
	var dot_r := clampi(int(round(min_dim * 0.06)), 3, 14)

	var remaining := PIP_COUNT
	var ring := 1
	var pip_index := 0
	while remaining > 0:
		var cap: int = ring * 6
		var take: int = mini(remaining, cap)
		var radius: float = float(ring) * step
		for i in take:
			var ang := TAU * (float(i) / float(take)) - PI / 2.0
			var pc := center + Vector2(cos(ang) * radius, sin(ang) * radius)
			@warning_ignore("integer_division")
			var group := (pip_index / GROUP_SIZE) % GROUP_COLORS.size()
			var col := GROUP_COLORS[group]
			CornerPipDraw.draw_dot_on_canvas(self, pc, dot_r, false, Color(col.r, col.g, col.b, 0.98))
			pip_index += 1
		remaining -= take
		ring += 1
