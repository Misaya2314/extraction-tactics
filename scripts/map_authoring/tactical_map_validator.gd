@tool
class_name TacticalMapValidator
extends RefCounted

## Pure structural validation helpers. They do not inspect or mutate a scene.


static func validate_library(library: TacticalPlaceableLibrary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if library == null:
		return _result(errors, warnings)
	if library.schema_version != TacticalPlaceableLibrary.CURRENT_SCHEMA_VERSION:
		errors.append("TML-008: Unsupported placeable library schema %d." % library.schema_version)
	errors.append_array(library.get_validation_errors())
	var bound_ids: Dictionary = {}
	for binding in library.item_bindings:
		if binding == null:
			continue
		bound_ids[binding.placeable_id] = true
	for definition in library.definitions:
		if definition is TacticalCellTileDefinition and not bound_ids.has(definition.placeable_id):
			warnings.append("TML-009: Placeable '%s' has no MeshItemBinding." % definition.placeable_id)
	return _result(errors, warnings)


static func validate_placeable_library(library: TacticalPlaceableLibrary) -> Dictionary:
	return validate_library(library)


static func validate_authoring_data(
	data: TacticalMapAuthoringData,
	footprint_size: Vector2i = Vector2i.ZERO,
	level_count: int = 0,
	placeable_library: TacticalPlaceableLibrary = null
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if data == null:
		return _result(errors, warnings)
	if data.schema_version != TacticalMapAuthoringData.CURRENT_SCHEMA_VERSION:
		errors.append("TMA-001: Unsupported map authoring data schema %d." % data.schema_version)
	var overrides: Dictionary = {}
	for cell_override in data.cell_overrides:
		if cell_override == null:
			errors.append("TMA-002: Null cell override.")
			continue
		if not cell_override.is_valid():
			errors.append("TMA-003: Invalid cell override at %s." % cell_override.coordinate)
		if overrides.has(cell_override.coordinate):
			errors.append("TMA-004: Duplicate cell override at %s." % cell_override.coordinate)
		overrides[cell_override.coordinate] = true
		if not _inside_volume(cell_override.coordinate, footprint_size, level_count):
			if footprint_size != Vector2i.ZERO and level_count > 0:
				errors.append("TMA-005: Cell override at %s is outside the declared volume." % cell_override.coordinate)
	var edges: Dictionary = {}
	for placement in data.edge_placements:
		if placement == null:
			errors.append("TMA-006: Null edge placement.")
			continue
		if not placement.is_valid():
			errors.append("TMA-007: Invalid edge placement at %s." % placement.key_string())
		elif placeable_library != null:
			var edge_definition := placeable_library.find_definition(placement.placeable_id)
			if edge_definition == null or edge_definition.placement_kind != TacticalPlaceableDefinition.PlacementKind.EDGE:
				errors.append("TMA-011: Edge placement '%s' references an orphan/non-edge placeable '%s'." % [placement.key_string(), placement.placeable_id])
		var key := placement.key_string()
		if edges.has(key):
			errors.append("TMA-008: Duplicate edge key '%s'." % key)
		edges[key] = true
		if footprint_size != Vector2i.ZERO and level_count > 0 and not _edge_in_volume(placement.edge_key, footprint_size, level_count):
			errors.append("TMA-009: Edge '%s' is outside the declared volume." % key)
	return _result(errors, warnings)


static func validate_against_cells(data: TacticalMapAuthoringData, cells: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if data == null:
		return _result(errors, warnings)
	for cell_override in data.cell_overrides:
		if cell_override == null:
			continue
		if not cells.has(cell_override.coordinate):
			errors.append("TMA-010: Orphan cell override at %s." % cell_override.coordinate)
	return _result(errors, warnings)


static func validate_schema_version(version: int) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if not TacticalMapDefinition.is_schema_version_supported(version):
		errors.append("TMD-001: Unsupported TacticalMapDefinition schema %d." % version)
	elif version < TacticalMapDefinition.CURRENT_SCHEMA_VERSION:
		warnings.append("TMD-002: TacticalMapDefinition schema %d requires migration to %d." % [version, TacticalMapDefinition.CURRENT_SCHEMA_VERSION])
	return _result(errors, warnings)


static func validate_definition_schema(definition: TacticalMapDefinition) -> Dictionary:
	var result := validate_schema_version(-1 if definition == null else definition.schema_version)
	var errors: Array[String] = result[&"errors"]
	var warnings: Array[String] = result[&"warnings"]
	if definition == null:
		errors.append("TMD-003: Missing TacticalMapDefinition.")
		return _result(errors, warnings)
	var edge_keys: Dictionary = {}
	for edge in definition.edges:
		if edge == null:
			errors.append("TMD-004: Null baked edge.")
			continue
		var key := edge.key_string()
		if not edge.get_key().is_valid():
			errors.append("TMD-005: Invalid baked edge key '%s'." % key)
		if edge_keys.has(key):
			errors.append("TMD-006: Duplicate baked edge key '%s'." % key)
		edge_keys[key] = true
	return _result(errors, warnings)


static func validate_map_definition(definition: TacticalMapDefinition) -> Dictionary:
	return validate_definition_schema(definition)


static func _inside_volume(cell: Vector3i, footprint_size: Vector2i, level_count: int) -> bool:
	return cell.x >= 0 and cell.z >= 0 and cell.y >= 0 \
		and cell.x < footprint_size.x and cell.z < footprint_size.y and cell.y < level_count


static func _edge_in_volume(key: TacticalEdgeKey, footprint_size: Vector2i, level_count: int) -> bool:
	if key == null or not key.is_valid():
		return false
	var a_inside := _inside_volume(key.cell_a, footprint_size, level_count)
	var b_inside := _inside_volume(key.cell_b, footprint_size, level_count)
	# An edge may lie on the outside boundary, but only one endpoint may be
	# outside the declared set of floor coordinates.
	return a_inside != b_inside or (a_inside and b_inside)


static func _result(errors: Array[String], warnings: Array[String]) -> Dictionary:
	return {&"valid": errors.is_empty(), &"errors": errors, &"warnings": warnings}
