class_name AlertState
extends RefCounted

enum Level {
	UNAWARE,
	SUSPICIOUS,
	ENGAGED,
}

signal level_changed(previous: Level, current: Level)

const INVALID_CELL := Vector3i(-1, -1, -1)

var _level: Level = Level.UNAWARE
var _target_id: StringName = &""
var _last_known_cell: Vector3i = INVALID_CELL


func get_level() -> Level:
	return _level


func become_suspicious(cell: Vector3i) -> bool:
	if _level == Level.ENGAGED:
		return false

	_last_known_cell = cell
	if _level == Level.SUSPICIOUS:
		return true

	_set_level(Level.SUSPICIOUS)
	return true


func engage(target_id: StringName, last_known_cell: Vector3i) -> bool:
	if target_id == &"":
		return false

	_target_id = target_id
	_last_known_cell = last_known_cell
	if _level == Level.ENGAGED:
		return true

	_set_level(Level.ENGAGED)
	return true


func calm_down() -> bool:
	match _level:
		Level.ENGAGED:
			_target_id = &""
			_set_level(Level.SUSPICIOUS)
			return true
		Level.SUSPICIOUS:
			_target_id = &""
			_set_level(Level.UNAWARE)
			return true
		Level.UNAWARE:
			return false

	return false


func reset() -> void:
	var previous := _level
	_level = Level.UNAWARE
	_target_id = &""
	_last_known_cell = INVALID_CELL
	if previous != _level:
		level_changed.emit(previous, _level)


func get_target_id() -> StringName:
	return _target_id


func get_last_known_cell() -> Vector3i:
	return _last_known_cell


func _set_level(next_level: Level) -> void:
	if _level == next_level:
		return
	var previous := _level
	_level = next_level
	level_changed.emit(previous, _level)
