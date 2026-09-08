extends SceneTree

## 搜打撤数据驱动任务系统测试：
## 1. 消灭敌人不结束游戏；
## 2. 0 AP 目标交互；
## 3. Undo 交互状态回滚；
## 4. 完成任务撤离结算；
## 5. 未完成任务也允许撤离并报告未完成状态。

const ControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const UnitScene = preload("res://scenes/main/prototype_unit.tscn")
const TerminalScene = preload("res://scenes/prototype/environment/prototype_objective_terminal.tscn")
const MissionDefinitionScript = preload("res://scripts/core/mission/mission_definition.gd")
const MissionStepDefinitionScript = preload("res://scripts/core/mission/mission_step_definition.gd")

class QuietExtractionController extends ControllerScript:
	func _update_hud(_message: String = "") -> void:
		pass
	func _refresh_highlights() -> void:
		pass
	func _update_enemy_visibility() -> void:
		pass
	func _log(_message: String) -> void:
		pass
	func _clear_highlights() -> void:
		pass
	func _refresh_result_panel() -> void:
		# 仅在需要时刷新文本，保持测试可验证
		super()

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_kill_enemy_does_not_win()
	_test_zero_ap_objective_interact_and_undo()
	_test_completed_mission_extraction()
	_test_incomplete_mission_extraction()
	_test_objective_match_by_definition_id()
	
	for failure in failures:
		push_error(failure)
	print("EXTRACTION_MISSION_TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _create_fixture(with_mission: bool = true) -> QuietExtractionController:
	var c := QuietExtractionController.new()
	c.grid = GridModel.new()
	
	var map := TacticalMapDefinition.new()
	map.map_id = &"test_extraction_map"
	map.footprint_size = Vector2i(10, 3)
	for x in range(10):
		for z in range(3):
			var cell := MapCellData.new()
			cell.coordinate = Vector3i(x, 0, z)
			cell.walkable = true
			map.cells.append(cell)
	
	# 添加任务目标终端放置物 (Kind.OBJECTIVE)
	var terminal_placement := MapObjectPlacement.new()
	terminal_placement.object_id = &"terminal_1"
	terminal_placement.definition_id = &"prototype_objective_terminal"
	terminal_placement.kind = MapObjectPlacement.Kind.OBJECTIVE
	terminal_placement.cell = Vector3i(3, 0, 1)
	terminal_placement.scene = TerminalScene
	terminal_placement.blocks_movement = true
	map.objects.append(terminal_placement)
	
	# 添加撤离点放置物 (Kind.EXTRACTION)
	var extraction_placement := MapObjectPlacement.new()
	extraction_placement.object_id = &"extraction_1"
	extraction_placement.kind = MapObjectPlacement.Kind.EXTRACTION
	extraction_placement.cell = Vector3i(6, 0, 1)
	map.objects.append(extraction_placement)
	
	# 配置任务定义
	if with_mission:
		var step = MissionStepDefinitionScript.new()
		step.step_id = &"hack_terminal"
		step.description = "破译前哨站机密终端"
		step.step_type = MissionStepDefinitionScript.StepType.INTERACT_OBJECT
		step.target_id = &"terminal_1"
		
		var mission = MissionDefinitionScript.new()
		mission.mission_id = &"outpost_heist"
		mission.title = "前哨站数据夺取"
		mission.steps.append(step)
		map.mission_definition = mission
	
	c.map_definition = map
	_expect(c.grid.configure_from_definition(map), "grid configuration")
	
	c.session_manager = GameStateManager.new()
	c.session_manager.start_exploration()
	c.session_manager.result_changed.connect(c._on_session_result_changed)
	c.turn_manager = TurnManager.new()
	c._configure_action_executor()
	
	# 创建简单武器与兵种
	var weapon := WeaponDefinition.new()
	weapon.weapon_id = &"rifle"
	weapon.display_name = "步枪"
	weapon.damage = 10
	weapon.range = 5
	
	var archetype := UnitArchetype.new()
	archetype.archetype_id = &"soldier"
	archetype.display_name = "士兵"
	archetype.max_hp = 10
	archetype.default_weapon = weapon
	
	# 生成 1 玩家单位与 1 敌人单位
	var player_id := &"player_0"
	var player_state := UnitRuntimeState.new(player_id, archetype, &"player", Vector3i(1, 0, 1), WeaponInstance.new(&"p_weap", weapon))
	var player_unit := UnitScene.instantiate() as PrototypeUnit
	player_unit.bind_runtime_state(player_state, Color.WHITE)
	get_root().add_child(player_unit)
	c.units_by_id[player_id] = player_unit
	c.grid.occupy(player_unit.grid_cell, player_id)
	c.all_player_ids.append(player_id)
	player_unit.died.connect(c._on_unit_died)
	
	var enemy_id := &"enemy_0"
	var enemy_state := UnitRuntimeState.new(enemy_id, archetype, &"enemy", Vector3i(8, 0, 1), WeaponInstance.new(&"e_weap", weapon))
	enemy_state.current_hp = 1 # 1点血便于消灭
	var enemy_unit := UnitScene.instantiate() as PrototypeUnit
	enemy_unit.bind_runtime_state(enemy_state, Color.RED)
	get_root().add_child(enemy_unit)
	c.units_by_id[enemy_id] = enemy_unit
	c.grid.occupy(enemy_unit.grid_cell, enemy_id)
	c.all_enemy_ids.append(enemy_id)
	enemy_unit.died.connect(c._on_unit_died)
	
	c._index_map_objects()
	c._apply_map_rules()
	c.mission_tracker.configure(map.mission_definition)
	c.selected_unit = player_unit
	c._configure_undo_manager()
	
	return c


func _cleanup(c: QuietExtractionController) -> void:
	for unit in c.units_by_id.values():
		unit.free()
	c.free()


func _test_kill_enemy_does_not_win() -> void:
	var c := _create_fixture(true)
	var enemy: PrototypeUnit = c.units_by_id[&"enemy_0"]
	
	# 击杀敌人
	enemy.take_damage(10)
	c._evaluate_mission_outcome()
	
	_expect(not enemy.is_alive(), "kill: enemy is dead")
	_expect(c.session_manager.is_active(), "kill: session is still active after killing enemy")
	_expect(not c.session_manager.is_terminal(), "kill: killing enemies never directly wins game")
	_cleanup(c)


func _test_zero_ap_objective_interact_and_undo() -> void:
	var c := _create_fixture(true)
	var player: PrototypeUnit = c.units_by_id[&"player_0"]
	
	# 移动玩家至 (2, 0, 1)，与位于 (3, 0, 1) 的终端相邻
	c.grid.vacate(player.grid_cell, player.unit_id)
	player.grid_cell = Vector3i(2, 0, 1)
	c.grid.occupy(player.grid_cell, player.unit_id)
	
	player.current_action_points = 2
	var ap_before := player.current_action_points
	
	# 与终端交互
	var result := c.interact_with_objective(&"terminal_1")
	_expect(result.success, "interact: objective interaction succeeded")
	_expect(player.current_action_points == ap_before, "0 AP: action points not consumed (was %d, now %d)" % [ap_before, player.current_action_points])
	_expect(c.mission_tracker.is_object_interacted(&"terminal_1"), "tracker: terminal marked as interacted")
	_expect(c.mission_tracker.are_all_main_steps_completed(), "tracker: all steps completed")
	
	# 重复交互应被拒绝
	var repeat_result := c.interact_with_objective(&"terminal_1")
	_expect(not repeat_result.success, "repeat interact rejected")
	
	# 测试 Undo
	c._on_undo_step_pressed()
	_expect(not c.mission_tracker.is_object_interacted(&"terminal_1"), "undo: terminal interaction reverted")
	_expect(not c.mission_tracker.are_all_main_steps_completed(), "undo: steps reverted to incomplete")
	
	# 再次交互
	result = c.interact_with_objective(&"terminal_1")
	_expect(result.success, "interact: can interact again after undo")
	_expect(c.mission_tracker.are_all_main_steps_completed(), "tracker: re-completed after redo interact")
	
	_cleanup(c)


func _test_completed_mission_extraction() -> void:
	var c := _create_fixture(true)
	var player: PrototypeUnit = c.units_by_id[&"player_0"]
	
	# 移动到终端并交互
	c.grid.vacate(player.grid_cell, player.unit_id)
	player.grid_cell = Vector3i(2, 0, 1)
	c.grid.occupy(player.grid_cell, player.unit_id)
	var interact_result := c.interact_with_objective(&"terminal_1")
	_expect(interact_result.success, "fixture: interacted with terminal")
	
	# 移动到撤离点 (6, 0, 1)
	c.grid.vacate(player.grid_cell, player.unit_id)
	player.grid_cell = Vector3i(6, 0, 1)
	c.grid.occupy(player.grid_cell, player.unit_id)
	player.current_action_points = 2
	
	# 撤离提示与确认
	var prompt := c.begin_extraction_prompt(&"extraction_1")
	_expect(prompt.success, "extraction prompt success")
	_expect(c.session_manager.get_state() == GameStateManager.State.EXTRACTION, "state is EXTRACTION")
	
	var confirm := c.confirm_extraction()
	_expect(confirm.success, "extraction confirm success")
	_expect(c.session_manager.is_terminal(), "terminal session")
	_expect(c.session_manager.is_success(), "session success")
	
	var summary: Dictionary = c.mission_tracker.get_summary()
	_expect(summary[&"all_completed"], "summary reports all completed")
	_expect(summary[&"completed_steps"].size() == 1, "summary completed step count is 1")
	
	_cleanup(c)


func _test_incomplete_mission_extraction() -> void:
	var c := _create_fixture(true)
	var player: PrototypeUnit = c.units_by_id[&"player_0"]
	
	# 不与终端交互，直接走到撤离点 (6, 0, 1)
	c.grid.vacate(player.grid_cell, player.unit_id)
	player.grid_cell = Vector3i(6, 0, 1)
	c.grid.occupy(player.grid_cell, player.unit_id)
	player.current_action_points = 2
	
	# 依然允许撤离！
	var prompt := c.begin_extraction_prompt(&"extraction_1")
	_expect(prompt.success, "extraction allowed even when mission incomplete")
	
	var confirm := c.confirm_extraction()
	_expect(confirm.success, "extraction confirmed successfully")
	_expect(c.session_manager.is_success(), "session marked success on extraction")
	
	# 结算中准确报告未完成
	var summary: Dictionary = c.mission_tracker.get_summary()
	_expect(not summary[&"all_completed"], "summary reports mission NOT all completed")
	_expect(summary[&"pending_steps"].size() == 1, "summary pending step count is 1")
	
	_cleanup(c)


func _test_objective_match_by_definition_id() -> void:
	var c := _create_fixture(true)
	# 把任务步骤的 target_id 配置为类型 ID (prototype_objective_terminal)
	c.map_definition.mission_definition.steps[0].target_id = &"prototype_objective_terminal"
	c.mission_tracker.configure(c.map_definition.mission_definition)
	
	var player: PrototypeUnit = c.units_by_id[&"player_0"]
	c.grid.vacate(player.grid_cell, player.unit_id)
	player.grid_cell = Vector3i(2, 0, 1)
	c.grid.occupy(player.grid_cell, player.unit_id)
	player.current_action_points = 2
	
	# 与具体实例 terminal_1 交互 (它的 definition_id 是 prototype_objective_terminal)
	var result := c.interact_with_objective(&"terminal_1")
	_expect(result.success, "interact with instance matching definition_id should succeed")
	_expect(player.current_action_points == 2, "interact with objective should cost 0 AP")
	_expect(c.mission_tracker.is_step_completed(&"hack_terminal"), "mission step completed via definition_id match")
	
	# 走到撤离点 (6, 0, 1) 确认撤离
	c.grid.vacate(player.grid_cell, player.unit_id)
	player.grid_cell = Vector3i(6, 0, 1)
	c.grid.occupy(player.grid_cell, player.unit_id)
	
	c.begin_extraction_prompt(&"extraction_1")
	c.confirm_extraction()
	_expect(c.session_manager.is_success(), "session marked success on extraction")
	var summary: Dictionary = c.mission_tracker.get_summary()
	_expect(summary[&"all_completed"], "all missions reported completed")
	_cleanup(c)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
