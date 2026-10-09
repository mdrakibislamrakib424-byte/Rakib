class_name PlaceLoader
extends Node3D
## Loads one "place" (a world: forest, desert, snow, sea ...) from a config file.
##
## Adding a new place = a baked scene + a JSON file in res://places/. No code changes.
## The scene must contain a Marker3D called "SpawnPoint" (the car starts there,
## facing the marker's +Z axis).
##
## Config keys (all optional except "scene"):
##   scene       res:// path of the place scene
##   headlights  true/false, switch the car headlights on
##   sun         { color, energy, rotation_degrees }
##   sky         { top, horizon, ground, energy }
##   ambient     { energy }
##   fog         { enabled, color, density }
## Colours are [r, g, b] arrays (0..1).

const PLACES_DIR: String = "res://places/"

@export var place_id: String = "forest_night"
@export var car: CarController
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
## The plain test ground; removed once a place has loaded.
@export var fallback_ground: Node3D

var current_place: Node3D = null
var config: Dictionary = {}


func _ready() -> void:
	load_place(place_id)


func load_place(id: String) -> bool:
	config = _read_config(id)
	if config.is_empty():
		push_error("PlaceLoader: no valid config for place '%s'. Using the test ground." % id)
		return false

	var scene_path: String = str(config.get("scene", ""))
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("PlaceLoader: cannot load scene '%s'. Using the test ground." % scene_path)
		return false

	if is_instance_valid(current_place):
		current_place.queue_free()
	current_place = packed.instantiate() as Node3D
	add_child(current_place)

	if is_instance_valid(fallback_ground):
		fallback_ground.queue_free()

	_apply_lighting()
	_place_car()
	return true


func _read_config(id: String) -> Dictionary:
	var path: String = PLACES_DIR + id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


func _place_car() -> void:
	if not is_instance_valid(car):
		car = get_tree().get_first_node_in_group("car") as CarController
	var spawn: Node3D = current_place.get_node_or_null("SpawnPoint") as Node3D
	if not is_instance_valid(car) or spawn == null:
		push_warning("PlaceLoader: car or SpawnPoint missing, the car stays where it is.")
		return
	car.global_transform = spawn.global_transform
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	var lights: Node3D = car.get_node_or_null("Headlights") as Node3D
	if lights != null:
		lights.visible = bool(config.get("headlights", false))


func _apply_lighting() -> void:
	var sun_cfg: Dictionary = config.get("sun", {})
	if is_instance_valid(sun) and not sun_cfg.is_empty():
		sun.light_color = _color(sun_cfg.get("color", [1, 1, 1]))
		sun.light_energy = float(sun_cfg.get("energy", 1.0))
		var rot: Array = sun_cfg.get("rotation_degrees", [-55, -35, 0])
		sun.rotation_degrees = Vector3(rot[0], rot[1], rot[2])

	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	var env: Environment = world_environment.environment

	var sky_cfg: Dictionary = config.get("sky", {})
	if not sky_cfg.is_empty() and env.sky != null:
		var sky_material: ProceduralSkyMaterial = env.sky.sky_material as ProceduralSkyMaterial
		if sky_material != null:
			sky_material.sky_top_color = _color(sky_cfg.get("top", [0.3, 0.5, 0.9]))
			sky_material.sky_horizon_color = _color(sky_cfg.get("horizon", [0.6, 0.7, 0.8]))
			sky_material.ground_horizon_color = _color(sky_cfg.get("horizon", [0.6, 0.7, 0.8]))
			sky_material.ground_bottom_color = _color(sky_cfg.get("ground", [0.2, 0.2, 0.2]))
			sky_material.sky_energy_multiplier = float(sky_cfg.get("energy", 1.0))

	var ambient_cfg: Dictionary = config.get("ambient", {})
	if not ambient_cfg.is_empty():
		env.ambient_light_energy = float(ambient_cfg.get("energy", 1.0))

	var fog_cfg: Dictionary = config.get("fog", {})
	if not fog_cfg.is_empty():
		env.fog_enabled = bool(fog_cfg.get("enabled", true))
		env.fog_light_color = _color(fog_cfg.get("color", [0.5, 0.6, 0.7]))
		env.fog_density = float(fog_cfg.get("density", 0.01))


func _color(values: Array) -> Color:
	return Color(float(values[0]), float(values[1]), float(values[2]))
