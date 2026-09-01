class_name GameStateManager
extends RefCounted

const SessionResultScript = preload("res://scripts/core/session/session_result.gd")

## Session-level state machine, intentionally independent from TurnManager.
##
## Combat resolution returns to exploration. A successful session can only be
## recorded by confirming extraction; clearing a combat encounter is never a
## session success by itself.

enum State {
	PREPARATION,
	EXPLORATION,
	COMBAT,
	EXTRACTION,
	RESULT,
}

enum Result {
	NONE,
	SUCCESS,
	FAILURE,
}

## Alias for callers that use "Outcome" terminology.
enum Outcome {
	NONE,
	SUCCESS,
	FAILURE,
}

signal state_changed(previous: State, current: State)
signal result_changed(result: RefCounted)

const DEFAULT_EXTRACTION_REASON: StringName = &"extracted"
const DEFAULT_DEFEAT_REASON: StringName = &"team_defeated"
const DEFAULT_COMBAT_REASON: StringName = &"combat_resolved"
const STATE_SNAPSHOT_SCHEMA_VERSION: int = 1

var _state: State = State.PREPARATION
var _result = SessionResultScript.new()


func get_state() -> State:
	return _state


## Phase alias keeps the state readable for systems that call this a phase.
func get_phase() -> State:
	return get_state()


func is_active() -> bool:
	return _state == State.EXPLORATION or _state == State.COMBAT or _state == State.EXTRACTION


func is_terminal() -> bool:
	return _state == State.RESULT


func has_result() -> bool:
	return _result.has_value


func get_result() -> RefCounted:
	return _result.duplicate_result()


func get_result_state() -> Result:
	if not _result.has_value:
		return Result.NONE
	return Result.SUCCESS if _result.success else Result.FAILURE


func get_result_success() -> bool:
	return _result.is_success()


func get_result_reason() -> StringName:
	return _result.reason


## Returns a detached pure-data snapshot of the session state and result.
func capture_state() -> Dictionary:
	return {
		&"schema_version": STATE_SNAPSHOT_SCHEMA_VERSION,
		&"state": int(_state),
		&"result": {
			&"has_value": _result.has_value,
			&"success": _result.success,
			&"reason": _result.reason,
		},
	}


## Restores a checkpoint without passing through the ordinary legal transition
## graph. Validation is completed before mutation; each changed signal is
## emitted at most once.
func restore_state(snapshot: Variant) -> bool:
	var decoded: Variant = _decode_state(snapshot)
	if decoded == null:
		return false
	var next_state: State = decoded[&"state"]
	var next_result: Dictionary = decoded[&"result"]
	var state_changed_value := _state != next_state
	var result_changed_value := not _result_matches(next_result)
	var previous_state := _state
	_state = next_state
	_result = SessionResultScript.new(
		bool(next_result[&"success"]),
		StringName(next_result[&"reason"]),
		bool(next_result[&"has_value"]),
	)
	if state_changed_value:
		state_changed.emit(previous_state, _state)
	if result_changed_value:
		result_changed.emit(_result.duplicate_result())
	return true


func is_success() -> bool:
	return _result.is_success()


func is_failure() -> bool:
	return _result.is_failure()


## Applies only the non-terminal legal transitions. RESULT must be entered via
## confirm_extraction() or report_team_defeated() so its outcome is explicit.
func transition_to(next_state: State) -> bool:
	if not _is_legal_transition(_state, next_state):
		return false
	_set_state(next_state)
	return true


func start_exploration() -> bool:
	return transition_to(State.EXPLORATION)


func begin_exploration() -> bool:
	return start_exploration()


func start_combat() -> bool:
	return transition_to(State.COMBAT)


func begin_combat() -> bool:
	return start_combat()


## Combat completion intentionally returns to EXPLORATION, even if the caller
## has just eliminated every enemy in that encounter.
func resolve_combat(reason: StringName = DEFAULT_COMBAT_REASON) -> bool:
	if _state != State.COMBAT:
		return false
	return transition_to(State.EXPLORATION)


func finish_combat(reason: StringName = DEFAULT_COMBAT_REASON) -> bool:
	return resolve_combat(reason)


func end_combat(reason: StringName = DEFAULT_COMBAT_REASON) -> bool:
	return resolve_combat(reason)


func start_extraction() -> bool:
	return transition_to(State.EXTRACTION)


func begin_extraction() -> bool:
	return start_extraction()


## Cancels an unconfirmed extraction without consuming an action point.
func cancel_extraction() -> bool:
	return transition_to(State.EXPLORATION)


func abort_extraction() -> bool:
	return cancel_extraction()


## Records a successful result only from the extraction confirmation state.
func confirm_extraction(reason: StringName = DEFAULT_EXTRACTION_REASON) -> bool:
	if _state != State.EXTRACTION:
		return false
	_record_result(true, reason if reason != &"" else DEFAULT_EXTRACTION_REASON)
	return true


## Records a failed result for any active in-session state. Preparation and an
## already terminal session cannot be failed by a duplicate notification.
func report_team_defeated(reason: StringName = DEFAULT_DEFEAT_REASON) -> bool:
	if not is_active():
		return false
	_record_result(false, reason if reason != &"" else DEFAULT_DEFEAT_REASON)
	return true


func team_defeated(reason: StringName = DEFAULT_DEFEAT_REASON) -> bool:
	return report_team_defeated(reason)


func fail_for_team_defeat(reason: StringName = DEFAULT_DEFEAT_REASON) -> bool:
	return report_team_defeated(reason)


## Starts a fresh session. Repeated reset calls are successful but emit no
## duplicate state signal when the manager is already in PREPARATION.
func reset() -> bool:
	var changed := _state != State.PREPARATION
	_result = SessionResultScript.new()
	if changed:
		_set_state(State.PREPARATION)
	return true


func restart() -> bool:
	return reset()


func _record_result(result_success: bool, result_reason: StringName) -> void:
	_result = SessionResultScript.new(result_success, result_reason, true)
	_set_state(State.RESULT)
	result_changed.emit(_result.duplicate_result())


func _set_state(next_state: State) -> void:
	if _state == next_state:
		return
	var previous := _state
	_state = next_state
	state_changed.emit(previous, next_state)


func _is_legal_transition(current: State, next_state: State) -> bool:
	match current:
		State.PREPARATION:
			return next_state == State.EXPLORATION
		State.EXPLORATION:
			return next_state == State.COMBAT or next_state == State.EXTRACTION
		State.COMBAT:
			return next_state == State.EXPLORATION
		State.EXTRACTION:
			return next_state == State.EXPLORATION
		State.RESULT:
			return false
	return false


static func _decode_state(snapshot: Variant) -> Variant:
	if not snapshot is Dictionary:
		return null
	var state_snapshot: Dictionary = snapshot
	if not state_snapshot.has(&"schema_version") or not state_snapshot[&"schema_version"] is int:
		return null
	if state_snapshot[&"schema_version"] != STATE_SNAPSHOT_SCHEMA_VERSION:
		return null
	if not state_snapshot.has(&"state") or not state_snapshot[&"state"] is int:
		return null
	var raw_state: int = state_snapshot[&"state"]
	if raw_state < int(State.PREPARATION) or raw_state > int(State.RESULT):
		return null
	var raw_result: Variant = state_snapshot.get(&"result", null)
	if not raw_result is Dictionary:
		return null
	var result: Dictionary = raw_result
	if not result.has(&"has_value") or not result[&"has_value"] is bool:
		return null
	if not result.has(&"success") or not result[&"success"] is bool:
		return null
	if not result.has(&"reason"):
		return null
	var raw_reason: Variant = result[&"reason"]
	if not (raw_reason is StringName or raw_reason is String):
		return null
	var has_value: bool = result[&"has_value"]
	var success: bool = result[&"success"]
	var reason := StringName(raw_reason)
	if not has_value and (success or reason != &""):
		return null
	if has_value and reason == &"":
		return null
	return {
		&"state": raw_state,
		&"result": {
			&"has_value": has_value,
			&"success": success,
			&"reason": reason,
		},
	}


func _result_matches(result: Dictionary) -> bool:
	return _result.has_value == result[&"has_value"] \
		and _result.success == result[&"success"] \
		and _result.reason == StringName(result[&"reason"])
