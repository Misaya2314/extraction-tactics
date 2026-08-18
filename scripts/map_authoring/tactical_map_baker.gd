class_name TacticalMapBaker
extends RefCounted

## Stateless authoring compiler. It can run from editor buttons or headless tests.

const FLOOR_GRID_NAME := &"FloorGrid"
const STRUCTURE_GRID_NAME := &"StructureGrid"


static func build(author: TacticalMapAuthor) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var definition := TacticalMapDefinition.new()
	if author == null:
		return {&"definition": definition, &"errors": ["Missing TacticalMapAuthor."], &"warnings": warnings}

	definition.map_id = author.map_id
	definition.footprint_size = author.footprint_size
	definition.level_count = author.level_count
	definition.cell_size = author.cell_dimensions
	definition.origin = author.grid_origin
	definition.authoring_scene_path = author.get_scene_file_path()
	var catalog := author.tile_catalog
	var floor_grid := author.get_node_or_null(NodePath(String(FLOOR_GRID_NAME))) as GridMap
	var structure_grid := author.get_node_or_null(NodePath(String(STRUCTURE_GRID_NAME))) as GridMap
	_validate_author_settings(author, floor_grid, structure_grid, catalog, errors)
	if floor_grid == null or catalog == null:
		return {&"definition": definition, &"errors": errors, &"warnings": warnings}

	var cells_by_coordinate: Dictionary = {}
	var floor_cells := floor_grid.get_used_cells()
	floor_cells.sort_custom(_cell_less)
	for coordinate in floor_cells:
		var item_id := floor_grid.get_cell_item(coordinate)
		var rule := catalog.find_rule(MapTileRule.Layer.FLOOR, item_id)
		if rule == null:
			errors.append("Floor item %d at %s has no catalog rule." % [item_id, coordinate])
			continue
		if not _inside_volume(author, coordinate):
			errors.append("Floor cell %s is outside the declared map volume." % coordinate)
			continue
		var cell_data := MapCellData.new()
		cell_data.coordinate = coordinate
		cell_data.walkable = rule.walkable
		cell_data.move_cost = maxi(rule.move_cost, 1)
		cell_data.blocks_los = rule.blocks_los
		cell_data.occluder_height = maxf(rule.occluder_height, 0.0)
		cell_data.terrain_id = rule.tile_id
		cell_data.cover_mask = _rotated_cover_mask(rule.cover_mask, floor_grid.get_cell_item_basis(coordinate))
		cells_by_coordinate[coordinate] = cell_data

	if structure_grid != null:
		var structure_cells := structure_grid.get_used_cells()
		structure_cells.sort_custom(_cell_less)
		for coordinate in structure_cells:
			var item_id := structure_grid.get_cell_item(coordinate)
			var rule := catalog.find_rule(MapTileRule.Layer.STRUCTURE, item_id)
			if rule == null:
				errors.append("Structure item %d at %s has no catalog rule." % [item_id, coordinate])
				continue
			if not cells_by_coordinate.has(coordinate):
				errors.append("Structure at %s has no floor surface beneath it." % coordinate)
				continue
			var cell_data: MapCellData = cells_by_coordinate[coordinate]
			cell_data.walkable = cell_data.walkable and rule.walkable
			cell_data.move_cost = maxi(cell_data.move_cost, rule.move_cost)
			cell_data.blocks_los = cell_data.blocks_los or rule.blocks_los
			cell_data.occluder_height = maxf(cell_data.occluder_height, rule.occluder_height)
			cell_data.cover_mask |= _rotated_cover_mask(rule.cover_mask, structure_grid.get_cell_item_basis(coordinate))

	var ordered_cells: Array = cells_by_coordinate.keys()
	ordered_cells.sort_custom(_cell_less)
	for coordinate in ordered_cells:
		definition.cells.append(cells_by_coordinate[coordinate])

	_collect_markers(author, definition, errors)
	_validate_definition(definition, errors, warnings)
	return {&"definition": definition, &"errors": errors, &"warnings": warnings}


static func save(author: TacticalMapAuthor) -> Dictionary:
	var result := build(author)
	var errors: Array[String] = result[&"errors"]
	if not errors.is_empty():
		return result
	var output_path := author.output_resource_path.strip_edges()
	if output_path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(output_path)
		if uid >= 0:
			output_path = ResourceUID.get_id_path(uid)
	if output_path.is_empty() or not output_path.begins_with("res://") or not output_path.ends_with(".tres"):
		errors.append("Output path must be a res:// path ending in .tres.")
		return result
	# Read existing UID before save so we can restore it after
	var existing_uid := _read_existing_uid(output_path)
	var save_error := ResourceSaver.save(result[&"definition"], output_path)
	if save_error != OK:
		errors.append("ResourceSaver failed for %s (error %d)." % [output_path, save_error])
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


static func _collect_markers(author: TacticalMapAuthor, definition: TacticalMapDefinition, errors: Array[String]) -> void:
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
			errors.append("A unit spawn has an empty unit name.")
		elif ids.has(spawn.unit_name):
			errors.append("Duplicate map id: %s." % spawn.unit_name)
		else:
			ids[spawn.unit_name] = true
	for placement in definition.objects:
		if placement.object_id == &"":
			errors.append("A map object has an empty id.")
		elif ids.has(placement.object_id):
			errors.append("Duplicate map id: %s." % placement.object_id)
		else:
			ids[placement.object_id] = true


static func _validate_author_settings(author: TacticalMapAuthor, floor_grid: GridMap, structure_grid: GridMap, catalog: MapTileCatalog, errors: Array[String]) -> void:
	if author.map_id == &"":
		errors.append("Map id cannot be empty.")
	if author.footprint_size.x <= 0 or author.footprint_size.y <= 0 or author.level_count <= 0:
		errors.append("Map footprint and level count must be positive.")
	if author.cell_dimensions.x <= 0.0 or author.cell_dimensions.y <= 0.0 or author.cell_dimensions.z <= 0.0:
		errors.append("Cell dimensions must be positive.")
	if floor_grid == null:
		errors.append("TacticalMapAuthor requires a direct FloorGrid child.")
	if catalog == null:
		errors.append("TacticalMapAuthor requires a MapTileCatalog.")
	for grid in [floor_grid, structure_grid]:
		if grid == null:
			continue
		if not grid.position.is_equal_approx(Vector3.ZERO) or not grid.rotation.is_equal_approx(Vector3.ZERO) or not grid.scale.is_equal_approx(Vector3.ONE):
			errors.append("%s transform must remain identity." % grid.name)
		if not grid.cell_size.is_equal_approx(author.cell_dimensions):
			errors.append("%s cell_size must match TacticalMapAuthor cell_dimensions." % grid.name)


static func _validate_definition(definition: TacticalMapDefinition, errors: Array[String], warnings: Array[String]) -> void:
	var cells: Dictionary = {}
	for cell_data in definition.cells:
		cells[cell_data.coordinate] = cell_data
	if cells.is_empty():
		errors.append("Map has no floor cells.")
	var occupied_spawn_cells: Dictionary = {}
	var player_spawn_count := 0
	for spawn in definition.spawns:
		if not cells.has(spawn.cell):
			errors.append("Spawn %s is not on a floor cell (%s)." % [spawn.unit_name, spawn.cell])
		elif not (cells[spawn.cell] as MapCellData).walkable:
			errors.append("Spawn %s is on a blocked cell (%s)." % [spawn.unit_name, spawn.cell])
		if occupied_spawn_cells.has(spawn.cell):
			errors.append("Multiple units spawn on %s." % spawn.cell)
		occupied_spawn_cells[spawn.cell] = true
		if spawn.faction == &"player":
			player_spawn_count += 1
	if player_spawn_count == 0:
		errors.append("Map needs at least one player spawn.")
	var extraction_cells: Array[Vector3i] = []
	for placement in definition.objects:
		if not cells.has(placement.cell):
			errors.append("Object %s is not on a floor cell (%s)." % [placement.object_id, placement.cell])
		elif placement.kind == MapObjectPlacement.Kind.EXTRACTION:
			extraction_cells.append(placement.cell)
		var loot_configuration_error := placement.get_loot_configuration_error()
		if not loot_configuration_error.is_empty():
			if placement.kind == MapObjectPlacement.Kind.LOOT:
				errors.append(loot_configuration_error)
			else:
				warnings.append(loot_configuration_error)
	if extraction_cells.is_empty():
		errors.append("Map needs at least one extraction marker.")
	for transition in definition.transitions:
		if transition.from_cell == transition.to_cell:
			errors.append("A traversal link connects %s to itself." % transition.from_cell)
		if not cells.has(transition.from_cell) or not cells.has(transition.to_cell):
			errors.append("Traversal link %s -> %s has a missing endpoint." % [transition.from_cell, transition.to_cell])
	for route in definition.patrol_routes:
		if route.route_id == &"":
			errors.append("A patrol route has an empty id.")
		if route.points.is_empty():
			warnings.append("Patrol route %s has no points." % route.route_id)
		for point in route.points:
			if not cells.has(point):
				errors.append("Patrol route %s references missing cell %s." % [route.route_id, point])
	var model := GridModel.new()
	if not model.configure_from_definition(definition):
		errors.append("Baked definition could not initialize GridModel.")
		return
	for route in definition.patrol_routes:
		for index in range(1, route.points.size()):
			if model.find_path(route.points[index - 1], route.points[index]).is_empty():
				errors.append("Patrol route %s is disconnected between %s and %s." % [route.route_id, route.points[index - 1], route.points[index]])
	if not extraction_cells.is_empty():
		for spawn_cell in definition.get_player_spawn_cells():
			var can_extract := false
			for extraction_cell in extraction_cells:
				if not model.find_path(spawn_cell, extraction_cell).is_empty():
					can_extract = true
					break
			if not can_extract:
				errors.append("Player spawn %s cannot reach any extraction point." % spawn_cell)


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
