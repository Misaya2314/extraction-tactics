class_name UnitStateSnapshot
extends RefCounted

## Serializable DTO for UnitRuntimeState.
##
## No Resource, Node, RID, Callable, signal or derived Grid data is stored.
## Definition resources and the weapon instance are resolved by the caller.

const CURRENT_STATE_VERSION: int = 1
const DEFAULT_CELL: Vector3i = Vector3i.ZERO

var instance_id: StringName = &""
var archetype_id: StringName = &""
var faction: StringName = &""
var current_hp: int = 0
var current_action_points: int = 0
var cell: Vector3i = DEFAULT_CELL
var weapon_instance_id: StringName = &""
var inventory_id: StringName = &""
var alive: bool = false
var state_version: int = CURRENT_STATE_VERSION


func _init(
	new_instance_id: Variant = &"",
	new_archetype_id: Variant = &"",
	new_faction: Variant = &"",
	new_current_hp: int = 0,
	new_current_action_points: int = 0,
	new_cell: Variant = DEFAULT_CELL,
	new_weapon_instance_id: Variant = &"",
	new_inventory_id: Variant = &"",
	new_alive: bool = false,
	new_state_version: int = CURRENT_STATE_VERSION,
	legacy_arg_1: Variant = null,
	legacy_arg_2: Variant = null,
) -> void:
	instance_id = _coerce_string_name(new_instance_id)
	archetype_id = _coerce_string_name(new_archetype_id)
	faction = _coerce_string_name(new_faction)
	current_hp = new_current_hp
	current_action_points = new_current_action_points
	if new_cell is Vector3i:
		cell = new_cell

	var actual_weapon_id: Variant = new_weapon_instance_id
	var actual_inventory_id: Variant = new_inventory_id
	var actual_alive: bool = new_alive
	var actual_version: int = new_state_version

	if new_weapon_instance_id is Vector2i:
		# Legacy signature: (id, arch, faction, hp, ap, cell, facing, weapon_id, inv_id, alive, version)
		actual_weapon_id = new_inventory_id
		actual_inventory_id = new_alive
		actual_alive = bool(new_state_version)
		actual_version = int(legacy_arg_1) if legacy_arg_1 != null else CURRENT_STATE_VERSION

	weapon_instance_id = _coerce_string_name(actual_weapon_id)
	inventory_id = _coerce_string_name(actual_inventory_id)
	alive = actual_alive
	state_version = actual_version


func is_valid() -> bool:
	## Snapshot validity is structural; Definition and weapon resolution belongs
	## to UnitRuntimeState hydration.
	return (
		instance_id != &""
		and archetype_id != &""
		and faction != &""
		and current_hp >= 0
		and current_action_points >= 0
		and is_valid_cell(cell)
		and alive == (current_hp > 0)
		and state_version == CURRENT_STATE_VERSION
	)


func validate() -> bool:
	return is_valid()


func get_definition_id() -> StringName:
	return archetype_id


func to_dictionary() -> Dictionary:
	return {
		&"instance_id": String(instance_id),
		&"archetype_id": String(archetype_id),
		&"faction": String(faction),
		&"current_hp": current_hp,
		&"current_action_points": current_action_points,
		&"cell": cell,
		&"weapon_instance_id": String(weapon_instance_id),
		&"inventory_id": String(inventory_id),
		&"alive": alive,
		&"state_version": state_version,
	}


func to_dict() -> Dictionary:
	return to_dictionary()


static func from_dictionary(data: Dictionary) -> UnitStateSnapshot:
	if data == null:
		return null
	var required_fields: Array[StringName] = [
		&"instance_id",
		&"archetype_id",
		&"faction",
		&"current_hp",
		&"current_action_points",
		&"cell",
		&"weapon_instance_id",
		&"inventory_id",
		&"alive",
		&"state_version",
	]
	for key in required_fields:
		if not _has_field(data, key):
			return null
	var raw_instance_id: Variant = _field(data, &"instance_id")
	var raw_archetype_id: Variant = _field(data, &"archetype_id")
	var raw_faction: Variant = _field(data, &"faction")
	var raw_hp: Variant = _field(data, &"current_hp")
	var raw_ap: Variant = _field(data, &"current_action_points")
	var raw_cell: Variant = _field(data, &"cell")
	var raw_weapon_instance_id: Variant = _field(data, &"weapon_instance_id")
	var raw_inventory_id: Variant = _field(data, &"inventory_id")
	var raw_alive: Variant = _field(data, &"alive")
	var raw_state_version: Variant = _field(data, &"state_version")
	if not _is_string_value(raw_instance_id) or not _is_string_value(raw_archetype_id) or not _is_string_value(raw_faction):
		return null
	if not _is_string_value(raw_weapon_instance_id) or not _is_string_value(raw_inventory_id):
		return null
	if typeof(raw_hp) != TYPE_INT or typeof(raw_ap) != TYPE_INT or typeof(raw_state_version) != TYPE_INT:
		return null
	if typeof(raw_cell) != TYPE_VECTOR3I or typeof(raw_alive) != TYPE_BOOL:
		return null
	var snapshot := UnitStateSnapshot.new(
		raw_instance_id,
		raw_archetype_id,
		raw_faction,
		int(raw_hp),
		int(raw_ap),
		raw_cell,
		raw_weapon_instance_id,
		raw_inventory_id,
		bool(raw_alive),
		int(raw_state_version),
	)
	return snapshot if snapshot.is_valid() else null


static func from_dict(data: Dictionary) -> UnitStateSnapshot:
	return from_dictionary(data)


func duplicate_snapshot() -> UnitStateSnapshot:
	return UnitStateSnapshot.new(
		instance_id,
		archetype_id,
		faction,
		current_hp,
		current_action_points,
		cell,
		weapon_instance_id,
		inventory_id,
		alive,
		state_version,
	)


static func is_valid_cell(candidate: Variant) -> bool:
	if not candidate is Vector3i:
		return false
	return true


static func _has_field(data: Dictionary, key: StringName) -> bool:
	return data.has(key) or data.has(String(key))


static func _field(data: Dictionary, key: StringName) -> Variant:
	return data[key] if data.has(key) else data[String(key)]


static func _is_string_value(value: Variant) -> bool:
	return value is StringName or value is String


static func _coerce_string_name(value: Variant) -> StringName:
	if value is StringName or value is String:
		return StringName(value)
	return &""
