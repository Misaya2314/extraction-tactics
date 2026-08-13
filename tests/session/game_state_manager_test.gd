extends SceneTree

const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_legal_and_illegal_transitions()
	_test_combat_returns_to_exploration()
	_test_extraction_is_the_only_success_path()
	_test_team_defeat_failure()
	_test_reset_and_signal_stability()
	_finish()


func _test_legal_and_illegal_transitions() -> void:
	var manager = GameStateManagerScript.new()
	var changes: Array = []
	manager.state_changed.connect(func(previous: int, current: int) -> void:
		changes.append([previous, current])
	)

	_expect(manager.get_state() == GameStateManagerScript.State.PREPARATION, "state: new manager should begin in preparation")
	_expect(not manager.start_combat(), "state: preparation cannot jump directly to combat")
	_expect(not manager.start_extraction(), "state: preparation cannot jump directly to extraction")
	_expect(changes.is_empty(), "state: illegal transitions must not emit state signals")
	_expect(manager.start_exploration(), "state: preparation should enter exploration")
	_expect(manager.get_state() == GameStateManagerScript.State.EXPLORATION, "state: exploration should be active")
	_expect(changes.size() == 1, "state: legal transition should emit once")
	_expect(not manager.start_exploration(), "state: duplicate transition should be rejected")
	_expect(changes.size() == 1, "state: duplicate transition must not emit")
	_expect(manager.start_combat(), "state: exploration should enter combat")
	_expect(manager.get_state() == GameStateManagerScript.State.COMBAT, "state: combat should be active")


func _test_combat_returns_to_exploration() -> void:
	var manager = GameStateManagerScript.new()
	_expect(manager.start_exploration(), "combat: setup should enter exploration")
	_expect(manager.start_combat(), "combat: exploration should enter combat")
	_expect(not manager.start_extraction(), "combat: combat cannot enter extraction directly")
	_expect(manager.resolve_combat(), "combat: resolved encounter should return to exploration")
	_expect(manager.get_state() == GameStateManagerScript.State.EXPLORATION, "combat: resolved encounter must not be terminal")
	_expect(not manager.resolve_combat(), "combat: duplicate resolution should be rejected")
	_expect(not manager.has_result(), "combat: clearing enemies must not create a session result")
	_expect(manager.start_extraction(), "combat: exploration after combat can enter extraction")


func _test_extraction_is_the_only_success_path() -> void:
	var manager = GameStateManagerScript.new()
	var result_events: Array = []
	manager.result_changed.connect(func(_result: RefCounted) -> void:
		result_events.append(true)
	)
	_expect(not manager.confirm_extraction(), "result: preparation cannot confirm extraction")
	_expect(manager.start_exploration(), "result: setup should enter exploration")
	_expect(not manager.confirm_extraction(), "result: exploration cannot confirm extraction")
	_expect(manager.start_extraction(), "result: exploration should enter extraction")
	_expect(manager.confirm_extraction(&"extraction_confirmed"), "result: extraction confirmation should succeed")
	_expect(manager.get_state() == GameStateManagerScript.State.RESULT, "result: confirmation should enter result")
	_expect(manager.get_result_state() == GameStateManagerScript.Result.SUCCESS, "result: extraction should record success")
	_expect(manager.get_result_success(), "result: success flag should be true")
	_expect(manager.get_result_reason() == &"extraction_confirmed", "result: success reason should be retained")
	_expect(result_events.size() == 1, "result: success should emit one result signal")
	_expect(not manager.confirm_extraction(), "result: terminal result cannot be confirmed twice")
	_expect(result_events.size() == 1, "result: duplicate confirmation must not emit")
	_expect(not manager.transition_to(GameStateManagerScript.State.EXPLORATION), "result: terminal state cannot transition back directly")


func _test_team_defeat_failure() -> void:
	var exploration_manager = GameStateManagerScript.new()
	_expect(exploration_manager.start_exploration(), "failure: setup should enter exploration")
	_expect(exploration_manager.report_team_defeated(&"all_players_down"), "failure: defeat should be accepted from exploration")
	_expect(exploration_manager.get_state() == GameStateManagerScript.State.RESULT, "failure: defeat should enter result")
	_expect(exploration_manager.get_result_state() == GameStateManagerScript.Result.FAILURE, "failure: defeat should record failure")
	_expect(exploration_manager.get_result_reason() == &"all_players_down", "failure: defeat reason should be retained")
	_expect(not exploration_manager.report_team_defeated(), "failure: terminal defeat cannot be reported twice")

	var combat_manager = GameStateManagerScript.new()
	combat_manager.start_exploration()
	combat_manager.start_combat()
	_expect(combat_manager.report_team_defeated(), "failure: defeat should be accepted during combat")
	_expect(combat_manager.is_failure(), "failure: combat defeat should be terminal failure")


func _test_reset_and_signal_stability() -> void:
	var manager = GameStateManagerScript.new()
	var state_events: Array = []
	var result_events: Array = []
	manager.state_changed.connect(func(_previous: int, _current: int) -> void:
		state_events.append(true)
	)
	manager.result_changed.connect(func(_result: RefCounted) -> void:
		result_events.append(true)
	)
	_expect(manager.reset(), "reset: initial reset should be harmless and successful")
	_expect(state_events.is_empty(), "reset: reset in preparation must not emit duplicate state signal")
	manager.start_exploration()
	manager.start_extraction()
	manager.confirm_extraction()
	_expect(manager.has_result(), "reset: setup should create a result")
	_expect(manager.reset(), "reset: terminal session should be restartable")
	_expect(manager.get_state() == GameStateManagerScript.State.PREPARATION, "reset: restart should return to preparation")
	_expect(not manager.has_result(), "reset: restart should clear the previous result")
	_expect(state_events.size() == 4, "reset: exploration, extraction, result and reset should signal once each")
	_expect(result_events.size() == 1, "reset: reset must not emit a duplicate result event")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GAME_STATE_MANAGER_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("GAME_STATE_MANAGER_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
