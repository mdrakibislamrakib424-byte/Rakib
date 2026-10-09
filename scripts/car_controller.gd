class_name CarController
extends VehicleBody3D
## Arcade-realistic vehicle controller.
## Input is decoupled: touch UI, AI traffic or tests only call the set_* / toggle_* functions.
## NOTE: VehicleBody3D drives towards its local +Z axis (Vector3.MODEL_FRONT).
## The car's LEFT side is +X and positive steering turns LEFT.
##
## Features: automatic gearbox with RPM, reverse, rear-wheel handbrake drift,
## drift assist, downforce, brake light state, turn indicators and horn.

signal speed_changed(speed_kmh: float)
signal indicator_changed(side: int, phase_on: bool)

enum Indicator { OFF, LEFT, RIGHT }

@export_group("Engine")
@export var max_engine_force: float = 2200.0
@export var max_reverse_force: float = 1200.0
@export var max_brake_force: float = 70.0
## Brake applied while the handbrake is held (the rear wheels also lose grip).
@export var handbrake_force: float = 60.0
## Light braking while coasting, so the car slows down on its own.
@export var coast_brake: float = 1.5
@export var max_speed_kmh: float = 140.0
@export var max_reverse_speed_kmh: float = 35.0
## Pushes the car into the road at speed (more grip, more stable).
@export var downforce: float = 3.5

@export_group("Steering")
@export var max_steer_angle_deg: float = 32.0
## How fast the wheels turn towards the target angle.
@export var steer_response: float = 4.0
## How fast the wheels return to the centre.
@export var steer_return_response: float = 6.5
## 0.0 = no reduction, 1.0 = full reduction at max speed.
@export_range(0.0, 1.0) var high_speed_steer_reduction: float = 0.65

@export_group("Handbrake drift")
## Rear grip while the handbrake is held (1.0 = normal grip, lower = more slide).
@export_range(0.1, 1.0) var handbrake_rear_grip: float = 0.45
@export var grip_change_rate: float = 8.0
## Steers gently into a slide so drifts stay controllable. 0 turns it off.
@export_range(0.0, 1.0) var drift_assist: float = 0.4

@export_group("Indicators")
@export var indicator_blink_interval: float = 0.35

var throttle_input: float = 0.0
var brake_input: float = 0.0
var steer_input: float = 0.0
var handbrake_active: bool = false
var horn_active: bool = false

## True while the car is in reverse gear.
var reversing: bool = false
## True while the brake lights should be on.
var brake_light_on: bool = false
## 0..1, how much the tyres are sliding (drives the tyre screech sound).
var slip_amount: float = 0.0
## One of Indicator.OFF / LEFT / RIGHT.
var indicator: int = Indicator.OFF
## Blink phase of the active indicator.
var indicator_phase_on: bool = false

var gearbox: Gearbox = Gearbox.new()

var _current_steer: float = 0.0
var _last_reported_speed: int = -1
var _wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []
var _rear_base_friction: Array[float] = []
var _rear_grip_scale: float = 1.0
var _blink_timer: float = 0.0
var _turn_armed: bool = false


func _ready() -> void:
	# Lets the camera, touch pad and HUD find the car without scene wiring.
	add_to_group("car")

	for child: Node in get_children():
		if child is VehicleWheel3D:
			var wheel: VehicleWheel3D = child as VehicleWheel3D
			_wheels.append(wheel)
			if not wheel.use_as_steering:
				_rear_wheels.append(wheel)
				_rear_base_friction.append(wheel.wheel_friction_slip)
	if _wheels.size() < 4:
		push_warning("CarController: expected 4 VehicleWheel3D children, found %d." % _wheels.size())

	gearbox.max_speed_kmh = max_speed_kmh


## Single entry point for the driving inputs.
func set_inputs(throttle: float, brake_amount: float, steer: float, use_handbrake: bool = false) -> void:
	throttle_input = clampf(throttle, 0.0, 1.0)
	brake_input = clampf(brake_amount, 0.0, 1.0)
	steer_input = clampf(steer, -1.0, 1.0)
	handbrake_active = use_handbrake


func set_horn(active: bool) -> void:
	horn_active = active


## Tap the same side again to switch the indicator off.
func toggle_indicator(side: int) -> void:
	if indicator == side:
		indicator = Indicator.OFF
		indicator_phase_on = false
	else:
		indicator = side
		indicator_phase_on = true
	_blink_timer = 0.0
	_turn_armed = false
	indicator_changed.emit(indicator, indicator_phase_on)


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


## Positive when moving forward (the vehicle's forward axis is +Z).
func get_forward_speed() -> float:
	return global_transform.basis.z.dot(linear_velocity)


## Engine speed for sound and HUD: 0 = idle, 1 = redline.
func get_rpm_ratio() -> float:
	return gearbox.rpm_ratio


## "R", "N" or "D1".."D5" for the HUD.
func get_gear_text() -> String:
	if reversing:
		return "R"
	if get_speed_kmh() < 1.5 and throttle_input <= 0.0 and brake_input <= 0.0:
		return "N"
	return "D%d" % gearbox.gear


func _physics_process(delta: float) -> void:
	var forward_speed: float = get_forward_speed()
	var speed_kmh: float = get_speed_kmh()

	_update_direction(forward_speed)
	gearbox.update(speed_kmh, throttle_input, reversing, delta)
	_apply_drive(forward_speed, speed_kmh)
	_apply_handbrake(speed_kmh, delta)
	_apply_steering(delta, forward_speed)
	_apply_downforce(speed_kmh)
	_update_slip(forward_speed, speed_kmh)
	_update_indicator(delta)
	_report_speed()


## Decides between drive and reverse: the BRAKE pad reverses once the car has stopped.
func _update_direction(forward_speed: float) -> void:
	if throttle_input > 0.0:
		if forward_speed > -1.0:
			reversing = false
	elif brake_input > 0.0:
		if forward_speed < 1.0:
			reversing = true
	elif absf(forward_speed) < 0.5:
		reversing = false


func _apply_drive(forward_speed: float, speed_kmh: float) -> void:
	var force: float = 0.0
	var brake_value: float = 0.0
	brake_light_on = false

	if throttle_input > 0.0:
		if forward_speed < -1.0:
			# Rolling backwards: brake first, then drive forward.
			brake_value = throttle_input * max_brake_force
			brake_light_on = true
		elif speed_kmh < max_speed_kmh:
			var taper: float = 1.0 - smoothstep(0.94, 1.0, speed_kmh / max_speed_kmh)
			force = throttle_input * max_engine_force * gearbox.get_force_multiplier(speed_kmh) * taper
	elif brake_input > 0.0:
		if reversing:
			if speed_kmh < max_reverse_speed_kmh:
				var reverse_taper: float = 1.0 - smoothstep(0.85, 1.0, speed_kmh / max_reverse_speed_kmh)
				force = -brake_input * max_reverse_force * reverse_taper
		else:
			# Still rolling forward: brake.
			brake_value = brake_input * max_brake_force
			brake_light_on = true
	else:
		brake_value = coast_brake

	if handbrake_active:
		brake_value = maxf(brake_value, handbrake_force)
		brake_light_on = true

	engine_force = force
	brake = brake_value


## Handbrake: the rear tyres lose grip so the tail slides out.
func _apply_handbrake(speed_kmh: float, delta: float) -> void:
	var sliding: bool = handbrake_active and speed_kmh > 8.0
	var target_scale: float = handbrake_rear_grip if sliding else 1.0
	_rear_grip_scale = lerpf(_rear_grip_scale, target_scale, clampf(grip_change_rate * delta, 0.0, 1.0))
	for i: int in _rear_wheels.size():
		_rear_wheels[i].wheel_friction_slip = _rear_base_friction[i] * _rear_grip_scale


func _apply_steering(delta: float, forward_speed: float) -> void:
	# Less steering at high speed keeps the car stable.
	var speed_ratio: float = clampf(get_speed_kmh() / max_speed_kmh, 0.0, 1.0)
	var max_angle: float = deg_to_rad(max_steer_angle_deg)
	var limit: float = max_angle * (1.0 - speed_ratio * high_speed_steer_reduction)
	var target: float = steer_input * limit

	# Drift assist: steer towards the direction the car is really travelling.
	if drift_assist > 0.0 and forward_speed > 6.0:
		var lateral: float = linear_velocity.dot(global_transform.basis.x)
		var slip_angle: float = atan2(lateral, forward_speed)
		var excess: float = absf(slip_angle) - deg_to_rad(5.0)
		if excess > 0.0:
			target += signf(slip_angle) * minf(excess, 0.5) * drift_assist
	target = clampf(target, -max_angle, max_angle)

	var rate: float = steer_response if absf(target) > absf(_current_steer) else steer_return_response
	_current_steer = lerpf(_current_steer, target, clampf(rate * delta, 0.0, 1.0))
	steering = _current_steer


func _apply_downforce(speed_kmh: float) -> void:
	var speed: float = speed_kmh / 3.6
	apply_central_force(Vector3.DOWN * downforce * speed * speed)


func _update_slip(forward_speed: float, speed_kmh: float) -> void:
	var contacts: int = 0
	for wheel: VehicleWheel3D in _wheels:
		if wheel.is_in_contact():
			contacts += 1
	if contacts == 0:
		slip_amount = 0.0
		return

	var lateral: float = absf(linear_velocity.dot(global_transform.basis.x))
	var slip: float = clampf((lateral - 2.5) / 6.0, 0.0, 1.0)
	if handbrake_active and speed_kmh > 15.0:
		slip = maxf(slip, 0.85)
	if brake_input > 0.7 and not reversing and forward_speed > 14.0:
		slip = maxf(slip, 0.45)
	slip_amount = slip


func _update_indicator(delta: float) -> void:
	if indicator == Indicator.OFF:
		return

	_blink_timer += delta
	if _blink_timer >= indicator_blink_interval:
		_blink_timer -= indicator_blink_interval
		indicator_phase_on = not indicator_phase_on
		indicator_changed.emit(indicator, indicator_phase_on)

	# Switch off by itself once the turn is finished (like a real car).
	var turn_angle: float = deg_to_rad(10.0)
	var toward_side: float = _current_steer if indicator == Indicator.LEFT else -_current_steer
	if toward_side > turn_angle:
		_turn_armed = true
	elif _turn_armed and absf(_current_steer) < deg_to_rad(2.0):
		toggle_indicator(indicator)


func _report_speed() -> void:
	var rounded: int = roundi(get_speed_kmh())
	if rounded != _last_reported_speed:
		_last_reported_speed = rounded
		speed_changed.emit(float(rounded))
