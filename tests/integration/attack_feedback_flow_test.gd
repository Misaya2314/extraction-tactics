extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main/prototype_main.tscn")

var _failures: Array[String] = []
var _feedback_event_log: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_controller_is_data_driven()
	await _test_player_rifle_click_and_reentry()
	await _test_player_shotgun_feedback()
	await _test_enemy_rifle_feedback()
	await _test_enemy_shotgun_feedback()
	await _test_rejected_attack_does_not_play()
	await _test_target_death_keeps_attacker_feedback()
	await _test_move_lock_restoration()
	_finish()


func _test_controller_is_data_driven() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/gameplay/prototype_controller.gd")
	_expect(not source.contains("weapon_id"), "controller: attack path must not branch on weapon_id")
	_expect(not source.contains("profile_id"), "controller: attack path must not branch on profile_id")


func _test_player_rifle_click_and_reentry() -> void:
	var setup := await _setup_player_attack(&"PlayerAlpha", &"EnemyScout")
	var prototype: PrototypeController = setup[&"prototype"]
	var attacker: PrototypeUnit = setup[&"attacker"]
	var target: PrototypeUnit = setup[&"target"]
	_expect(attacker.weapon.weapon_id == &"assault_rifle", "player rifle: PlayerAlpha should use assault_rifle")
	var hp_before := target.current_hp
	var ap_before := attacker.current_action_points
	var root_position := attacker.global_position
	_watch_feedback(attacker)
	prototype._on_attack_action_pressed()

	prototype._handle_cell_click(target.grid_cell)
	var feedback_started := await _wait_for_feedback_start(attacker)
	_expect(feedback_started and prototype.input_locked, "player rifle: click attack should lock input during feedback")
	var hp_during := target.current_hp
	var ap_during := attacker.current_action_points
	var play_count_during := attacker.attack_feedback_play_count
	prototype._handle_cell_click(target.grid_cell)
	await process_frame
	_expect(attacker.attack_feedback_play_count == play_count_during and target.current_hp == hp_during and attacker.current_action_points == ap_during, "player rifle: locked re-entry must not attack twice")

	_expect(await _wait_for_action_end(prototype, attacker), "player rifle: feedback/action should complete")
	_assert_successful_attack(prototype, attacker, target, hp_before, ap_before, &"rifle", 0.215, "player rifle", root_position)
	await _free_prototype(prototype)


func _test_player_shotgun_feedback() -> void:
	var setup := await _setup_player_attack(&"PlayerBravo", &"EnemyScout")
	var prototype: PrototypeController = setup[&"prototype"]
	var attacker: PrototypeUnit = setup[&"attacker"]
	var target: PrototypeUnit = setup[&"target"]
	_expect(attacker.weapon.weapon_id == &"shotgun", "player shotgun: PlayerBravo should use shotgun")
	var hp_before := target.current_hp
	var ap_before := attacker.current_action_points
	var root_position := attacker.global_position
	_watch_feedback(attacker)

	prototype._attack_with_unit(attacker, target)
	_expect(await _wait_for_feedback_start(attacker), "player shotgun: attack should start feedback")
	_expect(prototype.input_locked, "player shotgun: input should remain locked during feedback")
	_expect(await _wait_for_action_end(prototype, attacker), "player shotgun: feedback/action should complete")
	_assert_successful_attack(prototype, attacker, target, hp_before, ap_before, &"shotgun", 0.40, "player shotgun", root_position)
	_expect(attacker.last_attack_feedback_duration > 0.215, "player shotgun: shotgun feedback should outlast rifle feedback")
	await _free_prototype(prototype)


func _test_enemy_rifle_feedback() -> void:
	await _test_enemy_feedback(&"EnemyRifleman_2", &"rifle", 0.215, "enemy rifle")


func _test_enemy_shotgun_feedback() -> void:
	await _test_enemy_feedback(&"EnemyAssault_1", &"shotgun", 0.40, "enemy shotgun")


func _test_enemy_feedback(attacker_name: StringName, expected_profile: StringName, expected_duration: float, label: String) -> void:
	var prototype := await _spawn_prototype()
	var attacker := prototype._unit_by_name(attacker_name)
	var player := prototype._unit_by_name(&"PlayerAlpha")
	_expect(is_instance_valid(attacker) and is_instance_valid(player), "%s: expected units should spawn" % label)
	if not is_instance_valid(attacker) or not is_instance_valid(player):
		await _free_prototype(prototype)
		return

	for enemy_id in prototype.all_enemy_ids.duplicate():
		var other := prototype._unit_by_id(enemy_id)
		if is_instance_valid(other) and other != attacker and other.is_alive():
			other.take_damage(other.current_hp)
	_relocate_unit(prototype, player, Vector3i(5, 0, 1))
	_relocate_unit(prototype, attacker, Vector3i(6, 0, 1))
	prototype._set_debug_reveal_all(true)
	attacker.max_action_points = 1
	var hp_before := player.current_hp
	var root_position := attacker.global_position
	_watch_feedback(attacker)
	_expect(prototype._start_combat(true, attacker, player.grid_cell, player.unit_id), "%s: isolated encounter should start" % label)
	_expect(prototype.turn_manager.end_player_turn(), "%s: should enter enemy turn" % label)

	prototype._run_enemy_turn()
	var feedback_started := await _wait_for_feedback_start(attacker)
	_expect(feedback_started and prototype.input_locked and prototype.turn_manager.is_enemy_turn(), "%s: AI should stay locked in enemy turn during feedback" % label)
	_expect(await _wait_for_action_end(prototype, attacker), "%s: AI action should wait for feedback completion" % label)
	_expect(prototype.turn_manager.is_player_turn() and not prototype.input_locked, "%s: enemy turn should end only after feedback" % label)
	_expect(prototype.last_action_result != null and prototype.last_action_result.success and prototype.last_action_result.action_type == &"attack", "%s: AI attack should use the Attack action" % label)
	_expect(player.current_hp == hp_before - attacker.attack_damage, "%s: target HP should change exactly once" % label)
	_expect(attacker.current_action_points == 0, "%s: one-AP AI setup should spend exactly one AP" % label)
	_assert_feedback(attacker, expected_profile, expected_duration, label, root_position)
	var events: Dictionary = _feedback_events_for(attacker)
	_expect(events["started"].size() == 1 and events["finished"].size() == 1, "%s: feedback must emit one start and one finish" % label)
	await _free_prototype(prototype)


func _test_rejected_attack_does_not_play() -> void:
	var setup := await _setup_player_attack(&"PlayerAlpha", &"EnemyScout")
	var prototype: PrototypeController = setup[&"prototype"]
	var attacker: PrototypeUnit = setup[&"attacker"]
	var target: PrototypeUnit = setup[&"target"]
	_watch_feedback(attacker)
	attacker.spend_action_points(attacker.current_action_points)
	var hp_before := target.current_hp
	var rejected := await prototype._attack_with_unit(attacker, target)
	_expect(not rejected.success and rejected.reason == &"no_ap", "rejected attack: zero AP should be rejected before execution")
	_expect(attacker.attack_feedback_play_count == 0 and attacker.last_attack_feedback_profile_id == &"" and not attacker.is_attack_feedback_playing, "rejected attack: feedback state must remain untouched")
	_expect(target.current_hp == hp_before and attacker.current_action_points == 0 and not prototype.input_locked, "rejected attack: HP, AP and lock must remain unchanged")
	var events: Dictionary = _feedback_events_for(attacker)
	_expect(events["started"].is_empty() and events["finished"].is_empty(), "rejected attack: feedback signals must not fire")
	await _free_prototype(prototype)


func _test_target_death_keeps_attacker_feedback() -> void:
	var setup := await _setup_player_attack(&"PlayerAlpha", &"EnemyScout")
	var prototype: PrototypeController = setup[&"prototype"]
	var attacker: PrototypeUnit = setup[&"attacker"]
	var target: PrototypeUnit = setup[&"target"]
	_watch_feedback(attacker)
	target.current_hp = attacker.attack_damage
	var root_position := attacker.global_position

	prototype._attack_with_unit(attacker, target)
	_expect(await _wait_for_feedback_start(attacker), "death order: attacker feedback should start")
	_expect(not target.visible, "death order: killed target may be hidden immediately")
	_expect(await _wait_for_action_end(prototype, attacker), "death order: attacker feedback should finish after target hide")
	_expect(target.current_hp == 0 and not target.visible and not prototype.units_by_id.has(target.unit_id), "death order: target should be removed from active units")
	_assert_feedback(attacker, &"rifle", 0.215, "death order", root_position)
	var events: Dictionary = _feedback_events_for(attacker)
	_expect(events["started"].size() == 1 and events["finished"].size() == 1, "death order: attacker feedback must emit start and finish")
	await _free_prototype(prototype)


func _test_move_lock_restoration() -> void:
	var prototype := await _spawn_prototype()
	var player := prototype._unit_by_name(&"PlayerAlpha")
	var bravo := prototype._unit_by_name(&"PlayerBravo")
	var original_cell := player.grid_cell
	var destination := Vector3i(1, 0, 2)
	var path := prototype.grid.find_path(original_cell, destination)
	player.reset_action_points()
	prototype.input_locked = true
	var moved := await prototype._move_unit(player, destination, path, 1)
	_expect(moved and prototype.input_locked, "move lock: successful movement must preserve a pre-existing lock")
	_expect(player.grid_cell == destination and prototype.grid.get_occupant(destination) == player.unit_id, "move lock: successful movement must keep occupancy correct")

	var ap_before_failure := player.current_action_points
	var failure_path: Array[Vector3i] = [player.grid_cell, bravo.grid_cell]
	var failed := await prototype._move_unit(player, bravo.grid_cell, failure_path, 1)
	_expect(not failed and prototype.input_locked, "move lock: failed movement must preserve a pre-existing lock")
	_expect(player.grid_cell == destination and player.current_action_points == ap_before_failure, "move lock: failed movement must preserve position and AP")

	prototype.input_locked = false
	player.reset_action_points()
	var return_path := prototype.grid.find_path(player.grid_cell, original_cell)
	var player_move := await prototype._move_unit(player, original_cell, return_path, 1)
	_expect(player_move and not prototype.input_locked, "move lock: normal player movement must restore an unlocked state")
	await _free_prototype(prototype)


func _setup_player_attack(attacker_name: StringName, target_name: StringName) -> Dictionary:
	var prototype := await _spawn_prototype()
	var attacker := prototype._unit_by_name(attacker_name)
	var target := prototype._unit_by_name(target_name)
	_expect(is_instance_valid(attacker) and is_instance_valid(target), "player setup: expected attacker and target should spawn")
	if is_instance_valid(attacker) and is_instance_valid(target):
		_relocate_unit(prototype, attacker, Vector3i(5, 0, 1))
		_relocate_unit(prototype, target, Vector3i(7, 0, 2))
		prototype._set_debug_reveal_all(true)
		prototype._select_unit(attacker)
		attacker.reset_action_points()
	return {&"prototype": prototype, &"attacker": attacker, &"target": target}


func _assert_successful_attack(
		prototype: PrototypeController,
		attacker: PrototypeUnit,
		target: PrototypeUnit,
		hp_before: int,
		ap_before: int,
		expected_profile: StringName,
		expected_duration: float,
		label: String,
		root_position: Vector3
) -> void:
	_expect(prototype.last_action_result != null and prototype.last_action_result.success and prototype.last_action_result.action_type == &"attack", "%s: attack should succeed through the unified action path" % label)
	_expect(prototype.last_action_result.damage == attacker.attack_damage, "%s: result damage should match the weapon exactly once" % label)
	_expect(target.current_hp == hp_before - attacker.attack_damage, "%s: target HP should change exactly once" % label)
	_expect(attacker.current_action_points == ap_before - attacker.attack_ap_cost, "%s: attacker AP should change exactly once" % label)
	_assert_feedback(attacker, expected_profile, expected_duration, label, root_position)


func _assert_feedback(
		unit: PrototypeUnit,
		expected_profile: StringName,
		expected_duration: float,
		label: String,
		root_position: Vector3
) -> void:
	_expect(unit.attack_feedback_play_count == 1, "%s: feedback should play exactly once" % label)
	_expect(unit.last_attack_feedback_profile_id == expected_profile, "%s: feedback profile should be %s" % [label, expected_profile])
	_expect(absf(unit.last_attack_feedback_duration - expected_duration) < 0.001, "%s: feedback duration should be %.3f" % [label, expected_duration])
	_expect(not unit.is_attack_feedback_playing, "%s: feedback should be finished" % label)
	_expect(unit.global_position.is_equal_approx(root_position), "%s: unit root must not move during feedback" % label)


func _watch_feedback(unit: PrototypeUnit) -> void:
	_feedback_event_log[unit.unit_id] = {"started": [], "finished": []}
	unit.attack_feedback_started.connect(_on_attack_feedback_started)
	unit.attack_feedback_finished.connect(_on_attack_feedback_finished)


func _on_attack_feedback_started(unit: PrototypeUnit, profile_id: StringName) -> void:
	var events = _feedback_event_log.get(unit.unit_id)
	if events is Dictionary:
		(events["started"] as Array).append(profile_id)


func _on_attack_feedback_finished(unit: PrototypeUnit, profile_id: StringName) -> void:
	var events = _feedback_event_log.get(unit.unit_id)
	if events is Dictionary:
		(events["finished"] as Array).append(profile_id)


func _feedback_events_for(unit: PrototypeUnit) -> Dictionary:
	return _feedback_event_log.get(unit.unit_id, {"started": [], "finished": []})


func _wait_for_feedback_start(unit: PrototypeUnit, max_frames: int = 120) -> bool:
	for _frame in range(max_frames):
		if unit.is_attack_feedback_playing:
			return true
		await process_frame
	return unit.is_attack_feedback_playing


func _wait_for_action_end(prototype: PrototypeController, unit: PrototypeUnit, max_frames: int = 180) -> bool:
	for _frame in range(max_frames):
		if not prototype.input_locked and not unit.is_attack_feedback_playing:
			return true
		await process_frame
	return not prototype.input_locked and not unit.is_attack_feedback_playing


func _relocate_unit(prototype: PrototypeController, unit: PrototypeUnit, cell: Vector3i) -> void:
	prototype.grid.vacate(unit.grid_cell, unit.unit_id)
	prototype.grid.occupy(cell, unit.unit_id)
	unit.grid_cell = cell
	unit.global_position = prototype.grid.cell_to_world(cell)


func _spawn_prototype() -> PrototypeController:
	var prototype := MAIN_SCENE.instantiate() as PrototypeController
	get_root().add_child(prototype)
	await process_frame
	return prototype


func _free_prototype(prototype: PrototypeController) -> void:
	prototype.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ATTACK_FEEDBACK_FLOW_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ATTACK_FEEDBACK_FLOW_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
