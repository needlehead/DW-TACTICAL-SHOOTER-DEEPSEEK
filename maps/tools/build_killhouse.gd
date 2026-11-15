extends Node
## Generates res://maps/killhouse.tscn from the layout below (CSG greybox).
## Run: godot --headless --path . res://maps/tools/build_killhouse.tscn
## Rerunning overwrites manual edits to killhouse.tscn; edit the layout here or the scene, not both.

const OUT := "res://maps/killhouse.tscn"
const H := 3.0  # wall height
const T := 0.25  # solid wall
const THIN := 0.1  # penetrable wall
const DOOR := [1.1, 0.0, 2.2]  # [width, bottom, top]
const DOORWAY := [1.4, 0.0, 2.3]
const WINDOW := [1.2, 0.9, 2.1]
const RANGE_Z := 14.0  # firing line

var root: Node3D
var mats := {}


func _ready() -> void:
	root = Node3D.new()
	root.name = "Killhouse"
	_environment()
	var nav := NavigationRegion3D.new()
	nav.name = "NavigationRegion3D"
	var nm := NavigationMesh.new()
	# Multiples of the default 0.25 m cell size/height.
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Ballistics.WORLD
	nav.navigation_mesh = nm
	_box(nav, "Ground", Vector3(0, -0.5, 30), Vector3(300, 1, 300), "ground")
	_house(_group(nav, "House"))
	await _bake(nav)
	root.add_child(nav)
	_range(_group(root, "Range"))
	_doors(_group(root, "Doors"))
	_dummies(_group(root, "Dummies"))
	var player: Node3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(0, 0.05, RANGE_Z - 1.5)
	player.rotation.y = PI  # face down the range (+Z)
	root.add_child(player)
	_own(root)

	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("build_killhouse: %s, navmesh %d polygons" % [error_string(err), nm.get_polygon_count()])
	root.free()
	get_tree().quit(err)


## Bakes in the builder so the scene ships with a navmesh. CSG needs a couple of frames in the
## tree before its collision exists. After editing the level, use "Bake NavigationMesh" in the editor.
func _bake(nav: NavigationRegion3D) -> void:
	add_child(nav)
	var src := NavigationMeshSourceGeometryData3D.new()
	for i in 10:
		await get_tree().physics_frame
		NavigationServer3D.parse_source_geometry_data(nav.navigation_mesh, src, nav)
		if src.has_data():
			break
	NavigationServer3D.bake_from_source_geometry_data(nav.navigation_mesh, src)
	remove_child(nav)


## Owns every built node to root so pack() saves it; instanced scenes keep their own children.
func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = root
		if c.scene_file_path.is_empty():
			_own(c)


func _house(p: Node3D) -> void:
	# 24 x 18 m: central hallway (z -1.25..1.25), four rooms north (N1..N4) and four south (S1..S4).
	_wall(p, "ExtNorth", Vector2(-12, 9), Vector2(12, 9), [[3.0, WINDOW], [15.0, WINDOW], [21.0, DOORWAY]])
	_wall(p, "ExtSouth", Vector2(-12, -9), Vector2(12, -9), [[3.0, DOOR], [9.0, WINDOW], [21.0, WINDOW]])
	_wall(p, "ExtWest", Vector2(-12, -9), Vector2(-12, 9), [[9.0, DOORWAY], [14.0, WINDOW]])
	_wall(p, "ExtEast", Vector2(12, -9), Vector2(12, 9), [[4.0, WINDOW], [9.0, DOORWAY]])
	_wall(p, "HallNorth", Vector2(-12, 1.25), Vector2(12, 1.25), [[3.0, DOOR], [9.0, DOORWAY], [15.0, DOOR], [21.0, DOORWAY]])
	_wall(p, "HallSouth", Vector2(-12, -1.25), Vector2(12, -1.25), [[2.0, DOORWAY], [9.0, DOOR], [15.0, DOORWAY], [21.0, DOOR]])
	# Room dividers. Thin ones are penetrable test walls.
	_wall(p, "DivN1N2", Vector2(-6, 1.25), Vector2(-6, 9), [[3.75, DOORWAY]])
	_wall(p, "DivN2N3_Thin", Vector2(0, 1.25), Vector2(0, 9), [], true)
	_wall(p, "DivN3N4", Vector2(6, 1.25), Vector2(6, 9), [[3.75, WINDOW]])
	_wall(p, "DivS1S2_Thin", Vector2(-6, -9), Vector2(-6, -1.25), [[4.0, DOORWAY]], true)
	_wall(p, "DivS2S3", Vector2(0, -9), Vector2(0, -1.25), [[3.0, DOORWAY]])
	_wall(p, "DivS3S4_Thin", Vector2(6, -9), Vector2(6, -1.25), [], true)
	# Cover: 1 m crates are vaultable.
	_box(p, "CrateN2", Vector3(-3, 0.5, 6), Vector3(1.2, 1, 1.2), "crate")
	_box(p, "CrateS3", Vector3(3, 0.5, -6.5), Vector3(2, 1, 0.8), "crate")
	_box(p, "PillarN4", Vector3(9, H * 0.5, 5), Vector3(0.6, H, 0.6), "wall")
	_box(p, "CrateHall", Vector3(4, 0.5, 0.6), Vector3(0.9, 1, 0.6), "crate")
	_box(p, "CrateOutside", Vector3(-15, 0.5, -4), Vector3(1.2, 1, 2.4), "crate")


func _range(p: Node3D) -> void:
	_box(p, "FiringLine", Vector3(0, 0.01, RANGE_Z), Vector3(12, 0.02, 0.15), "marker").use_collision = false
	_label(p, "FIRING LINE", Vector3(-4.5, 2.0, RANGE_Z))
	_box(p, "BermWest", Vector3(-6.5, 1.25, RANGE_Z + 57), Vector3(1, 2.5, 110), "berm")
	_box(p, "BermEast", Vector3(6.5, 1.25, RANGE_Z + 57), Vector3(1, 2.5, 110), "berm")
	_box(p, "Backstop", Vector3(0, 3, RANGE_Z + 113), Vector3(14, 6, 1), "berm")
	var lanes := {10: -3.0, 25: -1.0, 50: 1.0, 100: 3.0}
	for dist: int in lanes:
		var z := RANGE_Z + dist
		_box(p, "Marker%d" % dist, Vector3(5.6, 0.75, z), Vector3(0.15, 1.5, 0.15), "marker")
		_label(p, "%d m" % dist, Vector3(lanes[dist], 2.5, z))
	# Penetration test: a dummy behind a thin board at 15 m.
	_box(p, "PenBoard_Thin", Vector3(4.5, 1.0, RANGE_Z + 14.4), Vector3(1.6, 2.0, THIN), "thin", Ballistics.WORLD | Ballistics.PENETRABLE)
	_label(p, "penetration", Vector3(4.5, 2.4, RANGE_Z + 14.4))


func _doors(p: Node3D) -> void:
	var door: PackedScene = load("res://maps/door.tscn")
	# Hinge at the left edge of each DOOR opening (opening centre - 0.5).
	for pos: Vector3 in [Vector3(-9.5, 0, 1.25), Vector3(2.5, 0, 1.25), Vector3(-3.5, 0, -1.25), Vector3(8.5, 0, -1.25), Vector3(-9.5, 0, -9)]:
		var d: Node3D = door.instantiate()
		d.position = pos
		_add(p, d)


func _dummies(p: Node3D) -> void:
	var scene: PackedScene = load("res://ai/dummy.tscn")
	var range_grey := Color(0.55, 0.55, 0.5)
	# Range targets: never shoot back.
	for spot: Vector3 in [Vector3(-3, 0, RANGE_Z + 10), Vector3(-1, 0, RANGE_Z + 25), Vector3(1, 0, RANGE_Z + 50), Vector3(3, 0, RANGE_Z + 100), Vector3(4.5, 0, RANGE_Z + 15)]:
		_dummy(p, scene, "Range", spot, 0.0, false, range_grey)  # yaw 0 faces -Z, toward the firing line
	# Stationary room dummies (one in S4 sits behind the thin S3/S4 wall).
	for spot: Vector3 in [Vector3(-9, 0, -6), Vector3(-3, 0, -6), Vector3(3, 0, 6), Vector3(9, 0, 3), Vector3(9, 0, -5)]:
		_dummy(p, scene, "Room", spot, 0.0, true, Color(0.8, 0.45, 0.3))
	# Patrols: hallway, N1<->N2 through the doorway, and outside along the south wall.
	var routes := [
		PackedVector3Array([Vector3(-10.5, 0, 0), Vector3(10.5, 0, 0)]),
		PackedVector3Array([Vector3(-9, 0, 5), Vector3(-3, 0, 3.5)]),
		PackedVector3Array([Vector3(-16, 0, -12), Vector3(16, 0, -12)]),
	]
	for route: PackedVector3Array in routes:
		var d := _dummy(p, scene, "Patrol", route[0], 0.0, true, Color(0.55, 0.35, 0.75))
		d.set("patrol_points", route)


func _dummy(p: Node3D, scene: PackedScene, kind: String, pos: Vector3, yaw: float, shoots: bool, color: Color) -> Node3D:
	var d: Node3D = scene.instantiate()
	d.name = "%s%d" % [kind, p.get_child_count()]
	d.position = pos
	d.rotation.y = yaw
	d.set("shoots_back", shoots)
	d.set("body_color", color)
	_add(p, d)
	return d


## Axis-aligned wall from a to b (x,z) split around openings: [distance_from_a, [width, bottom, top]].
func _wall(p: Node3D, wall_name: String, a: Vector2, b: Vector2, openings: Array, thin := false) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var thick := THIN if thin else T
	var layer := Ballistics.WORLD | (Ballistics.PENETRABLE if thin else 0)
	var mat := "thin" if thin else "wall"
	var pieces := []  # [t0, t1, y0, y1]
	var cursor := 0.0
	for o: Array in openings:
		var c: float = o[0]
		var spec: Array = o[1]
		var s: float = c - spec[0] * 0.5
		var e: float = c + spec[0] * 0.5
		pieces.append([cursor, s, 0.0, H])
		if spec[1] > 0.0:
			pieces.append([s, e, 0.0, spec[1]])
		if spec[2] < H:
			pieces.append([s, e, spec[2], H])
		cursor = e
	pieces.append([cursor, length, 0.0, H])
	var i := 0
	for pc: Array in pieces:
		var t0: float = pc[0]
		var t1: float = pc[1]
		var y0: float = pc[2]
		var y1: float = pc[3]
		if t1 - t0 < 0.01:
			continue
		# Pad ends by half a thickness so corners close.
		var pad0 := thick * 0.5 if t0 == 0.0 else 0.0
		var pad1 := thick * 0.5 if t1 == length else 0.0
		var mid := a + dir * ((t0 - pad0 + t1 + pad1) * 0.5)
		var along := t1 - t0 + pad0 + pad1
		var size := Vector3(along, y1 - y0, thick) if absf(dir.x) > 0.5 else Vector3(thick, y1 - y0, along)
		_box(p, "%s_%d" % [wall_name, i], Vector3(mid.x, (y0 + y1) * 0.5, mid.y), size, mat, layer)
		i += 1


func _box(p: Node3D, box_name: String, pos: Vector3, size: Vector3, mat: String, layer := Ballistics.WORLD) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = box_name
	b.position = pos
	b.size = size
	b.use_collision = true
	b.collision_layer = layer
	b.collision_mask = 0
	b.material = _mat(mat)
	_add(p, b)
	return b


func _mat(key: String) -> StandardMaterial3D:
	if not mats.has(key):
		var colors := {
			"ground": Color(0.42, 0.45, 0.38), "wall": Color(0.78, 0.76, 0.72), "thin": Color(0.85, 0.7, 0.45),
			"crate": Color(0.5, 0.42, 0.3), "berm": Color(0.45, 0.4, 0.33), "marker": Color(0.95, 0.85, 0.2),
		}
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[key]
		mats[key] = m
	return mats[key]


func _label(p: Node3D, text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.name = "Label_" + text.replace(" ", "_")
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.outline_size = 12
	_add(p, l)


func _group(p: Node3D, group_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	_add(p, n)
	return n


func _environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	_add(root, sun)
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(root, we)


func _add(p: Node, n: Node) -> void:
	p.add_child(n)
