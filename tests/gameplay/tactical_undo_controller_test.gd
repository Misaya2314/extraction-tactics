extends SceneTree

## Scene-free integration coverage for the Controller's undo adapter.  The
## fixture deliberately builds only an in-memory GridModel, session/turn
## managers, runtime states and View nodes; it never loads a map or main
## scene.  This keeps checkpoint semantics independent of authored content.

const ControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const UnitScript = preload("res://scripts/gameplay/prototype_unit.gd")
const UnitRuntimeStateScript = preload("res://scripts/core/units/unit_runtime_state.gd")
const WeaponDefinitionScript = preload("res://scripts/core/combat/weapon_definition.gd")
const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")
const UnitArchetypeScript = preload("res://scripts/core/units/unit_archetype.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const TurnManagerScript = preload("res://scripts/core/turn/turn_manager.gd")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")
const CoverCombatSettingsScript = preload("res://scripts/core/cover/cover_combat_settings.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")
const ItemDefinitionScript = preload("res://scripts/core/items/item_definition.gd")
const InventoryItemInstanceScript = preload("res://scripts/core/inventory/inventory_item_instance.gd")
const InventoryGridControlScript = preload("res://scripts/gameplay/ui/inventory_grid_control.gd")
const IdGeneratorScript = preload("res://scripts/core/runtime/instance_id_generator.gd")
const AlertStateScript = preload("res://scripts/core/encounter/alert_state.gd")

const PLAYER_ID: StringName = &"undo_player"
const ENEMY_ID: StringName = &"undo_enemy"
const START_CELL := Vector3i(1, 0, 1)
const ENEMY_CELL := Vector3i(4, 0, 1)

var _failures: Array[String] = []
var _controller
var _player
var _enemy
var _archetype
var _weapon_definition
var _view_root: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_main_scene_undo_controls()
	_test_inventory_panel_bounds()
	_test_initial_button_state_and_move_undo()
	_test_failed_action_does_not_replace_step()
	_test_inventory_checkpoint_restores_placement()
	_test_attack_undo_restores_dead_roster_member()
	_test_enemy_actions_do_not_create_checkpoint()
	_test_second_combat_turn_checkpoint_includes_ap_reset()
	_finish()


func _test_main_scene_undo_controls() -> void:
	var scene_text := FileAccess.get_file_as_string("res://scenes/main/prototype_main.tscn")
	_expect(not scene_text.is_empty(), "HUD: main scene should be readable")
	_expect(scene_text.contains("name=\"UndoStepButton\""), "HUD: main scene should declare step undo button")
	_expect(scene_text.contains("name=\"UndoTurnButton\""), "HUD: main scene should declare turn undo button")
	_expect(scene_text.contains("text = \"撤回上一步\""), "HUD: step undo label should be visible")
	_expect(scene_text.contains("text = \"撤回至回合开始\""), "HUD: turn undo label should be visible")
	_expect(scene_text.contains("name=\"ApLabel\""), "HUD: main scene should declare ApLabel in ActionBar")


func _test_inventory_panel_bounds() -> void:
	_build_fixture()
	var ui_root := Control.new()
	ui_root.name = "InventoryBoundsFixture"
	ui_root.size = Vector2(1366.0, 720.0)
	get_root().add_child(ui_root)

	var top_left_panel := PanelContainer.new()
	top_left_panel.name = "TopLeftPanel"
	top_left_panel.offset_left = 16.0
	top_left_panel.offset_right = 362.0
	top_left_panel.offset_top = 16.0
	top_left_panel.offset_bottom = 296.0
	ui_root.add_child(top_left_panel)
	var top_left_margin := MarginContainer.new()
	top_left_panel.add_child(top_left_margin)
	var top_left_vbox := VBoxContainer.new()
	top_left_margin.add_child(top_left_vbox)
	var multiline_selection := Label.new()
	multiline_selection.name = "SelectionLabel"
	multiline_selection.text = ("单位状态：长状态文本\n").repeat(16)
	top_left_vbox.add_child(multiline_selection)
	var top_left_minimum_height := top_left_panel.get_combined_minimum_size().y
	_expect(top_left_minimum_height > 280.0, "inventory bounds: multiline status should grow top-left minimum")
	_controller.top_left_panel = top_left_panel

	var panel := PanelContainer.new()
	panel.name = "InventoryPanel"
	panel.offset_left = 16.0
	panel.offset_right = 365.0
	panel.offset_top = 307.0
	panel.offset_bottom = 363.0
	ui_root.add_child(panel)
	_controller.inventory_panel = panel

	var margin := MarginContainer.new()
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "背包"
	header.add_child(title)
	var collapse_button := Button.new()
	collapse_button.text = "展开"
	header.add_child(collapse_button)
	_controller.inventory_collapse_button = collapse_button
	var summary := Label.new()
	summary.text = "背包 0/48 | 总价值 0 · 6×8"
	summary.visible = false
	vbox.add_child(summary)
	_controller.inventory_summary_label = summary
	var hint := Label.new()
	hint.text = "拖动重排；R 或右键旋转；Loot 物品拖入指定格"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.visible = false
	vbox.add_child(hint)
	_controller.inventory_hint_label = hint
	var grid := InventoryGridControlScript.new() as InventoryGridControl
	grid.custom_minimum_size = Vector2(180.0, 240.0)
	grid.visible = false
	vbox.add_child(grid)
	_controller.inventory_grid = grid
	var overview := Label.new()
	overview.text = "Loot 容器：0 个可搜刮"
	overview.visible = false
	vbox.add_child(overview)
	_controller.loot_overview_label = overview

	_controller._set_inventory_body_collapsed(true)
	var expected_top := top_left_panel.offset_top + maxf(top_left_panel.get_combined_minimum_size().y, top_left_panel.size.y) + 10.0
	_expect(panel.offset_top >= expected_top, "inventory bounds: collapsed top should follow top-left minimum")
	_expect(panel.offset_top > 307.0, "inventory bounds: multiline status should move inventory below authored top")
	_expect(panel.offset_bottom >= panel.offset_top, "inventory bounds: collapsed panel must not invert")
	_expect(is_equal_approx(panel.offset_bottom, panel.offset_top + 56.0), "inventory bounds: collapsed panel should use fixed height")
	_expect(panel.offset_top >= expected_top, "inventory bounds: top-left minimum plus gap must be respected")

	_controller._set_inventory_body_collapsed(false)
	var expanded_bottom := panel.offset_bottom
	_expect(is_equal_approx(panel.offset_top, expected_top), "inventory bounds: expanded top should remain synchronized")
	_expect(is_equal_approx(expanded_bottom - panel.offset_top, 410.0), "inventory bounds: expanded panel should use stable content height")
	_expect(expanded_bottom > panel.offset_top + 56.0, "inventory bounds: expanded panel should grow below collapsed bounds")
	_expect(expanded_bottom <= panel.offset_top + 420.0, "inventory bounds: expanded panel must not grow from outer minimum feedback")
	_controller._sync_inventory_panel_layout()
	var expanded_bottom_after_sync := panel.offset_bottom
	_controller._run_deferred_inventory_panel_layout_sync()
	var expanded_bottom_after_deferred := panel.offset_bottom
	_expect(is_equal_approx(expanded_bottom_after_sync, expanded_bottom), "inventory bounds: repeated sync must keep expanded height stable")
	_expect(is_equal_approx(expanded_bottom_after_deferred, expanded_bottom), "inventory bounds: deferred sync must not grow expanded height")

	_controller._set_inventory_body_collapsed(true)
	_expect(is_equal_approx(panel.offset_top, expected_top) and is_equal_approx(panel.offset_bottom, expected_top + 56.0), "inventory bounds: collapse after expand should restore valid bounds")
	var top_left_extent := top_left_panel.offset_top + maxf(top_left_panel.get_combined_minimum_size().y, top_left_panel.size.y)
	_expect(panel.offset_top >= top_left_extent + 10.0, "inventory bounds: repeated toggle must preserve status gap")
	ui_root.free()


func _build_fixture(lethal_attack: bool = false) -> void:
	if is_instance_valid(_controller):
		_free_fixture_ui(_controller)
		_controller.free()
	if not is_instance_valid(_view_root):
		_view_root = Node3D.new()
		_view_root.name = "UndoFixtureViews"
		get_root().add_child(_view_root)
	else:
		for child in _view_root.get_children():
			child.free()
	_controller = ControllerScript.new()
	_controller.grid = GridModelScript.new()
	_controller.grid.configure(Vector2i(8, 8), 2.0, Vector3.ZERO)
	_controller.turn_manager = TurnManagerScript.new()
	_controller.session_manager = GameStateManagerScript.new()
	_controller.session_manager.start_exploration()
	_controller.instance_id_generator = IdGeneratorScript.new(&"undo_fixture")
	_controller.squad_inventory = SquadInventoryScript.new()
	_controller.loot_containers = {}
	_controller.opaque_cells = {}
	_controller.cover_combat_settings = CoverCombatSettingsScript.make_default()
	_controller.debug_reveal_all = true

	_weapon_definition = WeaponDefinitionScript.new()
	_weapon_definition.weapon_id = &"undo_fixture_rifle"
	_weapon_definition.display_name = "Undo Rifle"
	_weapon_definition.damage = 20 if lethal_attack else 4
	_weapon_definition.range = 6
	_weapon_definition.ap_cost = 1
	_archetype = UnitArchetypeScript.new()
	_archetype.archetype_id = &"undo_fixture_soldier"
	_archetype.display_name = "Undo Soldier"
	_archetype.max_hp = 10
	_archetype.max_action_points = 3
	_archetype.move_range = 6
	_archetype.inner_vision_range = 2
	_archetype.vision_range = 6
	_archetype.default_weapon = _weapon_definition

	var player_weapon := WeaponInstanceScript.new(&"undo_weapon_player", _weapon_definition)
	var enemy_weapon := WeaponInstanceScript.new(&"undo_weapon_enemy", _weapon_definition)
	var player_state := UnitRuntimeStateScript.new(
		PLAYER_ID,
		_archetype,
		&"player",
		START_CELL,
		Vector2i(0, 1),
		player_weapon
	)
	var enemy_state := UnitRuntimeStateScript.new(
		ENEMY_ID,
		_archetype,
		&"enemy",
		ENEMY_CELL,
		Vector2i(0, -1),
		enemy_weapon
	)
	_expect(player_state.is_valid(), "fixture: player runtime state must be valid")
	_expect(enemy_state.is_valid(), "fixture: enemy runtime state must be valid")

	_player = _make_unit_view(player_state, "UndoPlayer", Color("4f9dff"))
	_enemy = _make_unit_view(enemy_state, "UndoEnemy", Color("ef5b5b"))

	var player_ids: Array[StringName] = [PLAYER_ID]
	var enemy_ids: Array[StringName] = [ENEMY_ID]
	_controller.all_player_ids = player_ids
	_controller.all_enemy_ids = enemy_ids
	_controller.units_by_id = {PLAYER_ID: _player, ENEMY_ID: _enemy}
	_controller.turn_manager.configure(player_ids, enemy_ids)
	_controller.grid.occupy(START_CELL, PLAYER_ID)
	_controller.grid.occupy(ENEMY_CELL, ENEMY_ID)
	_controller.selected_unit = _player
	_player.set_selected(true)

	# Synthetic presentation nodes let _update_hud/_post_undo_restore run
	# normally while keeping the test independent from a PackedScene.
	_controller.phase_label = Label.new()
	_controller.alert_label = Label.new()
	_controller.selection_label = Label.new()
	_controller.hint_label = Label.new()
	_controller.end_turn_button = Button.new()
	_controller.undo_step_button = Button.new()
	_controller.undo_turn_button = Button.new()

	_controller.enemy_alerts = {ENEMY_ID: AlertStateScript.new()}
	_controller.enemy_patrols = {}
	_controller.encounter_by_unit = {ENEMY_ID: &"undo_encounter"}
	_controller.encounter_members = {&"undo_encounter": enemy_ids}
	_controller.resolved_encounters = {}
	var discovering_ids: Array[StringName] = []
	_controller.discovering_enemy_ids = discovering_ids
	_controller.suspicious_investigations = {}
	_controller.input_locked = false
	_controller._configure_undo_manager()


func _make_unit_view(state: UnitRuntimeState, view_name: String, color: Color) -> PrototypeUnit:
	var unit := UnitScript.new() as PrototypeUnit
	unit.name = view_name
	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	var body := MeshInstance3D.new()
	body.name = "Body"
	visual_root.add_child(body)
	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	var weapon_model_root := Node3D.new()
	weapon_model_root.name = "WeaponModelRoot"
	weapon_pivot.add_child(weapon_model_root)
	var muzzle_flash := MeshInstance3D.new()
	muzzle_flash.name = "MuzzleFlash"
	weapon_pivot.add_child(muzzle_flash)
	visual_root.add_child(weapon_pivot)
	unit.add_child(visual_root)
	var selection_marker := MeshInstance3D.new()
	selection_marker.name = "SelectionMarker"
	unit.add_child(selection_marker)
	var facing_marker := MeshInstance3D.new()
	facing_marker.name = "FacingMarker"
	unit.add_child(facing_marker)
	var status_label := Label3D.new()
	status_label.name = "StatusLabel"
	unit.add_child(status_label)
	var alert_badge := Label3D.new()
	alert_badge.name = "AlertBadge"
	unit.add_child(alert_badge)
	_expect(unit.bind_runtime_state(state, color), "fixture: %s View should bind" % view_name)
	_view_root.add_child(unit)
	unit.global_position = _controller.grid.cell_to_world(state.cell)
	return unit


func _test_initial_button_state_and_move_undo() -> void:
	_build_fixture()
	_expect(_controller.undo_step_button.disabled, "buttons: step undo starts disabled")
	_expect(_controller.undo_turn_button.disabled, "buttons: turn undo starts disabled")
	_commit_player_move(Vector3i(2, 0, 1), "move: first player move should commit")
	_expect(_player.grid_cell == Vector3i(2, 0, 1), "move: state should reach destination")
	_expect(_controller.grid.get_occupant(Vector3i(2, 0, 1)) == PLAYER_ID, "move: destination should be occupied")
	_expect(_player.current_action_points == 2, "move: AP should be spent exactly once")
	_expect(not _controller.undo_step_button.disabled, "buttons: step undo enables after success")
	_expect(not _controller.undo_turn_button.disabled, "buttons: turn undo enables after success")

	_controller._perform_undo(false)
	_expect(_player.grid_cell == START_CELL, "move undo: cell should return to checkpoint")
	_expect(_player.current_action_points == 3, "move undo: AP should return to checkpoint")
	_expect(_controller.grid.get_occupant(START_CELL) == PLAYER_ID, "move undo: start occupancy should return")
	_expect(_controller.grid.get_occupant(Vector3i(2, 0, 1)) == &"", "move undo: destination occupancy should clear")
	_expect(_player.global_position == _controller.grid.cell_to_world(START_CELL), "move undo: View should return to grid center")
	_expect(_controller.undo_step_button.disabled, "buttons: consumed step undo should disable")
	_expect(not _controller.undo_turn_button.disabled, "buttons: step undo must leave turn undo available")


func _test_failed_action_does_not_replace_step() -> void:
	_build_fixture()
	_commit_player_move(Vector3i(2, 0, 1), "failed action: setup move should commit")
	var old_cell: Vector3i = _player.grid_cell
	var old_ap: int = _player.current_action_points
	var started: bool = _controller._begin_undo_player_action(_player)
	_expect(started, "failed action: transaction should open")
	_controller._finish_undo_player_action(started, false)
	_controller._refresh_undo_buttons()
	_expect(_player.grid_cell == old_cell and _player.current_action_points == old_ap, "failed action: rejected action must not mutate state")
	_expect(not _controller.undo_step_button.disabled, "failed action: rejected action must preserve old step")
	_controller._perform_undo(false)
	_expect(_player.grid_cell == START_CELL, "failed action: preserved step should still undo the move")
	_expect(_player.current_action_points == 3, "failed action: preserved step should restore AP")


func _test_attack_undo_restores_dead_roster_member() -> void:
	_build_fixture(true)
	_controller._configure_action_executor()
	_controller.turn_manager.phase_changed.connect(_controller._on_phase_changed)
	_controller.session_manager.state_changed.connect(_controller._on_session_state_changed)
	_controller.session_manager.result_changed.connect(_controller._on_session_result_changed)
	_enemy.died.connect(_controller._on_unit_died)

	var attack_result: ActionResult = await _controller._attack_with_unit(_player, _enemy)
	_expect(attack_result != null and attack_result.success, "attack: lethal synthetic attack should succeed")
	_expect(attack_result != null and attack_result.killed, "attack: result should record the kill")
	_expect(not _enemy.is_alive(), "attack: target should be dead after action")
	_expect(_enemy.visible == false, "attack: dead View should be hidden")
	_expect(not _controller.turn_manager.has_unit(ENEMY_ID), "attack: dead enemy should leave living turn roster")
	_expect(_player.current_action_points == 2, "attack: AP should be spent exactly once")
	_expect(not _controller.undo_step_button.disabled, "attack: successful attack should expose step undo")

	_controller._perform_undo(false)
	_expect(_enemy.is_alive(), "attack undo: dead runtime state should be restored")
	_expect(_enemy.visible, "attack undo: restored View should become visible")
	_expect(_enemy.process_mode != Node.PROCESS_MODE_DISABLED, "attack undo: restored View should process")
	_expect(_controller.units_by_id.has(ENEMY_ID), "attack undo: dead View should remain in roster index")
	_expect(_controller.turn_manager.get_phase() == TurnManagerScript.Phase.EXPLORATION, "attack undo: action should return to exploration")
	_expect(_controller._activate_encounter_for(_enemy), "attack undo: restored enemy should be re-activatable")
	_expect(_controller.grid.get_occupant(ENEMY_CELL) == ENEMY_ID, "attack undo: enemy occupancy should return")
	_expect(_player.current_action_points == 3, "attack undo: player AP should return")
	_expect(_enemy.global_position == _controller.grid.cell_to_world(ENEMY_CELL), "attack undo: enemy should be at grid center")


func _test_inventory_checkpoint_restores_placement() -> void:
	_build_fixture()
	var item_definition := ItemDefinitionScript.new()
	item_definition.item_id = &"undo_fixture_item"
	item_definition.display_name = "Undo Item"
	item_definition.value = 42
	item_definition.shape_cells = [Vector2i(0, 0), Vector2i(1, 0)]
	var item := InventoryItemInstanceScript.new(&"undo_item_instance", item_definition)
	_expect(item.is_valid(), "inventory undo: synthetic item should be valid")
	_expect(_controller.squad_inventory.place(item, Vector2i(0, 0), 0), "inventory undo: setup placement should succeed")
	var started: bool = _controller._begin_undo_player_action(_player)
	_expect(started, "inventory undo: management transaction should open")
	var moved: bool = _controller.squad_inventory.move(item.instance_id, Vector2i(2, 2), 90)
	var generated_id: StringName = _controller.instance_id_generator.next_id(&"undo_probe")
	_expect(moved and generated_id != &"", "inventory undo: placement and generator mutation should succeed")
	_controller._finish_undo_player_action(started, moved and generated_id != &"")
	_controller._refresh_undo_buttons()
	var changed_placement = _controller.squad_inventory.get_placement(item.instance_id)
	_expect(changed_placement != null and changed_placement.anchor == Vector2i(2, 2) and changed_placement.rotation == 90, "inventory undo: action should change authoritative placement")
	_expect(item.rotation == 0, "inventory undo: instance compatibility rotation must not be authoritative")
	_expect(not _controller.undo_step_button.disabled, "inventory undo: successful management action should expose step undo")

	_controller._perform_undo(false)
	var restored_placement = _controller.squad_inventory.get_placement(item.instance_id)
	_expect(restored_placement != null and restored_placement.anchor == Vector2i.ZERO and restored_placement.rotation == 0, "inventory undo: anchor and rotation should restore")
	_expect(restored_placement != null and restored_placement.instance == item, "inventory undo: same ItemInstance should be restored")
	_expect(item.get_owner_id() == &"inventory:squad_inventory", "inventory undo: item owner should restore")
	var next_generated_id: StringName = _controller.instance_id_generator.next_id(&"undo_probe")
	_expect(next_generated_id == &"undo_fixture:undo_probe:0000", "inventory undo: generator state should restore")


func _test_enemy_actions_do_not_create_checkpoint() -> void:
	_build_fixture()
	_controller.tactical_undo_manager.invalidate_all()
	_expect(_controller._capture_undo_turn_checkpoint(), "enemy action: fixture turn checkpoint should capture")
	var started: bool = _controller._begin_undo_player_action(_enemy)
	_expect(not started, "enemy action: enemy must not open a player undo transaction")
	_expect(_enemy.spend_action_points(1), "enemy action: synthetic enemy mutation should be possible")
	_controller._refresh_undo_buttons()
	_expect(not _controller.tactical_undo_manager.can_undo_step(), "enemy action: enemy mutation must not create step checkpoint")
	_expect(not _controller.tactical_undo_manager.can_undo_turn(), "enemy action: enemy mutation must not mark turn successful")


func _test_second_combat_turn_checkpoint_includes_ap_reset() -> void:
	_build_fixture()
	_expect(_controller.session_manager.start_combat(), "turn checkpoint: session should enter combat")
	_expect(_controller.turn_manager.start_combat(true), "turn checkpoint: first player turn should start")
	_player.reset_action_points()
	_controller.tactical_undo_manager.invalidate_all()
	_expect(_controller._capture_undo_turn_checkpoint(), "turn checkpoint: first combat turn should capture")
	_expect(_player.spend_action_points(2), "turn checkpoint: setup should deplete first-turn AP")
	_expect(_controller.turn_manager.end_player_turn(), "turn checkpoint: player turn should end")
	_controller._reset_faction_ap(&"player")
	_expect(_player.current_action_points == 3, "turn checkpoint: AP should reset between turns")
	_expect(_controller.turn_manager.end_enemy_turn(), "turn checkpoint: enemy turn should end")
	_expect(_controller._capture_undo_turn_checkpoint(), "turn checkpoint: second player turn should replace checkpoint")

	_commit_player_move(Vector3i(2, 0, 1), "turn checkpoint: second-turn move should commit")
	_controller._perform_undo(true)
	_expect(_player.grid_cell == START_CELL, "turn checkpoint undo: cell should use second-turn start")
	_expect(_player.current_action_points == 3, "turn checkpoint undo: checkpoint must include reset AP")
	_expect(_controller.session_manager.get_state() == GameStateManagerScript.State.COMBAT, "turn checkpoint undo: session should remain combat")
	_expect(_controller.turn_manager.get_phase() == TurnManagerScript.Phase.PLAYER_TURN, "turn checkpoint undo: phase should remain player turn")
	_expect(_controller.undo_step_button.disabled, "turn checkpoint undo: step should be consumed")
	_expect(_controller.undo_turn_button.disabled, "turn checkpoint undo: turn checkpoint should be consumed")


func _commit_player_move(destination: Vector3i, message: String) -> void:
	var started: bool = _controller._begin_undo_player_action(_player)
	_expect(started, message + " (transaction)")
	if not started:
		return
	var start: Vector3i = _player.grid_cell
	var changed: bool = _player.spend_action_points(1)
	var vacated: bool = _controller.grid.vacate(start, PLAYER_ID)
	var occupied: bool = _controller.grid.occupy(destination, PLAYER_ID)
	var moved: bool = _set_player_cell(destination)
	_player.global_position = _controller.grid.cell_to_world(destination)
	_expect(changed and vacated and occupied and moved, message + " (domain mutation)")
	_controller._finish_undo_player_action(started, changed and vacated and occupied and moved)
	_controller._refresh_undo_buttons()


func _set_player_cell(destination: Vector3i) -> bool:
	var before: Vector3i = _player.grid_cell
	_player.grid_cell = destination
	return _player.grid_cell == destination and before != destination


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _free_fixture_ui(controller: Variant) -> void:
	if controller == null:
		return
	var controls: Array = [
		controller.phase_label,
		controller.alert_label,
		controller.selection_label,
		controller.hint_label,
		controller.end_turn_button,
		controller.undo_step_button,
		controller.undo_turn_button,
	]
	for raw_control in controls:
		var control := raw_control as Node
		if is_instance_valid(control):
			control.free()


func _finish() -> void:
	if is_instance_valid(_controller):
		_free_fixture_ui(_controller)
		_controller.free()
	if is_instance_valid(_view_root):
		_view_root.free()
	if _failures.is_empty():
		print("TACTICAL_UNDO_CONTROLLER_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_UNDO_CONTROLLER_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
