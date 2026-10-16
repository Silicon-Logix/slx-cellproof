# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends SubViewportContainer

signal camera_changed

const JOINTS := ["shoulder_pan_joint", "shoulder_lift_joint", "elbow_joint", "wrist_1_joint", "wrist_2_joint", "wrist_3_joint"]
var view: SubViewport
var world: Node3D
var cell: Node3D
var camera: Camera3D
var nodes: Dictionary = {}
var original: Dictionary = {}
var markers: Node3D
var obstruction: MeshInstance3D
var trace: MeshInstance3D
var angle := -2.3
var elevation := 0.46
var distance := 4.8
var target := Vector3(0.45, 0.90, 0.0)
var dragging := false
var show_markers := false
var selected_part := ""

func _ready() -> void:
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	view = SubViewport.new()
	view.size = Vector2i(1000, 720)
	view.handle_input_locally = false
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	view.msaa_3d = Viewport.MSAA_2X
	add_child(view)
	world = Node3D.new()
	view.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("e7ecf4")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("e0e6f2")
	settings.ambient_light_energy = 0.85
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 140, 0)
	fill.light_energy = 0.35
	world.add_child(fill)
	var scene: PackedScene = load("res://assets/workcell.glb")
	cell = scene.instantiate()
	world.add_child(cell)
	_index(cell)
	for key in nodes:
		if str(key).contains("factory_backdrop_root"):
			nodes[key].visible = false
	for item in cell.find_children("*", "AnimationPlayer", true, false):
		# Presentation tracks must never override state received from the core.
		item.stop()
		item.active = false
	for item in cell.find_children("*", "Camera3D", true, false):
		item.current = false
	for item in cell.find_children("*", "Light3D", true, false):
		item.visible = false
	camera = Camera3D.new()
	camera.fov = 44
	camera.near = 0.05
	camera.far = 100
	world.add_child(camera)
	camera.current = true
	markers = Node3D.new()
	markers.visible = show_markers
	world.add_child(markers)
	obstruction = MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.45, 0.12, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	obstruction.material_override = material
	obstruction.visible = false
	world.add_child(obstruction)
	trace = MeshInstance3D.new()
	world.add_child(trace)
	set_guards(false)
	_update_camera()

func _index(node: Node) -> void:
	if node is Node3D:
		nodes[node.name] = node
		original[node.name] = node.transform
	for child in node.get_children():
		_index(child)

func _update_camera() -> void:
	camera.position = target + Vector3(cos(angle) * cos(elevation), sin(elevation), sin(angle) * cos(elevation)) * distance
	camera.look_at(target)

func _gui_input(event: InputEvent) -> void:
	var previous := Vector3(angle, elevation, distance)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(1.4, distance * 0.92)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(9.0, distance * 1.08)
		_update_camera()
	elif event is InputEventMouseMotion and dragging:
		angle -= event.relative.x * 0.006
		elevation = clampf(elevation + event.relative.y * 0.006, 0.05, 1.25)
		_update_camera()
	if previous != Vector3(angle, elevation, distance):
		camera_changed.emit()

func set_guards(visible_guard: bool) -> void:
	for key in nodes:
		if str(key).begins_with("guard_") or str(key).begins_with("RuntimeRigid_guard_") or str(key).contains("cell_guard_root") or str(key).contains("access_gate_joint"):
			nodes[key].visible = visible_guard

func set_points(points: Dictionary) -> void:
	if markers == null:
		return
	for child in markers.get_children():
		child.queue_free()
	for key in points:
		var p: Array = points[key].tcp_xyz_m
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.012
		sphere.height = 0.024
		marker.mesh = sphere
		marker.position = Vector3(p[0], p[2], -p[1])
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("5354e8")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = material
		markers.add_child(marker)
		var label := Label3D.new()
		label.text = key
		label.font_size = 20
		label.pixel_size = 0.001
		label.position = marker.position + Vector3(0, 0.035, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		markers.add_child(label)

func apply_state(state: Dictionary) -> void:
	if nodes.is_empty():
		return
	apply_joints(state.get("joints_rad", []))
	var door: Node3D = nodes.get("cnc_door_joint")
	if door:
		door.position = Vector3(original.cnc_door_joint.origin.x, original.cnc_door_joint.origin.y, -float(state.get("door_position_m", 0.85)))
	var jaw := float(state.get("jaw_closure", 0)) * 0.01
	for key in ["CP_Gripper_JawLeft", "CP_Gripper_JawRight"]:
		if nodes.has(key):
			nodes[key].position = original[key].origin + Vector3(jaw if key.ends_with("Left") else -jaw, 0, 0)
	var variant: String = state.get("part_variant", "A")
	var part_name := "CP_Part_B_8" if variant == "B" else ("CP_Part_C_2" if variant == "C" else "CP_Part_A_5")
	if selected_part != part_name and nodes.has(selected_part):
		nodes[selected_part].transform = original[selected_part]
		nodes[selected_part].visible = true
	selected_part = part_name
	if nodes.has(part_name):
		nodes[part_name].visible = state.get("part_available", true)
	if nodes.has(part_name) and state.has("part_pose"):
		var pose: Dictionary = state.part_pose
		var xyz: Array = pose.tcp_xyz_m
		var q: Array = pose.tcp_quaternion_xyzw
		var basis_change := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
		# Incoming REP-103 poses need a basis change; imported GLB meshes do not.
		var basis := basis_change * Basis(Quaternion(q[0], q[1], q[2], q[3])) * basis_change.inverse()
		nodes[part_name].global_transform = Transform3D(basis, Vector3(xyz[0], xyz[2], -xyz[1]))
	var config: Dictionary = state.get("configuration", {})
	var proxy = config.get("obstruction")
	obstruction.visible = proxy is Dictionary
	if proxy is Dictionary:
		var box := BoxMesh.new()
		box.size = Vector3(proxy.size_m[0], proxy.size_m[2], proxy.size_m[1])
		obstruction.mesh = box
		obstruction.position = Vector3(proxy.center_m[0], proxy.center_m[2], -proxy.center_m[1])
	if nodes.has("cnc_fixture_frame"):
		var offset: Array = config.get("cnc_offset_m", [0, 0, 0])
		nodes.cnc_fixture_frame.position = original.cnc_fixture_frame.origin + Vector3(offset[0], offset[2], -offset[1])

func apply_joints(joints: Array) -> void:
	# Imported motion nodes rotate about local Y; their fixed origins stay intact.
	if joints.size() != 6:
		return
	for index in range(6):
		if nodes.has(JOINTS[index]):
			nodes[JOINTS[index]].rotation = Vector3(0, joints[index], 0)

func set_trace_path(frames: Array, color: Color) -> void:
	if trace == null:
		return
	trace.mesh = null
	if frames.size() < 2:
		return
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for frame in frames:
		var p: Array = frame.tcp.tcp_xyz_m
		mesh.surface_add_vertex(Vector3(p[0], p[2], -p[1]))
	mesh.surface_end()
	trace.mesh = mesh
