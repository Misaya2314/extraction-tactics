@tool
class_name MeshItemBinding
extends Resource

## Adapter from a legacy/generated MeshLibrary item to a stable placeable ID.
## mesh_library is optional so one library can describe the same numeric item
## contract while an authoring scene supplies its own MeshLibrary instance.

@export var placeable_id: StringName = &""
@export var target_layer: MapTileRule.Layer = MapTileRule.Layer.FLOOR
@export var mesh_item_id: int = -1
@export var mesh_library: MeshLibrary


func is_valid() -> bool:
	return TacticalPlaceableDefinition.is_valid_id(placeable_id) and mesh_item_id >= 0


func binding_key() -> StringName:
	return StringName("%d:%d" % [int(target_layer), mesh_item_id])

