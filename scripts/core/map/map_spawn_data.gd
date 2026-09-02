@tool
class_name MapSpawnData
extends Resource

## Stable authoring identity. New content should set this explicitly; the
## factory can derive a deterministic compatibility ID for legacy resources.
@export var spawn_id: StringName = &""
@export var unit_name: StringName = &"Unit"
@export var faction: StringName = &"player"
@export var cell: Vector3i = Vector3i.ZERO
@export var visual_color: Color = Color.WHITE
@export var patrol_route_id: StringName = &""
@export var archetype: UnitArchetype
@export var weapon: WeaponDefinition
@export var encounter_id: StringName = &""


func has_explicit_spawn_id() -> bool:
	return not String(spawn_id).strip_edges().is_empty()


func get_stable_spawn_id(legacy_index: int = -1) -> StringName:
	if has_explicit_spawn_id():
		return spawn_id
	var base := String(unit_name).strip_edges()
	if base.is_empty():
		base = "spawn"
	base = _stable_token(base)
	if legacy_index >= 0:
		base = "%s_%04d" % [base, legacy_index]
	return StringName("legacy_%s" % base)


func get_compatible_spawn_id(legacy_index: int = -1) -> StringName:
	return get_stable_spawn_id(legacy_index)


static func _stable_token(value: String) -> String:
	var result := ""
	for character in value:
		if character == " " or character == "\t":
			result += "_"
		elif character in ["/", "\\", ":", "\r", "\n"]:
			result += "_"
		else:
			result += character
	return result if not result.is_empty() else "spawn"
