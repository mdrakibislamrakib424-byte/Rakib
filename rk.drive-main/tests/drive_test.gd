extends SceneTree
## Headless driving test on the real place: the car follows the dirt track waypoints.
const WAYPOINTS: Array[Vector2] = [
	Vector2(51.5, -55.3), Vector2(37.7, -40.6), Vector2(8.9, -23.0), Vector2(-19.5, -8.3),
	Vector2(-37.6, 5.6), Vector2(-41.2, 27.1), Vector2(-26.8, 48.3), Vector2(-2.0, 65.1), Vector2(21.1, 89.0),
]
var _path: Array[Vector2] = []
var _car: CarController
var _frames: int = 0
var _wp: int = 0
var _min_y: float = 1e9
var _max_off_track: float = 0.0

func _densify() -> void:
	for i: int in WAYPOINTS.size() - 1:
		var a: Vector2 = WAYPOINTS[i]
		var b: Vector2 = WAYPOINTS[i + 1]
		var n: int = maxi(1, int(a.distance_to(b) / 7.0))
		for k: int in n:
			_path.append(a.lerp(b, float(k) / float(n)))
	_path.append(WAYPOINTS[WAYPOINTS.size() - 1])

func _initialize() -> void:
	_densify()
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _physics_process(_d: float) -> bool:
	if _car == null:
		_car = get_first_node_in_group("car") as CarController
		if _car == null:
			return false
		print("car spawn: ", _car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), "  forward(+Z)=", _car.global_transform.basis.z.snapped(Vector3(0.01, 0.01, 0.01)))
	_frames += 1
	var p: Vector3 = _car.global_position
	_min_y = minf(_min_y, p.y)
	var target: Vector2 = _path[_wp]
	var to_wp: float = Vector2(p.x, p.z).distance_to(target)
	if to_wp < 9.0 and _wp < _path.size() - 1:
		_wp += 1
		target = _path[_wp]
	var local: Vector3 = _car.global_transform.affine_inverse() * Vector3(target.x, p.y, target.y)
	var steer: float = clampf(atan2(local.x, local.z) * 2.0, -1.0, 1.0)   # +X is the car's left
	var gas: float = 1.0 if _car.get_speed_kmh() < 40.0 else 0.0
	if _frames > 90:
		_car.set_inputs(gas, 0.0, steer, false)
	if _frames % 120 == 0:
		print("t=%4.1fs wp=%d/%d pos=(%.1f, %.1f, %.1f) speed=%.0f km/h gear=%s up.y=%.2f" % [_frames / 60.0, _wp, _path.size(), p.x, p.y, p.z, _car.get_speed_kmh(), _car.get_gear_text(), _car.global_transform.basis.y.y])
	if _frames == 60 * 30:
		_report_stuck()
	if _frames >= 60 * 45 or (_wp == _path.size() - 1 and to_wp < 9.0):
		print("RESULT: reached waypoint %d/%d, lowest y=%.1f, time=%.1fs" % [_wp + 1, _path.size(), _min_y, _frames / 60.0])
		quit()
	return false

func _report_stuck() -> void:
	var space: PhysicsDirectSpaceState3D = _car.get_world_3d().direct_space_state
	var fwd: Vector3 = _car.global_transform.basis.z
	var left: Vector3 = _car.global_transform.basis.x
	var p: Vector3 = _car.global_position
	print("STUCK at ", p.snapped(Vector3(0.1, 0.1, 0.1)), " engine_force=", _car.engine_force, " brake=", _car.brake, " steer=", _car.steering)
	for w: Node in _car.get_children():
		if w is VehicleWheel3D:
			print("  ", w.name, " contact=", (w as VehicleWheel3D).is_in_contact(), " skid=", (w as VehicleWheel3D).get_skidinfo())
	for d: float in [-4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0]:
		var row: String = ""
		for l: float in [-4.0, -2.0, 0.0, 2.0, 4.0]:
			var origin: Vector3 = p + fwd * d + left * l + Vector3.UP * 20.0
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 40.0))
			row += "%6.1f" % (hit.position.y if not hit.is_empty() else -99.0)
		print("  ahead %+4.0f m | left+4..-4: %s" % [d, row])
