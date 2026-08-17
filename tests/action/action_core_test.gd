extends SceneTree

const ActionResultScript = preload("res://scripts/core/action/action_result.gd")
const ActionRequestScript = preload("res://scripts/core/action/action_request.gd")
const ActionExecutionContextScript = preload("res://scripts/core/action/action_execution_context.gd")
const ActionExecutorScript = preload("res://scripts/core/action/action_executor.gd")

var _failures: Array[String] = []
var _executed_actions: Array[StringName] = []
var _commit_calls: int = 0
var _commit_should_fail: bool = false


func _init() -> void:
	_test_four_actions_share_one_executor()
	_test_validation_and_execution_fail_without_ap_commit()
	_test_unknown_action_and_ap_shortage()
	_finish()


func _test_four_actions_share_one_executor() -> void:
	var executor = ActionExecutorScript.new()
	executor.register_handler(&"move", Callable(self, "_handle_success"))
	executor.register_handler(&"loot", Callable(self, "_handle_success"))
	var context = _new_context(10)
	context.register_handler(&"interact", Callable(self, "_handle_success"))

	var move_request = ActionRequestScript.new(
		&"move",
		&"player_1",
		&"cell_2",
		2,
		{
			ActionExecutorScript.KEY_PATH: [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)],
			ActionExecutorScript.KEY_MAX_DISTANCE: 3,
			ActionExecutorScript.KEY_DESTINATION_AVAILABLE: true,
		}
	)
	var move_result = executor.execute(move_request, context)
	_expect(move_result.success, "action: move should execute through the shared executor")
	_expect(_has_metadata(move_result, &"move", &"player_1", &"cell_2", 2), "action: move metadata")
	_expect(context.current_ap == 8 and context.get_commit_count() == 1, "action: move should commit AP once")

	var attack_request = ActionRequestScript.new(
		&"attack",
		&"player_1",
		&"enemy_1",
		3,
		{
			ActionExecutorScript.KEY_ACTOR_CELL: Vector3i.ZERO,
			ActionExecutorScript.KEY_TARGET_CELL: Vector3i(1, 0, 1),
			ActionExecutorScript.KEY_ATTACK_RANGE: 2,
			ActionExecutorScript.KEY_TARGET_HP: 4,
			ActionExecutorScript.KEY_DAMAGE: 9,
		}
	)
	var attack_result = executor.execute(attack_request, context)
	_expect(attack_result.success, "action: attack should use CombatResolver through the shared executor")
	_expect(attack_result.damage == 4 and attack_result.killed, "action: attack damage and killed should pass through")
	_expect(_has_metadata(attack_result, &"attack", &"player_1", &"enemy_1", 3), "action: attack metadata")
	_expect(context.current_ap == 5 and context.get_commit_count() == 2, "action: attack should commit AP once")

	var interact_request = ActionRequestScript.new(
		&"interact",
		&"player_1",
		&"door_1",
		1,
		{
			ActionExecutorScript.KEY_ACTOR_CELL: Vector3i(2, 0, 2),
			ActionExecutorScript.KEY_TARGET_CELL: Vector3i(3, 0, 2),
			ActionExecutorScript.KEY_INTERACTION_RANGE: 1,
		}
	)
	var interact_result = executor.execute(interact_request, context)
	_expect(interact_result.success, "action: interact should dispatch a context handler")
	_expect(_has_metadata(interact_result, &"interact", &"player_1", &"door_1", 1), "action: interact metadata")

	var loot_request = ActionRequestScript.new(
		&"loot",
		&"player_1",
		&"crate_1",
		1,
		{
			ActionExecutorScript.KEY_ACTOR_CELL: Vector3i(2, 0, 2),
			ActionExecutorScript.KEY_TARGET_CELL: Vector3i(3, 0, 2),
			ActionExecutorScript.KEY_INTERACTION_RANGE: 1,
		}
	)
	var loot_result = executor.execute(loot_request, context)
	_expect(loot_result.success, "action: loot should dispatch an executor handler")
	_expect(_has_metadata(loot_result, &"loot", &"player_1", &"crate_1", 1), "action: loot metadata")
	_expect(context.current_ap == 3 and context.get_commit_count() == 4, "action: all successful actions should commit exactly once")
	_expect(_executed_actions == [&"move", &"interact", &"loot"], "action: all handlers should share one dispatch path")
	_expect(_commit_calls == 4, "action: AP committer should be called once per positive-cost success")


func _test_validation_and_execution_fail_without_ap_commit() -> void:
	var executor = ActionExecutorScript.new()
	executor.register_handler(&"move", Callable(self, "_handle_success"))
	var context = _new_context(4)
	var executed_before := _executed_actions.size()
	var commits_before := _commit_calls

	var invalid_path = ActionRequestScript.new(
		&"move",
		&"player_1",
		&"cell_bad",
		1,
		{
			ActionExecutorScript.KEY_PATH: [Vector2i.ZERO],
			ActionExecutorScript.KEY_MAX_DISTANCE: 3,
		}
	)
	var validation_failure = executor.execute(invalid_path, context)
	_expect(not validation_failure.success and validation_failure.reason == &"no_path", "action: validation failure reason")
	_expect(_has_metadata(validation_failure, &"move", &"player_1", &"cell_bad", 1), "action: rejected result metadata")
	_expect(context.current_ap == 4 and context.get_commit_count() == 0, "action: validation failure must not commit AP")
	_expect(_executed_actions.size() == executed_before and _commit_calls == commits_before, "action: validation failure must not execute a handler")

	_commit_should_fail = true
	var commit_failure_request = ActionRequestScript.new(
		&"move",
		&"player_1",
		&"cell_commit",
		1,
		{
			ActionExecutorScript.KEY_PATH_LENGTH: 1,
			ActionExecutorScript.KEY_MAX_DISTANCE: 1,
		}
	)
	var commit_failure = executor.execute(commit_failure_request, context)
	_expect(not commit_failure.success and commit_failure.reason == &"ap_commit_failed", "action: failed AP commit reason")
	_expect(context.current_ap == 4 and context.get_commit_count() == 0, "action: failed AP commit must leave AP unchanged")
	_expect(_commit_calls == commits_before + 1, "action: failed AP commit should still be attempted once")
	_commit_should_fail = false

	var execution_failure_context = _new_context(4)
	var failing_executor = ActionExecutorScript.new()
	failing_executor.register_handler(&"interact", Callable(self, "_handle_failure"))
	var execution_failure_request = ActionRequestScript.new(
		&"interact",
		&"player_1",
		&"door_fail",
		1,
		{
			ActionExecutorScript.KEY_ACTOR_CELL: Vector3i.ZERO,
			ActionExecutorScript.KEY_TARGET_CELL: Vector3i.ZERO,
			ActionExecutorScript.KEY_INTERACTION_RANGE: 0,
		}
	)
	var execution_failure = failing_executor.execute(execution_failure_request, execution_failure_context)
	_expect(not execution_failure.success and execution_failure.reason == &"execution_failed", "action: handler failure reason")
	_expect(execution_failure_context.current_ap == 4 and execution_failure_context.get_commit_count() == 0, "action: execution failure must not commit AP")


func _test_unknown_action_and_ap_shortage() -> void:
	var executor = ActionExecutorScript.new()
	executor.register_handler(&"move", Callable(self, "_handle_success"))
	var context = _new_context(0)
	var executed_before := _executed_actions.size()
	var commits_before := _commit_calls

	var no_ap_request = ActionRequestScript.new(
		&"move",
		&"player_1",
		&"cell_no_ap",
		1,
		{
			ActionExecutorScript.KEY_PATH_LENGTH: 1,
			ActionExecutorScript.KEY_MAX_DISTANCE: 1,
		}
	)
	var no_ap = executor.execute(no_ap_request, context)
	_expect(not no_ap.success and no_ap.reason == &"no_ap", "action: AP shortage should reject before execution")
	_expect(context.current_ap == 0 and context.get_commit_count() == 0, "action: AP shortage must not commit")
	_expect(_executed_actions.size() == executed_before and _commit_calls == commits_before, "action: AP shortage must not call handler or committer")

	var unknown = ActionRequestScript.new(&"teleport", &"player_1", &"cell_unknown", 1)
	var unknown_result = executor.execute(unknown, context)
	_expect(not unknown_result.success and unknown_result.reason == &"unknown_action", "action: unknown action should reject explicitly")
	_expect(unknown_result.action_type == &"teleport" and unknown_result.actor_id == &"player_1" and unknown_result.ap_cost == 1, "action: unknown result metadata")
	_expect(context.get_commit_count() == 0, "action: unknown action must not commit")


func _new_context(initial_ap: int):
	var context = ActionExecutionContextScript.new(initial_ap)
	context.set_ap_committer(Callable(self, "_commit_ap"))
	return context


func _handle_success(request, _context) -> bool:
	_executed_actions.append(request.action_type)
	return true


func _handle_failure(_request, _context) -> bool:
	return false


func _commit_ap(_cost: int) -> bool:
	_commit_calls += 1
	return not _commit_should_fail


func _has_metadata(result: ActionResult, action_type: StringName, actor_id: StringName, target_id: StringName, ap_cost: int) -> bool:
	return result.action_type == action_type and result.actor_id == actor_id and result.target_id == target_id and result.ap_cost == ap_cost


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ACTION_CORE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ACTION_CORE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
