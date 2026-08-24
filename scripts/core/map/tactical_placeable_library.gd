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
	if bound_definition is TacticalCellTileDefinition and not _definition_source_is_missing(bound_definition):
		var cell_definition := bound_definition as TacticalCellTileDefinition
		if cell_definition.target_layer == target_layer and cell_definition.mesh_item_id == mesh_item_id:
			return cell_definition
	return null


func find_cell_definition_for_item(target_layer: MapTileRule.Layer, mesh_item_id: int) -> TacticalCellTileDefinition:
	return find_cell_definition(target_layer, mesh_item_id)


## Return definitions whose external source file is gone, or whose serialized
## ext_resource was resolved to null after the source was deleted.  Embedded
## SubResources intentionally have an empty/resource-local path and are not
## considered missing.
func get_missing_definition_references() -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for index in range(definitions.size()):
		var definition := definitions[index] as TacticalPlaceableDefinition
		if definition == null:
			missing.append({
				&"index": index,
				&"placeable_id": &"",
				&"path": "",
				&"reason": &"null_definition",
			})
			continue
		var source_path := _definition_source_path(definition)
		if _definition_source_is_missing(definition):
			missing.append({
				&"index": index,
				&"placeable_id": definition.placeable_id,
				&"path": source_path,
				&"reason": &"missing_file",
			})
	return missing


## Remove only references that cannot be resolved anymore.  Invalid but still
## present Definitions are intentionally retained so validation can explain
## what needs fixing instead of silently deleting authored data.
func prune_missing_definition_references() -> Dictionary:
	var missing := get_missing_definition_references()
	var removed_indices: Dictionary = {}
	var removed_ids: Array[String] = []
	for reference in missing:
		var index := int(reference.get(&"index", -1))
		if index >= 0:
			removed_indices[index] = true
		var placeable_id := String(reference.get(&"placeable_id", ""))
		if not placeable_id.is_empty() and not removed_ids.has(placeable_id):
			removed_ids.append(placeable_id)

	var kept_definitions: Array[TacticalPlaceableDefinition] = []
	var retained_ids: Dictionary = {}
	for index in range(definitions.size()):
		if removed_indices.has(index):
			continue
		var definition := definitions[index] as TacticalPlaceableDefinition
		if definition == null:
			continue
		kept_definitions.append(definition)
		retained_ids[definition.placeable_id] = true

	var kept_bindings: Array[MeshItemBinding] = []
	var removed_binding_count := 0
	for binding in item_bindings:
		if binding == null or not retained_ids.has(binding.placeable_id):
			removed_binding_count += 1
			continue
		kept_bindings.append(binding)

	var removed_definition_count := definitions.size() - kept_definitions.size()
	var changed := removed_definition_count > 0 or removed_binding_count > 0
	if changed:
		definitions = kept_definitions
		item_bindings = kept_bindings
	return {
		&"changed": changed,
		&"missing": missing,
		&"removed_definition_count": removed_definition_count,
		&"removed_binding_count": removed_binding_count,
		&"removed_placeable_ids": removed_ids,
	}


func get_validation_errors(check_missing_definition_sources: bool = true) -> Array[String]:
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
	if check_missing_definition_sources:
		for reference in get_missing_definition_references():
			if String(reference.get(&"reason", "")) != "missing_file":
				continue
			errors.append("TML-010: Placeable definition '%s' references missing resource '%s'." % [
				String(reference.get(&"placeable_id", "")),
				String(reference.get(&"path", "")),
			])
	return errors


func is_valid() -> bool:
	return schema_version == CURRENT_SCHEMA_VERSION and get_validation_errors().is_empty()


static func _is_external_resource_path(path: String) -> bool:
	if path.is_empty() or path.contains("::"):
		return false
	return path.begins_with("res://") or path.begins_with("user://")


static func _definition_source_path(definition: TacticalPlaceableDefinition) -> String:
	if definition == null:
		return ""
	return String(definition.resource_path).strip_edges().replace("\\", "/")


static func _definition_source_is_missing(definition: TacticalPlaceableDefinition) -> bool:
	var source_path := _definition_source_path(definition)
	return _is_external_resource_path(source_path) and not FileAccess.file_exists(source_path)
