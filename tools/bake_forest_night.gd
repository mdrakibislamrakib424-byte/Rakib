extends SceneTree
## One-time baker: turns the 1480-mesh Sketchfab forest into a game-ready scene.
##   godot --headless --path . -s res://tools/bake_forest_night.gd
## Result: assets/places/forest_night/forest_night_baked.scn
##   - everything scaled up (the source model is a 19 m diorama)
##   - 1394 foliage cards + 85 trunks merged into a few chunks per material (fewer draw calls,
##     frustum culling per chunk)
##   - foliage uses alpha-scissor instead of alpha-blend (much cheaper on phones)
##   - trimesh collision for the terrain + invisible walls around it
##   - SpawnPoint marker on the dirt track, facing along the track

const SRC: String = "res://assets/places/forest_night/forest_night.glb"
const OUT: String = "res://assets/places/forest_night/forest_night_baked.scn"
const SCALE: float = 20.0
const CHUNK_SIZE: float = 48.0
## The source terrain has tiny bumps that become 1-2 m dents after scaling. The heights are
## averaged over this radius (metres) so a car can drive over it. Big hills are kept.
const SMOOTH_RADIUS: float = 9.0
const TERRAIN_MAT: String = "Material.003"
const TRUNK_MAT: String = "Material.004"
const FOLIAGE_MAT: String = "Material"
## Points on the dirt track, as UV positions on the terrain texture (start -> end).
const TRACK_UV: Array[Vector2] = [
	Vector2(0.77, 0.93), Vector2(0.78, 0.86), Vector2(0.70, 0.77), Vector2(0.55, 0.68),
	Vector2(0.39, 0.61), Vector2(0.29, 0.52), Vector2(0.28, 0.42), Vector2(0.35, 0.30),
	Vector2(0.49, 0.20), Vector2(0.61, 0.08),
]


var _t_xz: PackedVector2Array = PackedVector2Array()
var _t_delta: PackedFloat32Array = PackedFloat32Array()


func _initialize() -> void:
	var src_root: Node3D = (load(SRC) as PackedScene).instantiate()
	get_root().add_child(src_root)
	await process_frame

	var groups: Dictionary = {TERRAIN_MAT: [], TRUNK_MAT: [], FOLIAGE_MAT: []}
	for node: Node in src_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		var mat: Material = mi.mesh.surface_get_material(0)
		var key: String = String(mat.resource_name) if mat else ""
		if groups.has(key):
			groups[key].append(mi)
	print("terrain=%d trunks=%d foliage=%d" % [
		groups[TERRAIN_MAT].size(), groups[TRUNK_MAT].size(), groups[FOLIAGE_MAT].size()])

	# Lowest terrain point becomes y = 0.
	var terrain_mi: MeshInstance3D = groups[TERRAIN_MAT][0]
	var t_aabb: AABB = terrain_mi.global_transform * terrain_mi.mesh.get_aabb()
	var shift: Vector3 = Vector3(0.0, -t_aabb.position.y * SCALE, 0.0)
	var world_xf: Transform3D = Transform3D(Basis().scaled(Vector3.ONE * SCALE), shift)
	var terrain_world: AABB = world_xf * t_aabb
	print("terrain world aabb: ", terrain_world)

	var place: Node3D = Node3D.new()
	place.name = "Place"

	# --- Terrain -------------------------------------------------------------
	var terrain_mat: StandardMaterial3D = terrain_mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	terrain_mat.roughness = 0.92   # the source has roughness 0 (mirror-like dirt)
	var arrays: Array = terrain_mi.mesh.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var to_world: Transform3D = world_xf * terrain_mi.global_transform
	var world_verts: PackedVector3Array = PackedVector3Array()
	for v: Vector3 in src_verts:
		world_verts.append(to_world * v)
	var smooth_y: PackedFloat32Array = _smooth_heights(world_verts, SMOOTH_RADIUS)
	_t_xz = PackedVector2Array()
	_t_delta = PackedFloat32Array()
	for i: int in world_verts.size():
		_t_xz.append(Vector2(world_verts[i].x, world_verts[i].z))
		_t_delta.append(smooth_y[i] - world_verts[i].y)
		world_verts[i].y = smooth_y[i]
	arrays[Mesh.ARRAY_VERTEX] = world_verts
	var tmp: ArrayMesh = ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st: SurfaceTool = SurfaceTool.new()
	st.create_from(tmp, 0)
	st.set_material(terrain_mat)
	st.generate_normals()
	st.generate_tangents()
	var terrain_mesh: ArrayMesh = st.commit()
	var terrain_node: MeshInstance3D = MeshInstance3D.new()
	terrain_node.name = "Terrain"
	terrain_node.mesh = terrain_mesh
	terrain_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(place, terrain_node, place)

	# --- Collision -----------------------------------------------------------
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TerrainBody"
	_add(place, body, place)
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	shape_node.name = "TerrainShape"
	shape_node.shape = terrain_mesh.create_trimesh_shape()
	_add(body, shape_node, place)
	_add_walls(body, place, terrain_world)

	# --- Foliage and trunks, merged into spatial chunks -------------------------
	var foliage_mat: StandardMaterial3D = (groups[FOLIAGE_MAT][0] as MeshInstance3D).mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	foliage_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	foliage_mat.alpha_scissor_threshold = 0.5
	foliage_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	foliage_mat.roughness = 1.0
	var trunk_mat: StandardMaterial3D = (groups[TRUNK_MAT][0] as MeshInstance3D).mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	trunk_mat.roughness = 1.0
	_bake_chunks(place, "Foliage", groups[FOLIAGE_MAT], foliage_mat, world_xf, terrain_world, false)
	_bake_chunks(place, "Trunks", groups[TRUNK_MAT], trunk_mat, world_xf, terrain_world, true)

	# --- Spawn point on the track ---------------------------------------------
	var uv_lookup: Array = _uv_to_world(terrain_mesh)
	var track: Array[Vector3] = []
	for uv: Vector2 in TRACK_UV:
		track.append(_world_at_uv(uv_lookup, uv))
	var prev: Vector3 = track[0]
	for i: int in range(1, track.size()):
		var flat: float = Vector2(track[i].x - prev.x, track[i].z - prev.z).length()
		print("track %d: pos=%s  length=%.0f m  grade=%.0f%%" % [
			i, track[i].snapped(Vector3(0.1, 0.1, 0.1)), flat, 100.0 * (track[i].y - prev.y) / maxf(flat, 0.01)])
		prev = track[i]
	var dir: Vector3 = track[1] - track[0]
	var yaw: float = atan2(dir.x, dir.z)   # the car drives towards +Z
	var spawn: Marker3D = Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.transform = Transform3D(Basis(Vector3.UP, yaw), track[0] + Vector3.UP * 1.5)
	_add(place, spawn, place)
	print("spawn at ", spawn.position, " yaw(deg)=", rad_to_deg(yaw))

	var packed: PackedScene = PackedScene.new()
	print("pack: ", packed.pack(place))
	print("save: ", ResourceSaver.save(packed, OUT))
	quit()


func _add(parent: Node, child: Node, scene_owner: Node) -> void:
	parent.add_child(child)
	child.owner = scene_owner


func _add_walls(body: StaticBody3D, scene_owner: Node, area: AABB) -> void:
	var c: Vector3 = area.get_center()
	var h: float = 60.0
	var t: float = 2.0
	var walls: Array = [
		[Vector3(c.x, area.position.y + h * 0.5, area.position.z - t * 0.5), Vector3(area.size.x + 2.0 * t, h, t)],
		[Vector3(c.x, area.position.y + h * 0.5, area.end.z + t * 0.5), Vector3(area.size.x + 2.0 * t, h, t)],
		[Vector3(area.position.x - t * 0.5, area.position.y + h * 0.5, c.z), Vector3(t, h, area.size.z + 2.0 * t)],
		[Vector3(area.end.x + t * 0.5, area.position.y + h * 0.5, c.z), Vector3(t, h, area.size.z + 2.0 * t)],
	]
	for i: int in walls.size():
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.name = "Wall%d" % i
		var box: BoxShape3D = BoxShape3D.new()
		box.size = walls[i][1]
		cs.shape = box
		cs.position = walls[i][0]
		_add(body, cs, scene_owner)


func _bake_chunks(place: Node3D, prefix: String, meshes: Array, mat: Material,
		world_xf: Transform3D, area: AABB, tangents: bool) -> void:
	var cells: Dictionary = {}
	for mi: MeshInstance3D in meshes:
		var center: Vector3 = (world_xf * (mi.global_transform * mi.mesh.get_aabb())).get_center()
		# Follow the smoothed ground so trees do not float or sink.
		var lift: Transform3D = Transform3D(Basis(), Vector3(0.0, _delta_at(center.x, center.z), 0.0))
		var xf: Transform3D = lift * world_xf * mi.global_transform
		var cell: Vector2i = Vector2i(
			int(floorf((center.x - area.position.x) / CHUNK_SIZE)),
			int(floorf((center.z - area.position.z) / CHUNK_SIZE)))
		if not cells.has(cell):
			var st: SurfaceTool = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mat)
			cells[cell] = st
		(cells[cell] as SurfaceTool).append_from(mi.mesh, 0, xf)
	var total_verts: int = 0
	for cell: Vector2i in cells:
		var st2: SurfaceTool = cells[cell]
		st2.index()
		if tangents:
			st2.generate_tangents()
		var mesh: ArrayMesh = st2.commit()
		total_verts += mesh.surface_get_array_len(0)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "%s_%d_%d" % [prefix, cell.x, cell.y]
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(place, node, place)
	print("%s: %d meshes -> %d chunks, %d vertices" % [prefix, meshes.size(), cells.size(), total_verts])


## Pairs of [uv, world position] for every terrain vertex.
func _uv_to_world(mesh: ArrayMesh) -> Array:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var out: Array = []
	for i: int in verts.size():
		out.append([uvs[i], verts[i]])
	return out


func _world_at_uv(lookup: Array, uv: Vector2) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_d: float = INF
	for pair: Array in lookup:
		var d: float = (pair[0] as Vector2).distance_squared_to(uv)
		if d < best_d:
			best_d = d
			best = pair[1]
	return best


## Weighted average of the vertex heights within `radius` metres (cone weights).
func _smooth_heights(verts: PackedVector3Array, radius: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(verts.size())
	var r2: float = radius * radius
	for i: int in verts.size():
		var sum: float = 0.0
		var weight_sum: float = 0.0
		for j: int in verts.size():
			var dx: float = verts[j].x - verts[i].x
			var dz: float = verts[j].z - verts[i].z
			var d2: float = dx * dx + dz * dz
			if d2 < r2:
				var w: float = 1.0 - sqrt(d2) / radius
				sum += verts[j].y * w
				weight_sum += w
		out[i] = sum / weight_sum
	return out


func _delta_at(x: float, z: float) -> float:
	var best: float = INF
	var best_delta: float = 0.0
	var p: Vector2 = Vector2(x, z)
	for i: int in _t_xz.size():
		var d: float = _t_xz[i].distance_squared_to(p)
		if d < best:
			best = d
			best_delta = _t_delta[i]
	return best_delta
