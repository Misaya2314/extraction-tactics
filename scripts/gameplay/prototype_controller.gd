class_name PrototypeController
extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/main/prototype_unit.tscn")
const MOVE_ACTION_COST := 1
const PLAYER_COLOR := Color("4f9dff")
const ENEMY_COLOR := Color("ef5b5b")
const MOVE_HIGHLIGHT_COLOR := Color(0.2, 0.72, 1.0, 0.34)
const ATTACK_HIGHLIGHT_COLOR := Color(1.0, 0.23, 0.16, 0.48)
const MOVE_HIGHLIGHT_SURFACE_OFFSET := 0.025

@export var map_definition: TacticalMapDefinition

var grid: GridModel
var turn_manager: TurnManager
var selected_unit: PrototypeUnit
var units_by_id: Dictionary = {}
var enemy_alerts: Dictionary = {}
var enemy_patrols: Dictionary = {}
var opaque_cells: Dictionary = {}
var world_tick := 0
var input_locked := false

@onready var units_root: Node3D = $Units
@onready var highlights_root: Node3D = $MoveHighlights
@onready var attack_highlights_root: Node3D = $AttackHighlights
@onready var selection_label: Label = $HUD/TopLeftPanel/Margin/VBox/SelectionLabel
@onready var phase_label: Label = $HUD/TopLeftPanel/Margin/VBox/PhaseLabel
@onready var alert_label: Label = $HUD/TopLeftPanel/Margin/VBox/AlertLabel
@onready var hint_label: Label = $HUD/TopLeftPanel/Margin/VBox/HintLabel
@onready var end_turn_button: Button = $HUD/TopLeftPanel/Margin/VBox/EndTurnButton


func _ready() -> void:
	grid = GridModel.new()
	if map_definition == null or not grid.configure_from_definition(map_definition):
		push_error("PrototypeController requires a valid TacticalMapDefinition.")
		return
	_apply_map_rules()
	_spawn_initial_units()
	_configure_encounter_models()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	_update_enemy_visibility()
	var player_cells := map_definition.get_player_spawn_cells()
	if not player_cells.is_empty():
		_select_unit(_find_player_at(player_cells[0]))
	_evaluate_detection()
	_update_hud("探索中：蓝格为移动；看见敌人后点击红色单位攻击。")


func _unhandled_input(event: InputEvent) -> void:
	if input_locked or _is_terminal():
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_handle_world_click(mouse_event.position)


func _apply_map_rules() -> void:
	opaque_cells.clear()
	for cell_data in map_definition.cells:
		if cell_data.blocks_los:
			opaque_cells[cell_data.coordinate] = true
	for placement in map_definition.objects:
		if placement.blocks_movement:
			grid.set_walkable(placement.cell, false)
		if placement.blocks_los:
			opaque_cells[placement.cell] = true


func _spawn_initial_units() -> void:
	for spawn in map_definition.spawns:
		var color := spawn.visual_color
		if color == Color.WHITE:
			color = PLAYER_COLOR if spawn.faction == &"player" else ENEMY_COLOR
		var unit := _spawn_unit(spawn.unit_name, spawn.cell, spawn.faction, color)
		unit.set_facing(spawn.facing)


func _spawn_unit(unit_name: StringName, cell: Vector3i, faction: StringName, color: Color) -> PrototypeUnit:
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	unit.name = unit_name
	unit.configure(cell, faction, color)
	units_root.add_child(unit)
	unit.global_position = grid.cell_to_world(cell)
	unit.action_points_changed.connect(_on_unit_state_changed)
	unit.health_changed.connect(_on_unit_state_changed)
	unit.died.connect(_on_unit_died)
	if faction == &"enemy":
		unit.attack_range = 4
		unit.attack_damage = 3
		unit.vision_range = 6
	if not grid.occupy(cell, unit.unit_id):
		push_error("Failed to occupy %s for %s" % [cell, unit.name])
	units_by_id[unit.unit_id] = unit
	return unit


func _configure_encounter_models() -> void:
	var player_ids: Array[StringName] = []
	var enemy_ids: Array[StringName] = []
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == &"player":
			player_ids.append(unit.unit_id)
		else:
			enemy_ids.append(unit.unit_id)
	turn_manager = TurnManager.new()
	turn_manager.configure(player_ids, enemy_ids)
	turn_manager.phase_changed.connect(_on_phase_changed)
	for enemy_id in enemy_ids:
		enemy_alerts[enemy_id] = AlertState.new()
	for spawn in map_definition.spawns:
		if spawn.faction != &"enemy" or spawn.patrol_route_id == &"":
			continue
		var enemy := _unit_by_name(spawn.unit_name)
		var route_data := map_definition.find_patrol_route(spawn.patrol_route_id)
		if is_instance_valid(enemy) and route_data != null:
			var route := PatrolRoute.new()
			route.configure(route_data.points, route_data.loop)
			enemy_patrols[enemy.unit_id] = route


func _handle_world_click(screen_position: Vector2) -> void:
	if not _player_can_act():
		_update_hud("当前不是玩家行动阶段。")
		return
	var clicked_cell := _screen_to_cell(screen_position)
	if not grid.in_bounds(clicked_cell):
		_update_hud("点击位置在地图范围外。")
		return
	var clicked_player := _find_player_at(clicked_cell)
	if is_instance_valid(clicked_player):
		_select_unit(clicked_player)
		_update_hud("已选择 %s。" % clicked_player.name)
		return
	var clicked_enemy := _find_enemy_at(clicked_cell)
	if is_instance_valid(clicked_enemy):
		await _attack_with_unit(selected_unit, clicked_enemy)
		return
	await _try_move_selected(clicked_cell)


func _try_move_selected(destination: Vector3i) -> void:
	if not is_instance_valid(selected_unit):
		_update_hud("请先选择一个蓝色单位。")
		return
	var path := grid.find_path(selected_unit.grid_cell, destination)
	var validation := ActionValidator.validate_move(
		selected_unit.current_action_points,
		MOVE_ACTION_COST,
		maxi(grid.get_path_cost(path), 0),
		selected_unit.move_range,
		grid.is_walkable(destination) and not grid.is_occupied(destination)
	)
	if not validation.success:
		_update_hud("无法移动：%s。" % validation.reason)
		return
	await _move_unit(selected_unit, destination, path, validation.ap_cost)
	_evaluate_detection()


func _move_selected_unit(destination: Vector3i) -> void:
	await _try_move_selected(destination)


func _move_unit(unit: PrototypeUnit, destination: Vector3i, path: Array[Vector3i], ap_cost: int) -> bool:
	if path.size() < 2 or not unit.can_spend_action_points(ap_cost):
		return false
	var start_cell := unit.grid_cell
	if not grid.vacate(start_cell, unit.unit_id):
		return false
	if not grid.occupy(destination, unit.unit_id):
		grid.occupy(start_cell, unit.unit_id)
		return false
	input_locked = true
	end_turn_button.disabled = true
	_clear_highlights()
	unit.spend_action_points(ap_cost)
	var world_points: Array[Vector3] = []
	for index in range(1, path.size()):
		world_points.append(grid.cell_to_world(path[index]))
	await unit.move_along_world_path(world_points, destination)
	input_locked = false
	end_turn_button.disabled = false
	_update_enemy_visibility()
	_refresh_highlights()
	_update_hud("%s 移动到 %s，消耗 %d AP。" % [unit.name, destination, ap_cost])
	return true


func _attack_with_unit(attacker: PrototypeUnit, target: PrototypeUnit) -> ActionResult:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return ActionResult.rejected(&"invalid_target")
	if turn_manager.is_terminal():
		return ActionResult.rejected(&"terminal", attacker.unit_id, target.unit_id)
	if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION and attacker.faction != &"player":
		return ActionResult.rejected(&"wrong_phase", attacker.unit_id, target.unit_id)
	if turn_manager.is_player_turn() and attacker.faction != &"player":
		return ActionResult.rejected(&"wrong_phase", attacker.unit_id, target.unit_id)
	if turn_manager.is_enemy_turn() and attacker.faction != &"enemy":
		return ActionResult.rejected(&"wrong_phase", attacker.unit_id, target.unit_id)
	var has_los := GridVisibility.has_line_of_sight(
		attacker.grid_cell, target.grid_cell, opaque_cells, attacker.attack_range
	)
	var validation := ActionValidator.validate_attack(
		attacker.unit_id, target.unit_id, attacker.current_action_points,
		attacker.attack_ap_cost, attacker.grid_cell, target.grid_cell,
		attacker.attack_range, target.is_alive(), attacker.faction != target.faction, has_los
	)
	if not validation.success:
		_update_hud("无法攻击：%s。" % validation.reason)
		return validation
	if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION:
		_start_combat(true, target, attacker.grid_cell)
	attacker.set_facing(target.grid_cell - attacker.grid_cell)
	attacker.spend_action_points(validation.ap_cost)
	var result := CombatResolver.resolve_attack(validation, target.current_hp, attacker.attack_damage)
	var applied := target.take_damage(result.damage)
	_update_hud("%s 命中 %s，造成 %d 伤害%s。" % [
		attacker.name, target.name, applied, "并击杀目标" if result.killed else ""
	])
	_refresh_highlights()
	return result


func _run_exploration_tick() -> void:
	world_tick += 1
	for enemy_id in turn_manager.get_enemy_ids():
		var enemy := _unit_by_id(enemy_id)
		if not is_instance_valid(enemy) or not enemy_patrols.has(enemy_id):
			continue
		var route := enemy_patrols[enemy_id] as PatrolRoute
		var next_cell := route.peek_next()
		if next_cell == enemy.grid_cell:
			continue
		var path := grid.find_path(enemy.grid_cell, next_cell)
		if path.size() == 2:
			await _move_unit(enemy, next_cell, path, 0)
			route.advance()
			if _evaluate_detection():
				break
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == &"player":
			unit.reset_action_points()


func _evaluate_detection() -> bool:
	if turn_manager.get_phase() != TurnManager.Phase.EXPLORATION:
		return false
	for enemy_id in turn_manager.get_enemy_ids():
		var enemy := _unit_by_id(enemy_id)
		if not is_instance_valid(enemy):
			continue
		for player_id in turn_manager.get_player_ids():
			var player := _unit_by_id(player_id)
			if not is_instance_valid(player):
				continue
			if DetectionRules.can_detect(
				enemy.grid_cell, player.grid_cell, enemy.facing,
				enemy.vision_range, opaque_cells
			):
				_start_combat(false, enemy, player.grid_cell, player.unit_id)
				return true
	return false


func _start_combat(player_first: bool, alert_enemy: PrototypeUnit, known_cell: Vector3i, target_id: StringName = &"") -> void:
	if turn_manager.get_phase() != TurnManager.Phase.EXPLORATION:
		return
	if not is_instance_valid(alert_enemy):
		return
	var effective_target := target_id
	if effective_target.is_empty() and is_instance_valid(selected_unit):
		effective_target = selected_unit.unit_id
	if enemy_alerts.has(alert_enemy.unit_id):
		(enemy_alerts[alert_enemy.unit_id] as AlertState).engage(effective_target, known_cell)
	for enemy_id in turn_manager.get_enemy_ids():
		if enemy_alerts.has(enemy_id) and enemy_id != alert_enemy.unit_id:
			(enemy_alerts[enemy_id] as AlertState).become_suspicious(known_cell)
	turn_manager.start_combat(player_first)
	if not player_first:
		_run_enemy_turn.call_deferred()


func _run_enemy_turn() -> void:
	if not turn_manager.is_enemy_turn() or turn_manager.is_terminal():
		return
	input_locked = true
	end_turn_button.disabled = true
	_clear_highlights()
	for enemy_id in turn_manager.get_enemy_ids().duplicate():
		var enemy := _unit_by_id(enemy_id)
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		enemy.reset_action_points()
		while enemy.current_action_points > 0 and turn_manager.is_enemy_turn():
			var target := _nearest_living_player(enemy.grid_cell)
			if not is_instance_valid(target):
				break
			var has_los := GridVisibility.has_line_of_sight(
				enemy.grid_cell, target.grid_cell, opaque_cells, enemy.attack_range
			)
			var distance := _manhattan(enemy.grid_cell, target.grid_cell)
			if distance <= enemy.attack_range and has_los:
				await _attack_with_unit(enemy, target)
				continue
			var destination := _best_enemy_move(enemy, target)
			if destination == enemy.grid_cell:
				break
			var path := grid.find_path(enemy.grid_cell, destination)
			if not await _move_unit(enemy, destination, path, MOVE_ACTION_COST):
				break
	input_locked = false
	if turn_manager.is_enemy_turn():
		turn_manager.end_enemy_turn()
		_reset_faction_ap(&"player")
	end_turn_button.disabled = turn_manager.is_terminal()
	_refresh_highlights()


func _best_enemy_move(enemy: PrototypeUnit, target: PrototypeUnit) -> Vector3i:
	var best_cell := enemy.grid_cell
	var best_distance := _manhattan(enemy.grid_cell, target.grid_cell)
	for cell in grid.get_reachable_cells(enemy.grid_cell, enemy.move_range):
		if cell == enemy.grid_cell:
			continue
		var distance := _manhattan(cell, target.grid_cell)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell
		elif distance == best_distance and _cell_less(cell, best_cell):
			best_cell = cell
	return best_cell


func _select_unit(unit: PrototypeUnit) -> void:
	if is_instance_valid(unit) and (unit.faction != &"player" or not unit.is_alive()):
		unit = null
	if is_instance_valid(selected_unit):
		selected_unit.set_selected(false)
	selected_unit = unit
	if is_instance_valid(selected_unit):
		selected_unit.set_selected(true)
	_refresh_highlights()
	_update_hud()


func _refresh_highlights() -> void:
	_clear_highlights()
	if not _can_show_move_highlights():
		return
	highlights_root.visible = true
	attack_highlights_root.visible = true
	if selected_unit.can_spend_action_points(MOVE_ACTION_COST):
		for cell in grid.get_reachable_cells(selected_unit.grid_cell, selected_unit.move_range):
			if cell != selected_unit.grid_cell:
				_add_highlight(highlights_root, cell, MOVE_HIGHLIGHT_COLOR)
	if selected_unit.can_spend_action_points(selected_unit.attack_ap_cost):
		for enemy_id in turn_manager.get_enemy_ids():
			var enemy := _unit_by_id(enemy_id)
			if not is_instance_valid(enemy) or not enemy.visible:
				continue
			if GridVisibility.has_line_of_sight(
				selected_unit.grid_cell, enemy.grid_cell, opaque_cells, selected_unit.attack_range
			):
				_add_highlight(attack_highlights_root, enemy.grid_cell, ATTACK_HIGHLIGHT_COLOR)


func _refresh_move_highlights() -> void:
	_refresh_highlights()


func _add_highlight(parent: Node3D, cell: Vector3i, color: Color) -> void:
	if not is_instance_valid(parent):
		return
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(grid.cell_dimensions.x * 0.88, 0.035, grid.cell_dimensions.z * 0.88)
	var highlight := MeshInstance3D.new()
	highlight.name = "Cell_%d_%d_%d" % [cell.x, cell.y, cell.z]
	highlight.mesh = mesh
	highlight.material_override = material
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.set_meta(&"grid_cell", cell)
	parent.add_child(highlight)
	# Use a world-space placement after parenting so the highlight remains on the
	# correct 3D surface even if a presentation layer has a transform of its own.
	highlight.global_position = grid.cell_to_world(cell) + Vector3.UP * MOVE_HIGHLIGHT_SURFACE_OFFSET
	highlight.visible = true


func _clear_highlights() -> void:
	if is_instance_valid(highlights_root):
		_clear_children(highlights_root)
	if is_instance_valid(attack_highlights_root):
		_clear_children(attack_highlights_root)


func _clear_move_highlights() -> void:
	_clear_highlights()


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _on_end_turn_pressed() -> void:
	if input_locked or turn_manager.is_terminal():
		return
	if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION:
		await _run_exploration_tick()
		_evaluate_detection()
		_update_hud("探索世界 Tick %d。" % world_tick)
		return
	if turn_manager.end_player_turn():
		await _run_enemy_turn()


func _on_unit_died(unit: PrototypeUnit) -> void:
	grid.vacate(unit.grid_cell, unit.unit_id)
	turn_manager.remove_unit(unit.unit_id)
	units_by_id.erase(unit.unit_id)
	enemy_alerts.erase(unit.unit_id)
	enemy_patrols.erase(unit.unit_id)
	if selected_unit == unit:
		selected_unit = null
	unit.set_selected(false)
	unit.visible = false
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	_update_enemy_visibility()
	_refresh_highlights()
	_update_hud()


func _on_phase_changed(_previous: TurnManager.Phase, _current: TurnManager.Phase) -> void:
	_update_enemy_visibility()
	_refresh_highlights()
	_update_hud()


func _on_unit_state_changed(_current: int, _maximum: int) -> void:
	_refresh_highlights()
	_update_hud()


func _reset_faction_ap(faction: StringName) -> void:
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == faction and unit.is_alive():
			unit.reset_action_points()


func _find_player_at(cell: Vector3i) -> PrototypeUnit:
	return _find_faction_at(cell, &"player")


func _find_enemy_at(cell: Vector3i) -> PrototypeUnit:
	var enemy := _find_faction_at(cell, &"enemy")
	return enemy if is_instance_valid(enemy) and enemy.visible else null


func _find_faction_at(cell: Vector3i, faction: StringName) -> PrototypeUnit:
	var occupant_id := grid.get_occupant(cell)
	var unit := _unit_by_id(occupant_id)
	return unit if is_instance_valid(unit) and unit.faction == faction else null


func _unit_by_id(unit_id: StringName) -> PrototypeUnit:
	if unit_id.is_empty() or not units_by_id.has(unit_id):
		return null
	return units_by_id[unit_id] as PrototypeUnit


func _unit_by_name(unit_name: StringName) -> PrototypeUnit:
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.name == unit_name:
			return unit
	return null


func _nearest_living_player(from_cell: Vector3i) -> PrototypeUnit:
	var result: PrototypeUnit
	var best_distance := 1_000_000
	for player_id in turn_manager.get_player_ids():
		var player := _unit_by_id(player_id)
		if not is_instance_valid(player):
			continue
		var distance := _manhattan(from_cell, player.grid_cell)
		if distance < best_distance:
			best_distance = distance
			result = player
	return result


func _update_enemy_visibility() -> void:
	if not is_instance_valid(turn_manager):
		return
	for enemy_id in turn_manager.get_enemy_ids():
		var enemy := _unit_by_id(enemy_id)
		if not is_instance_valid(enemy):
			continue
		var visible_to_player := false
		for player_id in turn_manager.get_player_ids():
			var player := _unit_by_id(player_id)
			if is_instance_valid(player) and DetectionRules.can_player_see(
				player.grid_cell, enemy.grid_cell, player.vision_range, opaque_cells
			):
				visible_to_player = true
				break
		enemy.visible = visible_to_player


func _screen_to_cell(screen_position: Vector2) -> Vector3i:
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return grid.invalid_cell()
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000.0)
	query.collide_with_areas = true
	# FloorGrid and traversal surfaces are layer 1; blocking gameplay objects
	# may also be layer 2. Resolve any hit back to the nearest standable surface.
	query.collision_mask = 3
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return grid.invalid_cell()
	return grid.world_to_existing_cell(hit[&"position"])


func _player_can_act() -> bool:
	return is_instance_valid(turn_manager) and (
		turn_manager.get_phase() == TurnManager.Phase.EXPLORATION or turn_manager.is_player_turn()
	)


func _can_show_move_highlights() -> bool:
	return is_instance_valid(selected_unit) \
		and selected_unit.faction == &"player" \
		and selected_unit.is_alive() \
		and _player_can_act() \
		and selected_unit.can_spend_action_points(MOVE_ACTION_COST)


func _is_terminal() -> bool:
	return is_instance_valid(turn_manager) and turn_manager.is_terminal()


func _manhattan(a: Vector3i, b: Vector3i) -> int:
	return GridVisibility.tactical_distance(a, b)


func _cell_less(a: Vector3i, b: Vector3i) -> bool:
	return a.y < b.y or (a.y == b.y and (a.z < b.z or (a.z == b.z and a.x < b.x)))


func _alert_summary() -> String:
	var suspicious := 0
	var engaged := 0
	for alert_value in enemy_alerts.values():
		var alert := alert_value as AlertState
		if alert.get_level() == AlertState.Level.ENGAGED:
			engaged += 1
		elif alert.get_level() == AlertState.Level.SUSPICIOUS:
			suspicious += 1
	if engaged > 0:
		return "交战 %d · 怀疑 %d" % [engaged, suspicious]
	if suspicious > 0:
		return "怀疑 %d" % suspicious
	return "未警戒"


func _phase_name() -> String:
	match turn_manager.get_phase():
		TurnManager.Phase.EXPLORATION: return "探索阶段"
		TurnManager.Phase.PLAYER_TURN: return "交战 · 玩家回合"
		TurnManager.Phase.ENEMY_TURN: return "交战 · 敌方回合"
		TurnManager.Phase.VICTORY: return "胜利 · 敌方全灭"
		TurnManager.Phase.DEFEAT: return "失败 · 小队全灭"
	return "未知阶段"


func _update_hud(message: String = "") -> void:
	if not is_instance_valid(turn_manager):
		return
	phase_label.text = "%s · 世界 Tick %d" % [_phase_name(), world_tick]
	alert_label.text = "敌方警戒：%s" % _alert_summary()
	if is_instance_valid(selected_unit):
		selection_label.text = "%s | HP %d/%d | AP %d/%d | 格 %s | 射程 %d" % [
			selected_unit.name, selected_unit.current_hp, selected_unit.max_hp,
			selected_unit.current_action_points, selected_unit.max_action_points,
			selected_unit.grid_cell, selected_unit.attack_range,
		]
	else:
		selection_label.text = "未选择单位"
	end_turn_button.text = "推进探索 Tick" if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION else "结束玩家回合"
	end_turn_button.disabled = input_locked or turn_manager.is_terminal() or turn_manager.is_enemy_turn()
	if not message.is_empty():
		hint_label.text = message
