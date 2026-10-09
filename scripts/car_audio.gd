class_name CarAudio
extends Node
## All car sounds: engine (idle + running loop, pitch follows RPM), start-up,
## horn, tyre screech and indicator click.
## Add this node as a child of the CarController. Missing audio files are
## skipped with a warning, the game never crashes because of them.

const AUDIO_DIR: String = "res://assets/audio/"

@export_group("Files")
@export var idle_loop_file: String = "engine_idle_loop.ogg"
@export var run_loop_file: String = "engine_cruise_loop.ogg"
@export var start_file: String = "engine_start_v8.ogg"
@export var horn_file: String = "horn_1.ogg"
@export var screech_file: String = "tire_screech.ogg"
@export var screech_alt_file: String = "tire_screech_2.ogg"
@export var indicator_file: String = "indicator_click.ogg"

@export_group("Volume (dB)")
@export var idle_db: float = -8.0
@export var run_db: float = -6.0
@export var start_db: float = -6.0
@export var horn_db: float = -3.0
@export var screech_db: float = -6.0
@export var indicator_db: float = -10.0

@export_group("Engine")
## Start-up sound plays this long, then fades out.
@export var start_sound_seconds: float = 3.5
## The engine loops fade in after this delay and over this time.
@export var engine_delay: float = 0.8
@export var engine_fade_in: float = 1.5
@export var run_pitch_min: float = 0.6
@export var run_pitch_max: float = 1.9
@export var idle_pitch_min: float = 0.9
@export var idle_pitch_max: float = 1.15

@export_group("Tyres")
## Tyre screech starts above this slip amount (0..1).
@export var screech_threshold: float = 0.12

var _car: CarController
var _idle: AudioStreamPlayer
var _run: AudioStreamPlayer
var _start: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _screech: AudioStreamPlayer
var _screech_alt: AudioStreamPlayer
var _indicator: AudioStreamPlayer

var _elapsed: float = 0.0
var _engine_fade: float = 0.0
var _load: float = 0.0
var _screech_amount: float = 0.0
var _use_alt_screech: bool = false


func _ready() -> void:
	_car = get_parent() as CarController
	if _car == null:
		push_error("CarAudio: parent must be a CarController.")
		set_process(false)
		return

	_idle = _make_player(idle_loop_file, true, idle_db)
	_run = _make_player(run_loop_file, true, run_db)
	_start = _make_player(start_file, false, start_db)
	_horn = _make_player(horn_file, false, horn_db)
	_screech = _make_player(screech_file, false, screech_db)
	_screech_alt = _make_player(screech_alt_file, false, screech_db)
	_indicator = _make_player(indicator_file, false, indicator_db)

	# The engine loops run all the time; only their volume and pitch change.
	_set_silent(_idle)
	_set_silent(_run)
	_play_if_possible(_idle)
	_play_if_possible(_run)

	_car.indicator_changed.connect(_on_indicator_changed)
	_play_start_sound()


func _process(delta: float) -> void:
	if not is_instance_valid(_car):
		return
	_elapsed += delta
	if _elapsed > engine_delay:
		_engine_fade = move_toward(_engine_fade, 1.0, delta / maxf(engine_fade_in, 0.01))

	_update_engine(delta)
	_update_horn()
	_update_screech(delta)


func _update_engine(delta: float) -> void:
	var rpm: float = _car.get_rpm_ratio()
	_load = move_toward(_load, _car.throttle_input, delta * 3.0)

	# Idle layer fades out while the engine revs up.
	var idle_amount: float = (1.0 - smoothstep(0.05, 0.3, rpm)) * _engine_fade
	_idle.volume_db = idle_db + linear_to_db(maxf(idle_amount, 0.001))
	_idle.pitch_scale = lerpf(idle_pitch_min, idle_pitch_max, clampf(rpm / 0.3, 0.0, 1.0))

	# Running layer: louder under load, pitch follows RPM.
	var run_amount: float = smoothstep(0.0, 0.25, rpm) * (0.55 + 0.45 * _load) * _engine_fade
	_run.volume_db = run_db + linear_to_db(maxf(run_amount, 0.001))
	_run.pitch_scale = lerpf(run_pitch_min, run_pitch_max, clampf(rpm, 0.0, 1.0))


func _update_horn() -> void:
	if _horn.stream == null:
		return
	if _car.horn_active:
		if not _horn.playing:
			_horn.play()
	elif _horn.playing:
		_horn.stop()


func _update_screech(delta: float) -> void:
	var slip: float = _car.slip_amount
	var player: AudioStreamPlayer = _screech_alt if _use_alt_screech else _screech

	if slip > screech_threshold:
		_screech_amount = move_toward(_screech_amount, slip, delta * 6.0)
		if not _screech.playing and not _screech_alt.playing:
			# Alternate between the two clips so it does not sound repetitive.
			_use_alt_screech = not _use_alt_screech
			player = _screech_alt if _use_alt_screech else _screech
			_play_if_possible(player)
	else:
		_screech_amount = move_toward(_screech_amount, 0.0, delta * 5.0)
		if _screech_amount <= 0.01:
			_screech.stop()
			_screech_alt.stop()

	var volume: float = screech_db + linear_to_db(maxf(_screech_amount, 0.001))
	var pitch: float = lerpf(0.9, 1.15, _screech_amount)
	_screech.volume_db = volume
	_screech.pitch_scale = pitch
	_screech_alt.volume_db = volume
	_screech_alt.pitch_scale = pitch


func _on_indicator_changed(_side: int, _phase_on: bool) -> void:
	_play_if_possible(_indicator)


func _play_start_sound() -> void:
	if _start.stream == null:
		return
	_start.play()
	await get_tree().create_timer(start_sound_seconds).timeout
	if not is_inside_tree():
		return
	var tween: Tween = create_tween()
	tween.tween_property(_start, "volume_db", -60.0, 0.6)
	tween.tween_callback(_start.stop)


func _make_player(file_name: String, loop: bool, volume_db: float) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.volume_db = volume_db
	var path: String = AUDIO_DIR + file_name
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path) as AudioStream
		if loop and stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		player.stream = stream
	else:
		push_warning("CarAudio: audio file not found: %s" % path)
	add_child(player)
	return player


func _set_silent(player: AudioStreamPlayer) -> void:
	player.volume_db = -60.0


func _play_if_possible(player: AudioStreamPlayer) -> void:
	if player.stream != null:
		player.play()
