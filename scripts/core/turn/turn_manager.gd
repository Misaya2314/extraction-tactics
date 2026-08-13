class_name TurnManager
extends RefCounted

signal phase_changed(previous: Phase, current: Phase)

enum Phase {
	EXPLORATION,
	PLAYER_TURN,
	ENEMY_TURN,
	VICTORY,
	DEFEAT,
}

var _phase: Phase = Phase.EXPLORATION
var _player_ids: Array[StringName] = []
var _enemy_ids: Array[StringName] = []


## Replaces both faction rosters with stable, de-duplicated, non-empty IDs.
## Configuration resets the phase to exploration and cannot emit a phase signal
## because it is intended as pre-combat setup.
func configure(player_ids: Array[StringName], enemy_ids: Array[StringName]) -> void:
	_player_ids = _unique_non_empty(player_ids)
	_enemy_ids = _unique_non_empty(enemy_ids)
	_phase = Phase.EXPLORATION


func get_phase() -> Phase:
	return _phase


## Starts combat only when both factions contain at least one living ID and the
## manager is not already in a terminal state.
func start_combat(player_first: bool = true) -> bool:
	if is_terminal() or _player_ids.is_empty() or _enemy_ids.is_empty():
		return false
	_set_phase(Phase.PLAYER_TURN if player_first else Phase.ENEMY_TURN)
	return true


func end_player_turn() -> bool:
	if _phase != Phase.PLAYER_TURN or is_terminal():
		return false
	if _enemy_ids.is_empty():
		_set_phase(Phase.VICTORY)
		return true
	_set_phase(Phase.ENEMY_TURN)
	return true


func end_enemy_turn() -> bool:
	if _phase != Phase.ENEMY_TURN or is_terminal():
		return false
	if _player_ids.is_empty():
		_set_phase(Phase.DEFEAT)
		return true
	_set_phase(Phase.PLAYER_TURN)
	return true


## Removes a unit from whichever faction owns it. VICTORY/DEFEAT are encounter
## phases and are only emitted while a combat turn is active; the session
## controller decides whether a resolved encounter returns to exploration or
## the whole session enters RESULT.
func remove_unit(unit_id: StringName) -> void:
	if unit_id == &"" or is_terminal():
		return
	var removed := false
	removed = _remove_from_array(_player_ids, unit_id) or removed
	removed = _remove_from_array(_enemy_ids, unit_id) or removed
	if not removed:
		return
	if _phase == Phase.PLAYER_TURN or _phase == Phase.ENEMY_TURN:
		if _enemy_ids.is_empty():
			_set_phase(Phase.VICTORY)
		elif _player_ids.is_empty():
			_set_phase(Phase.DEFEAT)


func has_unit(unit_id: StringName) -> bool:
	return unit_id != &"" and (_player_ids.has(unit_id) or _enemy_ids.has(unit_id))


func get_player_ids() -> Array[StringName]:
	return _player_ids.duplicate()


func get_enemy_ids() -> Array[StringName]:
	return _enemy_ids.duplicate()


func is_player_turn() -> bool:
	return _phase == Phase.PLAYER_TURN


func is_enemy_turn() -> bool:
	return _phase == Phase.ENEMY_TURN


func is_terminal() -> bool:
	return _phase == Phase.VICTORY or _phase == Phase.DEFEAT


## Returns a resolved encounter to exploration even when the enemy roster is
## empty. DEFEAT remains terminal because it represents a squad failure, not a
## resolved encounter.
func reset_to_exploration() -> bool:
	if _phase == Phase.VICTORY:
		_set_phase(Phase.EXPLORATION)
		return true
	if is_terminal() or _player_ids.is_empty() or _enemy_ids.is_empty():
		return false
	_set_phase(Phase.EXPLORATION)
	return true


func _set_phase(next_phase: Phase) -> void:
	if _phase == next_phase:
		return
	var previous: Phase = _phase
	_phase = next_phase
	phase_changed.emit(previous, next_phase)


func _unique_non_empty(ids: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for unit_id in ids:
		if unit_id == &"" or result.has(unit_id):
			continue
		result.append(unit_id)
	return result


func _remove_from_array(ids: Array[StringName], unit_id: StringName) -> bool:
	var index: int = ids.find(unit_id)
	if index < 0:
		return false
	ids.remove_at(index)
	return true
