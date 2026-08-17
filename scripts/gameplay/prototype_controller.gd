class_name PrototypeController
extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/main/prototype_unit.tscn")
const ActionResultScript = preload("res://scripts/core/action/action_result.gd")
const ActionRequestScript = preload("res://scripts/core/action/action_request.gd")
const ActionExecutionContextScript = preload("res://scripts/core/action/action_execution_context.gd")
const ActionExecutorScript = preload("res://scripts/core/action/action_executor.gd")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")
const LootContainerScript = preload("res://scripts/core/loot/loot_container_model.gd")
const LootSettlementScript = preload("res://scripts/core/loot/loot_settlement.gd")
const InventoryGridScript = preload("res://scripts/gameplay/ui/inventory_grid_control.gd")
const LootGridScript = preload("res://scripts/gameplay/ui/loot_grid_control.gd")
const MOVE_ACTION_COST := 1
## Opening a Loot container is a one-AP Interact; confirming an extraction is
## also one AP, while taking items from an opened container is free.
const INTERACT_ACTION_COST := 1
const LOOT_OPEN_ACTION_COST := 1
const LOOT_ACTION_COST := 0
const INTERACTION_RANGE := 1
const ACTION_MOVE: StringName = &"move"
const ACTION_INTERACT: StringName = &"interact"
const ACTION_LOOT: StringName = &"loot"
const ACTION_ATTACK: StringName = &"attack"
const PLAYER_COLOR := Color("4f9dff")
const ENEMY_COLOR := Color("ef5b5b")
const MOVE_HIGHLIGHT_COLOR := Color(0.2, 0.72, 1.0, 0.34)
const ATTACK_HIGHLIGHT_COLOR := Color(1.0, 0.23, 0.16, 0.48)
const LOOT_HIGHLIGHT_COLOR := Color(1.0, 0.82, 0.16, 0.56)
const EXTRACTION_HIGHLIGHT_COLOR := Color(0.2, 0.95, 0.42, 0.56)
const MOVE_HIGHLIGHT_SURFACE_OFFSET := 0.025

@export var map_definition: TacticalMapDefinition

var grid: GridModel
var turn_manager: TurnManager
var action_executor: ActionExecutor
var last_action_result: ActionResult
var session_manager
var squad_inventory
var loot_settlement
var selected_unit: PrototypeUnit
var units_by_id: Dictionary = {}
var enemy_alerts: Dictionary = {}
var enemy_patrols: Dictionary = {}
var encounter_by_unit: Dictionary = {}
var encounter_members: Dictionary = {}
var resolved_encounters: Dictionary = {}
var all_player_ids: Array[StringName] = []
var all_enemy_ids: Array[StringName] = []
var active_encounter_id: StringName = &""
var opaque_cells: Dictionary = {}
var object_placements: Dictionary = {}
var loot_containers: Dictionary = {}
var extraction_cells: Array[Vector3i] = []
var open_loot_container_id: StringName = &""
var world_tick := 0
var input_locked := false
var debug_reveal_all := false
const VISION_BLOCK_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const ENEMY_VISION_COLOR := Color(0.62, 0.4, 1.0, 0.22)
const ENEMY_DANGER_COLOR := Color(1.0, 0.55, 0.1, 0.3)
const ENEMY_MOVE_COLOR := Color(0.3, 0.9, 0.95, 0.32)
var inventory_body_collapsed := true
var _restore_inventory_after_loot := false
const INVENTORY_PANEL_EXPANDED_BOTTOM := 570.0
const INVENTORY_PANEL_COLLAPSED_BOTTOM := 300.0

@onready var units_root: Node3D = $Units
@onready var camera_rig: TacticalCameraRig = $TacticalCameraRig
@onready var highlights_root: Node3D = $MoveHighlights
@onready var attack_highlights_root: Node3D = $AttackHighlights
@onready var object_highlights_root: Node3D = $ObjectHighlights
@onready var vision_highlights_root: Node3D = $VisionHighlights
@onready var selection_label: Label = $HUD/TopLeftPanel/Margin/VBox/SelectionLabel
@onready var phase_label: Label = $HUD/TopLeftPanel/Margin/VBox/PhaseLabel
@onready var alert_label: Label = $HUD/TopLeftPanel/Margin/VBox/AlertLabel
@onready var hint_label: Label = $HUD/TopLeftPanel/Margin/VBox/HintLabel
@onready var end_turn_button: Button = $HUD/TopLeftPanel/Margin/VBox/EndTurnButton
@onready var inventory_summary_label: Label = $HUD/InventoryPanel/Margin/VBox/InventorySummary
@onready var inventory_hint_label: Label = $HUD/InventoryPanel/Margin/VBox/InventoryHint
@onready var inventory_panel: PanelContainer = $HUD/InventoryPanel
@onready var inventory_collapse_button: Button = $HUD/InventoryPanel/Margin/VBox/HeaderRow/CollapseButton
@onready var inventory_grid: InventoryGridControl = $HUD/InventoryPanel/Margin/VBox/InventoryItems
@onready var loot_overview_label: Label = $HUD/InventoryPanel/Margin/VBox/LootOverview
@onready var loot_panel: PanelContainer = $HUD/LootPanel
@onready var loot_title_label: Label = $HUD/LootPanel/Margin/VBox/LootTitle
@onready var loot_grid: LootGridControl = $HUD/LootPanel/Margin/VBox/LootItems
@onready var loot_all_button: Button = $HUD/LootPanel/Margin/VBox/LootButtons/LootAllButton
@onready var loot_close_button: Button = $HUD/LootPanel/Margin/VBox/LootButtons/LootCloseButton
@onready var extraction_panel: PanelContainer = $HUD/ExtractionPanel
@onready var extraction_confirm_button: Button = $HUD/ExtractionPanel/Margin/VBox/Buttons/ConfirmButton
@onready var extraction_cancel_button: Button = $HUD/ExtractionPanel/Margin/VBox/Buttons/CancelButton
@onready var result_panel: PanelContainer = $HUD/ResultPanel
@onready var result_title_label: Label = $HUD/ResultPanel/Margin/VBox/ResultTitle
@onready var result_items_label: Label = $HUD/ResultPanel/Margin/VBox/ResultItems
@onready var result_value_label: Label = $HUD/ResultPanel/Margin/VBox/ResultValue
@onready var restart_button: Button = $HUD/ResultPanel/Margin/VBox/RestartButton


func _ready() -> void:
	grid = GridModel.new()
	if map_definition == null or not grid.configure_from_definition(map_definition):
		push_error("PrototypeController requires a valid TacticalMapDefinition.")
		return
	_apply_camera_bounds()
	session_manager = GameStateManagerScript.new()
	_configure_action_executor()
	squad_inventory = SquadInventoryScript.new()
	loot_settlement = null
	session_manager.state_changed.connect(_on_session_state_changed)
	session_manager.result_changed.connect(_on_session_result_changed)
	_index_map_objects()
	_apply_map_rules()
	_spawn_initial_units()
	_configure_encounter_models()
	_configure_inventory_ui()
	session_manager.start_exploration()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	loot_all_button.pressed.connect(_on_loot_all_button_pressed)
	loot_close_button.pressed.connect(_close_loot_panel)
	extraction_confirm_button.pressed.connect(_on_extraction_confirm_pressed)
	extraction_cancel_button.pressed.connect(_on_extraction_cancel_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	_update_enemy_visibility()
	var player_cells := map_definition.get_player_spawn_cells()
	if not player_cells.is_empty():
		_select_unit(_find_player_at(player_cells[0]))
	_evaluate_detection()
	_update_hud("探索中：蓝格为移动；看见敌人后点击红色单位攻击。")


func _configure_inventory_ui() -> void:
	if is_instance_valid(inventory_grid):
		inventory_grid.configure(squad_inventory, Callable(self, "preview_inventory_command"), Callable(self, "handle_inventory_command"))
	if is_instance_valid(loot_grid):
		loot_grid.configure(
			Callable(self, "_place_loot_first_fit"),
			Callable(self, "_place_loot_first_fit"),
			Callable(self, "return_inventory_instance_to_loot"),
			Callable(self, "_can_return_inventory_instance_to_loot")
		)


func _configure_action_executor() -> void:
	action_executor = ActionExecutorScript.new()
	action_executor.register_handler(ACTION_MOVE, Callable(self, "_handle_move_action"))
	action_executor.register_handler(ACTION_ATTACK, Callable(self, "_handle_attack_action"))
	action_executor.register_handler(ACTION_INTERACT, Callable(self, "_handle_interact_action"))
	action_executor.register_handler(ACTION_LOOT, Callable(self, "_handle_loot_action"))


func _execute_runtime_action(request: Variant, actor: PrototypeUnit = null) -> ActionResult:
	if action_executor == null or request == null:
		last_action_result = ActionResultScript.rejected(&"invalid_request")
		return last_action_result
	var current_ap := actor.current_action_points if is_instance_valid(actor) else 0
	var context = ActionExecutionContextScript.new(current_ap)
	if is_instance_valid(actor):
		context.set_ap_committer(Callable(actor, "spend_action_points"))
	last_action_result = action_executor.execute(request, context)
	return last_action_result


func _handle_move_action(request: Variant, _context: Variant) -> Variant:
	var payload: Dictionary = request.payload
	var unit := payload.get(&"unit") as PrototypeUnit
	var start_cell: Vector3i = payload.get(&"start_cell", Vector3i(-1, -1, -1))
	var destination: Vector3i = payload.get(&"destination", Vector3i(-1, -1, -1))
	if not is_instance_valid(unit) or start_cell == destination:
		return false
	if not grid.vacate(start_cell, unit.unit_id):
		return false
	if not grid.occupy(destination, unit.unit_id):
		grid.occupy(start_cell, unit.unit_id)
		return false
	unit.grid_cell = destination
	return true


func _handle_attack_action(request: Variant, _context: Variant) -> Variant:
	var payload: Dictionary = request.payload
	var attacker := payload.get(&"attacker") as PrototypeUnit
	var target := payload.get(&"target") as PrototypeUnit
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return false
	if payload.get(&"enter_combat", false) and not _start_combat(true, target, attacker.grid_cell, attacker.unit_id):
		return _action_rejected(&"wrong_phase", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	attacker.set_facing(target.grid_cell - attacker.grid_cell)
	var accepted := ActionResultScript.accepted(request.actor_id, request.target_id, request.ap_cost, ACTION_ATTACK)
	var resolved := CombatResolver.resolve_attack(accepted, target.current_hp, attacker.attack_damage)
	var applied := target.take_damage(resolved.damage)
	return {&"success": true, &"damage": applied, &"killed": resolved.killed}


func _handle_interact_action(request: Variant, _context: Variant) -> Variant:
	var operation: StringName = StringName(request.payload.get(&"operation", &""))
	match operation:
		&"loot_open":
			var container = loot_containers.get(request.target_id)
			if container == null or not container.open():
				return _action_rejected(&"container_unavailable", ACTION_INTERACT, request.actor_id, request.target_id)
			open_loot_container_id = request.target_id
			_refresh_loot_panel()
			loot_panel.visible = true
			if inventory_body_collapsed:
				_restore_inventory_after_loot = true
				_set_inventory_body_collapsed(false)
			return true
		&"extraction_prompt":
			if not session_manager.start_extraction():
				return _action_rejected(&"wrong_phase", ACTION_INTERACT, request.actor_id, request.target_id)
			extraction_panel.visible = true
			return true
		&"extraction_confirm":
			if not session_manager.confirm_extraction():
				return _action_rejected(&"wrong_phase", ACTION_INTERACT, request.actor_id, request.target_id)
			return true
	return _action_rejected(&"invalid_target", ACTION_INTERACT, request.actor_id, request.target_id)


func _handle_loot_action(request: Variant, _context: Variant) -> Variant:
	var operation: StringName = StringName(request.payload.get(&"operation", &""))
	var container = loot_containers.get(request.target_id)
	if container == null:
		return _action_rejected(&"invalid_container", ACTION_LOOT, request.actor_id, request.target_id)
	if operation == &"place_item":
		var index := int(request.payload.get(&"index", -1))
		var anchor: Vector2i = request.payload.get(&"anchor", Vector2i(-1, -1))
		var rotation := int(request.payload.get(&"rotation", 0))
		if not container.transfer_to_inventory_at(index, squad_inventory, anchor, rotation):
			return _action_rejected(&"inventory_full", ACTION_LOOT, request.actor_id, request.target_id)
		return true
	if operation == &"loot_all":
		if not container.transfer_all_to_inventory(squad_inventory):
			return _action_rejected(&"inventory_full", ACTION_LOOT, request.actor_id, request.target_id)
		return true
	return _action_rejected(&"invalid_target", ACTION_LOOT, request.actor_id, request.target_id)


func _unhandled_input(event: InputEvent) -> void:
	if input_locked or _is_terminal():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_X:
			_set_debug_reveal_all(not debug_reveal_all)
			return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_handle_world_click(mouse_event.position)


func _set_debug_reveal_all(enabled: bool) -> void:
	debug_reveal_all = enabled
	_update_enemy_visibility()
	_refresh_highlights()

func _index_map_objects() -> void:
	object_placements.clear()
	loot_containers.clear()
	extraction_cells.clear()
	for placement in map_definition.objects:
		if placement == null or placement.object_id == &"":
			continue
		object_placements[placement.object_id] = placement
		if placement.kind == MapObjectPlacement.Kind.EXTRACTION:
			if not extraction_cells.has(placement.cell):
				extraction_cells.append(placement.cell)
		elif placement.kind == MapObjectPlacement.Kind.LOOT:
			var table = _placement_property(placement, &"loot_table")
			if table == null:
				push_warning("Loot placement %s has no loot_table; container skipped." % placement.object_id)
				continue
			var seed := int(_placement_property(placement, &"loot_seed", -1))
			var container := LootContainerScript.new()
			if table != null and container.initialize(placement.object_id, table, seed):
				loot_containers[placement.object_id] = container
			else:
				push_warning("Loot placement %s has an invalid loot_table; container skipped." % placement.object_id)


func _placement_has_property(placement: Object, property_name: StringName) -> bool:
	for property_info in placement.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			return true
	return false


func _placement_property(placement: Object, property_name: StringName, default_value: Variant = null) -> Variant:
	if _placement_has_property(placement, property_name):
		return placement.get(property_name)
	return placement.get_meta(property_name, default_value)


func _apply_camera_bounds() -> void:
	if not is_instance_valid(camera_rig):
		return
	var bounds_min := Vector2(map_definition.origin.x, map_definition.origin.z)
	var bounds_max := bounds_min + Vector2(
		float(map_definition.footprint_size.x) * map_definition.cell_size.x,
		float(map_definition.footprint_size.y) * map_definition.cell_size.z
	)
	camera_rig.set_map_bounds(bounds_min, bounds_max)


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
		var unit := _spawn_unit(spawn.unit_name, spawn.cell, spawn.faction, color, spawn.archetype, spawn.weapon)
		unit.set_facing(spawn.facing)


func _spawn_unit(unit_name: StringName, cell: Vector3i, faction: StringName, color: Color, archetype: UnitArchetype = null, weapon: WeaponDefinition = null) -> PrototypeUnit:
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	unit.name = unit_name
	unit.configure(cell, faction, color, archetype, weapon)
	units_root.add_child(unit)
	unit.global_position = grid.cell_to_world(cell)
	unit.action_points_changed.connect(_on_unit_state_changed)
	unit.health_changed.connect(_on_unit_state_changed)
	unit.died.connect(_on_unit_died)
	if not grid.occupy(cell, unit.unit_id):
		push_error("Failed to occupy %s for %s" % [cell, unit.name])
	units_by_id[unit.unit_id] = unit
	return unit


func _configure_encounter_models() -> void:
	var player_ids: Array[StringName] = []
	var enemy_ids: Array[StringName] = []
	all_player_ids.clear()
	all_enemy_ids.clear()
	encounter_by_unit.clear()
	encounter_members.clear()
	resolved_encounters.clear()
	active_encounter_id = &""
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == &"player":
			player_ids.append(unit.unit_id)
			all_player_ids.append(unit.unit_id)
		else:
			enemy_ids.append(unit.unit_id)
			all_enemy_ids.append(unit.unit_id)
	turn_manager = TurnManager.new()
	# Exploration has no active enemy roster. A detection or proactive attack
	# loads exactly one encounter group into TurnManager.
	turn_manager.configure(player_ids, [])
	turn_manager.phase_changed.connect(_on_phase_changed)
	for enemy_id in enemy_ids:
		enemy_alerts[enemy_id] = AlertState.new()
	for spawn in map_definition.spawns:
		if spawn.faction != &"enemy":
			continue
		var enemy := _unit_by_name(spawn.unit_name)
		var encounter_id := spawn.encounter_id if not spawn.encounter_id.is_empty() else &"default"
		if is_instance_valid(enemy):
			encounter_by_unit[enemy.unit_id] = encounter_id
			if not encounter_members.has(encounter_id):
				encounter_members[encounter_id] = []
			(encounter_members[encounter_id] as Array).append(enemy.unit_id)
		if spawn.patrol_route_id == &"":
			continue
		var route_data := map_definition.find_patrol_route(spawn.patrol_route_id)
		if is_instance_valid(enemy) and route_data != null:
			var route := PatrolRoute.new()
			route.configure(route_data.points, route_data.loop)
			enemy_patrols[enemy.unit_id] = route


func _living_player_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for unit_id in all_player_ids:
		var unit := _unit_by_id(unit_id)
		if is_instance_valid(unit) and unit.is_alive():
			result.append(unit_id)
	return result


func _living_enemy_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for unit_id in all_enemy_ids:
		var unit := _unit_by_id(unit_id)
		if is_instance_valid(unit) and unit.is_alive():
			result.append(unit_id)
	return result


func _enemy_ids_for_context() -> Array[StringName]:
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.COMBAT:
		return turn_manager.get_enemy_ids()
	return _living_enemy_ids()


func _activate_encounter_for(alert_enemy: PrototypeUnit) -> bool:
	if not is_instance_valid(alert_enemy):
		return false
	var encounter_id: StringName = encounter_by_unit.get(alert_enemy.unit_id, &"default")
	if encounter_id.is_empty() or resolved_encounters.has(encounter_id):
		return false
	var group_ids: Array[StringName] = []
	for enemy_id in encounter_members.get(encounter_id, []):
		var enemy := _unit_by_id(enemy_id)
		if is_instance_valid(enemy) and enemy.is_alive():
			group_ids.append(enemy_id)
	if group_ids.is_empty():
		return false
	turn_manager.configure(_living_player_ids(), group_ids)
	active_encounter_id = encounter_id
	return true


func _handle_world_click(screen_position: Vector2) -> void:
	if not _player_can_act():
		_update_hud("当前不是玩家行动阶段。")
		return
	var clicked_cell := _screen_to_cell(screen_position)
	if not grid.in_bounds(clicked_cell):
		_update_hud("点击位置在地图范围外。")
		return
	await _handle_cell_click(clicked_cell)


## Stable cell-level input entry used by both the world raycast and tests.
## Unit selection and object handling happen before movement so an extraction
## cell can be approached and confirmed through the same click path.
func _handle_cell_click(clicked_cell: Vector3i) -> void:
	if input_locked or not grid.in_bounds(clicked_cell) or not _player_can_act():
		return
	var clicked_player := _find_player_at(clicked_cell)
	if is_instance_valid(clicked_player):
		_select_unit(clicked_player)
		var extraction_id := _extraction_at_cell(clicked_cell)
		if extraction_id != &"":
			begin_extraction_prompt(extraction_id)
		else:
			_update_hud("已选择 %s。" % clicked_player.name)
		return
	var clicked_enemy := _find_enemy_at(clicked_cell)
	if is_instance_valid(clicked_enemy):
		# With a player unit selected that can afford an attack, clicking an
		# enemy attacks it; otherwise the click inspects the enemy.
		var can_attack := is_instance_valid(selected_unit) \
			and selected_unit.faction == &"player" \
			and selected_unit.is_alive() \
			and selected_unit.can_spend_action_points(selected_unit.attack_ap_cost)
		if can_attack:
			await _attack_with_unit(selected_unit, clicked_enemy)
		else:
			_select_unit(clicked_enemy, true)
			_update_hud("已选择 %s（敌方单位，仅侦察）。" % clicked_enemy.name)
		return
	var object_id := _object_at_cell(clicked_cell)
	if object_id != &"":
		var placement = object_placements.get(object_id)
		if placement != null and placement.kind == MapObjectPlacement.Kind.LOOT:
			interact_with_loot(object_id)
			return
		if placement != null and placement.kind == MapObjectPlacement.Kind.EXTRACTION:
			if is_instance_valid(selected_unit) and selected_unit.grid_cell == clicked_cell:
				begin_extraction_prompt(object_id)
				return
			var moved := await _try_move_selected(clicked_cell)
			if moved and is_instance_valid(selected_unit) and selected_unit.grid_cell == clicked_cell and session_manager.get_state() == GameStateManagerScript.State.EXPLORATION:
				begin_extraction_prompt(object_id)
			return
	# Only a highlighted (reachable) tile moves the unit; clicking any other
	# tile cancels the current selection instead of issuing a stray move.
	# The reachability gate mirrors the move-highlight gate (AP affordability),
	# so a selection with no AP left always deselects on any tile click.
	var can_move := is_instance_valid(selected_unit) \
		and selected_unit.faction == &"player" \
		and selected_unit.is_alive() \
		and selected_unit.can_spend_action_points(MOVE_ACTION_COST)
	var reachable_cells: Array[Vector3i] = []
	if can_move:
		reachable_cells = grid.get_reachable_cells(selected_unit.grid_cell, selected_unit.move_range)
	if can_move and reachable_cells.has(clicked_cell):
		await _try_move_selected(clicked_cell)
	else:
		_select_unit(null)
		_update_hud("已取消选择。")


## Stable integration entry for UI/tests. Opening a Loot container is a
## one-AP Interact; ActionExecutor validation runs before the open handler.
func interact_with_loot(container_id: StringName) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", &"interact")
	var container = loot_containers.get(container_id)
	var placement = object_placements.get(container_id)
	var player := selected_unit
	var actor_id: StringName = player.unit_id if is_instance_valid(player) else &""
	var actor_cell: Vector3i = player.grid_cell if is_instance_valid(player) else Vector3i(-1, -1, -1)
	var target_cell: Vector3i = placement.cell if placement != null else Vector3i(-1, -1, -1)
	var request := ActionRequestScript.new(
		ACTION_INTERACT,
		actor_id,
		container_id,
		LOOT_OPEN_ACTION_COST,
		{
			&"operation": &"loot_open",
			ActionExecutorScript.KEY_ACTOR_CELL: actor_cell,
			ActionExecutorScript.KEY_TARGET_CELL: target_cell,
			ActionExecutorScript.KEY_INTERACTION_RANGE: INTERACTION_RANGE,
			ActionExecutorScript.KEY_TARGET_VALID: container != null and placement != null,
			ActionExecutorScript.KEY_TARGET_AVAILABLE: container != null and not container.is_depleted(),
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		if result.reason == &"target_unavailable" or result.reason == &"container_unavailable":
			_update_hud("Loot 箱已耗尽，不能重复搜刮。")
		else:
			_update_hud(_action_message("无法交互", result.reason))
		return result
	_update_hud("已打开 %s（消耗 1 AP），可单项或全部拾取。" % container_id)
	_log("打开 Loot 箱 %s（消耗 1 AP，%d 件）。" % [container_id, container.get_item_count()])
	_refresh_highlights()
	return result


func interact_with_object(object_id: StringName) -> ActionResult:
	var placement = object_placements.get(object_id)
	if placement == null:
		return _action_rejected(&"invalid_target", ACTION_INTERACT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", object_id)
	if placement.kind == MapObjectPlacement.Kind.LOOT:
		return interact_with_loot(object_id)
	if placement.kind == MapObjectPlacement.Kind.EXTRACTION:
		return begin_extraction_prompt(object_id)
	return _action_rejected(&"invalid_target", ACTION_INTERACT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", object_id)


func loot_item(index: int) -> ActionResult:
	var container = loot_containers.get(open_loot_container_id)
	if container == null:
		return _action_rejected(&"invalid_container", ACTION_LOOT)
	var item: InventoryItemInstance = container.get_item(index)
	if item == null or squad_inventory == null:
		return _action_rejected(&"invalid_target", ACTION_LOOT)
	var anchor: Vector2i = squad_inventory.find_first_fit(item)
	if anchor == SquadInventoryScript.NO_FIT:
		_update_hud("空间碎片：背包总空格可能足够，但该形状没有连续合法位置。")
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", open_loot_container_id)
	return place_loot_instance(open_loot_container_id, index, anchor, item.rotation)


func loot_all() -> ActionResult:
	return _loot_all(open_loot_container_id)


## Stable 2D inventory command entry points.  UI drag/drop and tests both use
## these methods; no UI path mutates the core models directly.
func preview_inventory_command(
		container_id: StringName,
		index: int,
		instance_id: StringName,
		anchor: Vector2i,
		rotation: int,
		source_kind: StringName
	) -> Dictionary:
	var cells: Array[Vector2i] = []
	var valid := false
	if not _can_use_loot_action():
		return {"valid": false, "cells": cells, "reason": &"wrong_phase"}
	if source_kind == &"loot":
		if container_id != open_loot_container_id:
			return {"valid": false, "cells": cells, "reason": &"invalid_container"}
		var container = loot_containers.get(container_id)
		var item = container.get_item(index) if container != null else null
		if container == null or not container.is_opened() or container.is_depleted() or item == null or item.instance_id != instance_id:
			return {"valid": false, "cells": cells, "reason": &"invalid_target"}
		if item != null:
			valid = squad_inventory.can_place(item, anchor, rotation)
			cells = _instance_cells(item, anchor, rotation)
	elif source_kind == &"inventory":
		var placement = squad_inventory.get_placement(instance_id)
		if placement != null and placement.instance != null:
			valid = squad_inventory.can_move(instance_id, anchor, rotation)
			cells = _instance_cells(placement.instance, anchor, rotation)
	else:
		return {"valid": false, "cells": cells, "reason": &"invalid_target"}
	return {"valid": valid, "cells": cells, "reason": &"accepted" if valid else &"inventory_full"}


func handle_inventory_command(command: Dictionary) -> Variant:
	var command_type := StringName(command.get("type", &""))
	match command_type:
		&"place_loot":
			return place_loot_instance(
				StringName(command.get("container_id", &"")),
				int(command.get("index", -1)),
				command.get("anchor", Vector2i(-1, -1)),
				int(command.get("rotation", 0))
			)
		&"move_inventory":
			return move_inventory_instance(
				StringName(command.get("instance_id", &"")),
				command.get("anchor", Vector2i(-1, -1)),
				int(command.get("rotation", -1))
			)
		&"rotate_inventory":
			return rotate_inventory_instance(StringName(command.get("instance_id", &"")))
	return _action_rejected(&"invalid_target", &"loot")


func place_loot_instance(container_id: StringName, index: int, anchor: Vector2i, rotation: int = 0) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	var container = loot_containers.get(container_id)
	var placement = object_placements.get(container_id)
	var player := selected_unit
	var item = container.get_item(index) if container != null else null
	var can_receive: bool = item != null and squad_inventory != null and squad_inventory.can_place(item, anchor, rotation)
	var request := ActionRequestScript.new(
		ACTION_LOOT,
		player.unit_id,
		container_id,
		LOOT_ACTION_COST,
		{
			&"operation": &"place_item",
			&"index": index,
			&"anchor": anchor,
			&"rotation": rotation,
			ActionExecutorScript.KEY_ACTOR_CELL: player.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: placement.cell if placement != null else Vector3i(-1, -1, -1),
			ActionExecutorScript.KEY_INTERACTION_RANGE: INTERACTION_RANGE,
			ActionExecutorScript.KEY_CONTAINER_VALID: container != null and placement != null and container_id == open_loot_container_id and item != null,
			ActionExecutorScript.KEY_CONTAINER_AVAILABLE: container != null and not container.is_depleted(),
			ActionExecutorScript.KEY_INVENTORY_CAN_RECEIVE: can_receive,
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		if result.reason == &"inventory_full":
			_update_hud("空间碎片或位置冲突：该物品无法放在目标格，Loot 与 AP 未改变。")
		else:
			_update_hud(_action_message("无法放置 Loot", result.reason))
		return result
	_refresh_inventory_ui()
	_update_hud("已将 %s 放入背包（不消耗 AP）。" % item.display_name)
	_log("拾取 %s 放入背包（不消耗 AP）。" % item.display_name)
	_refresh_highlights()
	return result


func move_inventory_instance(instance_id: StringName, anchor: Vector2i, rotation: int = -1) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	if squad_inventory == null or squad_inventory.get_placement(instance_id) == null:
		return _action_rejected(&"invalid_target", ACTION_LOOT, selected_unit.unit_id, instance_id)
	if not squad_inventory.can_move(instance_id, anchor, rotation):
		_update_hud("背包位置无效：越界、重叠或形状无法放置。")
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id, instance_id)
	if not squad_inventory.move(instance_id, anchor, rotation):
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id, instance_id)
	_refresh_inventory_ui()
	_update_hud("已重新排列背包物品。")
	return ActionResultScript.accepted(selected_unit.unit_id, instance_id, 0, ACTION_LOOT)


func rotate_inventory_instance(instance_id: StringName) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	var placement = squad_inventory.get_placement(instance_id) if squad_inventory != null else null
	if placement == null:
		return _action_rejected(&"invalid_target", ACTION_LOOT, selected_unit.unit_id, instance_id)
	if not squad_inventory.can_rotate(instance_id, placement.rotation + 90):
		_update_hud("旋转后形状与边界/其他物品冲突。")
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id, instance_id)
	if not squad_inventory.rotate_by(instance_id, 90):
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id, instance_id)
	_refresh_inventory_ui()
	_update_hud("已旋转物品 90°。")
	return ActionResultScript.accepted(selected_unit.unit_id, instance_id, 0, ACTION_LOOT)


func return_inventory_instance_to_loot(instance_id: StringName, container_id: StringName) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	var container = loot_containers.get(container_id)
	if container == null or container_id != open_loot_container_id:
		return _action_rejected(&"invalid_container", ACTION_LOOT, selected_unit.unit_id, container_id)
	if not container.transfer_from_inventory(instance_id, squad_inventory):
		_update_hud("无法将物品放回当前 Loot 箱。")
		return _action_rejected(&"invalid_target", ACTION_LOOT, selected_unit.unit_id, container_id)
	if is_instance_valid(loot_grid):
		loot_grid.clear_pending_rotation(instance_id)
	_refresh_inventory_ui()
	_update_hud("已将物品放回 Loot；背包管理不消耗 AP。")
	_log("将 %s 放回 Loot 箱 %s。" % [instance_id, container_id])
	_refresh_highlights()
	return ActionResultScript.accepted(selected_unit.unit_id, container_id, 0, ACTION_LOOT)


func _can_return_inventory_instance_to_loot(instance_id: StringName, container_id: StringName) -> bool:
	return _can_use_loot_action() and container_id == open_loot_container_id \
		and loot_containers.get(container_id) != null \
		and squad_inventory != null and squad_inventory.get_placement(instance_id) != null


func _place_loot_first_fit(container_id: StringName, index: int, rotation: int = -1) -> ActionResult:
	var container = loot_containers.get(container_id)
	var item = container.get_item(index) if container != null else null
	if item == null or squad_inventory == null:
		return _action_rejected(&"invalid_target", ACTION_LOOT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", container_id)
	var anchor: Vector2i = squad_inventory.find_first_fit(item, rotation)
	if anchor == SquadInventoryScript.NO_FIT:
		_update_hud("空间碎片：没有可容纳该形状的连续空间。")
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", container_id)
	return place_loot_instance(container_id, index, anchor, rotation)


func _instance_cells(item: InventoryItemInstance, anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if item == null or item.definition == null:
		return cells
	for relative_cell in item.definition.get_rotated_cells(rotation):
		cells.append(anchor + relative_cell)
	return cells


func _refresh_inventory_ui() -> void:
	if is_instance_valid(inventory_grid):
		inventory_grid.refresh()
	if is_instance_valid(loot_grid):
		loot_grid.refresh()


func begin_extraction_prompt(extraction_id: StringName = &"") -> ActionResult:
	if not _can_use_exploration_action():
		return _action_rejected(&"wrong_phase", ACTION_INTERACT)
	# The prompt itself is a zero-cost Interact, but a player with no AP cannot
	# complete the required one-AP confirmation, so do not open a dead-end panel.
	if selected_unit.current_action_points < INTERACT_ACTION_COST:
		_update_hud("无法开始撤离：AP 不足。")
		return _action_rejected(&"no_ap", ACTION_INTERACT, selected_unit.unit_id, extraction_id)
	var target_id := extraction_id if extraction_id != &"" else _extraction_at_cell(selected_unit.grid_cell if is_instance_valid(selected_unit) else Vector3i(-1, -1, -1))
	var placement = object_placements.get(target_id)
	var player := selected_unit
	var request := ActionRequestScript.new(
		ACTION_INTERACT,
		player.unit_id,
		target_id,
		0,
		{
			&"operation": &"extraction_prompt",
			ActionExecutorScript.KEY_ACTOR_CELL: player.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: placement.cell if placement != null else Vector3i(-1, -1, -1),
			ActionExecutorScript.KEY_INTERACTION_RANGE: 0,
			ActionExecutorScript.KEY_TARGET_VALID: placement != null and placement.kind == MapObjectPlacement.Kind.EXTRACTION,
			ActionExecutorScript.KEY_TARGET_AVAILABLE: true,
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		_update_hud(_action_message("无法开始撤离", result.reason))
		return result
	_update_hud("已进入撤离确认，请确认或取消。")
	_log("%s 请求在 %s 撤离。" % [player.name, target_id])
	_refresh_highlights()
	return result


func confirm_extraction() -> ActionResult:
	if session_manager == null or session_manager.get_state() != GameStateManagerScript.State.EXTRACTION:
		return _action_rejected(&"wrong_phase", ACTION_INTERACT)
	var player := selected_unit
	var target_id := _extraction_at_cell(player.grid_cell if is_instance_valid(player) else Vector3i(-1, -1, -1))
	var placement = object_placements.get(target_id)
	if not is_instance_valid(player):
		return _action_rejected(&"invalid_target", ACTION_INTERACT)
	var request := ActionRequestScript.new(
		ACTION_INTERACT,
		player.unit_id,
		target_id,
		INTERACT_ACTION_COST,
		{
			&"operation": &"extraction_confirm",
			ActionExecutorScript.KEY_ACTOR_CELL: player.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: placement.cell if placement != null else Vector3i(-1, -1, -1),
			ActionExecutorScript.KEY_INTERACTION_RANGE: 0,
			ActionExecutorScript.KEY_TARGET_VALID: placement != null and placement.kind == MapObjectPlacement.Kind.EXTRACTION,
			ActionExecutorScript.KEY_TARGET_AVAILABLE: true,
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		_update_hud(_action_message("无法确认撤离", result.reason))
		return result
	_log("确认撤离：%s 从 %s 撤离。" % [player.name, target_id])
	return result


func cancel_extraction() -> bool:
	if session_manager == null or not session_manager.cancel_extraction():
		return false
	extraction_panel.visible = false
	_update_hud("已取消撤离，可继续探索。")
	_log("取消撤离，继续探索。")
	_refresh_highlights()
	return true


func _try_move_selected(destination: Vector3i) -> bool:
	if not is_instance_valid(selected_unit) or selected_unit.faction != &"player" or not selected_unit.is_alive():
		_update_hud("请先选择一个蓝色单位。")
		return false
	var path := grid.find_path(selected_unit.grid_cell, destination)
	var moved := await _move_unit(selected_unit, destination, path, MOVE_ACTION_COST)
	_evaluate_detection()
	return moved


func _move_selected_unit(destination: Vector3i) -> void:
	await _try_move_selected(destination)


func _move_unit(unit: PrototypeUnit, destination: Vector3i, path: Array[Vector3i], ap_cost: int) -> bool:
	if not is_instance_valid(unit) or path.size() < 2:
		return false
	var start_cell := unit.grid_cell
	var actor_id := unit.unit_id
	var target_id := StringName("cell_%d_%d_%d" % [destination.x, destination.y, destination.z])
	var request := ActionRequestScript.new(
		ACTION_MOVE,
		actor_id,
		target_id,
		ap_cost,
		{
			ActionExecutorScript.KEY_PATH: path,
			ActionExecutorScript.KEY_PATH_LENGTH: maxi(grid.get_path_cost(path), 0),
			ActionExecutorScript.KEY_MAX_DISTANCE: unit.move_range,
			ActionExecutorScript.KEY_DESTINATION_AVAILABLE: grid.is_walkable(destination) and not grid.is_occupied(destination),
			&"unit": unit,
			&"start_cell": start_cell,
			&"destination": destination,
		}
	)
	var previous_input_locked := input_locked
	input_locked = true
	end_turn_button.disabled = true
	_clear_highlights()
	var result := _execute_runtime_action(request, unit)
	if not result.success:
		input_locked = previous_input_locked
		_refresh_highlights()
		_update_hud("无法移动：%s。" % result.reason)
		return false
	var world_points: Array[Vector3] = []
	for index in range(1, path.size()):
		world_points.append(grid.cell_to_world(path[index]))
	await unit.move_along_world_path(world_points, destination)
	input_locked = previous_input_locked
	_update_enemy_visibility()
	_refresh_highlights()
	_update_hud("%s 移动到 %s，消耗 %d AP。" % [unit.name, destination, ap_cost])
	_log("%s 移动 %s → %s（消耗 %d AP）。" % [unit.name, start_cell, destination, ap_cost])
	return true


func _attack_with_unit(attacker: PrototypeUnit, target: PrototypeUnit) -> ActionResult:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return _action_rejected(&"invalid_target", ACTION_ATTACK)
	if _is_terminal() or session_manager == null:
		return _action_rejected(&"terminal", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION and attacker.faction != &"player":
		return _action_rejected(&"wrong_phase", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	if turn_manager.is_player_turn() and attacker.faction != &"player":
		return _action_rejected(&"wrong_phase", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	if turn_manager.is_enemy_turn() and attacker.faction != &"enemy":
		return _action_rejected(&"wrong_phase", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	var has_los := GridVisibility.has_line_of_sight(
		attacker.grid_cell, target.grid_cell, opaque_cells, attacker.attack_range
	)
	var request := ActionRequestScript.new(
		ACTION_ATTACK,
		attacker.unit_id,
		target.unit_id,
		attacker.attack_ap_cost,
		{
			&"attacker": attacker,
			&"target": target,
			&"enter_combat": turn_manager.get_phase() == TurnManager.Phase.EXPLORATION,
			ActionExecutorScript.KEY_ACTOR_CELL: attacker.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: target.grid_cell,
			ActionExecutorScript.KEY_ATTACK_RANGE: attacker.attack_range,
			ActionExecutorScript.KEY_TARGET_ALIVE: target.is_alive(),
			ActionExecutorScript.KEY_HOSTILE: attacker.faction != target.faction,
			ActionExecutorScript.KEY_HAS_LOS: has_los,
		}
	)
	var previous_input_locked := input_locked
	input_locked = true
	end_turn_button.disabled = true
	_clear_highlights()
	var result := _execute_runtime_action(request, attacker)
	if not result.success:
		input_locked = previous_input_locked
		_refresh_highlights()
		_update_hud("无法攻击：%s。" % result.reason)
		return result
	await attacker.play_attack_feedback()
	input_locked = previous_input_locked
	var applied := result.damage
	_update_hud("%s 命中 %s，造成 %d 伤害%s。" % [
		attacker.name, target.name, applied, "并击杀目标" if result.killed else ""
	])
	_log("%s 攻击 %s：造成 %d 伤害%s。" % [
		attacker.name, target.name, applied, "，目标阵亡" if result.killed else ""
	])
	_refresh_highlights()
	return result


func _run_exploration_tick() -> void:
	world_tick += 1
	for enemy_id in _living_enemy_ids():
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
	for enemy_id in _living_enemy_ids():
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
				_start_combat(true, enemy, player.grid_cell, player.unit_id, "发现玩家")
				return true
	return false


func _start_combat(player_first: bool, alert_enemy: PrototypeUnit, known_cell: Vector3i, target_id: StringName = &"", reason: String = "") -> bool:
	if turn_manager.get_phase() != TurnManager.Phase.EXPLORATION or session_manager == null:
		return false
	if not is_instance_valid(alert_enemy):
		return false
	if not _activate_encounter_for(alert_enemy):
		return false
	var reason_text := reason if reason != "" else ("被玩家主动攻击" if player_first else "发现玩家")
	_log("进入交战：%s%s（位置 %s）。" % [alert_enemy.name, reason_text, known_cell])
	var effective_target := target_id
	if effective_target.is_empty() and is_instance_valid(selected_unit):
		effective_target = selected_unit.unit_id
	if enemy_alerts.has(alert_enemy.unit_id):
		(enemy_alerts[alert_enemy.unit_id] as AlertState).engage(effective_target, known_cell)
	for enemy_id in turn_manager.get_enemy_ids():
		if enemy_alerts.has(enemy_id) and enemy_id != alert_enemy.unit_id:
			(enemy_alerts[enemy_id] as AlertState).become_suspicious(known_cell)
	if not session_manager.start_combat():
		turn_manager.configure(_living_player_ids(), [])
		active_encounter_id = &""
		return false
	if not turn_manager.start_combat(player_first):
		turn_manager.configure(_living_player_ids(), [])
		active_encounter_id = &""
		session_manager.resolve_combat()
		return false
	if not player_first:
		_run_enemy_turn.call_deferred()
	return true


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
		var action_attempts := 0
		var max_action_attempts := maxi(enemy.max_action_points + 1, 1)
		while enemy.current_action_points > 0 and turn_manager.is_enemy_turn() and action_attempts < max_action_attempts:
			action_attempts += 1
			var target := _nearest_living_player(enemy.grid_cell)
			if not is_instance_valid(target):
				break
			var has_los := GridVisibility.has_line_of_sight(
				enemy.grid_cell, target.grid_cell, opaque_cells, enemy.attack_range
			)
			var distance := _manhattan(enemy.grid_cell, target.grid_cell)
			if distance <= enemy.attack_range and has_los:
				var attack_result := await _attack_with_unit(enemy, target)
				if not attack_result.success:
					# A failed action, especially no_ap after a move, cannot change
					# the tactical situation. End this unit's loop instead of retrying.
					break
				if enemy.attack_ap_cost <= 0 or enemy.current_action_points < enemy.attack_ap_cost:
					break
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


func _select_unit(unit: PrototypeUnit, allow_enemy: bool = false) -> void:
	if is_instance_valid(unit):
		if unit.faction == &"player":
			if not unit.is_alive():
				unit = null
		elif not allow_enemy:
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
	var can_show_tactical_highlights := _can_show_move_highlights()
	if is_instance_valid(highlights_root):
		highlights_root.visible = can_show_tactical_highlights
	if is_instance_valid(attack_highlights_root):
		attack_highlights_root.visible = can_show_tactical_highlights
	if is_instance_valid(object_highlights_root):
		object_highlights_root.visible = can_show_tactical_highlights
	if can_show_tactical_highlights and selected_unit.can_spend_action_points(MOVE_ACTION_COST):
		for cell in grid.get_reachable_cells(selected_unit.grid_cell, selected_unit.move_range):
			if cell != selected_unit.grid_cell:
				_add_highlight(highlights_root, cell, MOVE_HIGHLIGHT_COLOR)
	if can_show_tactical_highlights and selected_unit.can_spend_action_points(selected_unit.attack_ap_cost):
		for enemy_id in _enemy_ids_for_context():
			var enemy := _unit_by_id(enemy_id)
			if not is_instance_valid(enemy) or not enemy.visible:
				continue
			if GridVisibility.has_line_of_sight(
				selected_unit.grid_cell, enemy.grid_cell, opaque_cells, selected_unit.attack_range
			):
				_add_highlight(attack_highlights_root, enemy.grid_cell, ATTACK_HIGHLIGHT_COLOR)
	_refresh_object_highlights()
	_refresh_vision_overlay()
	if is_instance_valid(selected_unit) and selected_unit.faction == &"enemy":
		_refresh_enemy_range_overlays(selected_unit)


## When an enemy unit is selected, tints its vision / danger / move zones on
## the overlay (nested layers, drawn bottom-up so inner zones read on top).
## The danger zone is every cell within attack_range of some cell the enemy
## can move to this turn (reachable cells × attack range union).
func _refresh_enemy_range_overlays(enemy: PrototypeUnit) -> void:
	var origin := enemy.grid_cell
	var danger: Dictionary = {}
	for target_cell in grid.get_reachable_cells(origin, enemy.move_range):
		for level in range(grid.get_level_count()):
			for z in range(grid.get_grid_size().y):
				for x in range(grid.get_grid_size().x):
					var cell := Vector3i(x, level, z)
					if grid.has_cell(cell) and GridVisibility.tactical_distance(target_cell, cell) <= enemy.attack_range:
						danger[cell] = true
	var footprint := grid.get_grid_size()
	for level in range(grid.get_level_count()):
		for z in range(footprint.y):
			for x in range(footprint.x):
				var cell := Vector3i(x, level, z)
				if not grid.has_cell(cell) or cell == origin:
					continue
				var distance := GridVisibility.tactical_distance(origin, cell)
				if distance <= enemy.vision_range:
					_add_highlight(vision_highlights_root, cell, ENEMY_VISION_COLOR, 0.045)
				if danger.has(cell):
					_add_highlight(vision_highlights_root, cell, ENEMY_DANGER_COLOR, 0.065)
				if distance <= enemy.move_range:
					_add_highlight(vision_highlights_root, cell, ENEMY_MOVE_COLOR, 0.085)


func _refresh_move_highlights() -> void:
	_refresh_highlights()


func _add_highlight(parent: Node3D, cell: Vector3i, color: Color, height_offset: float = MOVE_HIGHLIGHT_SURFACE_OFFSET) -> void:
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
	highlight.global_position = grid.cell_to_world(cell) + Vector3.UP * height_offset
	highlight.visible = true


func _refresh_object_highlights() -> void:
	if not is_instance_valid(object_highlights_root):
		return
	if input_locked:
		return
	if session_manager == null or not _player_can_act():
		return
	if not is_instance_valid(selected_unit) or selected_unit.faction != &"player" or not selected_unit.is_alive():
		return
	var state: int = session_manager.get_state()
	var can_loot: bool = state == GameStateManagerScript.State.EXPLORATION \
		or (state == GameStateManagerScript.State.COMBAT and turn_manager.is_player_turn())
	var can_extract: bool = state == GameStateManagerScript.State.EXPLORATION
	for object_id in loot_containers.keys():
		var container = loot_containers[object_id]
		var placement = object_placements.get(object_id)
		if placement == null or container == null or container.is_depleted():
			continue
		if can_loot and _manhattan(selected_unit.grid_cell, placement.cell) <= INTERACTION_RANGE:
			_add_highlight(object_highlights_root, placement.cell, LOOT_HIGHLIGHT_COLOR)
	for cell in extraction_cells:
		if can_extract and _manhattan(selected_unit.grid_cell, cell) <= INTERACTION_RANGE:
			_add_highlight(object_highlights_root, cell, EXTRACTION_HIGHLIGHT_COLOR)


func _clear_highlights() -> void:
	if is_instance_valid(highlights_root):
		_clear_children(highlights_root)
	if is_instance_valid(attack_highlights_root):
		_clear_children(attack_highlights_root)
	if is_instance_valid(object_highlights_root):
		_clear_children(object_highlights_root)


## Darkens every cell NOT visible to any living player unit (range + LOS)
## with a semi-transparent black overlay, always on. Rebuilds on every
## highlight refresh.
func _refresh_vision_overlay() -> void:
	if not is_instance_valid(vision_highlights_root):
		return
	_clear_children(vision_highlights_root)
	if debug_reveal_all:
		return
	var observers: Array = []
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == &"player" and unit.is_alive():
			observers.append([unit.grid_cell, unit.vision_range])
	if observers.is_empty():
		return
	var footprint := grid.get_grid_size()
	for level in range(grid.get_level_count()):
		for z in range(footprint.y):
			for x in range(footprint.x):
				var cell := Vector3i(x, level, z)
				if not grid.has_cell(cell):
					continue
				var visible := false
				for observer in observers:
					if GridVisibility.has_line_of_sight(observer[0], cell, opaque_cells, observer[1]):
						visible = true
						break
				if not visible:
					_add_highlight(vision_highlights_root, cell, VISION_BLOCK_COLOR)


func _clear_move_highlights() -> void:
	_clear_highlights()


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _on_end_turn_pressed() -> void:
	if input_locked or _is_terminal() or session_manager == null:
		return
	if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION:
		await _run_exploration_tick()
		_evaluate_detection()
		_update_hud("探索世界 Tick %d。" % world_tick)
		_log("世界 Tick %d：敌人巡逻，玩家 AP 重置。" % world_tick)
		return
	if turn_manager.end_player_turn():
		await _run_enemy_turn()


func _on_unit_died(unit: PrototypeUnit) -> void:
	_log("%s 阵亡（HP 归零）。" % unit.name)
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
	if unit.faction == &"player" and _living_player_count() == 0:
		if session_manager != null:
			session_manager.report_team_defeated()
	_update_enemy_visibility()
	_refresh_highlights()
	_update_hud()


func _on_phase_changed(_previous: TurnManager.Phase, _current: TurnManager.Phase) -> void:
	match _current:
		TurnManager.Phase.PLAYER_TURN:
			_log("—— 玩家回合开始 ——")
		TurnManager.Phase.ENEMY_TURN:
			_log("—— 敌方回合开始 ——")
		TurnManager.Phase.VICTORY:
			_log("—— 交战结束：敌方全灭 ——")
		TurnManager.Phase.DEFEAT:
			_log("—— 交战结束：小队全灭 ——")
	if _current == TurnManager.Phase.VICTORY and session_manager != null and session_manager.get_state() == GameStateManagerScript.State.COMBAT:
		var resolved_id := active_encounter_id
		turn_manager.reset_to_exploration()
		if not resolved_id.is_empty():
			resolved_encounters[resolved_id] = true
		active_encounter_id = &""
		turn_manager.configure(_living_player_ids(), [])
		session_manager.resolve_combat()
	elif _current == TurnManager.Phase.DEFEAT and session_manager != null:
		session_manager.report_team_defeated()
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
	for player_id in _living_player_ids():
		var player := _unit_by_id(player_id)
		if not is_instance_valid(player):
			continue
		var distance := _manhattan(from_cell, player.grid_cell)
		if distance < best_distance:
			best_distance = distance
			result = player
	return result


func _living_player_count() -> int:
	var count := 0
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if is_instance_valid(unit) and unit.faction == &"player" and unit.is_alive():
			count += 1
	return count


func _object_at_cell(cell: Vector3i) -> StringName:
	for object_id in object_placements.keys():
		var placement = object_placements[object_id]
		if placement != null and placement.cell == cell:
			return object_id
	return &""


func _extraction_at_cell(cell: Vector3i) -> StringName:
	for object_id in object_placements.keys():
		var placement = object_placements[object_id]
		if placement != null and placement.kind == MapObjectPlacement.Kind.EXTRACTION and placement.cell == cell:
			return object_id
	return &""


## Loot / inventory management is allowed during exploration AND during the
## player's turn in combat (enemy turns block it via _player_can_act).
func _can_use_loot_action() -> bool:
	if not is_instance_valid(selected_unit) or not selected_unit.is_alive() or session_manager == null:
		return false
	if not _player_can_act():
		return false
	var state: int = session_manager.get_state()
	return state == GameStateManagerScript.State.EXPLORATION \
		or (state == GameStateManagerScript.State.COMBAT and turn_manager.is_player_turn())


## Extraction confirmation remains an exploration-only action.
func _can_use_exploration_action() -> bool:
	return is_instance_valid(selected_unit) and selected_unit.is_alive() and session_manager != null \
		and session_manager.get_state() == GameStateManagerScript.State.EXPLORATION \
		and _player_can_act()


func _loot_item(container_id: StringName, index: int) -> ActionResult:
	if container_id != open_loot_container_id:
		return _action_rejected(&"invalid_container", ACTION_LOOT)
	var container = loot_containers.get(container_id)
	var item = container.get_item(index) if container != null else null
	if item == null or squad_inventory == null:
		return _action_rejected(&"invalid_target", ACTION_LOOT)
	var anchor: Vector2i = squad_inventory.find_first_fit(item)
	if anchor == SquadInventoryScript.NO_FIT:
		_update_hud("空间碎片：该物品没有连续合法位置，Loot 与 AP 未改变。")
		return _action_rejected(&"inventory_full", ACTION_LOOT)
	return place_loot_instance(container_id, index, anchor, item.rotation)


func _loot_all(container_id: StringName) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	var container = loot_containers.get(container_id)
	var placement = object_placements.get(container_id)
	var player := selected_unit
	var contents: Array = container.get_contents_instances() if container != null else []
	var request := ActionRequestScript.new(
		ACTION_LOOT,
		player.unit_id,
		container_id,
		LOOT_ACTION_COST,
		{
			&"operation": &"loot_all",
			ActionExecutorScript.KEY_ACTOR_CELL: player.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: placement.cell if placement != null else Vector3i(-1, -1, -1),
			ActionExecutorScript.KEY_INTERACTION_RANGE: INTERACTION_RANGE,
			ActionExecutorScript.KEY_CONTAINER_VALID: container != null and placement != null and container_id == open_loot_container_id,
			ActionExecutorScript.KEY_CONTAINER_AVAILABLE: container != null and not container.is_depleted(),
			ActionExecutorScript.KEY_INVENTORY_CAN_RECEIVE: squad_inventory != null and container != null and squad_inventory.can_add_items(contents),
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		_update_hud(_action_message("无法全部拾取", result.reason))
		return result
	_refresh_inventory_ui()
	_update_hud("已全部拾取（不消耗 AP）。")
	_log("全部拾取 %s（%d 件，不消耗 AP）。" % [container_id, contents.size()])
	_refresh_highlights()
	return result


func _on_loot_item_pressed(index: int) -> void:
	loot_item(index)


func _on_loot_all_button_pressed() -> void:
	loot_all()


func _refresh_loot_panel() -> void:
	if not is_instance_valid(loot_grid):
		return
	var container = loot_containers.get(open_loot_container_id)
	if container == null:
		loot_title_label.text = "Loot"
		loot_all_button.disabled = true
		loot_grid.clear_container()
		return
	loot_title_label.text = "%s | %d 件" % [open_loot_container_id, container.get_item_count()]
	loot_all_button.disabled = container.is_depleted()
	loot_grid.set_container(container)
	if container.is_depleted():
		loot_title_label.text += " | 已耗尽"


func _close_loot_panel() -> void:
	if is_instance_valid(loot_panel):
		loot_panel.visible = false
	open_loot_container_id = &""
	_restore_inventory_after_loot_state()


func _on_extraction_confirm_pressed() -> void:
	confirm_extraction()


func _on_extraction_cancel_pressed() -> void:
	cancel_extraction()


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


func _on_inventory_collapse_pressed() -> void:
	_set_inventory_body_collapsed(not inventory_body_collapsed)


func _set_inventory_body_collapsed(collapsed: bool) -> void:
	inventory_body_collapsed = collapsed
	var body_visible := not collapsed
	inventory_summary_label.visible = body_visible
	inventory_hint_label.visible = body_visible
	inventory_grid.visible = body_visible
	loot_overview_label.visible = body_visible
	inventory_collapse_button.text = "展开" if collapsed else "收起"
	inventory_panel.offset_bottom = INVENTORY_PANEL_COLLAPSED_BOTTOM if collapsed else INVENTORY_PANEL_EXPANDED_BOTTOM


func _restore_inventory_after_loot_state() -> void:
	if not _restore_inventory_after_loot:
		return
	_restore_inventory_after_loot = false
	_set_inventory_body_collapsed(true)


func _on_session_state_changed(_previous: int, current: int) -> void:
	if current != GameStateManagerScript.State.EXTRACTION and is_instance_valid(extraction_panel):
		extraction_panel.visible = false
	if current != GameStateManagerScript.State.RESULT and is_instance_valid(result_panel):
		result_panel.visible = false
	if current != GameStateManagerScript.State.EXPLORATION and current != GameStateManagerScript.State.COMBAT and is_instance_valid(loot_panel):
		loot_panel.visible = false
		open_loot_container_id = &""
		_restore_inventory_after_loot_state()
	if is_instance_valid(inventory_grid):
		inventory_grid.refresh()
	if is_instance_valid(loot_grid) and current != GameStateManagerScript.State.EXPLORATION:
		loot_grid.clear_container()
	_refresh_highlights()
	_update_hud()


func _on_session_result_changed(result: RefCounted) -> void:
	if result.success:
		loot_settlement = LootSettlementScript.from_inventory(true, squad_inventory)
		_log("结算：撤离成功，带出 %d 件物品，总价值 %d。" % [loot_settlement.get_items().size(), loot_settlement.get_total_value()])
	else:
		loot_settlement = LootSettlementScript.failure_snapshot()
		_log("结算：任务失败，小队全灭，Loot 全部丢失。")
	_refresh_result_panel()
	_update_hud("撤离成功，结算已完成。" if result.success else "小队全灭，Loot 全部丢失。")


func _refresh_result_panel() -> void:
	if not is_instance_valid(result_panel):
		return
	result_panel.visible = true
	var successful: bool = loot_settlement != null and loot_settlement.is_successful()
	result_title_label.text = "任务成功" if successful else "任务失败"
	result_value_label.text = "带出总价值：%d" % (loot_settlement.get_total_value() if loot_settlement != null else 0)
	var names: Array[String] = []
	if loot_settlement != null:
		for item in loot_settlement.get_items():
			names.append("%s（占%d格，%d°）" % [item.display_name, item.slot_size, item.rotation])
	result_items_label.text = "带出物品：" + ("、".join(names) if not names.is_empty() else "无")


func _action_rejected(reason: StringName, action_type: StringName, actor_id: StringName = &"", target_id: StringName = &"") -> ActionResult:
	last_action_result = ActionResultScript.rejected(reason, actor_id, target_id, action_type)
	return last_action_result


func _action_message(prefix: String, reason: StringName) -> String:
	var messages := {
		&"invalid_target": "目标无效",
		&"invalid_container": "容器无效",
		&"target_unavailable": "目标不可用",
		&"container_unavailable": "容器已耗尽",
		&"no_ap": "AP 不足",
		&"out_of_range": "距离过远",
		&"inventory_full": "背包空间不足",
		&"wrong_phase": "当前阶段不可操作",
	}
	return "%s：%s。" % [prefix, messages.get(reason, String(reason))]


func _update_enemy_visibility() -> void:
	if not is_instance_valid(turn_manager):
		return
	for enemy_id in _living_enemy_ids():
		var enemy := _unit_by_id(enemy_id)
		if not is_instance_valid(enemy):
			continue
		var visible_to_player := debug_reveal_all
		for player_id in _living_player_ids():
			if visible_to_player:
				break
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
	return is_instance_valid(turn_manager) and session_manager != null and session_manager.is_active() and (
		session_manager.get_state() != GameStateManagerScript.State.EXTRACTION and (
			turn_manager.get_phase() == TurnManager.Phase.EXPLORATION or turn_manager.is_player_turn()
		)
	)


func _can_show_move_highlights() -> bool:
	return not input_locked \
		and is_instance_valid(selected_unit) \
		and selected_unit.faction == &"player" \
		and selected_unit.is_alive() \
		and _player_can_act() \
		and selected_unit.can_spend_action_points(MOVE_ACTION_COST)


func _is_terminal() -> bool:
	return session_manager != null and session_manager.is_terminal()


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


## Prints a structured combat/exploration line to the Godot Output log,
## prefixed with the current side and world tick.
func _log(message: String) -> void:
	print("[%s · T%d] %s" % [_log_side_name(), world_tick, message])


func _log_side_name() -> String:
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.COMBAT and turn_manager != null:
		match turn_manager.get_phase():
			TurnManager.Phase.PLAYER_TURN: return "玩家回合"
			TurnManager.Phase.ENEMY_TURN: return "敌方回合"
		return "交战"
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.EXTRACTION:
		return "撤离"
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.RESULT:
		return "结算"
	return "探索"


func _phase_name() -> String:
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.RESULT:
		return "结果"
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.EXTRACTION:
		return "撤离确认"
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
		if selected_unit.faction == &"enemy":
			var alert_text := "未警戒"
			if enemy_alerts.has(selected_unit.unit_id):
				var alert := enemy_alerts[selected_unit.unit_id] as AlertState
				match alert.get_level():
					AlertState.Level.SUSPICIOUS: alert_text = "怀疑"
					AlertState.Level.ENGAGED: alert_text = "交战"
			selection_label.text = "%s | HP %d/%d | 移动 %d | 伤害 %d (危险 %d) | 视野 %d | %s" % [
				selected_unit.name, selected_unit.current_hp, selected_unit.max_hp,
				selected_unit.move_range, selected_unit.attack_damage,
				selected_unit.attack_range, selected_unit.vision_range, alert_text,
			]
		else:
			var archetype_name := selected_unit.archetype.display_name if selected_unit.archetype != null else "未配置原型"
			selection_label.text = "%s | 原型 %s | 武器 %s\n伤害 %d | 射程 %d | 攻击 AP %d\nHP %d/%d | AP %d/%d | 格 %s" % [
				selected_unit.name, archetype_name, selected_unit.get_weapon_display_name(),
				selected_unit.attack_damage, selected_unit.attack_range, selected_unit.attack_ap_cost,
				selected_unit.current_hp, selected_unit.max_hp,
				selected_unit.current_action_points, selected_unit.max_action_points,
				selected_unit.grid_cell,
			]
	else:
		selection_label.text = "未选择单位"
	end_turn_button.text = "推进探索 Tick" if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION else "结束玩家回合"
	end_turn_button.disabled = input_locked or _is_terminal() or turn_manager.is_enemy_turn() or (session_manager != null and session_manager.get_state() == GameStateManagerScript.State.EXTRACTION)
	if is_instance_valid(inventory_summary_label) and squad_inventory != null:
		inventory_summary_label.text = "背包 6×8 · %d/%d | 总价值 %d" % [squad_inventory.used, squad_inventory.capacity, squad_inventory.total_value()]
	if is_instance_valid(inventory_grid) and squad_inventory != null:
		inventory_grid.refresh()
	if is_instance_valid(loot_overview_label):
		var available := 0
		for container_value in loot_containers.values():
			var container = container_value
			if container != null and not container.is_depleted():
				available += 1
		loot_overview_label.text = "Loot 容器：%d 个可搜刮" % available
	if not message.is_empty():
		hint_label.text = message
