class_name PrototypeController
extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/main/prototype_unit.tscn")
const GRID_SIZE := Vector2i(12, 10)
const CELL_SIZE := 2.0
const MOVE_ACTION_COST := 1
const PLAYER_COLOR := Color("4f9dff")
const ENEMY_COLOR := Color("ef5b5b")
const FALLBACK_BLOCKED_CELLS: Array[Vector2i] = [
	Vector2i(4, 1),
	Vector2i(4, 2),
	Vector2i(4, 3),
	Vector2i(4, 5),
	Vector2i(4, 6),
	Vector2i(4, 7),
	Vector2i(8, 3),
	Vector2i(8, 4),
	Vector2i(8, 5),
	Vector2i(2, 4),
	Vector2i(6, 2),
	Vector2i(6, 6),
	Vector2i(9, 7),
]

var grid: GridModel
var selected_unit: PrototypeUnit
var units_by_id: Dictionary = {}
var world_tick := 0
var input_locked := false

@onready var units_root: Node3D = $Units
@onready var highlights_root: Node3D = $MoveHighlights
@onready var selection_label: Label = $HUD/TopLeftPanel/Margin/VBox/SelectionLabel
@onready var phase_label: Label = $HUD/TopLeftPanel/Margin/VBox/PhaseLabel
@onready var hint_label: Label = $HUD/TopLeftPanel/Margin/VBox/HintLabel
@onready var end_turn_button: Button = $HUD/TopLeftPanel/Margin/VBox/EndTurnButton


func _ready() -> void:
	grid = GridModel.new()
	grid.configure(GRID_SIZE, CELL_SIZE, Vector3.ZERO)
	_apply_environment_blockers()
	_spawn_initial_units()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	_select_unit(_find_player_at(Vector2i(1, 1)))
	_update_hud("选择蓝色单位，然后点击高亮格移动。")


func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_handle_world_click(mouse_event.position)


func _apply_environment_blockers() -> void:
	var blocker_count := 0
	for blocker in get_tree().get_nodes_in_group(&"grid_blocker"):
		if not blocker.has_meta(&"grid_cell"):
			continue
		var cell_value: Variant = blocker.get_meta(&"grid_cell")
		if cell_value is Vector2i and grid.set_walkable(cell_value, false):
			blocker_count += 1

	if blocker_count > 0:
		return
	for cell in FALLBACK_BLOCKED_CELLS:
		grid.set_walkable(cell, false)


func _spawn_initial_units() -> void:
	_spawn_unit(&"PlayerAlpha", Vector2i(1, 1), &"player", PLAYER_COLOR)
	_spawn_unit(&"PlayerBravo", Vector2i(2, 1), &"player", PLAYER_COLOR.lightened(0.12))
	_spawn_unit(&"EnemyScout", Vector2i(7, 2), &"enemy", ENEMY_COLOR)
	_spawn_unit(&"EnemyGuard", Vector2i(10, 7), &"enemy", ENEMY_COLOR.darkened(0.08))


func _spawn_unit(
		unit_name: StringName,
		cell: Vector2i,
		faction: StringName,
		color: Color
) -> PrototypeUnit:
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	unit.name = unit_name
	unit.configure(cell, faction, color)
	units_root.add_child(unit)
	unit.global_position = grid.cell_to_world(cell)
	unit.action_points_changed.connect(_on_unit_action_points_changed)
	if not grid.occupy(cell, unit.unit_id):
		push_error("Failed to occupy %s for %s" % [cell, unit.name])
	units_by_id[unit.unit_id] = unit
	return unit


func _handle_world_click(screen_position: Vector2) -> void:
	var clicked_cell := _screen_to_cell(screen_position)
	if not grid.in_bounds(clicked_cell):
		_update_hud("点击位置在地图范围外。")
		return

	var clicked_player := _find_player_at(clicked_cell)
	if is_instance_valid(clicked_player):
		_select_unit(clicked_player)
		_update_hud("已选择 %s。" % clicked_player.name)
		return

	if not is_instance_valid(selected_unit):
		_update_hud("请先选择一个蓝色单位。")
		return
	if not selected_unit.can_spend_action_points(MOVE_ACTION_COST):
		_update_hud("该单位 AP 不足，请结束回合。")
		return

	var reachable_cells := grid.get_reachable_cells(
		selected_unit.grid_cell,
		selected_unit.move_range
	)
	if clicked_cell not in reachable_cells or clicked_cell == selected_unit.grid_cell:
		_update_hud("目标格不可到达或已被占用。")
		return

	await _move_selected_unit(clicked_cell)


func _move_selected_unit(destination: Vector2i) -> void:
	var path := grid.find_path(selected_unit.grid_cell, destination)
	if path.size() < 2:
		_update_hud("没有可用路径。")
		return

	var moving_unit := selected_unit
	var start_cell := moving_unit.grid_cell
	if not grid.vacate(start_cell, moving_unit.unit_id):
		_update_hud("起点占用状态异常，移动已取消。")
		return
	if not grid.occupy(destination, moving_unit.unit_id):
		grid.occupy(start_cell, moving_unit.unit_id)
		_update_hud("目标格已被占用，移动已取消。")
		return

	input_locked = true
	end_turn_button.disabled = true
	_clear_move_highlights()
	moving_unit.spend_action_points(MOVE_ACTION_COST)

	var world_points: Array[Vector3] = []
	for path_index in range(1, path.size()):
		world_points.append(grid.cell_to_world(path[path_index]))
	await moving_unit.move_along_world_path(world_points, destination)

	input_locked = false
	end_turn_button.disabled = false
	_refresh_move_highlights()
	_update_hud("%s 移动到 %s，消耗 %d AP。" % [
		moving_unit.name,
		destination,
		MOVE_ACTION_COST,
	])


func _select_unit(unit: PrototypeUnit) -> void:
	if is_instance_valid(selected_unit):
		selected_unit.set_selected(false)
	selected_unit = unit
	if is_instance_valid(selected_unit):
		selected_unit.set_selected(true)
	_refresh_move_highlights()
	_update_hud()


func _find_player_at(cell: Vector2i) -> PrototypeUnit:
	var occupant_id := grid.get_occupant(cell)
	if occupant_id.is_empty() or not units_by_id.has(occupant_id):
		return null
	var unit := units_by_id[occupant_id] as PrototypeUnit
	if unit.faction != &"player":
		return null
	return unit


func _refresh_move_highlights() -> void:
	_clear_move_highlights()
	if not is_instance_valid(selected_unit):
		return
	if not selected_unit.can_spend_action_points(MOVE_ACTION_COST):
		return

	var highlight_material := StandardMaterial3D.new()
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.albedo_color = Color(0.2, 0.72, 1.0, 0.34)
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for cell in grid.get_reachable_cells(selected_unit.grid_cell, selected_unit.move_range):
		if cell == selected_unit.grid_cell:
			continue
		var highlight_mesh := BoxMesh.new()
		highlight_mesh.size = Vector3(CELL_SIZE * 0.88, 0.035, CELL_SIZE * 0.88)
		var highlight := MeshInstance3D.new()
		highlight.name = "Cell_%d_%d" % [cell.x, cell.y]
		highlight.mesh = highlight_mesh
		highlight.material_override = highlight_material
		highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		highlight.position = grid.cell_to_world(cell) + Vector3.UP * 0.025
		highlights_root.add_child(highlight)


func _clear_move_highlights() -> void:
	for child in highlights_root.get_children():
		highlights_root.remove_child(child)
		child.queue_free()


func _screen_to_cell(screen_position: Vector2) -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return Vector2i(-1, -1)
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) < 0.0001:
		return Vector2i(-1, -1)
	var distance_to_ground := -ray_origin.y / ray_direction.y
	if distance_to_ground < 0.0:
		return Vector2i(-1, -1)
	return grid.world_to_cell(ray_origin + ray_direction * distance_to_ground)


func _on_end_turn_pressed() -> void:
	if input_locked:
		return
	world_tick += 1
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == &"player":
			unit.reset_action_points()
	_refresh_move_highlights()
	_update_hud("世界 Tick %d：敌方原型暂时仅占位，玩家 AP 已重置。" % world_tick)


func _on_unit_action_points_changed(_current: int, _maximum: int) -> void:
	_update_hud()


func _update_hud(message: String = "") -> void:
	phase_label.text = "探索阶段 · 世界 Tick %d" % world_tick
	if is_instance_valid(selected_unit):
		selection_label.text = "%s  |  HP %d/%d  |  AP %d/%d  |  格 %s" % [
			selected_unit.name,
			selected_unit.current_hp,
			selected_unit.max_hp,
			selected_unit.current_action_points,
			selected_unit.max_action_points,
			selected_unit.grid_cell,
		]
	else:
		selection_label.text = "未选择单位"
	if not message.is_empty():
		hint_label.text = message
