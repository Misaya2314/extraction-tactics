extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main/prototype_main.tscn")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var prototype := MAIN_SCENE.instantiate() as PrototypeController
	get_root().add_child(prototype)
	await process_frame

	var players: Array[PrototypeUnit] = []
	var enemies: Array[PrototypeUnit] = []
	for unit_value in prototype.units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == &"player":
			players.append(unit)
		else:
			enemies.append(unit)
	_expect(players.size() == 2 and enemies.size() == 6, "content: two players and six enemies should spawn")
	var alpha := prototype._unit_by_name(&"PlayerAlpha")
	var bravo := prototype._unit_by_name(&"PlayerBravo")
	var rifleman := prototype._unit_by_name(&"EnemyScout")
	var assault := prototype._unit_by_name(&"EnemyAssault_1")
	var outpost_guard := prototype._unit_by_name(&"EnemyGuard")
	_expect(alpha.weapon.weapon_id != bravo.weapon.weapon_id, "content: players should be equipped differently")
	_expect(alpha.attack_damage == alpha.weapon.damage and alpha.attack_range == alpha.weapon.range and alpha.attack_ap_cost == alpha.weapon.ap_cost, "content: player attack stats should come from weapon")
	_expect(alpha.attack_ap_cost == 1 and bravo.attack_ap_cost == 1, "content: shotgun player should have the one AP attack cost")
	_expect(rifleman.archetype.archetype_id == &"rifleman" and assault.archetype.archetype_id == &"assault", "content: enemy archetypes should be distinct")
	_expect(rifleman.move_range != assault.move_range and rifleman.vision_range != assault.vision_range, "content: enemy archetypes should differ mechanically")
	_expect(prototype.encounter_members.get(&"warehouse", []).size() == 3, "encounter: warehouse should contain three enemies")
	_expect(prototype.encounter_members.get(&"outpost", []).size() == 3, "encounter: outpost should contain three enemies")
	_expect(prototype.turn_manager.get_enemy_ids().is_empty(), "encounter: exploration should not preload enemy turn roster")
	_expect(prototype.loot_nodes_by_id.size() == 4, "loot visibility: all loot placements should have visual nodes")
	_expect(not (prototype.loot_nodes_by_id[&"loot_3"] as Node3D).visible, "loot visibility: unseen loot should be hidden")
	var hidden_loot_result := prototype.interact_with_loot(&"loot_3")
	_expect(not hidden_loot_result.success and hidden_loot_result.reason == &"invalid_target", "loot visibility: unseen loot should reject interaction")
	prototype._set_debug_reveal_all(true)
	_expect((prototype.loot_nodes_by_id[&"loot_3"] as Node3D).visible, "loot visibility: debug reveal should show unseen loot")
	prototype._set_debug_reveal_all(false)

	var hidden_enemy := prototype._unit_by_name(&"EnemyScout")
	prototype._set_debug_reveal_all(true)
	_expect(hidden_enemy.visible, "debug reveal: all living enemies should be visible")
	_expect(prototype.vision_highlights_root.get_child_count() == 0, "debug reveal: vision overlay should be cleared")
	prototype._set_debug_reveal_all(false)
	_expect(prototype.vision_highlights_root.get_child_count() > 0, "debug reveal: disabling reveal should restore the vision overlay")

	var player := alpha
	_expect(prototype._start_combat(true, rifleman, player.grid_cell, player.unit_id), "encounter: warehouse should activate")
	_expect(prototype.active_encounter_id == &"warehouse", "encounter: warehouse ID should be active")
	_expect(prototype.turn_manager.get_enemy_ids().size() == 3, "encounter: warehouse roster should have three enemies")
	_expect(prototype.turn_manager.get_enemy_ids().has(assault.unit_id), "encounter: warehouse should include its assault unit")
	_expect(not prototype.turn_manager.get_enemy_ids().has(outpost_guard.unit_id), "encounter: outpost should stay out of warehouse combat")
	for enemy_id in prototype.turn_manager.get_enemy_ids().duplicate():
		var enemy := prototype._unit_by_id(enemy_id)
		if is_instance_valid(enemy):
			enemy.take_damage(enemy.current_hp)
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXPLORATION, "encounter: resolving warehouse should return to exploration")
	_expect(not prototype.session_manager.is_terminal(), "encounter: resolving warehouse should not finish the session")

	var outpost_enemy := outpost_guard
	_expect(prototype._start_combat(true, outpost_enemy, player.grid_cell, player.unit_id), "encounter: outpost should activate later")
	_expect(prototype.active_encounter_id == &"outpost" and prototype.turn_manager.get_enemy_ids().size() == 3, "encounter: outpost roster should be independent")
	for enemy_id in prototype.turn_manager.get_enemy_ids().duplicate():
		var enemy := prototype._unit_by_id(enemy_id)
		if is_instance_valid(enemy):
			enemy.take_damage(enemy.current_hp)
	_expect(prototype.session_manager.get_state() == GameStateManagerScript.State.EXPLORATION, "encounter: resolving outpost should return to exploration")

	prototype.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("UNIT_CONTENT_ENCOUNTER_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("UNIT_CONTENT_ENCOUNTER_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
