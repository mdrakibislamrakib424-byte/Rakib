extends SceneTree
func _initialize() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	(main.get_node("PlaceLoader") as PlaceLoader).place_id = "does_not_exist"
	root.add_child(main)
	await create_timer(1.5).timeout
	var car: CarController = get_first_node_in_group("car")
	print("FALLBACK car y=%.2f (flat ground expected ~ -0.1)" % car.global_position.y)
	quit()
