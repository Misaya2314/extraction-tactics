@tool
class_name TacticalPlaceableDefinition
extends Resource

## Stable, editor-independent identity for anything that can be placed on a map.
## MeshLibrary item IDs are adapters only; placeable_id is the durable contract.

enum PlacementKind {
	CELL,
	EDGE,
	OBJECT,
	STAMP,
}

@export var placeable_id: StringName = &""
@export var display_name: String = ""
@export var placement_kind: PlacementKind = PlacementKind.CELL
@export var tags: PackedStringArray = PackedStringArray()
@export var enabled: bool = true


static func is_valid_id(value: StringName) -> bool:
	var text := String(value).strip_edges()
	if text.is_empty():
		return false
	for character in [" ", "\\t", "\\r", "\\n", "/", "\\"]:
		if text.contains(character):
			return false
	return true


func is_valid() -> bool:
	return is_valid_id(placeable_id)


func get_kind_name() -> StringName:
	return StringName(PlacementKind.keys()[placement_kind].to_lower())

