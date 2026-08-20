extends SceneTree

## Dynamic authoring coverage uses only in-memory authors.  It intentionally
## does not load or assert any production map layout.

const SessionScript = preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_baker_normalizes_actual_bounds()
	_test_empty_author_is_explicitly_invalid()
	_test_session_supports_negative_cells_and_marker_strokes()
	_test_property_service_uses_dynamic_horizontal_bounds()
	_finish()


func _test_baker_normalizes_actual_bounds() -> void:
	var author := _make_author(true)
	var result := TacticalMapBaker.build(author)
	var definition: TacticalMapDefinition = result[&"definition"]
	_expect(result[&"errors"].is_empty(), "baker: valid sparse negative-coordinate author should build")
	_expect(definition.footprint_size == Vector2i(3, 3), "baker: footprint should come from authored X/Z bounds")
	_expect(definition.level_count == 1, "baker: level count should come from authored content")
	_expect(definition.origin.is_equal_approx(Vector3(-4.0, 0.0, -6.0)), "baker: origin should compensate the X/Z normalization")
	var normalized_floor := _find_cell(definition, Vector3i.ZERO)
	var far_floor := _find_cell(definition, Vector3i(2, 0, 2))
	_expect(normalized_floor != null and far_floor != null, "baker: normalized cells should use zero-based runtime coordinates")
	_expect(definition.spawns.size() == 1 and definition.spawns[0].cell == Vector3i.ZERO, "baker: spawn should shift with the floor")
	_expect(definition.objects.size() == 1 and definition.objects[0].cell == Vector3i(2, 0, 2), "baker: object should shift with the floor")
	_expect(definition.transitions.size() == 1 and definition.transitions[0].from_cell == Vector3i.ZERO and definition.transitions[0].to_cell == Vector3i(2, 0, 2), "baker: traversal endpoints should shift together")
	_expect(definition.patrol_routes.size() == 1 and definition.patrol_routes[0].points[0] == Vector3i.ZERO and definition.patrol_routes[0].points[1] == Vector3i(2, 0, 2), "baker: patrol points should shift together")
	_expect(definition.edges.size() == 1 and definition.edges[0].cell_a == Vector3i.ZERO and definition.edges[0].cell_b == Vector3i(1, 0, 0), "baker: edge endpoints should shift together")
	var raw_cell := Vector3i(-2, 0, -3)
	var raw_world := author.cell_to_local(raw_cell)
	var baked_world := definition.origin + Vector3(0.5 * definition.cell_size.x, 0.5 * definition.cell_size.y, 0.5 * definition.cell_size.z)
	_expect(raw_world.is_equal_approx(baked_world), "baker: origin shift must preserve the cell world center")
	author.free()


func _test_empty_author_is_explicitly_invalid() -> void:
	var author := _make_author(false)
	var result := TacticalMapBaker.build(author)
	_expect(not result[&"errors"].is_empty(), "baker: empty author should fail explicitly")
	_expect(_has_diagnostic(result[&"diagnostics"], &"TMB-040"), "baker: empty author should expose no-floor diagnostic")
	author.free()


func _test_session_supports_negative_cells_and_marker_strokes() -> void:
	var author := _make_author(false)
	var floor_grid := author.get_node("FloorGrid") as GridMap
	floor_grid.set_cell_item(Vector3i(-2, 0, -3), 0)
	floor_grid.set_cell_item(Vector3i(-1, 0, -3), 0)
	var session := SessionScript.new()
	session.begin_for_author(author, author)
	_expect(session.can_edit_cell(Vector3i(-2, 0, -3), SessionScript.Tool.PAINT).get("valid", false), "session: negative X/Z should not be rejected by footprint_size")
	session.set_floor_level(31)
	_expect(session.floor_level == 31, "session: non-negative floors should remain editable up to the shared cap")
	session.set_floor_level(0)
	var enemy_index := _find_placeable(session.get_placeables(), "marker:enemy_spawn")
	_expect(enemy_index >= 0, "session: enemy spawn palette entry should be available")
	if enemy_index >= 0:
		session.select_placeable(enemy_index)
		session.set_selected_spawn_configuration({
		&"encounter_id": &"encounter_a",
		&"patrol_route_id": &"route_a",
	})
		var undo_redo := UndoRedo.new()
		session.begin_stroke("enemy spawn")
		_expect(session.apply_at(Vector3i(-2, 0, -3)), "session: enemy spawn should paint on a negative cell")
		_expect(session.finish_stroke(undo_redo), "session: spawn stroke should create one undo action")
		var spawns := author.get_node("Spawns")
		_expect(spawns.get_child_count() == 1 and (spawns.get_child(0) as UnitSpawnMarker3D).encounter_id == &"encounter_a", "session: spawn fields should be copied to UnitSpawnMarker3D")
		undo_redo.undo()
		_expect(spawns.get_child_count() == 0, "session: spawn stroke undo should remove the marker")
		undo_redo.redo()
		_expect(spawns.get_child_count() == 1, "session: spawn stroke redo should restore the marker")
		undo_redo.free()

	var traversal_index := _find_placeable(session.get_placeables(), "marker:traversal_link")
	_expect(traversal_index >= 0, "session: traversal palette entry should be available")
	if traversal_index >= 0:
		session.select_placeable(traversal_index)
		session.begin_stroke("traversal from")
		_expect(session.apply_at(Vector3i(-2, 0, -3)), "session: traversal first click should select from endpoint")
		session.finish_stroke(null)
		session.begin_stroke("traversal to")
		_expect(session.apply_at(Vector3i(-1, 0, -3)), "session: traversal second click should create link")
		session.finish_stroke(null)
		var links := author.get_node("TraversalLinks")
		_expect(links.get_child_count() == 1, "session: traversal should create one link after two endpoints")
		var link := links.get_child(0) as TraversalLink3D
		_expect(link != null and link.from_cell == Vector3i(-2, 0, -3) and link.to_cell == Vector3i(-1, 0, -3), "session: traversal should preserve authored endpoint order")

	var patrol_index := _find_placeable(session.get_placeables(), "marker:patrol_route")
	_expect(patrol_index >= 0, "session: patrol palette entry should be available")
	if patrol_index >= 0:
		session.select_placeable(patrol_index)
		session.begin_stroke("patrol route")
		session.apply_at(Vector3i(-2, 0, -3))
		session.apply_at(Vector3i(-1, 0, -3))
		session.apply_at(Vector3i(-2, 0, -3))
		_expect(session.finish_patrol_route(null), "session: patrol route should have an explicit finish operation")
		var routes := author.get_node("PatrolRoutes")
		_expect(routes.get_child_count() == 1, "session: patrol stroke should create one route")
		var route := routes.get_child(0) as PatrolRoute3D
		_expect(route != null and route.points.size() == 3, "session: patrol route should retain continuous points")

	var selected := session.get_selected_placeable()
	var selected_id := String(selected.get("id", ""))
	session.reload_placeables(true)
	var reloaded := session.get_selected_placeable()
	_expect(String(reloaded.get("id", "")) == selected_id, "session: reload_placeables should preserve stable selection")
	for key in ["definition", "kind", "layer", "item_id", "scene"]:
		_expect(reloaded.has(key), "session: selected descriptor should retain preview key %s" % key)
	author.free()


func _test_property_service_uses_dynamic_horizontal_bounds() -> void:
	var author := _make_author(false)
	var floor_grid := author.get_node("FloorGrid") as GridMap
	floor_grid.set_cell_item(Vector3i(-4, 0, 7), 0)
	var service := TacticalMapPropertyService.new()
	_expect(service.apply_override_field(author, [Vector3i(-4, 0, 7)], TacticalCellOverride.Field.MOVE_COST, 8), "property: override should accept a negative/outside-footprint X/Z cell")
	var inspection := service.inspect_cells(author, [Vector3i(-4, 0, 7)])
	_expect(inspection[&"cells"].size() == 1 and inspection[&"cells"][0][&"effective_rules"].move_cost == 8, "property: dynamic cell should use the Baker effective rule")
	var authoring := TacticalMapAuthoringData.new()
	var override := TacticalCellOverride.new()
	override.coordinate = Vector3i(-50, 0, -50)
	authoring.cell_overrides.append(override)
	var validation := TacticalMapValidator.validate_authoring_data(authoring, Vector2i.ONE, 1)
	_expect(not _contains_error(validation[&"errors"], "outside the declared volume"), "validator: legacy footprint should not reject horizontal coordinates")
	author.free()


func _make_author(with_content: bool) -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"dynamic_bounds_synthetic"
	author.footprint_size = Vector2i.ONE
	author.level_count = 1
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	var mesh_library := MeshLibrary.new()
	mesh_library.create_item(0)
	mesh_library.create_item(1)
	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = mesh_library
	floor_grid.cell_size = author.cell_dimensions
	if with_content:
		floor_grid.set_cell_item(Vector3i(-2, 0, -3), 0)
		floor_grid.set_cell_item(Vector3i(0, 0, -1), 0)
	author.add_child(floor_grid)
	var structure_grid := GridMap.new()
	structure_grid.name = "StructureGrid"
	structure_grid.mesh_library = mesh_library
	structure_grid.cell_size = author.cell_dimensions
	if with_content:
		structure_grid.set_cell_item(Vector3i(-2, 0, -3), 1)
	author.add_child(structure_grid)
	var objects := Node3D.new()
	objects.name = "Objects"
	author.add_child(objects)
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	author.add_child(spawns)
	var routes := Node3D.new()
	routes.name = "PatrolRoutes"
	author.add_child(routes)
	var links := Node3D.new()
	links.name = "TraversalLinks"
	author.add_child(links)
	var catalog := MapTileCatalog.new()
	var floor_rule := MapTileRule.new()
	floor_rule.layer = MapTileRule.Layer.FLOOR
	floor_rule.item_id = 0
	floor_rule.tile_id = &"synthetic_floor"
	floor_rule.walkable = true
	floor_rule.move_cost = 1
	var structure_rule := MapTileRule.new()
	structure_rule.layer = MapTileRule.Layer.STRUCTURE
	structure_rule.item_id = 1
	structure_rule.tile_id = &"synthetic_structure"
	structure_rule.walkable = true
	structure_rule.move_cost = 1
	catalog.rules = [floor_rule, structure_rule]
	author.tile_catalog = catalog
	if with_content:
		var spawn := UnitSpawnMarker3D.new()
		spawn.unit_name = &"SyntheticPlayer"
		spawn.faction = "player"
		spawn.cell = Vector3i(-2, 0, -3)
		spawns.add_child(spawn)
		var extraction := MapObjectMarker3D.new()
		extraction.object_id = &"SyntheticExtraction"
		extraction.kind = MapObjectPlacement.Kind.EXTRACTION
		extraction.cell = Vector3i(0, 0, -1)
		objects.add_child(extraction)
		var route := PatrolRoute3D.new()
		route.route_id = &"route_a"
		route.points = [Vector3i(-2, 0, -3), Vector3i(0, 0, -1)]
		routes.add_child(route)
		var link := TraversalLink3D.new()
		link.from_cell = Vector3i(-2, 0, -3)
		link.to_cell = Vector3i(0, 0, -1)
		links.add_child(link)
		var data := TacticalMapAuthoringData.new()
		var edge := TacticalEdgePlacement.new()
		edge.edge_key = TacticalEdgeKey.new()
		edge.edge_key.cell_a = Vector3i(-2, 0, -3)
		edge.edge_key.cell_b = Vector3i(-1, 0, -3)
		edge.placeable_id = &"edge.synthetic"
		data.edge_placements.append(edge)
		author.authoring_data = data
	return author


func _find_cell(definition: TacticalMapDefinition, coordinate: Vector3i) -> MapCellData:
	for cell in definition.cells:
		if cell != null and cell.coordinate == coordinate:
			return cell
	return null


func _find_placeable(entries: Array, id: String) -> int:
	for index in range(entries.size()):
		if String(entries[index].get("id", "")) == id:
			return index
	return -1


func _has_diagnostic(diagnostics: Array, code: StringName) -> bool:
	for diagnostic in diagnostics:
		if diagnostic is Dictionary and StringName(diagnostic.get(&"code", &"")) == code:
			return true
	return false


func _contains_error(errors: Array, fragment: String) -> bool:
	for error in errors:
		if String(error).contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_DYNAMIC_BOUNDS_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_DYNAMIC_BOUNDS_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
