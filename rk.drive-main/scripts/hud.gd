class_name GameHud
extends Control
## Racing HUD drawn in code at the top right: speed, gear (D1-D5 / R / N)
## and an RPM bar. Everything scales with the screen height.

const WHITE: Color = Color(1.0, 1.0, 1.0, 0.95)
const SOFT_WHITE: Color = Color(1.0, 1.0, 1.0, 0.75)
const DIM: Color = Color(1.0, 1.0, 1.0, 0.16)
const ORANGE: Color = Color(1.0, 0.62, 0.1)
const RED: Color = Color(1.0, 0.2, 0.15)
const OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.85)
const SEGMENTS: int = 24

@export var car: CarController


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Finds the car by scene path first, then by the "car" group.
func _find_car() -> CarController:
	var found: Node = get_node_or_null("../../Car")
	if found == null:
		found = get_tree().get_first_node_in_group("car")
	return found as CarController


func _process(_delta: float) -> void:
	if not is_instance_valid(car):
		car = _find_car()
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var u: float = size.y / 720.0
	var right: float = size.x - 36.0 * u

	if not is_instance_valid(car):
		_text_right(font, "CAR NOT FOUND", right, 60.0 * u, int(32.0 * u), WHITE)
		return

	# Speed.
	_text_right(font, str(roundi(car.get_speed_kmh())), right, 100.0 * u, int(96.0 * u), WHITE)
	_text_right(font, "KM/H", right, 132.0 * u, int(26.0 * u), SOFT_WHITE)

	# RPM bar.
	var bar_width: float = 340.0 * u
	var bar_height: float = 16.0 * u
	var bar_x: float = right - bar_width
	var bar_y: float = 150.0 * u
	var gap: float = 3.0 * u
	var segment_width: float = (bar_width - gap * float(SEGMENTS - 1)) / float(SEGMENTS)
	var rpm: float = car.get_rpm_ratio()
	for i: int in SEGMENTS:
		var position_ratio: float = float(i + 1) / float(SEGMENTS)
		var color: Color = DIM
		if position_ratio <= rpm + 0.001:
			if position_ratio < 0.7:
				color = WHITE
			elif position_ratio < 0.85:
				color = ORANGE
			else:
				color = RED
		var x: float = bar_x + float(i) * (segment_width + gap)
		draw_rect(Rect2(x, bar_y, segment_width, bar_height), color)

	# Gear, left of the RPM bar.
	var gear_text: String = car.get_gear_text()
	var gear_color: Color = WHITE
	if gear_text == "R":
		gear_color = ORANGE
	elif gear_text == "N":
		gear_color = SOFT_WHITE
	_text_right(font, gear_text, bar_x - 20.0 * u, bar_y + bar_height, int(46.0 * u), gear_color)

	# Handbrake warning.
	if car.handbrake_active:
		_text_left(font, "HANDBRAKE", bar_x, 132.0 * u, int(24.0 * u), RED)


func _text_right(font: Font, text: String, right_x: float, baseline_y: float, font_size: int, color: Color) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text_left(font, text, right_x - width, baseline_y, font_size, color)


func _text_left(font: Font, text: String, left_x: float, baseline_y: float, font_size: int, color: Color) -> void:
	var position_xy: Vector2 = Vector2(left_x, baseline_y)
	var outline_size: int = int(maxf(2.0, float(font_size) * 0.12))
	draw_string_outline(font, position_xy, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, OUTLINE)
	draw_string(font, position_xy, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
