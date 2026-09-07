extends SceneTree

## Full production controller/UI lifecycle with an in-memory synthetic map.
const FIXTURE_PATH := "res://tests/session/_mission_restart_fixture.tscn"
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://scenes/main/prototype_main.tscn") as PackedScene
	var initial := scene.instantiate() as PrototypeController
	var map := TacticalMapDefinition.new()
	map.map_id = &"mission_synthetic"
	map.footprint_size = Vector2i(8, 3)
	for x in range(8):
		for z in range(3):
			var cell := MapCellData.new()
			cell.coordinate = Vector3i(x, 0, z)
			map.cells.append(cell)
	for i in range(2):
		var spawn := MapSpawnData.new()
		spawn.spawn_id = StringName("spawn_%d" % i)
		spawn.unit_name = StringName("MissionUnit%d" % i)
		spawn.faction = &"player" if i == 0 else &"enemy"
		spawn.cell = Vector3i(i * 6, 0, 1)
		spawn.archetype = load("res://resources/units/player_alpha.tres" if i == 0 else "res://resources/units/rifleman.tres")
		map.spawns.append(spawn)
	map.objective_spawn_ids = [&"spawn_1"]
	initial.map_definition = map
	var packed := PackedScene.new()
	_expect(packed.pack(initial) == OK, "fixture packs")
	initial.free()
	_expect(ResourceSaver.save(packed, FIXTURE_PATH) == OK, "fixture saves")
	var c := (load(FIXTURE_PATH) as PackedScene).instantiate() as PrototypeController
	get_root().add_child(c)
	current_scene = c
	await process_frame
	_expect(c.mission_objective.target_ids.size() == 1, "authored target resolved to runtime ID")
	_expect(not c.result_panel.visible, "result hidden before outcome")
	_expect(c.phase_label.text.contains("0/1"), "HUD initial objective")
	var player: PrototypeUnit = c.units_by_id[c.all_player_ids[0]]
	var enemy: PrototypeUnit = c.units_by_id[c.all_enemy_ids[0]]
	var enemy_hp := enemy.current_hp
	enemy.runtime_state.current_hp = 1
	c.grid.vacate(enemy.grid_cell, enemy.unit_id)
	enemy.grid_cell = Vector3i(1, 0, 1)
	c.grid.occupy(enemy.grid_cell, enemy.unit_id)
	var attack := await c._attack_with_unit(player, enemy)
	_expect(attack.success, "real weapon action succeeds")
	_expect(c.session_manager.is_success() and c.result_panel.visible, "victory shows actual result panel")
	_expect(c.result_title_label.text == "关卡胜利", "victory title")
	_expect(c.result_value_label.text.contains("1 / 1"), "result progress")
	_expect(c.end_turn_button.disabled, "terminal end-turn disabled")
	_expect(not c._can_undo_in_current_context(), "terminal undo disabled")
	c._on_restart_pressed()
	await scene_changed
	await process_frame
	c = current_scene as PrototypeController
	_expect(c != null and c.session_manager.is_active(), "restart opens active mission")
	_expect(c.units_by_id[c.all_enemy_ids[0]].current_hp == enemy_hp, "restart restores enemy HP")
	_expect(c.mission_objective.progress(c.units_by_id)[&"completed"] == 0, "restart resets target progress")
	_expect(not c.result_panel.visible and not c.input_locked, "restart clears terminal UI/input")
	player = c.units_by_id[c.all_player_ids[0]]
	player.runtime_state.current_hp = 1
	enemy = c.units_by_id[c.all_enemy_ids[0]]
	c.grid.vacate(enemy.grid_cell, enemy.unit_id)
	enemy.grid_cell = Vector3i(1, 0, 1)
	c.grid.occupy(enemy.grid_cell, enemy.unit_id)
	c.session_manager.start_combat()
	c.turn_manager.configure(c.all_player_ids, c.all_enemy_ids)
	c.turn_manager.start_combat(false)
	await c._run_enemy_turn()
	_expect(c.session_manager.is_failure() and c.result_title_label.text == "关卡失败", "defeat shows actual result panel")
	_expect(c.mission_round == 1 and c.input_locked, "enemy animation cannot advance next round or unlock terminal input")
	c._on_restart_pressed()
	await scene_changed
	await process_frame
	c = current_scene as PrototypeController
	_expect(c.session_manager.is_active() and c._living_player_count() == 1, "retry after defeat restores player")
	# Restart while the final attack's presentation and delayed impact are pending.
	player = c.units_by_id[c.all_player_ids[0]]
	enemy = c.units_by_id[c.all_enemy_ids[0]]
	enemy.runtime_state.current_hp = 1
	c.grid.vacate(enemy.grid_cell, enemy.unit_id)
	enemy.grid_cell = Vector3i(1, 0, 1)
	c.grid.occupy(enemy.grid_cell, enemy.unit_id)
	c._attack_with_unit(player, enemy)
	_expect(c.session_manager.is_success(), "final attack commits before animation")
	_expect(c.combat_presentation.active and not c.result_panel.visible, "final result waits for presentation")
	_expect(enemy.visible, "logically dead target retained for death animation")
	c._on_restart_pressed()
	await scene_changed
	await create_timer(0.5).timeout
	c = current_scene as PrototypeController
	_expect(c.session_manager.is_active() and not c.input_locked, "pending old animation cannot affect restarted mission")
	_expect(c.units_by_id[c.all_enemy_ids[0]].current_hp == enemy_hp, "pending impact cannot damage new units")
	# The public skill path must batch self-damage and enemy death before judging victory.
	player = c.units_by_id[c.all_player_ids[0]]
	enemy = c.units_by_id[c.all_enemy_ids[0]]
	player.runtime_state.current_hp = 1
	enemy.runtime_state.current_hp = 1
	c.grid.vacate(enemy.grid_cell, enemy.unit_id)
	enemy.grid_cell = player.grid_cell + Vector3i(1, 0, 0)
	c.grid.occupy(enemy.grid_cell, enemy.unit_id)
	await c._cast_skill_at_cell(player, player.runtime_state.get_skill(0), 0, player.grid_cell)
	_expect(c.last_action_result.success and c.session_manager.is_failure(), "public grenade path resolves simultaneous wipe as defeat")
	_expect(c.result_panel.visible and not c.combat_presentation.active, "grenade result waits for shared presentation")
	_expect(not player.visible and not enemy.visible, "grenade cleans every dead view")
	_expect(not player.defer_damage_feedback and not enemy.defer_damage_feedback, "deferred audio state restored")
	current_scene = null
	c.queue_free()
	await process_frame
	DirAccess.remove_absolute(FIXTURE_PATH)
	for failure in failures:
		push_error(failure)
	print("MISSION_SCENE_TEST: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
