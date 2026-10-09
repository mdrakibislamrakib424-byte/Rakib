class_name FollowCamera
extends Camera3D
## Smooth chase camera that follows a vehicle from behind.
## It only follows the vehicle's heading (yaw), so bumps and body roll do not shake the view.
## At speed it pulls back, widens the field of view, and during a slide it swings
## towards the direction the car is really travelling.

@export var target: VehicleBody3D

@export_group("Position")
@export var distance: float = 7.5
## Extra distance at max speed.
@export var speed_distance_extra: float = 1.8
@export var height: float = 2.8
@export var look_height: float = 1.0

@export_group("Smoothing")
@export var position_smoothing: float = 7.0
@export var rotation_smoothing: float = 3.5

@export_group("Drift view")
## 0 = always behind the car's nose, 1 = follows the direction of travel in a slide.
@export_range(0.0, 1.0) var drift_follow: float = 0.45

@export_group("Field of view")
@export var base_fov: float = 65.0
@export var max_fov_boost: float = 14.0
## Used when the target is not a CarController (a CarController supplies its own max speed).
@export var max_speed_kmh: float = 140.0

var _yaw: float = 0.0
var _speed_ratio: float = 0.0
var _bound: bool = false


func _ready() -> void:
	fov = base_fov
	make_current()
	_bind_target()


## Finds the car (scene wiring first, then node name, then "car" group)
## and snaps behind it once. Retries every frame until the car exists,
## so the camera can never get stuck at the world origin again.
func _bind_target() -> bool:
	if _bound and is_instance_valid(target):
		return true
	if not is_instance_valid(target):
		var found: Node = get_node_or_null("../Car")
		if found == null:
			found = get_tree().get_first_node_in_group("car")
		target = found as VehicleBody3D
	if not is_instance_valid(target):
		return false
	_bound = true
	_update_speed_ratio()
	_yaw = _get_target_yaw()
	global_position = _get_desired_position()
	_look_at_target()
	return true


func _process(delta: float) -> void:
	if not _bind_target():
		return
	_update_speed_ratio()
	_yaw = lerp_angle(_yaw, _get_target_yaw(), 1.0 - exp(-rotation_smoothing * delta))
	global_position = global_position.lerp(
		_get_desired_position(), 1.0 - exp(-position_smoothing * delta))
	_look_at_target()

	# Widen the field of view with speed for a stronger sense of motion.
	fov = lerpf(fov, base_fov + max_fov_boost * _speed_ratio, 1.0 - exp(-3.0 * delta))


func _update_speed_ratio() -> void:
	var top_speed: float = max_speed_kmh
	if target is CarController:
		top_speed = (target as CarController).max_speed_kmh
	var speed_kmh: float = target.linear_velocity.length() * 3.6
	_speed_ratio = clampf(speed_kmh / maxf(top_speed, 1.0), 0.0, 1.0)


## Heading of the vehicle around the Y axis (its forward axis is +Z).
## While sliding forwards, it blends towards the direction of travel.
func _get_target_yaw() -> float:
	var forward: Vector3 = target.global_transform.basis.z
	var heading_yaw: float = atan2(forward.x, forward.z)

	var velocity: Vector3 = target.linear_velocity
	var forward_speed: float = forward.dot(velocity)
	if drift_follow > 0.0 and forward_speed > 6.0:
		var travel_yaw: float = atan2(velocity.x, velocity.z)
		var weight: float = drift_follow * clampf((forward_speed - 6.0) / 10.0, 0.0, 1.0)
		return lerp_angle(heading_yaw, travel_yaw, weight)
	return heading_yaw


func _get_desired_position() -> Vector3:
	var heading: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	var back: float = distance + speed_distance_extra * _speed_ratio
	return target.global_position - heading * back + Vector3.UP * height


func _look_at_target() -> void:
	look_at(target.global_position + Vector3.UP * look_height, Vector3.UP)
