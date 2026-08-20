@tool
class_name TacticalMapValidator
extends RefCounted

## Pure structural validation helpers. They do not inspect or mutate a scene.


static func validate_library(library: TacticalPlaceableLibrary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var diagnostics: Array[Dictionary] = []
	if library == null:
		return _result(errors, warnings, diagnostics)
	if library.schema_version != TacticalPlaceableLibrary.CURRENT_SCHEMA_VERSION:
		var schema_message := "TML-008: Unsupported placeable library schema %d." % library.schema_version
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TML-008", schema_message)
	var library_errors: Array[String] = library.get_validation_errors()
	errors.append_array(library_errors)
	for library_error in library_errors:
		TacticalMapDiagnostics.append_existing(diagnostics, &"error", _code_from_message(library_error, &"TML-VALIDATION"), library_error)
	var bound_ids: Dictionary = {}
	for binding in library.item_bindings:
		if binding == null:
			continue
		bound_ids[binding.placeable_id] = true
	for definition in library.definitions:
		if definition is TacticalCellTileDefinition and not bound_ids.has(definition.placeable_id):
			var warning_message := "TML-009: Placeable '%s' has no MeshItemBinding." % definition.placeable_id
			TacticalMapDiagnostics.append_warning(warnings, diagnostics, &"TML-009", warning_message)
	return _result(errors, warnings, diagnostics)


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
	var diagnostics: Array[Dictionary] = []
	if data == null:
		return _result(errors, warnings, diagnostics)
	if data.schema_version != TacticalMapAuthoringData.CURRENT_SCHEMA_VERSION:
		var schema_message := "TMA-001: Unsupported map authoring data schema %d." % data.schema_version
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-001", schema_message)
	var overrides: Dictionary = {}
	for cell_override in data.cell_overrides:
		if cell_override == null:
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-002", "TMA-002: Null cell override.")
			continue
		if not cell_override.is_valid():
			var invalid_message := "TMA-003: Invalid cell override at %s." % cell_override.coordinate
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-003", invalid_message, cell_override.coordinate)
		if overrides.has(cell_override.coordinate):
			var duplicate_message := "TMA-004: Duplicate cell override at %s." % cell_override.coordinate
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-004", duplicate_message, cell_override.coordinate)
		overrides[cell_override.coordinate] = true
		if not _inside_volume(cell_override.coordinate, footprint_size, level_count):
			if footprint_size != Vector2i.ZERO and level_count > 0:
				var volume_message := "TMA-005: Cell override at %s is outside the declared volume." % cell_override.coordinate
				TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-005", volume_message, cell_override.coordinate)
	var edges: Dictionary = {}
	for placement in data.edge_placements:
		if placement == null:
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-006", "TMA-006: Null edge placement.")
			continue
		if not placement.is_valid():
			var invalid_edge_message := "TMA-007: Invalid edge placement at %s." % placement.key_string()
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-007", invalid_edge_message, _edge_coordinate(placement))
		elif placeable_library != null:
			var edge_definition := placeable_library.find_definition(placement.placeable_id)
			if edge_definition == null or edge_definition.placement_kind != TacticalPlaceableDefinition.PlacementKind.EDGE:
				var orphan_edge_message := "TMA-011: Edge placement '%s' references an orphan/non-edge placeable '%s'." % [placement.key_string(), placement.placeable_id]
				TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-011", orphan_edge_message, _edge_coordinate(placement))
		var key := placement.key_string()
		if edges.has(key):
			var duplicate_edge_message := "TMA-008: Duplicate edge key '%s'." % key
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-008", duplicate_edge_message, _edge_coordinate(placement))
		edges[key] = true
		if footprint_size != Vector2i.ZERO and level_count > 0 and not _edge_in_volume(placement.edge_key, footprint_size, level_count):
			var edge_volume_message := "TMA-009: Edge '%s' is outside the declared volume." % key
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-009", edge_volume_message, _edge_coordinate(placement))
	return _result(errors, warnings, diagnostics)


static func validate_against_cells(data: TacticalMapAuthoringData, cells: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var diagnostics: Array[Dictionary] = []
	if data == null:
		return _result(errors, warnings, diagnostics)
	for cell_override in data.cell_overrides:
		if cell_override == null:
			continue
		if not cells.has(cell_override.coordinate):
			var orphan_message := "TMA-010: Orphan cell override at %s." % cell_override.coordinate
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMA-010", orphan_message, cell_override.coordinate)
	return _result(errors, warnings, diagnostics)


static func validate_schema_version(version: int) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var diagnostics: Array[Dictionary] = []
	if not TacticalMapDefinition.is_schema_version_supported(version):
		var unsupported_message := "TMD-001: Unsupported TacticalMapDefinition schema %d." % version
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMD-001", unsupported_message)
	elif version < TacticalMapDefinition.CURRENT_SCHEMA_VERSION:
		var migration_message := "TMD-002: TacticalMapDefinition schema %d requires migration to %d." % [version, TacticalMapDefinition.CURRENT_SCHEMA_VERSION]
		TacticalMapDiagnostics.append_warning(warnings, diagnostics, &"TMD-002", migration_message)
	return _result(errors, warnings, diagnostics)


static func validate_definition_schema(definition: TacticalMapDefinition) -> Dictionary:
	var result := validate_schema_version(-1 if definition == null else definition.schema_version)
	var errors: Array[String] = result[&"errors"]
	var warnings: Array[String] = result[&"warnings"]
	var diagnostics: Array[Dictionary] = result[&"diagnostics"]
	if definition == null:
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMD-003", "TMD-003: Missing TacticalMapDefinition.")
		return _result(errors, warnings, diagnostics)
	var edge_keys: Dictionary = {}
	for edge in definition.edges:
		if edge == null:
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMD-004", "TMD-004: Null baked edge.")
			continue
		var key := edge.key_string()
		if not edge.get_key().is_valid():
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMD-005", "TMD-005: Invalid baked edge key '%s'." % key, _edge_coordinate_from_key(edge.get_key()))
		if edge_keys.has(key):
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMD-006", "TMD-006: Duplicate baked edge key '%s'." % key, _edge_coordinate_from_key(edge.get_key()))
		edge_keys[key] = true
	return _result(errors, warnings, diagnostics)


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


static func _result(errors: Array[String], warnings: Array[String], diagnostics: Array[Dictionary]) -> Dictionary:
	return {
		&"valid": errors.is_empty(),
		&"errors": errors,
		&"warnings": warnings,
		&"diagnostics": TacticalMapDiagnostics.sort_diagnostics(diagnostics),
	}


static func _code_from_message(message: String, fallback: StringName) -> StringName:
	var separator := message.find(":")
	if separator > 0:
		var candidate := message.substr(0, separator)
		if candidate.begins_with("TML-"):
			return StringName(candidate)
	return fallback


static func _edge_coordinate(placement: TacticalEdgePlacement) -> Variant:
	if placement != null and placement.edge_key != null:
		return placement.edge_key.cell_a
	return null


static func _edge_coordinate_from_key(key: TacticalEdgeKey) -> Variant:
	return key.cell_a if key != null else null
