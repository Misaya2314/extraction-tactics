extends SceneTree

const ControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const UnitScene = preload("res://scenes/main/prototype_unit.tscn")
const MissionObjectiveScript = preload("res://scripts/core/session/mission_objective.gd")

class QuietController extends ControllerScript:
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
		pass

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_partial_and_complete()
	_test_batch_tie(false)
	_test_batch_tie(true)
	_test_grenade_self_damage()
	_test_explosion_chain()
	_test_rejected_action()
	_test_map_without_extraction()
	for failure in failures:
		push_error(failure)
	print("MISSION_FLOW_TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _fixture() -> QuietController:
	var c := QuietController.new()
	c.grid = GridModel.new()
	var map := TacticalMapDefinition.new()
	map.footprint_size = Vector2i(6, 3)
	for x in range(6):
		for z in range(3):
			var cell := MapCellData.new()
			cell.coordinate = Vector3i(x, 0, z)
			map.cells.append(cell)
	c.map_definition = map
	_expect(c.grid.configure_from_definition(map), "fixture: valid grid")
	c.session_manager = GameStateManager.new()
	c.session_manager.start_exploration()
	c.session_manager.start_combat()
	c.session_manager.result_changed.connect(c._on_session_result_changed)
	c.turn_manager = TurnManager.new()
	c._configure_action_executor()
	var weapon := WeaponDefinition.new()
	weapon.weapon_id = &"fixture_weapon"
	weapon.display_name = "Fixture"
	weapon.damage = 4
	weapon.range = 6
	var archetype := UnitArchetype.new()
	archetype.archetype_id = &"fixture_unit"
	archetype.display_name = "Fixture"
	archetype.max_hp = 4
	archetype.default_weapon = weapon
	for i in range(3):
		var id := StringName("unit_%d" % i)
		var faction: StringName = &"player" if i == 0 else &"enemy"
		var state := UnitRuntimeState.new(id, archetype, faction, Vector3i(i, 0, 1), WeaponInstance.new(StringName("weapon_%d" % i), weapon))
		var unit := UnitScene.instantiate() as PrototypeUnit
		unit.bind_runtime_state(state, Color.WHITE)
		get_root().add_child(unit)
		c.units_by_id[id] = unit
		c.grid.occupy(unit.grid_cell, id)
		unit.died.connect(c._on_unit_died)
		if i == 0:
			c.all_player_ids.append(id)
		else:
			c.all_enemy_ids.append(id)
	c.turn_manager.configure(c.all_player_ids, c.all_enemy_ids)
	c.turn_manager.start_combat()
	c.turn_manager.phase_changed.connect(c._on_phase_changed)
	c.mission_objective.configure(c.all_enemy_ids)
	return c


func _cleanup(c: QuietController) -> void:
	for unit in c.units_by_id.values():
		unit.free()
	c.free()


func _request() -> ActionRequest:
	return ActionRequest.new(&"skill", &"unit_0", &"", 1, {})


func _test_partial_and_complete() -> void:
	var c := _fixture()
	var actor: PrototypeUnit = c.units_by_id[&"unit_0"]
	var count := [0]
	var first_state: UnitRuntimeState = c.units_by_id[&"unit_1"].runtime_state
	var original_snapshot = first_state.to_snapshot()
	c.session_manager.result_changed.connect(func(_r): count[0] += 1)
	# Local encounter only contains the first target. Its victory must not win the mission.
	c.turn_manager.configure([&"unit_0"], [&"unit_1"])
	c.turn_manager.start_combat()
	c.action_executor.register_handler(&"skill", func(_r, _ctx):
		c.units_by_id[&"unit_1"].take_damage(4)
		_expect(not c.session_manager.is_terminal(), "partial: no outcome inside handler")
		return ActionResult.accepted(&"unit_0"))
	var result := c._execute_runtime_action(_request(), actor)
	_expect(result.success and not c.session_manager.is_terminal(), "partial: encounter victory is not mission victory")
	_expect(c.mission_objective.progress(c.units_by_id)[&"completed"] == 1, "partial: target progress")
	# A restored unit immediately restores objective progress, without a separate kill counter.
	first_state.hydrate_from_snapshot(original_snapshot, first_state.archetype, first_state.weapon_instance)
	_expect(c.mission_objective.progress(c.units_by_id)[&"completed"] == 0, "restore: progress derives from HP")
	c.units_by_id[&"unit_1"].runtime_state.current_hp = 0
	c.units_by_id[&"unit_1"].runtime_state.alive = false
	c.action_executor.register_handler(&"skill", func(_r, _ctx):
		c.units_by_id[&"unit_2"].take_damage(4)
		_expect(count[0] == 0, "final target: no result before action finishes")
		return ActionResult.accepted(&"unit_0"))
	result = c._execute_runtime_action(_request(), actor)
	_expect(result.success and c.session_manager.is_success(), "complete: mission victory")
	_expect(actor.current_action_points == 0, "complete: AP committed before result")
	_expect(count[0] == 1 and c.input_locked, "complete: one result and locked input")
	c._evaluate_mission_outcome()
	_expect(not c.session_manager.complete_mission() and count[0] == 1, "complete: duplicate signals ignored")
	_expect(not c._execute_runtime_action(_request(), actor).success, "complete: actions rejected after result")
	_cleanup(c)
	var fresh := _fixture()
	_expect(not fresh.session_manager.is_terminal() and fresh.mission_objective.progress(fresh.units_by_id)[&"completed"] == 0, "restart: clean mission")
	_cleanup(fresh)


func _test_batch_tie(player_first: bool) -> void:
	var c := _fixture()
	var order := [0, 1, 2] if player_first else [1, 2, 0]
	c.action_executor.register_handler(&"skill", func(_r, _ctx):
		for i in order:
			c.units_by_id[StringName("unit_%d" % i)].take_damage(4)
			_expect(not c.session_manager.is_terminal(), "tie: no early session outcome")
			_expect(not c.turn_manager.is_terminal(), "tie: no early encounter outcome")
		return ActionResult.accepted(&"unit_0"))
	var result := c._execute_runtime_action(_request(), c.units_by_id[&"unit_0"])
	_expect(result.success, "tie: dead actor AP commit succeeds")
	_expect(c.session_manager.is_failure(), "tie: failure wins regardless of damage order")
	_expect(c.turn_manager.get_player_ids().is_empty() and c.turn_manager.get_enemy_ids().is_empty(), "tie: all deaths removed from roster")
	_cleanup(c)


func _test_grenade_self_damage() -> void:
	var c := _fixture()
	var grenade := GrenadeSkillDefinition.new()
	grenade.aoe_radius = 3
	c.action_executor.register_handler(&"skill", func(request, context):
		context.state[&"units_query"] = Callable(c, "_query_units_in_radius")
		return grenade.execute_skill(request, context))
	var request := _request()
	request.payload[&"target_cell"] = Vector3i(1, 0, 1)
	var result := c._execute_runtime_action(request, c.units_by_id[&"unit_0"])
	_expect(result.success and c.session_manager.is_failure(), "grenade: real self damage resolves as failure, not AP error")
	_expect(c.mission_objective.progress(c.units_by_id)[&"completed"] == 2, "grenade: all effects finish")
	_cleanup(c)


func _test_explosion_chain() -> void:
	var c := _fixture()
	var definition := TacticalObjectDefinition.new()
	definition.placeable_id = &"chain_barrel"
	definition.display_name = "Chain Barrel"
	definition.damageable = true
	definition.targetable = true
	definition.max_hp = 1
	var effect := ExplosionEffectDefinition.new()
	effect.effect_id = &"chain"
	effect.damage = 4
	effect.radius = 2
	effect.affect_players = true
	effect.affect_enemies = true
	effect.affect_environment_objects = true
	effect.allow_chain = true
	definition.on_destroy_effects.append(effect)
	var states: Array[EnvironmentObjectRuntimeState] = []
	for i in range(2):
		var placement := MapObjectPlacement.new()
		placement.object_id = StringName("barrel_%d" % i)
		placement.cell = Vector3i(i + 1, 0, 1)
		var state := EnvironmentObjectRuntimeState.new(placement.object_id, definition, placement)
		_expect(state.is_valid(), "fixture: valid barrel")
		states.append(state)
		c.environment_objects_by_instance_id[state.instance_id] = state
	c.action_executor.register_handler(&"skill", func(_r, _ctx):
		states[0].apply_damage(1)
		var summary := c._resolve_environment_destruction(states[0])
		_expect(summary[&"chain_count"] == 1, "chain: secondary barrel resolves")
		_expect(not c.session_manager.is_terminal(), "chain: no result inside handler")
		return ActionResult.accepted(&"unit_0"))
	var result := c._execute_runtime_action(_request(), c.units_by_id[&"unit_0"])
	_expect(result.success and c.session_manager.is_failure(), "chain: full effects then failure")
	_cleanup(c)


func _test_rejected_action() -> void:
	var c := _fixture()
	var r := _request()
	r.ap_cost = 99
	var result := c._execute_runtime_action(r, c.units_by_id[&"unit_0"])
	_expect(not result.success and not c.session_manager.is_terminal(), "rejected: no state mutation")
	_cleanup(c)


func _test_map_without_extraction() -> void:
	var definition := TacticalMapDefinition.new()
	definition.footprint_size = Vector2i(2, 1)
	var cell := MapCellData.new()
	definition.cells.append(cell)
	var player := MapSpawnData.new()
	player.spawn_id = &"player"
	definition.spawns.append(player)
	var enemy := MapSpawnData.new()
	enemy.spawn_id = &"enemy"
	enemy.faction = &"enemy"
	enemy.cell = Vector3i(1, 0, 0)
	var other := MapCellData.new()
	other.coordinate = enemy.cell
	definition.cells.append(other)
	definition.spawns.append(enemy)
	definition.objective_spawn_ids = [&"enemy"]
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var diagnostics: Array[Dictionary] = []
	TacticalMapBaker._validate_definition(definition, errors, warnings, diagnostics)
	_expect(errors.is_empty(), "map: no extraction needed: %s" % str(errors))
	definition.objective_spawn_ids = [&"missing"]
	errors.clear()
	TacticalMapBaker._validate_definition(definition, errors, warnings, diagnostics)
	_expect(not errors.is_empty(), "map: invalid objective rejected")
	definition.objective_spawn_ids = [&"enemy", &"enemy"]
	errors.clear()
	TacticalMapBaker._validate_definition(definition, errors, warnings, diagnostics)
	_expect(not errors.is_empty(), "map: duplicate objective rejected")
	var objective := MissionObjectiveScript.new()
	_expect(not objective.progress({})[&"success"], "empty objective must not win")
	objective.configure([&"missing"])
	_expect(not objective.progress({})[&"success"], "missing runtime target must not count as killed")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
