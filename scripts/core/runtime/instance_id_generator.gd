class_name InstanceIdGenerator
extends RefCounted

## Deterministic IDs are based only on explicit session/content inputs. Godot
## Object or Node instance IDs are deliberately not used.

const DYNAMIC_SEPARATOR := ":"

var session_id: StringName = &""
var _counters: Dictionary = {}
var _reserved_ids: Dictionary = {}


func _init(initial_session_id: StringName = &"") -> void:
	configure(initial_session_id)


func configure(new_session_id: StringName) -> bool:
	if not _is_token_valid(new_session_id, true):
		return false
	session_id = new_session_id
	_counters.clear()
	_reserved_ids.clear()
	return true


func next_id(definition_type: StringName) -> StringName:
	if not _is_token_valid(session_id, true) or not _is_token_valid(definition_type, true):
		return &""
	var counter := int(_counters.get(definition_type, 0))
	var candidate := _dynamic_id(definition_type, counter)
	while _reserved_ids.has(candidate):
		counter += 1
		candidate = _dynamic_id(definition_type, counter)
	_counters[definition_type] = counter + 1
	_reserved_ids[candidate] = true
	return candidate


func next_dynamic(definition_type: StringName) -> StringName:
	return next_id(definition_type)


func id_for_placement(definition_type: StringName, map_id: StringName, placement_id: StringName) -> StringName:
	if not _is_token_valid(session_id, true) \
		or not _is_token_valid(definition_type, true) \
		or not _is_token_valid(map_id, true) \
		or not _is_token_valid(placement_id, true):
		return &""
	var candidate := StringName("%s%s%s%s%s%s%s" % [
		session_id,
		DYNAMIC_SEPARATOR,
		definition_type,
		DYNAMIC_SEPARATOR,
		map_id,
		DYNAMIC_SEPARATOR,
		placement_id,
	])
	_reserved_ids[candidate] = true
	return candidate


func fixed_point(definition_type: StringName, map_id: StringName, placement_id: StringName) -> StringName:
	return id_for_placement(definition_type, map_id, placement_id)


func reserve(instance_id: StringName) -> bool:
	if not _is_token_valid(instance_id, false) or _reserved_ids.has(instance_id):
		return false
	_reserved_ids[instance_id] = true
	_advance_counter_from_dynamic_id(instance_id)
	return true


func is_reserved(instance_id: StringName) -> bool:
	return _reserved_ids.has(instance_id)


func capture_state() -> Dictionary:
	var counters: Dictionary = {}
	for definition_type in _counters.keys():
		counters[definition_type] = int(_counters[definition_type])
	var reserved: Array[StringName] = []
	for instance_id in _reserved_ids.keys():
		reserved.append(instance_id)
	reserved.sort_custom(func(first: StringName, second: StringName) -> bool: return String(first) < String(second))
	return {
		&"session_id": session_id,
		&"counters": counters,
		&"reserved_ids": reserved,
	}


func restore_state(state: Variant) -> bool:
	if typeof(state) != TYPE_DICTIONARY:
		return false
	var saved_session_value = state.get(&"session_id", null)
	if not _is_string_like(saved_session_value):
		return false
	var saved_session := StringName(saved_session_value)
	if saved_session != session_id:
		return false
	var saved_counters = state.get(&"counters", {})
	var saved_reserved = state.get(&"reserved_ids", [])
	if not saved_counters is Dictionary or not saved_reserved is Array:
		return false
	var new_counters: Dictionary = {}
	for raw_type in saved_counters.keys():
		if not _is_string_like(raw_type):
			return false
		var definition_type := StringName(raw_type)
		var counter_value = saved_counters[raw_type]
		if typeof(counter_value) != TYPE_INT:
			return false
		var counter: int = counter_value
		if not _is_token_valid(definition_type, true) or counter < 0:
			return false
		new_counters[definition_type] = counter
	var new_reserved: Dictionary = {}
	for raw_id in saved_reserved:
		if not _is_string_like(raw_id):
			return false
		var instance_id := StringName(raw_id)
		if not _is_token_valid(instance_id, false) or new_reserved.has(instance_id):
			return false
		new_reserved[instance_id] = true
	_counters = new_counters
	_reserved_ids = new_reserved
	for instance_id in _reserved_ids.keys():
		_advance_counter_from_dynamic_id(instance_id)
	return true


func restore_counters(counters: Dictionary) -> bool:
	var state := capture_state()
	state[&"counters"] = counters
	return restore_state(state)


func _dynamic_id(definition_type: StringName, counter: int) -> StringName:
	return StringName("%s%s%s%s%04d" % [session_id, DYNAMIC_SEPARATOR, definition_type, DYNAMIC_SEPARATOR, counter])


func _advance_counter_from_dynamic_id(instance_id: StringName) -> void:
	var parts := String(instance_id).split(DYNAMIC_SEPARATOR)
	if parts.size() != 3 or StringName(parts[0]) != session_id or not parts[2].is_valid_int():
		return
	var definition_type := StringName(parts[1])
	var next_counter := int(parts[2]) + 1
	_counters[definition_type] = maxi(int(_counters.get(definition_type, 0)), next_counter)


static func _is_token_valid(value: StringName, reject_colon: bool) -> bool:
	var text := String(value).strip_edges()
	if text.is_empty():
		return false
	for character in ["\t", "\r", "\n", "/", "\\"]:
		if text.contains(character):
			return false
	if reject_colon and text.contains(":"):
		return false
	return true


static func _is_string_like(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING_NAME or typeof(value) == TYPE_STRING
