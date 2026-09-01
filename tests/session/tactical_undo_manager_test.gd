extends SceneTree

const TacticalUndoManagerScript = preload("res://scripts/core/undo/tactical_undo_manager.gd")
const TurnManagerScript = preload("res://scripts/core/turn/turn_manager.gd")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")

var _failures: Array[String] = []
var _model: Dictionary = {}
var _capture_should_fail: bool = false
var _restore_should_succeed: bool = true
var _undo_manager_under_test
var _observe_restore_availability: bool = false
var _restore_saw_unavailable: bool = false


func _init() -> void:
	_test_undo_manager_checkpoints_and_atomicity()
	_test_undo_manager_restore_failure_and_locking()
	_test_turn_manager_state_roundtrip_and_validation()
	_test_game_state_manager_state_roundtrip_and_validation()
	_finish()


func _test_undo_manager_checkpoints_and_atomicity() -> void:
	_model = {
		&"counter": 0,
		&"nested": {&"values": [1]},
	}
	_capture_should_fail = false
	var manager := TacticalUndoManagerScript.new()
	manager.configure(Callable(self, "_capture_test_model"), Callable(self, "_restore_test_model"))
	var availability_events: Array = []
	manager.availability_changed.connect(func(can_step: bool, can_turn: bool) -> void:
		availability_events.append([can_step, can_turn])
	)

	_expect(manager.capture_turn_checkpoint(), "undo: turn checkpoint should capture at turn start")
	_expect(not manager.can_undo_turn(), "undo: turn undo requires a successful player action")
	_expect(manager.begin_player_action(), "undo: first player action should begin")
	_expect(not manager.can_undo_step() and not manager.can_undo_turn(), "undo: both undo scopes must be hidden during an action")
	_model[&"counter"] = 1
	_expect(manager.commit_player_action(), "undo: successful action should commit a step checkpoint")
	_capture_should_fail = true
	_expect(not manager.begin_player_action(), "undo: failed action capture should be rejected")
	_expect(manager.can_undo_step() and manager.can_undo_turn(), "undo: failed action capture must preserve prior checkpoints")
	_capture_should_fail = false
	_model[&"counter"] = 7
	_model[&"nested"][&"values"][0] = 99
	_expect(manager.can_undo_step() and manager.can_undo_turn(), "undo: completed action should enable both undo scopes")
	_expect(manager.undo_step(), "undo: step undo should restore the last action boundary")
	_expect(_model[&"counter"] == 0, "undo: step undo should restore the pre-action counter")
	_expect(_model[&"nested"][&"values"][0] == 1, "undo: turn capture should be detached from later nested mutation")
	_expect(not manager.can_undo_step(), "undo: step checkpoint is consumed after one undo")
	_expect(manager.can_undo_turn(), "undo: step undo must retain the turn checkpoint")
	_expect(not manager.undo_step(), "undo: a consumed step checkpoint cannot be used twice")
	_expect(manager.undo_turn(), "undo: turn undo should restore the player-turn entry state")
	_expect(_model[&"counter"] == 0 and _model[&"nested"][&"values"][0] == 1, "undo: turn undo should restore the detached turn snapshot")
	_expect(not manager.can_undo_step() and not manager.can_undo_turn(), "undo: turn undo consumes both checkpoints")
	_expect(availability_events.has([true, true]), "undo: availability should signal both actions becoming available")
	_expect(availability_events.has([false, true]), "undo: availability should signal step consumption")
	_expect(availability_events.has([false, false]), "undo: availability should signal turn consumption")

	_model[&"counter"] = 10
	_expect(manager.capture_turn_checkpoint(), "undo: a new turn should replace the old turn checkpoint")
	_expect(manager.begin_player_action(), "undo: action should begin after a new turn checkpoint")
	_model[&"counter"] = 11
	_expect(manager.commit_player_action(), "undo: replacement turn action should commit")
	_expect(manager.begin_player_action(), "undo: second action should begin")
	_model[&"counter"] = 12
	_expect(manager.cancel_player_action(), "undo: cancelled action should close without committing")
	_expect(manager.undo_step(), "undo: cancelled action must leave the prior step checkpoint intact")
	_expect(_model[&"counter"] == 10, "undo: failed/cancelled action must not overwrite the prior step")
	_expect(not manager.commit_player_action(), "undo: commit without an open action must be rejected")


func _test_undo_manager_restore_failure_and_locking() -> void:
	_model = {&"counter": 20}
	_restore_should_succeed = true
	var manager := TacticalUndoManagerScript.new()
	manager.configure(Callable(self, "_capture_test_model"), Callable(self, "_restore_test_model"))
	_expect(manager.capture_turn_checkpoint(), "undo failure: turn checkpoint should capture")
	_expect(manager.begin_player_action(), "undo failure: action should begin")
	_model[&"counter"] = 21
	_expect(manager.commit_player_action(), "undo failure: action should commit")

	_restore_should_succeed = false
	_expect(not manager.undo_step(), "undo failure: failed restore should be rejected")
	_expect(manager.can_undo_step() and manager.can_undo_turn(), "undo failure: failed restore must retain both checkpoints")
	_restore_should_succeed = true

	manager.set_locked(true)
	_expect(not manager.can_undo_step() and not manager.can_undo_turn(), "undo lock: locked manager must hide both actions")
	_expect(not manager.undo_step(), "undo lock: locked manager must reject undo")
	manager.set_locked(false)
	_expect(manager.can_undo_step() and manager.can_undo_turn(), "undo lock: unlocking must restore availability")

	_undo_manager_under_test = manager
	_observe_restore_availability = true
	_restore_saw_unavailable = false
	_expect(manager.undo_step(), "undo restore: successful retry should restore")
	_observe_restore_availability = false
	_expect(_restore_saw_unavailable, "undo restore: availability must be hidden during restore callback")
	_expect(_model[&"counter"] == 20, "undo restore: retry should restore the pre-action state")

	manager.invalidate_all()
	_expect(not manager.can_undo_step() and not manager.can_undo_turn(), "undo invalidation: invalidate_all clears both checkpoints")


func _test_turn_manager_state_roundtrip_and_validation() -> void:
	var manager := TurnManagerScript.new()
	var players: Array[StringName] = [&"p1", &"p1", &"p2"]
	var enemies: Array[StringName] = [&"e1"]
	manager.configure(players, enemies)
	var entry_snapshot: Dictionary = manager.capture_state()
	_expect(entry_snapshot[&"schema_version"] == 1, "turn snapshot: schema version should be explicit")
	_expect(manager.start_combat(), "turn snapshot: combat should start from configured rosters")
	_expect(manager.end_player_turn(), "turn snapshot: player turn should advance to enemy turn")
	var phase_events: Array = []
	manager.phase_changed.connect(func(previous: int, current: int) -> void:
		phase_events.append([previous, current])
	)
	_expect(manager.restore_state(entry_snapshot), "turn snapshot: valid entry snapshot should restore")
	_expect(manager.get_phase() == TurnManagerScript.Phase.EXPLORATION, "turn snapshot: phase should round-trip")
	_expect(manager.get_player_ids() == [&"p1", &"p2"], "turn snapshot: player IDs should round-trip in stable order")
	_expect(manager.get_enemy_ids() == [&"e1"], "turn snapshot: enemy IDs should round-trip")
	_expect(phase_events.size() == 1, "turn snapshot: changed restore should emit one phase signal")
	_expect(manager.restore_state(entry_snapshot), "turn snapshot: restoring the same state should remain accepted")
	_expect(phase_events.size() == 1, "turn snapshot: unchanged restore must not emit a duplicate signal")

	var stable_snapshot: Dictionary = manager.capture_state()
	var bad_phase: Dictionary = stable_snapshot.duplicate(true)
	bad_phase[&"phase"] = &"not_an_int"
	_expect(not manager.restore_state(bad_phase), "turn snapshot: wrong phase type must be rejected")
	_expect(manager.capture_state() == stable_snapshot, "turn snapshot: invalid phase restore must be atomic")
	_expect(not manager.restore_state(42), "turn snapshot: non-dictionary restore must be rejected")
	_expect(manager.capture_state() == stable_snapshot, "turn snapshot: non-dictionary restore must be atomic")
	var bad_ids: Dictionary = stable_snapshot.duplicate(true)
	bad_ids[&"player_ids"] = [42]
	_expect(not manager.restore_state(bad_ids), "turn snapshot: wrong roster element type must be rejected")
	_expect(manager.capture_state() == stable_snapshot, "turn snapshot: invalid roster restore must be atomic")


func _test_game_state_manager_state_roundtrip_and_validation() -> void:
	var manager := GameStateManagerScript.new()
	var state_events: Array = []
	var result_events: Array = []
	manager.state_changed.connect(func(previous: int, current: int) -> void:
		state_events.append([previous, current])
	)
	manager.result_changed.connect(func(_result: RefCounted) -> void:
		result_events.append(true)
	)
	var empty_snapshot: Dictionary = manager.capture_state()
	_expect(not empty_snapshot[&"result"][&"has_value"], "session snapshot: new session result should be empty")
	_expect(manager.start_exploration(), "session snapshot: setup should enter exploration")
	_expect(manager.start_extraction(), "session snapshot: setup should enter extraction")
	_expect(manager.confirm_extraction(&"undo_test_extracted"), "session snapshot: setup should record success")
	var success_snapshot: Dictionary = manager.capture_state()
	_expect(success_snapshot[&"state"] == GameStateManagerScript.State.RESULT, "session snapshot: result state should be captured")
	_expect(success_snapshot[&"result"][&"reason"] == &"undo_test_extracted", "session snapshot: result reason should be captured")

	_expect(manager.reset(), "session snapshot: reset should provide a different state to restore into")
	state_events.clear()
	result_events.clear()
	_expect(manager.restore_state(success_snapshot), "session snapshot: valid result snapshot should restore")
	_expect(manager.is_success() and manager.get_result_reason() == &"undo_test_extracted", "session snapshot: result fields should round-trip")
	_expect(state_events.size() == 1, "session snapshot: changed state restore should emit one state signal")
	_expect(result_events.size() == 1, "session snapshot: changed result restore should emit one result signal")
	_expect(manager.restore_state(success_snapshot), "session snapshot: unchanged result restore should remain accepted")
	_expect(state_events.size() == 1 and result_events.size() == 1, "session snapshot: unchanged restore must not duplicate signals")

	var stable_snapshot: Dictionary = manager.capture_state()
	var bad_result: Dictionary = stable_snapshot.duplicate(true)
	bad_result[&"result"][&"success"] = 1
	_expect(not manager.restore_state(bad_result), "session snapshot: wrong result type must be rejected")
	_expect(manager.capture_state() == stable_snapshot, "session snapshot: invalid result restore must be atomic")
	_expect(not manager.restore_state(42), "session snapshot: non-dictionary restore must be rejected")
	_expect(manager.capture_state() == stable_snapshot, "session snapshot: non-dictionary restore must be atomic")
	var bad_empty_result: Dictionary = stable_snapshot.duplicate(true)
	bad_empty_result[&"result"] = {&"has_value": false, &"success": false, &"reason": &"stale"}
	_expect(not manager.restore_state(bad_empty_result), "session snapshot: inconsistent empty result must be rejected")
	_expect(manager.capture_state() == stable_snapshot, "session snapshot: inconsistent result must not mutate state")


func _capture_test_model() -> Variant:
	if _capture_should_fail:
		return null
	return _model


func _restore_test_model(snapshot: Variant) -> bool:
	if _observe_restore_availability and _undo_manager_under_test != null:
		if not _undo_manager_under_test.can_undo_step() and not _undo_manager_under_test.can_undo_turn():
			_restore_saw_unavailable = true
	if not _restore_should_succeed or not snapshot is Dictionary:
		return false
	_model = (snapshot as Dictionary).duplicate(true)
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_UNDO_MANAGER_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_UNDO_MANAGER_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
