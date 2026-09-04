extends SceneTree

const ActionResultScript = preload("res://scripts/core/action/action_result.gd")
const ActionRequestScript = preload("res://scripts/core/action/action_request.gd")
const ActionExecutionContextScript = preload("res://scripts/core/action/action_execution_context.gd")
const ActionExecutorScript = preload("res://scripts/core/action/action_executor.gd")
const ActionValidatorScript = preload("res://scripts/core/action/action_validator.gd")
const UnitRuntimeStateScript = preload("res://scripts/core/units/unit_runtime_state.gd")
const UnitArchetypeScript = preload("res://scripts/core/units/unit_archetype.gd")
const WeaponDefinitionScript = preload("res://scripts/core/combat/weapon_definition.gd")
const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")
const SkillDefinitionScript = preload("res://scripts/core/skills/skill_definition.gd")
const SkillInstanceScript = preload("res://scripts/core/skills/skill_instance.gd")
const GrenadeSkillDefinitionScript = preload("res://scripts/core/skills/grenade_skill_definition.gd")
const SprintSkillDefinitionScript = preload("res://scripts/core/skills/sprint_skill_definition.gd")
const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_skill_slot_equip_and_unequip()
	_test_skill_instance_cooldown_lifecycle()
	_test_action_validator_skill()
	_test_action_executor_skill_pipeline()
	_test_unit_state_snapshot_and_undo_restore()
	_test_concrete_skills_behavior()
	_test_grid_manhattan_and_valid_target_cells()
	_test_skill_tooltips()
	_finish()


func _test_skill_slot_equip_and_unequip() -> void:
	var unit := _make_test_unit()
	_expect(unit.MAX_SKILL_SLOTS == 2, "slot: should have 2 skill slots by default")
	_expect(unit.get_skill(0) == null, "slot: slot 0 initially null")
	_expect(unit.get_skill(1) == null, "slot: slot 1 initially null")

	var grenade_def = GrenadeSkillDefinitionScript.new()
	var skill_0 := SkillInstanceScript.new(&"skill_inst_0", grenade_def)
	var sprint_def = SprintSkillDefinitionScript.new()
	var skill_1 := SkillInstanceScript.new(&"skill_inst_1", sprint_def)

	var tracker := { "signal_fired": false }
	unit.skill_slot_changed.connect(func(slot_idx, prev, curr):
		if slot_idx == 0 and prev == null and curr == skill_0:
			tracker["signal_fired"] = true
	)

	_expect(unit.equip_skill(0, skill_0), "slot: equip to slot 0 should succeed")
	_expect(tracker["signal_fired"], "slot: skill_slot_changed signal emitted")
	_expect(unit.get_skill(0) == skill_0, "slot: get_skill(0) returns skill_0")

	_expect(unit.equip_skill(1, skill_1), "slot: equip to slot 1 should succeed")
	_expect(unit.get_skill(1) == skill_1, "slot: get_skill(1) returns skill_1")

	# Out of bounds slot
	_expect(not unit.equip_skill(2, skill_0), "slot: slot 2 should be rejected")
	_expect(not unit.equip_skill(-1, skill_0), "slot: negative slot should be rejected")

	# Unequip
	var unequipped = unit.unequip_skill(0)
	_expect(unequipped == skill_0, "slot: unequip_skill returns previous skill")
	_expect(unit.get_skill(0) == null, "slot: slot 0 becomes null after unequip")


func _test_skill_instance_cooldown_lifecycle() -> void:
	var grenade_def = GrenadeSkillDefinitionScript.new()
	grenade_def.cooldown_turns = 2
	var skill := SkillInstanceScript.new(&"skill_inst", grenade_def)

	_expect(skill.is_ready(), "cooldown: initially ready")
	_expect(skill.current_cooldown == 0, "cooldown: initially 0")

	skill.trigger_cooldown()
	_expect(not skill.is_ready(), "cooldown: not ready after trigger")
	_expect(skill.current_cooldown == 2, "cooldown: set to definition cooldown_turns")

	skill.on_turn_started()
	_expect(skill.current_cooldown == 1, "cooldown: decrements on round turn start")
	_expect(not skill.is_ready(), "cooldown: still not ready at 1 turn CD")

	skill.on_turn_started()
	_expect(skill.current_cooldown == 0, "cooldown: reaches 0")
	_expect(skill.is_ready(), "cooldown: ready again at 0 CD")


func _test_action_validator_skill() -> void:
	# AP check
	var res_no_ap = ActionValidatorScript.validate_skill(&"actor_1", 0, 1, true, true, true)
	_expect(not res_no_ap.success and res_no_ap.reason == ActionValidatorScript.REASON_NO_AP, "validator: reject when insufficient AP")

	# Not equipped
	var res_not_equipped = ActionValidatorScript.validate_skill(&"actor_1", 2, 1, false, true, true)
	_expect(not res_not_equipped.success and res_not_equipped.reason == &"skill_not_equipped", "validator: reject when skill not equipped")

	# Not ready (in CD)
	var res_not_ready = ActionValidatorScript.validate_skill(&"actor_1", 2, 1, true, false, true)
	_expect(not res_not_ready.success and res_not_ready.reason == &"skill_not_ready", "validator: reject when skill not ready")

	# Out of range
	var res_out_range = ActionValidatorScript.validate_skill(&"actor_1", 2, 1, true, true, false)
	_expect(not res_out_range.success and res_out_range.reason == ActionValidatorScript.REASON_OUT_OF_RANGE, "validator: reject when out of range")

	# All valid
	var res_valid = ActionValidatorScript.validate_skill(&"actor_1", 2, 1, true, true, true)
	_expect(res_valid.success and res_valid.ap_cost == 1, "validator: accept valid skill request")


func _test_action_executor_skill_pipeline() -> void:
	var executor = ActionExecutorScript.new()
	var grenade_def = GrenadeSkillDefinitionScript.new()
	var skill_inst = SkillInstanceScript.new(&"g_inst", grenade_def)

	var tracker := { "handler_called": false }
	executor.register_handler(&"skill", func(req, ctx):
		tracker["handler_called"] = true
		skill_inst.trigger_cooldown()
		return ActionResultScript.accepted(req.actor_id, &"", req.ap_cost, &"skill")
	)

	var context = ActionExecutionContextScript.new(2)
	var request = ActionRequestScript.new(
		&"skill",
		&"player_1",
		&"",
		1,
		{
			ActionExecutorScript.KEY_SKILL_EQUIPPED: true,
			ActionExecutorScript.KEY_SKILL_READY: skill_inst.is_ready(),
			ActionExecutorScript.KEY_TARGET_IN_RANGE: true,
			ActionExecutorScript.KEY_HAS_LOS: true,
			ActionExecutorScript.KEY_TARGET_ALIVE: true,
		}
	)

	var result = executor.execute(request, context)
	_expect(result.success, "executor: execute skill succeeds")
	_expect(tracker["handler_called"], "executor: skill handler called")
	_expect(context.current_ap == 1, "executor: AP committed exactly once")
	_expect(not skill_inst.is_ready(), "executor: skill triggered cooldown")


func _test_unit_state_snapshot_and_undo_restore() -> void:
	var unit := _make_test_unit()
	var grenade_def = GrenadeSkillDefinitionScript.new()
	grenade_def.cooldown_turns = 3
	var skill_inst := SkillInstanceScript.new(&"skill_undo_inst", grenade_def)
	unit.equip_skill(0, skill_inst)

	# Initial state snapshot (skill ready, CD = 0)
	var snap_before := unit.to_snapshot_resource()

	# Spend skill (enters CD = 3)
	skill_inst.trigger_cooldown()
	_expect(skill_inst.current_cooldown == 3, "undo: cooldown triggered to 3")

	# Restore from snapshot (simulating Undo Step)
	var hydrated := unit.hydrate_from_snapshot(snap_before, unit.archetype, unit.weapon_instance)
	_expect(hydrated, "undo: hydrate_from_snapshot succeeds")
	_expect(unit.get_skill(0).current_cooldown == 0, "undo: skill cooldown safely restored to 0 via snapshot")
	_expect(unit.get_skill(0).is_ready(), "undo: skill is ready again after undo")


func _test_concrete_skills_behavior() -> void:
	# Test Sprint
	var unit := _make_test_unit()
	var initial_move := unit.move_range
	var sprint_def = SprintSkillDefinitionScript.new()
	sprint_def.bonus_movement = 3

	var context = ActionExecutionContextScript.new(2)
	context.state[&"actor"] = unit
	var request = ActionRequestScript.new(&"skill", unit.instance_id, unit.instance_id, 1)

	var result = sprint_def.execute_skill(request, context)
	_expect(result.success, "sprint: execution succeeds")
	_expect(unit.temporary_bonus_move == 3, "sprint: temporary_bonus_move added")
	_expect(unit.move_range == initial_move + 3, "sprint: move_range increased by 3")

	# On turn start: temporary bonus reset
	unit.on_round_turn_started()
	_expect(unit.temporary_bonus_move == 0, "sprint: temporary bonus reset on round turn start")
	_expect(unit.move_range == initial_move, "sprint: move_range back to normal")


func _test_grid_manhattan_and_valid_target_cells() -> void:
	var grid := GridModelScript.new(Vector2i(10, 10))
	var grenade_def := GrenadeSkillDefinitionScript.new()
	grenade_def.cast_range = 3

	var actor_cell := Vector3i(5, 0, 5)
	# GridModel.get_cells_in_manhattan_range
	var manhattan_cells: Array[Vector3i] = grid.get_cells_in_manhattan_range(actor_cell, 3)
	_expect(not manhattan_cells.is_empty(), "grid: get_cells_in_manhattan_range returns non-empty array")
	_expect(manhattan_cells.has(actor_cell), "grid: includes actor_cell itself in range query")
	_expect(manhattan_cells.has(Vector3i(5, 0, 8)), "grid: includes distance 3 cell (5,0,8)")
	_expect(manhattan_cells.has(Vector3i(6, 0, 6)), "grid: includes distance 2 cell (6,0,6)")
	_expect(not manhattan_cells.has(Vector3i(5, 0, 9)), "grid: excludes distance 4 cell (5,0,9)")

	# SkillDefinition.get_valid_target_cells
	var valid_cells: Array[Vector3i] = grenade_def.get_valid_target_cells(actor_cell, grid)
	_expect(not valid_cells.is_empty(), "grenade: valid target cells is non-empty")
	_expect(not valid_cells.has(actor_cell), "grenade: does not include actor_cell itself for TARGET_CELL")
	_expect(valid_cells.has(Vector3i(5, 0, 8)), "grenade: includes target cell at distance 3")
	_expect(valid_cells.has(Vector3i(6, 0, 6)), "grenade: includes target cell at distance 2")
	_expect(not valid_cells.has(Vector3i(5, 0, 9)), "grenade: excludes out of range cell")


func _test_skill_tooltips() -> void:
	var grenade_def := GrenadeSkillDefinitionScript.new()
	var skill_inst := SkillInstanceScript.new(&"inst_grenade", grenade_def)

	var tooltip_ready := skill_inst.get_tooltip_text()
	_expect(tooltip_ready.contains("破片手雷"), "tooltip: contains skill name")
	_expect(tooltip_ready.contains("消耗: 1 AP"), "tooltip: contains AP cost")
	_expect(tooltip_ready.contains("基础冷却: 2 回合"), "tooltip: contains cooldown")
	_expect(tooltip_ready.contains("3x3"), "tooltip: contains AoE range")
	_expect(tooltip_ready.contains("准备就绪"), "tooltip: indicates ready status when CD is 0")

	skill_inst.trigger_cooldown()
	var tooltip_cd := skill_inst.get_tooltip_text()
	_expect(tooltip_cd.contains("冷却中 (剩余 2 回合)"), "tooltip: indicates cooldown status when in CD")


func _make_test_unit() -> UnitRuntimeState:
	var weapon_def := WeaponDefinitionScript.new()
	weapon_def.weapon_id = &"test_weapon"
	weapon_def.display_name = "Test Weapon"
	weapon_def.damage = 2
	weapon_def.range = 5
	weapon_def.ap_cost = 1

	var weapon_inst := WeaponInstanceScript.new(&"weapon_inst", weapon_def)

	var arch := UnitArchetypeScript.new()
	arch.archetype_id = &"test_arch"
	arch.display_name = "Test Archetype"
	arch.max_hp = 10
	arch.max_action_points = 2
	arch.move_range = 4
	arch.vision_range = 6
	arch.default_weapon = weapon_def

	return UnitRuntimeStateScript.new(&"unit_test_1", arch, &"player", Vector3i.ZERO, weapon_inst)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		print("FAIL: %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("SKILL_SYSTEM_TEST: PASS")
		quit(0)
	else:
		print("SKILL_SYSTEM_TEST: %d failure(s)" % _failures.size())
		quit(1)