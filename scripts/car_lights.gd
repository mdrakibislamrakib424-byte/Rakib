class_name CarLights
extends Node
## Brake lights and turn indicators, using the glowing lenses of the car model.
## Add this node as a child of the CarController (next to the "Model" node).
##  - Rear red lenses: dim tail light, bright when braking.
##  - Rear and front lenses on the indicator side blink amber.
## The car's LEFT side is +X (the model's "L" parts).

const MODEL_NODE_NAME: String = "Model"
const REAR_LEFT: String = "LensLTL_EmissionRed"
const REAR_RIGHT: String = "LensRTL_EmissionRed"
const FRONT_LEFT: String = "LensLHL_HeadLights"
const FRONT_RIGHT: String = "LensRHL_HeadLights"
const AMBER: Color = Color(1.0, 0.55, 0.05)
const TAIL_RED: Color = Color(1.0, 0.05, 0.03)

@export_group("Brightness")
## Rear lens brightness (relative to the model) with the lights idle.
@export var tail_energy_scale: float = 0.45
@export var brake_energy_scale: float = 2.8
@export var amber_energy: float = 4.0


## The glowing materials of one lens mesh, plus their original look.
class Lens:
	var materials: Array[BaseMaterial3D] = []
	var base_color: Color = Color.WHITE
	var base_energy: float = 1.0
	var base_texture: Texture2D = null


var _car: CarController
var _rear_left: Lens
var _rear_right: Lens
var _front_left: Lens
var _front_right: Lens
var _last_state: int = -1


func _ready() -> void:
	_car = get_parent() as CarController
	if _car == null:
		push_error("CarLights: parent must be a CarController.")
		set_process(false)
		return

	var model: Node = _car.get_node_or_null(MODEL_NODE_NAME)
	if model == null:
		push_warning("CarLights: child node '%s' not found." % MODEL_NODE_NAME)
		set_process(false)
		return

	_rear_left = _collect(model, REAR_LEFT, true)
	_rear_right = _collect(model, REAR_RIGHT, true)
	_front_left = _collect(model, FRONT_LEFT, false)
	_front_right = _collect(model, FRONT_RIGHT, false)


func _process(_delta: float) -> void:
	var brake_on: bool = _car.brake_light_on
	var left_amber: bool = _car.indicator == CarController.Indicator.LEFT and _car.indicator_phase_on
	var right_amber: bool = _car.indicator == CarController.Indicator.RIGHT and _car.indicator_phase_on

	# Only touch the materials when something actually changed.
	var state: int = 0
	if brake_on:
		state |= 1
	if left_amber:
		state |= 2
	if right_amber:
		state |= 4
	if state == _last_state:
		return
	_last_state = state

	var rear_scale: float = brake_energy_scale if brake_on else tail_energy_scale
	_show(_rear_left, left_amber, rear_scale)
	_show(_rear_right, right_amber, rear_scale)
	_show(_front_left, left_amber, 1.0)
	_show(_front_right, right_amber, 1.0)


func _show(lens: Lens, amber: bool, energy_scale: float) -> void:
	for material: BaseMaterial3D in lens.materials:
		material.emission_enabled = true
		if amber:
			material.emission = AMBER
			material.emission_texture = null
			material.emission_energy_multiplier = amber_energy
		else:
			material.emission = lens.base_color
			material.emission_texture = lens.base_texture
			material.emission_energy_multiplier = lens.base_energy * energy_scale


## Finds a mesh by name and gives it its own copy of the materials,
## so changing one lens never changes the other side.
## tint_red: rear lenses that are not already red are shown red.
func _collect(model: Node, node_name: String, tint_red: bool) -> Lens:
	var lens: Lens = Lens.new()
	var mesh_instance: MeshInstance3D = model.find_child(node_name, true, false) as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		push_warning("CarLights: lens '%s' not found in the model." % node_name)
		return lens

	for surface: int in mesh_instance.mesh.get_surface_count():
		var original: BaseMaterial3D = mesh_instance.get_active_material(surface) as BaseMaterial3D
		if original == null:
			continue
		var copy: BaseMaterial3D = original.duplicate() as BaseMaterial3D
		mesh_instance.set_surface_override_material(surface, copy)
		if lens.materials.is_empty():
			lens.base_color = copy.emission
			lens.base_energy = copy.emission_energy_multiplier
			lens.base_texture = copy.emission_texture
		lens.materials.append(copy)

	# A white or non-glowing rear lens is shown red, so tail lights never look white.
	if tint_red and lens.base_texture == null and lens.base_color.s < 0.3:
		lens.base_color = TAIL_RED
	return lens
