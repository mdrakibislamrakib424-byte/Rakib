class_name Gearbox
extends RefCounted
## Virtual automatic gearbox: 5 forward gears + reverse.
##
## It does not move the car by itself. The car asks it for
##  - the pulling power of the current gear (get_force_multiplier), and
##  - a smoothed engine RPM value (rpm_ratio, 0 = idle, 1 = redline),
## which the engine sound and the HUD read.

signal gear_changed(gear: int)

const REVERSE: int = -1
const TOP_GEAR: int = 5

## Top speed of every gear as a fraction of the car's max speed.
var gear_speed_fractions: Array[float] = [0.27, 0.48, 0.70, 0.90, 1.10]
## Pulling power of every gear (1.0 = the car's full engine force).
var gear_force: Array[float] = [1.0, 0.90, 0.80, 0.72, 0.65]

var max_speed_kmh: float = 140.0
## Shift up when the speed passes this fraction of the gear's top speed.
var upshift_ratio: float = 0.93
## Shift down when the speed falls below this fraction of the lower gear's top speed.
var downshift_ratio: float = 0.62
## Power is cut for this long while the gear changes (gives the "shift" feel).
var shift_duration: float = 0.28
var min_time_between_shifts: float = 0.6
## RPM (0..1) the engine jumps to when you floor the gas from a standstill.
var launch_rpm: float = 0.32
var rev_up_rate: float = 9.0
var rev_down_rate: float = 4.5

var gear: int = 1
## 0 = idle, 1 = redline.
var rpm_ratio: float = 0.0

var _shift_timer: float = 0.0
var _since_shift: float = 99.0


func top_speed(for_gear: int) -> float:
	return max_speed_kmh * gear_speed_fractions[clampi(for_gear, 1, TOP_GEAR) - 1]


func is_shifting() -> bool:
	return _shift_timer > 0.0


## Multiplier (0..1) applied to the engine force at the given speed.
func get_force_multiplier(speed_kmh: float) -> float:
	if gear < 1:
		return 1.0
	var power: float = gear_force[gear - 1]
	var ratio: float = clampf(speed_kmh / top_speed(gear), 0.0, 1.0)
	# Power fades out close to the redline of the gear.
	power *= 1.0 - smoothstep(0.88, 1.0, ratio) * 0.8
	if is_shifting():
		power *= 0.2
	return power


## Call once per physics frame. speed_kmh is the absolute speed.
func update(speed_kmh: float, throttle: float, reversing: bool, delta: float) -> void:
	_shift_timer = maxf(0.0, _shift_timer - delta)
	_since_shift += delta

	var wanted: int = gear
	if reversing:
		wanted = REVERSE
	elif gear < 1:
		wanted = 1
	elif _since_shift >= min_time_between_shifts:
		var ratio: float = speed_kmh / top_speed(gear)
		if ratio > upshift_ratio and gear < TOP_GEAR:
			wanted = gear + 1
		elif gear > 1 and speed_kmh < top_speed(gear - 1) * downshift_ratio:
			wanted = gear - 1
	if wanted != gear:
		_change_gear(wanted)

	# Reverse behaves like first gear for the engine sound.
	var rpm_gear: int = 1 if gear < 1 else gear
	var speed_ratio: float = clampf(speed_kmh / top_speed(rpm_gear), 0.0, 1.0)
	var target: float = maxf(speed_ratio, clampf(throttle, 0.0, 1.0) * launch_rpm)
	var rate: float = rev_up_rate if target > rpm_ratio else rev_down_rate
	rpm_ratio = lerpf(rpm_ratio, target, clampf(rate * delta, 0.0, 1.0))


func _change_gear(new_gear: int) -> void:
	var old_gear: int = gear
	gear = new_gear
	if old_gear >= 1 and new_gear >= 1:
		_shift_timer = shift_duration
		_since_shift = 0.0
	gear_changed.emit(gear)
