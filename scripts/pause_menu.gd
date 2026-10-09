class_name PauseMenu
extends Control
## Pause menu built in code: Resume, Restart and a Sound on/off switch.
## Opens with the on-screen pause pad, the Android back button, P / Esc on a PC,
## or automatically when the app goes to the background.
## Requires `application/config/quit_on_go_back=false` in project.godot.

@export var click_sound_path: String = "res://assets/audio/ui_click.ogg"
@export var title_text: String = "PAUSED"

const PANEL_COLOR: Color = Color(0.08, 0.09, 0.12, 0.96)
const BUTTON_COLOR: Color = Color(0.19, 0.21, 0.27)
const BUTTON_HOVER_COLOR: Color = Color(0.26, 0.29, 0.37)
const BUTTON_PRESSED_COLOR: Color = Color(0.85, 0.35, 0.12)
## Ignore "focus lost" for this long after the game starts.
const STARTUP_GRACE_MS: int = 1500

var _click: AudioStreamPlayer
var _sound_button: Button
var _sound_on: bool = true
var _started_ms: int = 0


func _ready() -> void:
	# The menu keeps working while the rest of the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_started_ms = Time.get_ticks_msec()

	_sound_on = not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
	_build_ui()
	_make_click_player()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		toggle_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if Time.get_ticks_msec() - _started_ms > STARTUP_GRACE_MS and not get_tree().paused:
			_set_paused(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo:
			if key_event.physical_keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_P:
				toggle_pause()
				get_viewport().set_input_as_handled()


## Called by the pause pad through the "pause_menu" group.
func toggle_pause() -> void:
	_set_paused(not get_tree().paused)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	visible = paused
	if paused:
		_play_click()


func _on_resume() -> void:
	_play_click()
	_set_paused(false)


func _on_restart() -> void:
	_play_click()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_sound() -> void:
	_sound_on = not _sound_on
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not _sound_on)
	_update_sound_label()
	_play_click()


func _update_sound_label() -> void:
	_sound_button.text = "SOUND: ON" if _sound_on else "SOUND: OFF"


func _build_ui() -> void:
	# Dark overlay that also blocks touches from reaching the game.
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_COLOR, 28))
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 36)
	panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	var title: Label = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	box.add_child(title)

	box.add_child(_make_button("RESUME", _on_resume))
	box.add_child(_make_button("RESTART", _on_restart))
	_sound_button = _make_button("", _on_sound)
	box.add_child(_sound_button)
	_update_sound_label()


func _make_button(label: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(420.0, 76.0)
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_stylebox_override("normal", _make_style(BUTTON_COLOR, 18))
	button.add_theme_stylebox_override("hover", _make_style(BUTTON_HOVER_COLOR, 18))
	button.add_theme_stylebox_override("pressed", _make_style(BUTTON_PRESSED_COLOR, 18))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(callback)
	return button


func _make_style(color: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


func _make_click_player() -> void:
	_click = AudioStreamPlayer.new()
	if ResourceLoader.exists(click_sound_path):
		_click.stream = load(click_sound_path) as AudioStream
	add_child(_click)


func _play_click() -> void:
	if _click != null and _click.stream != null:
		_click.play()
