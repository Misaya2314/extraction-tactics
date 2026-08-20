class_name TacticalMapBaker
extends RefCounted

## Stateless authoring compiler. It can run from editor buttons or headless tests.

const FLOOR_GRID_NAME := &"FloorGrid"
const STRUCTURE_GRID_NAME := &"StructureGrid"


static func build(author: TacticalMapAuthor) -> Dictionary:
	var definition := TacticalMapDefinition.new()
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

	if author.authoring_data != null:
		_collect_edges(author.authoring_data, definition, errors, warnings, diagnostics)

	_collect_markers(author, definition, errors, diagnostics)
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
	# Read existing UID before save so we can restore it after
	var existing_uid := _read_existing_uid(output_path)
	var save_error := ResourceSaver.save(result[&"definition"], output_path)
	if save_error != OK:
		var save_failure_message := "ResourceSaver failed for %s (error %d)." % [output_path, save_error]
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-061", save_failure_message)
		result[&"diagnostics"] = TacticalMapDiagnostics.sort_diagnostics(diagnostics)
		return result
	# ResourceSaver may generate a new UID; restore the original to avoid
	# breaking ext_resource references in .tscn files.
	if existing_uid != "":
		_restore_uid_in_file(output_path, existing_uid)
	return result


static func _read_existing_uid(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var first_line := file.get_line()
	file.close()
	# Format: [gd_resource ... uid="uid://xxxxx" ...]
	var uid_start := first_line.find("uid=\"uid://")
	if uid_start < 0:
		return ""
	uid_start += 5  # skip uid="
	var uid_end := first_line.find("\"", uid_start)
	if uid_end < 0:
		return ""
	return first_line.substr(uid_start, uid_end - uid_start)


static func _restore_uid_in_file(path: String, uid: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var content := file.get_as_text()
	file.close()
	# Replace uid="uid://new" with uid="uid://old" on the first line
	var new_uid_start := content.find("uid=\"uid://")
	if new_uid_start < 0:
		return
	var new_uid_value_start := new_uid_start + 5
	var new_uid_end := content.find("\"", new_uid_value_start)
	if new_uid_end < 0:
		return
	var old_uid := content.substr(new_uid_value_start, new_uid_end - new_uid_value_start)
	if old_uid == uid:
		return  # already correct
	content = content.substr(0, new_uid_value_start) + uid + content.substr(new_uid_end)
	var write_file := FileAccess.open(path, FileAccess.WRITE)
	if write_file == null:
		return
	write_file.store_string(content)
	write_file.close()


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
	data: TacticalMapAuthoringData,
	definition: TacticalMapDefinition,
	_errors: Array[String],
	_warnings: Array[String],
	diagnostics: Array[Dictionary]
) -> void:
	if data == null:
		return
	var ordered: Array[TacticalEdgePlacement] = []
	for placement in data.edge_placements:
		if placement != null and placement.enabled:
			ordered.append(placement)
	ordered.sort_custom(func(a: TacticalEdgePlacement, b: TacticalEdgePlacement) -> bool:
		return a.key_string() < b.key_string()
	)
	var seen: Dictionary = {}
	for placement in ordered:
		if not placement.is_valid():
			continue
		var key := placement.key_string()
		if seen.has(key):
			var duplicate_message := "TMB-003: Duplicate edge key '%s'." % key
			TacticalMapDiagnostics.append_error(_errors, diagnostics, &"TMB-003", duplicate_message, placement.edge_key.cell_a if placement.edge_key != null else null)
			continue
		seen[key] = true
		definition.edges.append(MapEdgeData.from_placement(placement))


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
	if author.footprint_size.x <= 0 or author.footprint_size.y <= 0 or author.level_count <= 0:
		TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-011", "Map footprint and level count must be positive.")
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
		var missing_endpoint: Variant = null
		if not cells.has(transition.from_cell):
			missing_endpoint = transition.from_cell
		elif not cells.has(transition.to_cell):
			missing_endpoint = transition.to_cell
		if missing_endpoint != null:
			TacticalMapDiagnostics.append_error(errors, diagnostics, &"TMB-048", "Traversal link %s -> %s has a missing endpoint." % [transition.from_cell, transition.to_cell], missing_endpoint)
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
	return cell.x >= 0 and cell.z >= 0 and cell.y >= 0 \
		and cell.x < author.footprint_size.x and cell.z < author.footprint_size.y and cell.y < author.level_count


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
		var target_index := 0
		if absf(rotated.x) > absf(rotated.z):
			target_index = 1 if rotated.x > 0.0 else 3
		else:
			target_index = 2 if rotated.z > 0.0 else 0
		result |= 1 << target_index
	return result


static func _cell_less(a: Vector3i, b: Vector3i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	if a.z != b.z:
		return a.z < b.z
	return a.x < b.x
