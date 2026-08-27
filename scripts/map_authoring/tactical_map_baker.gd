class_name TacticalMapBaker
extends RefCounted

## Stateless authoring compiler. It can run from editor buttons or headless tests.

const FLOOR_GRID_NAME := &"FloorGrid"
const STRUCTURE_GRID_NAME := &"StructureGrid"


static func build(author: TacticalMapAuthor) -> Dictionary:
	var definition := TacticalMapDefinition.new()
	definition.schema_version = TacticalMapDefinition.CURRENT_SCHEMA_VERSION
	if author == null:
		var missing_author_message := "Missing TacticalMapAuthor."
		return {
			&"definition": definition,
			&"errors": [missing_author_message],
			&"warnings": [],
			&"diagnostics": [TacticalMapDiagnostics.error(&"TMB-000", missing_author_message)],
		}

	definition.map_id = author.map_id
	definition.footprint_size = author.footprint_size
	definition.level_count = author.level_count
	definition.cell_size = author.cell_dimensions
	definition.origin = author.grid_origin
	definition.authoring_scene_path = author.get_scene_file_path()
	var cell_compile := compile_cells(author, true)
	var errors: Array[String] = cell_compile[&"errors"]
	var warnings: Array[String] = cell_compile[&"warnings"]
	var diagnostics: Array[Dictionary] = cell_compile[&"diagnostics"]
	var cells_by_coordinate: Dictionary = cell_compile[&"cells"]
	var ordered_cells: Array = cells_by_coordinate.keys()
	ordered_cells.sort_custom(_cell_less)
	for coordinate in ordered_cells:
		definition.cells.append(cells_by_coordinate[coordinate])

	if not bool(cell_compile[&"can_compile"]):
		return {
			&"definition": definition,
			&"errors": errors,
			&"warnings": warnings,
			&"diagnostics": TacticalMapDiagnostics.sort_diagnostics(diagnostics),
		}

	_collect_edges(author, cell_compile, definition, errors, warnings, diagnostics)

	_collect_markers(author, definition, errors, diagnostics)
	_normalize_definition_coordinates(definition, author)
	_validate_definition(definition, errors, warnings, diagnostics)
	return {
		&"definition": definition,
		&"errors": errors,
		&"warnings": warnings,
		&"diagnostics": TacticalMapDiagnostics.sort_diagnostics(diagnostics),
	}


## Compiles the cell layers once and exposes both pre-override and effective
## rules. build() consumes this result so editor property inspection and the
## runtime definition share the same merge authority.
static func compile_cells(author: TacticalMapAuthor, apply_overrides: bool = true) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var diagnostics: Array[Dictionary] = []
	var empty_result := {
		&"can_compile": false,
		&"cells": {},
		&"base_cells": {},
		&"base_rules": {},
		&"effective_rules": {},
		&"floor_content": {},
		&"structure_content": {},
		&"structure_edge_candidates": [],
		&"errors": errors,
		&"warnings": warnings,
		&"diagnostics": diagnostics,
	}
	if author == null:
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-000", "Missing TacticalMapAuthor.")
		return empty_result

	var catalog := author.tile_catalog
	var placeable_library := author.placeable_library
	var floor_grid := author.get_node_or_null(NodePath(String(FLOOR_GRID_NAME))) as GridMap
	var structure_grid := author.get_node_or_null(NodePath(String(STRUCTURE_GRID_NAME))) as GridMap
	if placeable_library != null:
		var library_validation := TacticalMapValidator.validate_library(placeable_library)
		errors.append_array(library_validation[&"errors"])
		warnings.append_array(library_validation[&"warnings"])
		diagnostics.append_array(library_validation[&"diagnostics"])
	_validate_author_settings(author, floor_grid, structure_grid, catalog, placeable_library, errors, diagnostics)
	var can_compile := floor_grid != null and (catalog != null or placeable_library != null)
	if not can_compile:
		return empty_result

	var cells_by_coordinate: Dictionary = {}
	var base_rules_by_coordinate: Dictionary = {}
	var effective_rules_by_coordinate: Dictionary = {}
	var floor_content: Dictionary = {}
	var structure_content: Dictionary = {}
	var structure_edge_candidates: Array[Dictionary] = []
	var floor_cells := floor_grid.get_used_cells()
	floor_cells.sort_custom(_cell_less)
	for coordinate in floor_cells:
		var item_id := floor_grid.get_cell_item(coordinate)
		var resolved := _resolve_cell_rule(MapTileRule.Layer.FLOOR, item_id, catalog, placeable_library, errors, warnings, diagnostics)
		if resolved.is_empty():
			continue
		if not _inside_volume(author, coordinate):
			var floor_volume_message := "Floor cell %s is outside the declared map volume." % coordinate
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-018", floor_volume_message, coordinate)
			continue
		var rules: TacticalCellRules = resolved[&"rules"]
		var terrain_id: StringName = resolved[&"terrain_id"]
		var cover_mask: int = _rotated_cover_mask(int(resolved[&"cover_mask"]), floor_grid.get_cell_item_basis(coordinate))
		cells_by_coordinate[coordinate] = TacticalRuleMerger.to_map_cell_data(coordinate, rules, terrain_id, cover_mask)
		base_rules_by_coordinate[coordinate] = rules.duplicate_rules()
		floor_content[coordinate] = {
			&"layer": MapTileRule.Layer.FLOOR,
			&"item_id": item_id,
			&"placeable_id": resolved.get(&"placeable_id", &""),
			&"tile_id": terrain_id,
			&"source": resolved.get(&"source", &""),
		}

	if structure_grid != null:
		var structure_cells := structure_grid.get_used_cells()
		structure_cells.sort_custom(_cell_less)
		for coordinate in structure_cells:
			var item_id := structure_grid.get_cell_item(coordinate)
			var resolved := _resolve_cell_rule(MapTileRule.Layer.STRUCTURE, item_id, catalog, placeable_library, errors, warnings, diagnostics)
			if resolved.is_empty():
				continue
			if not _inside_volume(author, coordinate):
				var structure_volume_message := "Structure cell %s is outside the declared map volume." % coordinate
				TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-019", structure_volume_message, coordinate)
				continue
			if not cells_by_coordinate.has(coordinate):
				var missing_floor_message := "Structure at %s has no floor surface beneath it." % coordinate
				TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-020", missing_floor_message, coordinate)
				continue
			var cell_data: MapCellData = cells_by_coordinate[coordinate]
			var merged_rules := TacticalRuleMerger.merge(base_rules_by_coordinate[coordinate], resolved[&"rules"])
			var structure_cover := _rotated_cover_mask(int(resolved[&"cover_mask"]), structure_grid.get_cell_item_basis(coordinate))
			cell_data.copy_from(TacticalRuleMerger.to_map_cell_data(
				coordinate,
				merged_rules,
				cell_data.terrain_id,
				cell_data.cover_mask | structure_cover
			))
			base_rules_by_coordinate[coordinate] = merged_rules
			var cell_definition := resolved.get(&"cell_definition") as TacticalCellTileDefinition
			if cell_definition != null:
				for contribution in cell_definition.edge_contributions:
					if contribution != null and contribution.enabled:
						structure_edge_candidates.append({
							&"source_cell": coordinate,
							&"item_id": item_id,
							&"placeable_id": resolved.get(&"placeable_id", &""),
							&"contribution": contribution,
							&"basis": structure_grid.get_cell_item_basis(coordinate),
						})
			structure_content[coordinate] = {
				&"layer": MapTileRule.Layer.STRUCTURE,
				&"item_id": item_id,
				&"placeable_id": resolved.get(&"placeable_id", &""),
				&"tile_id": resolved.get(&"terrain_id", &""),
				&"source": resolved.get(&"source", &""),
			}

	var base_cells: Dictionary = {}
	for coordinate in cells_by_coordinate.keys():
		var base_cell := MapCellData.new()
		base_cell.copy_from(cells_by_coordinate[coordinate])
		base_cells[coordinate] = base_cell
		effective_rules_by_coordinate[coordinate] = (base_rules_by_coordinate[coordinate] as TacticalCellRules).duplicate_rules()

	if author.authoring_data != null:
		var authoring_validation := TacticalMapValidator.validate_authoring_data(
			author.authoring_data,
			author.footprint_size,
			author.level_count,
			author.placeable_library
		)
		errors.append_array(authoring_validation[&"errors"])
		warnings.append_array(authoring_validation[&"warnings"])
		diagnostics.append_array(authoring_validation[&"diagnostics"])
		var orphan_validation := TacticalMapValidator.validate_against_cells(author.authoring_data, cells_by_coordinate)
		errors.append_array(orphan_validation[&"errors"])
		warnings.append_array(orphan_validation[&"warnings"])
		diagnostics.append_array(orphan_validation[&"diagnostics"])
		if apply_overrides:
			_apply_cell_overrides(author.authoring_data, cells_by_coordinate, base_rules_by_coordinate, effective_rules_by_coordinate, errors)

	return {
		&"can_compile": true,
		&"cells": cells_by_coordinate,
		&"base_cells": base_cells,
		&"base_rules": base_rules_by_coordinate,
		&"effective_rules": effective_rules_by_coordinate,
		&"floor_content": floor_content,
		&"structure_content": structure_content,
		&"structure_edge_candidates": structure_edge_candidates,
		&"errors": errors,
		&"warnings": warnings,
		&"diagnostics": TacticalMapDiagnostics.sort_diagnostics(diagnostics),
	}


static func save(author: TacticalMapAuthor) -> Dictionary:
	var result := build(author)
	var errors: Array[String] = result[&"errors"]
	var diagnostics: Array[Dictionary] = result[&"diagnostics"]
	if not errors.is_empty():
		return result
	var output_path := author.output_resource_path.strip_edges()
	if output_path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(output_path)
		if uid >= 0:
			output_path = ResourceUID.get_id_path(uid)
	if output_path.is_empty() or not output_path.begins_with("res://") or not output_path.ends_with(".tres"):
		var invalid_output_message := "Output path must be a res:// path ending in .tres."
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-060", invalid_output_message)
		result[&"diagnostics"] = TacticalMapDiagnostics.sort_diagnostics(diagnostics)
		return result
	# Capture the registered UID before overwriting. ResourceSaver.save() does
	# not preserve it on its own, while ResourceSaver.set_uid() updates both the
	# resource header and Godot's UID cache through the supported API.
	var existing_uid := _existing_resource_uid(output_path)
	var save_error := ResourceSaver.save(result[&"definition"], output_path)
	if save_error != OK:
		var save_failure_message := "ResourceSaver failed for %s (error %d)." % [output_path, save_error]
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-061", save_failure_message)
		result[&"diagnostics"] = TacticalMapDiagnostics.sort_diagnostics(diagnostics)
		return result
	var uid_error := _ensure_saved_uid(output_path, existing_uid)
	if uid_error != OK:
		var uid_failure_message := "ResourceSaver.set_uid failed for %s (error %d)." % [output_path, uid_error]
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-061", uid_failure_message)
		result[&"diagnostics"] = TacticalMapDiagnostics.sort_diagnostics(diagnostics)
		return result
	return result


static func _ensure_saved_uid(path: String, prior_uid: int) -> Error:
	var uid := prior_uid
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var save_uid_error := ResourceSaver.set_uid(path, uid)
	if save_uid_error != OK:
		return save_uid_error
	# ResourceSaver.set_uid persists the UID in the file. Keep the in-process
	# ResourceUID registry in sync as well; this matters for subsequent saves
	# in the same editor session and for UID-based scene references.
	if ResourceUID.has_id(uid):
		ResourceUID.set_id(uid, path)
	else:
		ResourceUID.add_id(uid, path)
	return OK


static func _existing_resource_uid(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	var registered_uid := ResourceLoader.get_resource_uid(path)
	if registered_uid != ResourceUID.INVALID_ID:
		return registered_uid
	# A freshly created/imported file may not be present in the UID cache yet.
	# Read its declared UID only as a lookup fallback; all persistence still
	# goes through ResourceSaver.set_uid(), never through text rewriting.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ResourceUID.INVALID_ID
	var first_line := file.get_line()
	file.close()
	var marker := "uid=\""
	var marker_start := first_line.find(marker)
	if marker_start < 0:
		return ResourceUID.INVALID_ID
	var value_start := marker_start + marker.length()
	var value_end := first_line.find("\"", value_start)
	if value_end < 0:
		return ResourceUID.INVALID_ID
	var text_uid := first_line.substr(value_start, value_end - value_start)
	if not text_uid.begins_with("uid://"):
		return ResourceUID.INVALID_ID
	var declared_uid := ResourceUID.text_to_id(text_uid)
	if declared_uid == ResourceUID.INVALID_ID:
		return ResourceUID.INVALID_ID
	if ResourceUID.has_id(declared_uid):
		var registered_path := ResourceUID.get_id_path(declared_uid)
		if registered_path != "" and registered_path != path:
			return ResourceUID.INVALID_ID
	else:
		ResourceUID.add_id(declared_uid, path)
	return declared_uid


static func _resolve_cell_rule(
	layer: MapTileRule.Layer,
	item_id: int,
	catalog: MapTileCatalog,
	placeable_library: TacticalPlaceableLibrary,
	errors: Array[String],
	warnings: Array[String],
	diagnostics: Array[Dictionary]
) -> Dictionary:
	if placeable_library != null:
		var placeable := placeable_library.find_cell_definition(layer, item_id)
		if placeable != null:
			var placeable_rules := placeable.rule_contribution
			if placeable_rules == null:
				placeable_rules = TacticalCellRules.new()
			return {
				&"rules": placeable_rules,
				&"terrain_id": placeable.tile_id,
				&"cover_mask": 0,
				&"placeable_id": placeable.placeable_id,
				&"cell_definition": placeable,
				&"source": &"placeable_library",
			}
	if catalog != null:
		var legacy_rule := catalog.find_rule(layer, item_id)
		if legacy_rule != null:
			if placeable_library != null:
				var fallback_message := "TMB-001: %s item %d has no placeable binding; fell back to MapTileCatalog." % [layer, item_id]
				TacticalMapDiagnostics.append_warning(warnings, diagnostics, &"TMB-001", fallback_message)
			return {
				&"rules": TacticalRuleMerger.from_legacy(legacy_rule),
				&"terrain_id": legacy_rule.tile_id,
				&"cover_mask": legacy_rule.cover_mask,
				&"placeable_id": &"",
				&"cell_definition": null,
				&"source": &"legacy_catalog",
			}
	var layer_name := "Floor" if layer == MapTileRule.Layer.FLOOR else "Structure"
	var missing_rule_message := "TMB-002: %s item %d has no placeable or catalog rule." % [layer_name, item_id]
	TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-002", missing_rule_message)
	return {}


static func _apply_cell_overrides(
	data: TacticalMapAuthoringData,
	cells_by_coordinate: Dictionary,
	base_rules_by_coordinate: Dictionary,
	effective_rules_by_coordinate: Dictionary,
	_errors: Array[String]
) -> void:
	if data == null:
		return
	for cell_override in data.cell_overrides:
		if cell_override == null or not cell_override.is_valid():
			continue
		if not cells_by_coordinate.has(cell_override.coordinate):
			continue
		var merged_rules := TacticalRuleMerger.apply_override(base_rules_by_coordinate[cell_override.coordinate], cell_override)
		var old_cell: MapCellData = cells_by_coordinate[cell_override.coordinate]
		old_cell.copy_from(TacticalRuleMerger.to_map_cell_data(
			cell_override.coordinate,
			merged_rules,
			old_cell.terrain_id,
			old_cell.cover_mask
		))
		effective_rules_by_coordinate[cell_override.coordinate] = merged_rules


static func _collect_edges(
	author: TacticalMapAuthor,
	cell_compile: Dictionary,
	definition: TacticalMapDefinition,
	errors: Array[String],
	warnings: Array[String],
	diagnostics: Array[Dictionary]
) -> void:
	if author == null or definition == null:
		return
	var settings := CoverCombatSettings.load_default()
	var candidates: Array[Dictionary] = []
	var data := author.authoring_data
	var cells: Dictionary = cell_compile.get(&"cells", {})
	if data != null:
		for placement in data.edge_placements:
			if placement == null or not placement.enabled or not placement.is_valid():
				continue
			var edge := MapEdgeData.from_placement(placement)
			_prepare_edge_profiles(edge, settings, errors, warnings, diagnostics)
			candidates.append(_edge_candidate(edge, 3))

	var structure_candidates: Array = cell_compile.get(&"structure_edge_candidates", [])
	for source in structure_candidates:
		if not source is Dictionary:
			continue
		var contribution := source.get(&"contribution") as TacticalLocalEdgeContribution
		if contribution == null or not contribution.is_active():
			continue
		var source_cell: Vector3i = source.get(&"source_cell", Vector3i.ZERO)
		var basis: Basis = source.get(&"basis", Basis.IDENTITY)
		var direction := _rotated_local_edge_direction(contribution.local_direction, basis)
		if direction == Vector3i.ZERO:
			continue
		var neighbor_cell := source_cell + direction
		var provenance := {
			&"source_type": &"structure_derived",
			&"source_layer": &"structure",
			&"source_cell": source_cell,
			&"source_placeable_id": StringName(source.get(&"placeable_id", &"")),
			&"source_mesh_item_id": int(source.get(&"item_id", -1)),
		}
		var edge := MapEdgeData.from_rules(source_cell, neighbor_cell, contribution.edge_rules, provenance)
		# A shared boundary inside a solid Structure mass is not a usable cover
		# edge: neither side can host a standing unit. Use the final compiled cell
		# rules (including overrides), while preserving boundary/standable edges.
		if not _edge_has_walkable_endpoint(edge, cells):
			continue
		_prepare_edge_profiles(edge, settings, errors, warnings, diagnostics)
		candidates.append(_edge_candidate(edge, 2))

	var floor_content: Dictionary = cell_compile.get(&"floor_content", {})
	var ordered_cells: Array = cells.keys()
	ordered_cells.sort_custom(_cell_less)
	for coordinate in ordered_cells:
		var cell_data := cells[coordinate] as MapCellData
		if cell_data == null or cell_data.cover_mask == 0:
			continue
		var content: Dictionary = floor_content.get(coordinate, {})
		for direction_index in range(4):
			if cell_data.cover_mask & (1 << direction_index) == 0:
				continue
			var source_cell: Vector3i = coordinate
			var neighbor_cell := source_cell + _cardinal_cell_vector(direction_index)
			var rules := TacticalEdgeRules.new()
			rules.cover_a = TacticalEdgeRules.CoverLevel.HALF
			rules.cover_b = TacticalEdgeRules.CoverLevel.NONE
			rules.cover_profile_a = settings.get_profile_for_level(int(TacticalEdgeRules.CoverLevel.HALF))
			rules.cover_profile_b = settings.get_profile_for_level(int(TacticalEdgeRules.CoverLevel.NONE))
			var provenance := {
				&"source_type": &"legacy_cover_mask",
				&"source_layer": &"legacy",
				&"source_cell": source_cell,
				&"source_placeable_id": StringName(content.get(&"placeable_id", &"")),
				&"source_mesh_item_id": -1,
			}
			var edge := MapEdgeData.from_rules(source_cell, neighbor_cell, rules, provenance)
			_prepare_edge_profiles(edge, settings, errors, warnings, diagnostics)
			candidates.append(_edge_candidate(edge, 1))

	var grouped: Dictionary = {}
	for candidate in candidates:
		var edge := candidate.get(&"edge") as MapEdgeData
		if edge == null:
			continue
		var key := edge.key_string()
		if not grouped.has(key):
			grouped[key] = []
		(grouped[key] as Array).append(candidate)
	var ordered_keys: Array = grouped.keys()
	ordered_keys.sort()
	for key in ordered_keys:
		var entries: Array = grouped[key]
		entries.sort_custom(_edge_candidate_less)
		if entries.is_empty():
			continue
		var winner := entries[0] as Dictionary
		var winner_edge := winner[&"edge"] as MapEdgeData
		if winner_edge == null or not winner_edge.get_key().is_valid():
			var invalid_message := "TMB-067: Invalid derived EdgeKey '%s'." % key
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-067", invalid_message, winner_edge.source_cell if winner_edge != null else null)
			continue
		for index in range(1, entries.size()):
			var other := entries[index] as Dictionary
			var other_edge := other[&"edge"] as MapEdgeData
			if int(other[&"priority"]) == int(winner[&"priority"]):
				if other_edge.semantic_key() == winner_edge.semantic_key():
					TacticalMapDiagnostics.append_existing(
						diagnostics,
						&"info",
						&"TMB-066",
						"TMB-066: Equivalent Edge rules were deduplicated for '%s'." % key,
						winner_edge.source_cell
					)
				else:
					var conflict_message := "TMB-068: Same-priority Edge rules conflict for '%s'." % key
					TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-068", conflict_message, other_edge.source_cell)
			else:
				var override_message := "TMB-062: Higher-priority Edge source kept '%s' over %s." % [key, other_edge.source_type]
				TacticalMapDiagnostics.append_existing(diagnostics, &"info", &"TMB-062", override_message, winner_edge.source_cell)
		definition.edges.append(winner_edge)
	definition.edges.sort_custom(_edge_data_less)


static func _edge_has_walkable_endpoint(edge: MapEdgeData, cells: Dictionary) -> bool:
	if edge == null:
		return false
	return _cell_is_walkable(cells, edge.cell_a) or _cell_is_walkable(cells, edge.cell_b)


static func _cell_is_walkable(cells: Dictionary, coordinate: Vector3i) -> bool:
	var cell := cells.get(coordinate) as MapCellData
	return cell != null and cell.walkable


static func _edge_candidate(edge: MapEdgeData, priority: int) -> Dictionary:
	return {&"edge": edge, &"priority": priority}


static func _edge_candidate_less(first: Dictionary, second: Dictionary) -> bool:
	var first_priority := int(first.get(&"priority", 0))
	var second_priority := int(second.get(&"priority", 0))
	if first_priority != second_priority:
		return first_priority > second_priority
	var first_edge := first.get(&"edge") as MapEdgeData
	var second_edge := second.get(&"edge") as MapEdgeData
	if first_edge.source_type != second_edge.source_type:
		return String(first_edge.source_type) < String(second_edge.source_type)
	if first_edge.source_cell != second_edge.source_cell:
		return _cell_less(first_edge.source_cell, second_edge.source_cell)
	if first_edge.source_placeable_id != second_edge.source_placeable_id:
		return String(first_edge.source_placeable_id) < String(second_edge.source_placeable_id)
	if first_edge.source_mesh_item_id != second_edge.source_mesh_item_id:
		return first_edge.source_mesh_item_id < second_edge.source_mesh_item_id
	return first_edge.semantic_key() < second_edge.semantic_key()


static func _edge_data_less(first: MapEdgeData, second: MapEdgeData) -> bool:
	if first.cell_a != second.cell_a:
		return _cell_less(first.cell_a, second.cell_a)
	return _cell_less(first.cell_b, second.cell_b)


static func _prepare_edge_profiles(
	edge: MapEdgeData,
	settings: CoverCombatSettings,
	errors: Array[String],
	warnings: Array[String],
	diagnostics: Array[Dictionary]
) -> void:
	if edge == null:
		return
	var profile_a := _resolve_edge_profile(edge.cover_profile_a, edge.cover_a, settings, edge, &"A", errors, warnings, diagnostics)
	var profile_b := _resolve_edge_profile(edge.cover_profile_b, edge.cover_b, settings, edge, &"B", errors, warnings, diagnostics)
	_append_profile_warnings(profile_a, edge, &"A", warnings, diagnostics)
	_append_profile_warnings(profile_b, edge, &"B", warnings, diagnostics)
	edge.cover_profile_a = profile_a
	edge.cover_profile_b = profile_b
	if profile_a != null and profile_a.is_valid():
		edge.cover_a = profile_a.cover_level
	if profile_b != null and profile_b.is_valid():
		edge.cover_b = profile_b.cover_level


static func _resolve_edge_profile(
	authored_profile: TacticalCoverProfile,
	legacy_level: TacticalEdgeRules.CoverLevel,
	settings: CoverCombatSettings,
	edge: MapEdgeData,
	side: StringName,
	errors: Array[String],
	warnings: Array[String],
	diagnostics: Array[Dictionary]
) -> TacticalCoverProfile:
	if authored_profile != null and authored_profile.is_valid():
		return authored_profile
	var fallback := settings.resolve_profile(authored_profile, int(legacy_level))
	if fallback != null and fallback.is_valid():
		if authored_profile != null:
			TacticalMapDiagnostics.append_warning(
				warnings,
				diagnostics,
				&"TMB-063",
				"TMB-063: Invalid %s-side CoverProfile on Edge '%s'; legacy CoverLevel fallback was used." % [side, edge.key_string()],
				edge.source_cell
			)
		return fallback
	var invalid_message := "TMB-063: Edge '%s' has no valid %s-side CoverProfile or legacy fallback." % [edge.key_string(), side]
	TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-063", invalid_message, edge.source_cell)
	return null


static func _append_profile_warnings(
	profile: TacticalCoverProfile,
	edge: MapEdgeData,
	side: StringName,
	warnings: Array[String],
	diagnostics: Array[Dictionary]
) -> void:
	if profile == null or edge == null:
		return
	for profile_warning in profile.validation_warnings():
		var warning_message := "TMB-065: %s-side CoverProfile '%s' on Edge '%s': %s" % [side, profile.cover_id, edge.key_string(), profile_warning]
		TacticalMapDiagnostics.append_warning(warnings, diagnostics, &"TMB-065", warning_message, edge.source_cell)


static func _collect_markers(author: TacticalMapAuthor, definition: TacticalMapDefinition, errors: Array[String], diagnostics: Array[Dictionary]) -> void:
	for node in _descendants(author):
		if node is UnitSpawnMarker3D:
			definition.spawns.append((node as UnitSpawnMarker3D).to_data())
		elif node is MapObjectMarker3D:
			definition.objects.append((node as MapObjectMarker3D).to_data())
		elif node is PatrolRoute3D:
			definition.patrol_routes.append((node as PatrolRoute3D).to_data())
		elif node is TraversalLink3D:
			definition.transitions.append((node as TraversalLink3D).to_data())
	definition.spawns.sort_custom(func(a: MapSpawnData, b: MapSpawnData) -> bool: return String(a.unit_name) < String(b.unit_name))
	definition.objects.sort_custom(func(a: MapObjectPlacement, b: MapObjectPlacement) -> bool: return String(a.object_id) < String(b.object_id))
	definition.patrol_routes.sort_custom(func(a: MapPatrolRouteData, b: MapPatrolRouteData) -> bool: return String(a.route_id) < String(b.route_id))
	definition.transitions.sort_custom(func(a: MapTransitionData, b: MapTransitionData) -> bool:
		return _cell_less(a.from_cell, b.from_cell) or (a.from_cell == b.from_cell and _cell_less(a.to_cell, b.to_cell))
	)
	var ids: Dictionary = {}
	for spawn in definition.spawns:
		if spawn.unit_name == &"":
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-030", "A unit spawn has an empty unit name.", spawn.cell)
		elif ids.has(spawn.unit_name):
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-031", "Duplicate map id: %s." % spawn.unit_name, spawn.cell)
		else:
			ids[spawn.unit_name] = true
	for placement in definition.objects:
		if placement.object_id == &"":
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-032", "A map object has an empty id.", placement.cell)
		elif ids.has(placement.object_id):
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-033", "Duplicate map id: %s." % placement.object_id, placement.cell)
		else:
			ids[placement.object_id] = true


static func _validate_author_settings(
	author: TacticalMapAuthor,
	floor_grid: GridMap,
	structure_grid: GridMap,
	catalog: MapTileCatalog,
	placeable_library: TacticalPlaceableLibrary,
	errors: Array[String],
	diagnostics: Array[Dictionary]
) -> void:
	if author.map_id == &"":
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-010", "Map id cannot be empty.")
	if author.level_count <= 0:
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-011", "Map level count must be positive.")
	if author.cell_dimensions.x <= 0.0 or author.cell_dimensions.y <= 0.0 or author.cell_dimensions.z <= 0.0:
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-012", "Cell dimensions must be positive.")
	if floor_grid == null:
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-013", "TacticalMapAuthor requires a direct FloorGrid child.")
	if catalog == null and placeable_library == null:
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-014", "TacticalMapAuthor requires a MapTileCatalog or TacticalPlaceableLibrary.")
	if placeable_library != null and placeable_library.schema_version != TacticalPlaceableLibrary.CURRENT_SCHEMA_VERSION:
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-015", "TacticalMapAuthor has an unsupported TacticalPlaceableLibrary schema.")
	for grid in [floor_grid, structure_grid]:
		if grid == null:
			continue
		if not grid.position.is_equal_approx(Vector3.ZERO) or not grid.rotation.is_equal_approx(Vector3.ZERO) or not grid.scale.is_equal_approx(Vector3.ONE):
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-016", "%s transform must remain identity." % grid.name)
		if not grid.cell_size.is_equal_approx(author.cell_dimensions):
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-017", "%s cell_size must match TacticalMapAuthor cell_dimensions." % grid.name)


static func _validate_definition(definition: TacticalMapDefinition, errors: Array[String], warnings: Array[String], diagnostics: Array[Dictionary]) -> void:
	var cells: Dictionary = {}
	for cell_data in definition.cells:
		cells[cell_data.coordinate] = cell_data
	if cells.is_empty():
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-040", "Map has no floor cells.")
	for edge in definition.edges:
		if edge == null:
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-067", "TMB-067: Map contains a null Edge entry.")
			continue
		var edge_key := edge.get_key()
		if edge_key == null or not edge_key.is_valid():
			TacticalMapDiagnostics.append_error(
				errors,
				diagnostics,
				&"TMB-067",
				"TMB-067: Edge '%s' is not a valid horizontal adjacent EdgeKey." % edge.key_string(),
				edge.source_cell
			)
			continue
		if not cells.has(edge.cell_a) and not cells.has(edge.cell_b):
			TacticalMapDiagnostics.append_warning(
				warnings,
				diagnostics,
				&"TMB-064",
				"TMB-064: Edge '%s' has no valid map Cell on either side." % edge.key_string(),
				edge.source_cell
			)
		if edge.cover_profile_a == null or not edge.cover_profile_a.is_valid():
			TacticalMapDiagnostics.append_error(
				errors,
				diagnostics,
				&"TMB-063",
				"TMB-063: Edge '%s' has no valid A-side CoverProfile." % edge.key_string(),
				edge.source_cell
			)
		if edge.cover_profile_b == null or not edge.cover_profile_b.is_valid():
			TacticalMapDiagnostics.append_error(
				errors,
				diagnostics,
				&"TMB-063",
				"TMB-063: Edge '%s' has no valid B-side CoverProfile." % edge.key_string(),
				edge.source_cell
			)
	var occupied_spawn_cells: Dictionary = {}
	var player_spawn_count := 0
	for spawn in definition.spawns:
		if not cells.has(spawn.cell):
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-041", "Spawn %s is not on a floor cell (%s)." % [spawn.unit_name, spawn.cell], spawn.cell)
		elif not (cells[spawn.cell] as MapCellData).walkable:
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-042", "Spawn %s is on a blocked cell (%s)." % [spawn.unit_name, spawn.cell], spawn.cell)
		if occupied_spawn_cells.has(spawn.cell):
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-043", "Multiple units spawn on %s." % spawn.cell, spawn.cell)
		occupied_spawn_cells[spawn.cell] = true
		if spawn.faction == &"player":
			player_spawn_count += 1
	if player_spawn_count == 0:
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-044", "Map needs at least one player spawn.")
	var extraction_cells: Array[Vector3i] = []
	for placement in definition.objects:
		if not cells.has(placement.cell):
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-045", "Object %s is not on a floor cell (%s)." % [placement.object_id, placement.cell], placement.cell)
		elif placement.kind == MapObjectPlacement.Kind.EXTRACTION:
			extraction_cells.append(placement.cell)
		var loot_configuration_error := placement.get_loot_configuration_error()
		if not loot_configuration_error.is_empty():
			if placement.kind == MapObjectPlacement.Kind.LOOT:
				TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-054", loot_configuration_error, placement.cell)
			else:
				TacticalMapDiagnostics.append_warning(warnings, diagnostics, &"TMB-055", loot_configuration_error, placement.cell)
	if extraction_cells.is_empty():
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-046", "Map needs at least one extraction marker.")
	for transition in definition.transitions:
		if transition.from_cell == transition.to_cell:
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-047", "A traversal link connects %s to itself." % transition.from_cell, transition.from_cell)
		var missing_from := not cells.has(transition.from_cell)
		var missing_to := not cells.has(transition.to_cell)
		if missing_from:
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-048", "Traversal link %s -> %s has a missing endpoint." % [transition.from_cell, transition.to_cell], transition.from_cell)
		if missing_to:
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-048", "Traversal link %s -> %s has a missing endpoint." % [transition.from_cell, transition.to_cell], transition.to_cell)
	for route in definition.patrol_routes:
		if route.route_id == &"":
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-049", "A patrol route has an empty id.")
		if route.points.is_empty():
			TacticalMapDiagnostics.append_warning(warnings, diagnostics, &"TMB-056", "Patrol route %s has no points." % route.route_id)
		for point in route.points:
			if not cells.has(point):
				TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-050", "Patrol route %s references missing cell %s." % [route.route_id, point], point)
	var model := GridModel.new()
	if not model.configure_from_definition(definition):
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-051", "Baked definition could not initialize GridModel.")
		return
	for route in definition.patrol_routes:
		for index in range(1, route.points.size()):
			if model.find_path(route.points[index - 1], route.points[index]).is_empty():
				var disconnected_message := "Patrol route %s is disconnected between %s and %s." % [route.route_id, route.points[index - 1], route.points[index]]
				TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-052", disconnected_message, route.points[index])
	if not extraction_cells.is_empty():
		for spawn_cell in definition.get_player_spawn_cells():
			var can_extract := false
			for extraction_cell in extraction_cells:
				if not model.find_path(spawn_cell, extraction_cell).is_empty():
					can_extract = true
					break
			if not can_extract:
				TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-053", "Player spawn %s cannot reach any extraction point." % spawn_cell, spawn_cell)


static func _inside_volume(author: TacticalMapAuthor, cell: Vector3i) -> bool:
	return author != null and cell.y >= 0 and cell.y < TacticalMapDefinition.MAX_LEVEL_COUNT


## Convert arbitrary authoring coordinates into the runtime zero-based X/Z
## contract while moving the definition origin by the same physical offset.
## This operates only on the freshly-created runtime definition; authoring
## GridMaps and marker cells remain in their authored coordinate space.
static func _normalize_definition_coordinates(definition: TacticalMapDefinition, author: TacticalMapAuthor) -> void:
	if definition == null or author == null:
		return
	var bounds := _definition_bounds(definition)
	if not bool(bounds.get(&"has_content", false)):
		return
	var min_x := int(bounds[&"min_x"])
	var min_z := int(bounds[&"min_z"])
	var max_x := int(bounds[&"max_x"])
	var max_z := int(bounds[&"max_z"])
	var max_y := int(bounds[&"max_y"])
	var shift := Vector3i(-min_x, 0, -min_z)
	definition.origin = author.grid_origin + Vector3(
		float(min_x) * definition.cell_size.x,
		0.0,
		float(min_z) * definition.cell_size.z
	)
	definition.footprint_size = Vector2i(max_x - min_x + 1, max_z - min_z + 1)
	definition.level_count = clampi(max_y + 1, 1, TacticalMapDefinition.MAX_LEVEL_COUNT)
	for cell_data in definition.cells:
		if cell_data != null:
			cell_data.coordinate += shift
	for spawn in definition.spawns:
		if spawn != null:
			spawn.cell += shift
	for placement in definition.objects:
		if placement != null:
			placement.cell += shift
	for route in definition.patrol_routes:
		if route == null:
			continue
		for index in range(route.points.size()):
			route.points[index] += shift
	for transition in definition.transitions:
		if transition != null:
			transition.from_cell += shift
			transition.to_cell += shift
	for edge in definition.edges:
		if edge != null:
			edge.cell_a += shift
			edge.cell_b += shift
			edge.source_cell += shift


static func _definition_bounds(definition: TacticalMapDefinition) -> Dictionary:
	var bounds := {
		&"has_content": false,
		&"min_x": 0,
		&"max_x": 0,
		&"min_z": 0,
		&"max_z": 0,
		&"max_y": 0,
	}
	if definition == null:
		return bounds
	for cell_data in definition.cells:
		if cell_data != null:
			_include_definition_bound(bounds, cell_data.coordinate)
	for spawn in definition.spawns:
		if spawn != null:
			_include_definition_bound(bounds, spawn.cell)
	for placement in definition.objects:
		if placement != null:
			_include_definition_bound(bounds, placement.cell)
	for route in definition.patrol_routes:
		if route != null:
			for point in route.points:
				_include_definition_bound(bounds, point)
	for transition in definition.transitions:
		if transition != null:
			_include_definition_bound(bounds, transition.from_cell)
			_include_definition_bound(bounds, transition.to_cell)
	for edge in definition.edges:
		if edge != null:
			_include_definition_bound(bounds, edge.cell_a)
			_include_definition_bound(bounds, edge.cell_b)
	return bounds


static func _include_definition_bound(bounds: Dictionary, cell: Vector3i) -> void:
	if not bool(bounds.get(&"has_content", false)):
		bounds[&"has_content"] = true
		bounds[&"min_x"] = cell.x
		bounds[&"max_x"] = cell.x
		bounds[&"min_z"] = cell.z
		bounds[&"max_z"] = cell.z
		bounds[&"max_y"] = cell.y
		return
	bounds[&"min_x"] = mini(int(bounds[&"min_x"]), cell.x)
	bounds[&"max_x"] = maxi(int(bounds[&"max_x"]), cell.x)
	bounds[&"min_z"] = mini(int(bounds[&"min_z"]), cell.z)
	bounds[&"max_z"] = maxi(int(bounds[&"max_z"]), cell.z)
	bounds[&"max_y"] = maxi(int(bounds[&"max_y"]), cell.y)


static func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = []
	for child in root.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result


static func _rotated_cover_mask(mask: int, basis: Basis) -> int:
	if mask == 0:
		return 0
	var result := 0
	var directions: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for index in range(4):
		if mask & (1 << index) == 0:
			continue
		var rotated: Vector3 = basis * directions[index]
		var target_index := _cardinal_direction_index(rotated)
		result |= 1 << target_index
	return result


static func _rotated_local_edge_direction(local_direction: int, basis: Basis) -> Vector3i:
	var directions: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	var local_index := clampi(local_direction, 0, 3)
	return _cardinal_cell_vector(_cardinal_direction_index(basis * directions[local_index]))


static func _cardinal_direction_index(direction: Vector3) -> int:
	if absf(direction.x) > absf(direction.z):
		return 1 if direction.x > 0.0 else 3
	return 2 if direction.z > 0.0 else 0


static func _cardinal_cell_vector(direction_index: int) -> Vector3i:
	return [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)][clampi(direction_index, 0, 3)]


static func _cell_less(a: Vector3i, b: Vector3i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	if a.z != b.z:
		return a.z < b.z
	return a.x < b.x
