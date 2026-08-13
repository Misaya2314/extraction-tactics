extends SceneTree

const ActionResultScript = preload("res://scripts/core/action/action_result.gd")
const ActionValidatorScript = preload("res://scripts/core/action/action_validator.gd")
const CombatResolverScript = preload("res://scripts/core/combat/combat_resolver.gd")
const TurnManagerScript = preload("res://scripts/core/turn/turn_manager.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_move_validation()
	_test_attack_validation()
	_test_interact_and_loot_validation()
	_test_combat_resolution()
	_test_turn_flow()

	if _failures.is_empty():
		print("COMBAT_CORE_TEST: PASS")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	print("COMBAT_CORE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)


func _test_move_validation() -> void:
	var accepted := ActionValidatorScript.validate_move(2, 1, 2, 3, true)
	_expect(accepted.success, "move: valid request should be accepted")
	_expect(accepted.ap_cost == 1 and accepted.reason == &"accepted", "move: accepted result should retain cost and reason")
	_expect(accepted.action_type == &"move", "move: result should identify its action type")
	_expect(not ActionValidatorScript.validate_move(2, -1, 1, 3, true).success, "move: negative cost should reject")
	_expect(ActionValidatorScript.validate_move(2, -1, 1, 3, true).reason == &"invalid_cost", "move: negative cost reason")
	_expect(ActionValidatorScript.validate_move(2, 1, 0, 3, true).reason == &"no_path", "move: zero-length path reason")
	_expect(ActionValidatorScript.validate_move(2, 1, 4, 3, true).reason == &"no_path", "move: over-distance path reason")
	_expect(ActionValidatorScript.validate_move(2, 1, 1, -1, true).reason == &"no_path", "move: negative max distance reason")
	_expect(ActionValidatorScript.validate_move(0, 1, 1, 3, true).reason == &"no_ap", "move: insufficient AP reason")
	_expect(ActionValidatorScript.validate_move(2, 1, 1, 3, false).reason == &"destination_unavailable", "move: unavailable destination reason")


func _test_attack_validation() -> void:
	var actor: StringName = &"player_1"
	var target: StringName = &"enemy_1"
	var valid := ActionValidatorScript.validate_attack(actor, target, 2, 1, Vector3i(1, 0, 1), Vector3i(2, 0, 2), 2, true, true, true)
	_expect(valid.success, "attack: valid request should be accepted")
	_expect(valid.actor_id == actor and valid.target_id == target and valid.ap_cost == 1, "attack: accepted metadata")
	_expect(valid.action_type == &"attack", "attack: result should identify its action type")

	var invalid_cost := ActionValidatorScript.validate_attack(actor, target, 2, -1, Vector3i.ZERO, Vector3i(1, 0, 1), 2, true, true, true)
	_expect(invalid_cost.reason == &"invalid_cost", "attack: invalid cost reason")
	var no_ap := ActionValidatorScript.validate_attack(actor, target, 0, 1, Vector3i.ZERO, Vector3i(1, 0, 1), 2, true, true, true)
	_expect(no_ap.reason == &"no_ap", "attack: insufficient AP reason")
	var no_path := ActionValidatorScript.validate_attack(actor, target, 2, 1, Vector3i.ZERO, Vector3i(1, 0, 1), -1, true, true, true)
	_expect(no_path.reason == &"invalid_cost", "attack: invalid range is rejected as invalid configuration")
	var self_target := ActionValidatorScript.validate_attack(actor, actor, 2, 1, Vector3i.ZERO, Vector3i.ZERO, 2, true, true, true)
	_expect(self_target.reason == &"invalid_target", "attack: self-target reason")
	var dead := ActionValidatorScript.validate_attack(actor, target, 2, 1, Vector3i.ZERO, Vector3i(1, 0, 1), 2, false, true, true)
	_expect(dead.reason == &"target_dead", "attack: dead target reason")
	var friendly := ActionValidatorScript.validate_attack(actor, target, 2, 1, Vector3i.ZERO, Vector3i(1, 0, 1), 2, true, false, true)
	_expect(friendly.reason == &"not_hostile", "attack: friendly target reason")
	var far := ActionValidatorScript.validate_attack(actor, target, 2, 1, Vector3i.ZERO, Vector3i(3, 0, 0), 2, true, true, true)
	_expect(far.reason == &"out_of_range", "attack: out-of-range reason")
	var blocked := ActionValidatorScript.validate_attack(actor, target, 2, 1, Vector3i.ZERO, Vector3i(1, 0, 1), 2, true, true, false)
	_expect(blocked.reason == &"no_los", "attack: no LOS reason")


func _test_interact_and_loot_validation() -> void:
	var actor: StringName = &"player_1"
	var object: StringName = &"door_1"
	var cell := Vector3i(2, 0, 2)
	var near_cell := Vector3i(3, 0, 2)
	var far_cell := Vector3i(6, 0, 2)

	var interact := ActionValidatorScript.validate_interact(actor, object, 2, 1, cell, near_cell, 1)
	_expect(interact.success, "interact: valid target should be accepted")
	_expect(interact.action_type == &"interact" and interact.ap_cost == 1, "interact: result metadata")
	_expect(ActionValidatorScript.validate_interact(actor, object, 2, 1, cell, near_cell, 1, false, true).reason == &"invalid_target", "interact: invalid target reason")
	_expect(ActionValidatorScript.validate_interact(actor, object, 2, 1, cell, near_cell, 1, true, false).reason == &"target_unavailable", "interact: unavailable target reason")
	_expect(ActionValidatorScript.validate_interact(actor, object, 0, 1, cell, near_cell, 1).reason == &"no_ap", "interact: insufficient AP reason")
	_expect(ActionValidatorScript.validate_interact(actor, object, 2, 1, cell, far_cell, 1).reason == &"out_of_range", "interact: out-of-range reason")

	var container: StringName = &"loot_crate_1"
	var loot := ActionValidatorScript.validate_loot(actor, container, 2, 1, cell, near_cell, 1)
	_expect(loot.success, "loot: valid container should be accepted")
	_expect(loot.action_type == &"loot" and loot.target_id == container, "loot: result metadata")
	_expect(ActionValidatorScript.validate_loot(actor, container, 2, 1, cell, near_cell, 1, false, true, true).reason == &"invalid_container", "loot: invalid container reason")
	_expect(ActionValidatorScript.validate_loot(actor, container, 2, 1, cell, near_cell, 1, true, false, true).reason == &"container_unavailable", "loot: unavailable container reason")
	_expect(ActionValidatorScript.validate_loot(actor, container, 0, 1, cell, near_cell, 1).reason == &"no_ap", "loot: insufficient AP reason")
	_expect(ActionValidatorScript.validate_loot(actor, container, 2, 1, cell, far_cell, 1).reason == &"out_of_range", "loot: out-of-range reason")
	_expect(ActionValidatorScript.validate_loot(actor, container, 2, 1, cell, near_cell, 1, true, true, false).reason == &"inventory_full", "loot: inventory capacity reason")

	var legacy := ActionResultScript.accepted(actor, object, 1)
	_expect(legacy.success and legacy.action_type == &"", "action: legacy factory call should remain compatible")


func _test_combat_resolution() -> void:
	var validation := ActionResultScript.accepted(&"player_1", &"enemy_1", 1, &"attack")
	var result := CombatResolverScript.resolve_attack(validation, 10, 4)
	_expect(result.success, "combat: accepted validation should resolve")
	_expect(result.action_type == &"attack", "combat: resolved result should preserve action type")
	_expect(result.damage == 4 and not result.killed, "combat: normal damage")
	_expect(CombatResolverScript.remaining_hp(10, result) == 6, "combat: remaining HP after normal damage")

	var kill := CombatResolverScript.resolve_attack(validation, 3, 10)
	_expect(kill.damage == 3 and kill.killed, "combat: overkill should clamp and kill")
	_expect(CombatResolverScript.remaining_hp(3, kill) == 0, "combat: killed target reaches zero HP")
	var zero_damage := CombatResolverScript.resolve_attack(validation, 3, -5)
	_expect(zero_damage.damage == 0 and not zero_damage.killed, "combat: negative damage should clamp to zero")
	var zero_hp := CombatResolverScript.resolve_attack(validation, 0, 10)
	_expect(zero_hp.damage == 0 and not zero_hp.killed, "combat: already zero HP should not be killed again")

	var rejected := ActionResultScript.rejected(&"no_los", &"player_1", &"enemy_1")
	rejected.damage = 99
	var rejected_result := CombatResolverScript.resolve_attack(rejected, 10, 5)
	_expect(not rejected_result.success and rejected_result.reason == &"no_los", "combat: rejected validation remains rejected")
	_expect(rejected_result.action_type == &"", "combat: legacy rejected result remains compatible")
	_expect(rejected_result.damage == 99, "combat: rejected result preserves existing fields")
	_expect(CombatResolverScript.remaining_hp(10, rejected_result) == 10, "combat: rejected result causes no HP loss")


func _test_turn_flow() -> void:
	var manager = TurnManagerScript.new()
	manager.configure([&"p1", &"p1", &"", &"p2"], [&"e1", &"e1", &"", &"e2"])
	_expect(manager.get_player_ids() == [&"p1", &"p2"], "turn: player IDs should be stable and deduplicated")
	_expect(manager.get_enemy_ids() == [&"e1", &"e2"], "turn: enemy IDs should be stable and deduplicated")
	_expect(manager.get_phase() == TurnManagerScript.Phase.EXPLORATION, "turn: configure starts in exploration")
	_expect(manager.has_unit(&"p1") and not manager.has_unit(&"missing"), "turn: unit membership")
	_expect(not manager.end_player_turn(), "turn: cannot end player turn during exploration")

	manager.start_combat()
	_expect(manager.is_player_turn(), "turn: combat can start with player first")
	_expect(manager.end_player_turn() and manager.is_enemy_turn(), "turn: player to enemy transition")
	_expect(manager.end_enemy_turn() and manager.is_player_turn(), "turn: enemy to player transition")
	_expect(not manager.end_enemy_turn(), "turn: cannot end enemy turn during player turn")

	_expect(manager.reset_to_exploration(), "turn: live combat can reset to exploration")
	_expect(manager.get_phase() == TurnManagerScript.Phase.EXPLORATION, "turn: reset phase")
	manager.start_combat(false)
	_expect(manager.is_enemy_turn(), "turn: enemy-first combat start")
	manager.remove_unit(&"e1")
	_expect(manager.has_unit(&"e2") and not manager.has_unit(&"e1"), "turn: remove one enemy")
	manager.remove_unit(&"e2")
	_expect(manager.get_phase() == TurnManagerScript.Phase.VICTORY and manager.is_terminal(), "turn: last enemy creates victory")
	_expect(manager.reset_to_exploration(), "turn: resolved victory should return to exploration")
	_expect(manager.get_phase() == TurnManagerScript.Phase.EXPLORATION and not manager.is_terminal(), "turn: exploration after victory is not terminal")
	_expect(not manager.end_enemy_turn(), "turn: exploration cannot end enemy turn")
	manager.remove_unit(&"p1")
	_expect(manager.get_phase() == TurnManagerScript.Phase.EXPLORATION, "turn: exploration remains stable after roster cleanup")

	var defeat_manager = TurnManagerScript.new()
	defeat_manager.configure([&"p1"], [&"e1"])
	defeat_manager.start_combat()
	defeat_manager.remove_unit(&"p1")
	_expect(defeat_manager.get_phase() == TurnManagerScript.Phase.DEFEAT, "turn: last player creates defeat")
	_expect(not defeat_manager.reset_to_exploration(), "turn: defeat cannot reset")
	defeat_manager.remove_unit(&"e1")
	_expect(defeat_manager.get_phase() == TurnManagerScript.Phase.DEFEAT, "turn: terminal defeat cannot be overwritten")

	var invalid_manager = TurnManagerScript.new()
	invalid_manager.configure([], [&"e1"])
	invalid_manager.start_combat()
	_expect(invalid_manager.get_phase() == TurnManagerScript.Phase.EXPLORATION, "turn: missing faction prevents combat start")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
