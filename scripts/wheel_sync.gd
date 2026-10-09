class_name WheelSync
extends Node
## Keeps the visual wheels of the imported car model in sync with the
## VehicleWheel3D physics wheels (spin, steering and suspension travel).
## Add this node as a child of the car (VehicleBody3D).

## Physics wheel node name -> visual wheel node name inside the model.
const WHEEL_MAP: Dictionary = {
	"WheelFL": "CTRL_Wheel_FL",
	"WheelFR": "CTRL_Wheel_FR",
	"WheelRL": "CTRL_Wheel_RL",
	"WheelRR": "CTRL_Wheel_RR",
}
const MODEL_NODE_NAME: String = "Model"

var _physics_wheels: Array[VehicleWheel3D] = []
var _visual_wheels: Array[Node3D] = []


func _ready() -> void:
	var car: VehicleBody3D = get_parent() as VehicleBody3D
	if car == null:
		push_error("WheelSync: parent must be a VehicleBody3D.")
		set_process(false)
		return

	var model: Node = car.get_node_or_null(MODEL_NODE_NAME)
	if model == null:
		push_error("WheelSync: child node '%s' not found." % MODEL_NODE_NAME)
		set_process(false)
		return

	for physics_name: String in WHEEL_MAP:
		var physics_wheel: VehicleWheel3D = car.get_node_or_null(physics_name) as VehicleWheel3D
		var visual_wheel: Node3D = model.find_child(WHEEL_MAP[physics_name], true, false) as Node3D
		if physics_wheel == null or visual_wheel == null:
			push_warning("WheelSync: could not pair '%s'." % physics_name)
			continue
		_physics_wheels.append(physics_wheel)
		_visual_wheels.append(visual_wheel)

	if _physics_wheels.is_empty():
		set_process(false)


func _process(_delta: float) -> void:
	for i: int in _physics_wheels.size():
		_visual_wheels[i].global_transform = _physics_wheels[i].global_transform
