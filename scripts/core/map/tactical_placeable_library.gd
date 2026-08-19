@tool
class_name TacticalPlaceableLibrary
extends Resource

## Data-only palette/library contract. Definitions own stable IDs; bindings
## translate editor MeshLibrary item IDs without making them gameplay IDs.

const CURRENT_SCHEMA_VERSION: int = 1

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var definitions: Array[TacticalPlaceableDefinition] = []
@export var generated_mesh_library: MeshLibrary
@export var item_bindings: Array[MeshItemBinding] = []


func find_definition(id: StringName) -> TacticalPlaceableDefinition:
	for definition in definitions:
		if definition != null and definition.placeable_id == id:
			return definition
	return null


func get_definition(id: StringName) -> TacticalPlaceableDefinition:
	return find_definition(id)


func find_binding(target_layer: MapTileRule.Layer, mesh_item_id: int) -> MeshItemBinding:
	for binding in item_bindings:
		if binding != null and binding.target_layer == target_layer and binding.mesh_item_id == mesh_item_id:
			return binding
	return null


func find_cell_definition(target_layer: MapTileRule.Layer, mesh_item_id: int) -> TacticalCellTileDefinition:
	var binding := find_binding(target_layer, mesh_item_id)
	if binding == null:
		return null
	var bound_definition := find_definition(binding.placeable_id)
	if bound_definition is TacticalCellTileDefinition:
		var cell_definition := bound_definition as TacticalCellTileDefinition
		if cell_definition.target_layer == target_layer and cell_definition.mesh_item_id == mesh_item_id:
			return cell_definition
	return null


func find_cell_definition_for_item(target_layer: MapTileRule.Layer, mesh_item_id: int) -> TacticalCellTileDefinition:
	return find_cell_definition(target_layer, mesh_item_id)


func get_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var ids: Dictionary = {}
	for definition in definitions:
		if definition == null:
			errors.append("TML-001: Placeable library contains a null definition.")
			continue
		if not definition.is_valid():
			errors.append("TML-002: Invalid placeable definition '%s'." % definition.placeable_id)
		if ids.has(definition.placeable_id):
			errors.append("TML-003: Duplicate placeable_id '%s'." % definition.placeable_id)
		else:
			ids[definition.placeable_id] = true
	var bindings: Dictionary = {}
	for binding in item_bindings:
		if binding == null:
			errors.append("TML-004: Placeable library contains a null MeshItemBinding.")
			continue
		if not binding.is_valid():
			errors.append("TML-005: Invalid MeshItemBinding '%s'." % binding.placeable_id)
		if not ids.has(binding.placeable_id):
			errors.append("TML-006: MeshItemBinding references orphan placeable_id '%s'." % binding.placeable_id)
		else:
			var bound_definition := find_definition(binding.placeable_id)
			if not (bound_definition is TacticalCellTileDefinition):
				errors.append("TML-008: MeshItemBinding '%s' must reference a Cell definition." % binding.placeable_id)
			else:
				var cell_definition := bound_definition as TacticalCellTileDefinition
				if cell_definition.target_layer != binding.target_layer or cell_definition.mesh_item_id != binding.mesh_item_id:
					errors.append("TML-009: MeshItemBinding '%s' target_layer/mesh_item_id does not match its Cell definition." % binding.placeable_id)
		var key := binding.binding_key()
		if bindings.has(key):
			errors.append("TML-007: Duplicate MeshItemBinding key '%s'." % key)
		else:
			bindings[key] = true
	return errors


func is_valid() -> bool:
	return schema_version == CURRENT_SCHEMA_VERSION and get_validation_errors().is_empty()
