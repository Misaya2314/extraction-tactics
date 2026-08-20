extends SceneTree

## Pure editor-session coverage. This test builds an in-memory author with
## synthetic GridMaps and definitions; it never loads a production map scene.

const SessionScript = preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_catalog_integer_layer_routing()
	_test_library_integer_placement_and_layer_routing()
	_test_paint_uses_selected_entry_layer()
	_test_noop_stroke_does_not_commit()
	_test_undo_snapshot_call_signature()
	_test_object_snapshot_includes_facing()
	_test_erase_validation_ignores_paint_selection()
	_test_next_object_id_scans_existing_markers()
	_test_selection_is_deterministic_and_clears_on_floor_change()
	_test_property_override_batch_undo_and_inherit()
	_test_debug_views_validation_and_focus()
	_test_legacy_default_descriptor_constraints()
	_test_default_property_service_undo_and_null_restore()
	_finish()


func _test_catalog_integer_layer_routing() -> void:
	var author := _make_author()
	var catalog := MapTileCatalog.new()
	catalog.rules = [
		_legacy_rule(0, 1, &"floor"),
		_legacy_rule(1, 2, &"wall"),
		_legacy_rule(1, 3, &"low_cover"),
	]
	author.tile_catalog = catalog

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var wall_index := _find_placeable(session.get_placeables(), "catalog:1:2")
	var low_cover_index := _find_placeable(session.get_placeables(), "catalog:1:3")
	_expect(wall_index >= 0 and low_cover_index >= 0, "catalog: wall and low_cover should be discoverable")
	if wall_index < 0 or low_cover_index < 0:
		author.free()
		return
	var wall_entry: Dictionary = session.get_placeables()[wall_index]
	var low_cover_entry: Dictionary = session.get_placeables()[low_cover_index]
	_expect(int(wall_entry.get("layer", -1)) == SessionScript.TargetLayer.STRUCTURE, "catalog: wall integer layer should route to Structure")
	_expect(int(low_cover_entry.get("layer", -1)) == SessionScript.TargetLayer.STRUCTURE, "catalog: low_cover integer layer should route to Structure")

	session.select_placeable(wall_index)
	session.begin_stroke("catalog wall")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "catalog: wall should paint")
	session.finish_stroke(null)
	session.select_placeable(low_cover_index)
	session.begin_stroke("catalog low cover")
	_expect(session.apply_at(Vector3i(1, 0, 0)), "catalog: low_cover should paint")
	session.finish_stroke(null)
	var structure_grid := author.get_node("StructureGrid") as GridMap
	_expect(structure_grid.get_cell_item(Vector3i(0, 0, 0)) == 2, "catalog: wall should be written to StructureGrid")
	_expect(structure_grid.get_cell_item(Vector3i(1, 0, 0)) == 3, "catalog: low_cover should be written to StructureGrid")
	_expect((author.get_node("FloorGrid") as GridMap).get_cell_item(Vector3i(0, 0, 0)) == 0, "catalog: FloorGrid should remain unchanged")
	author.free()


func _test_library_integer_placement_and_layer_routing() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var structure := TacticalCellTileDefinition.new()
	structure.placeable_id = &"library.structure"
	structure.display_name = "Library Structure"
	structure.placement_kind = 0
	structure.target_layer = 1
	structure.mesh_item_id = 4
	var object := TacticalObjectDefinition.new()
	object.placeable_id = &"library.object"
	object.display_name = "Library Object"
	object.placement_kind = 2
	object.blocks_movement = true
	object.blocks_los = true
	var edge := TacticalEdgeDefinition.new()
	edge.placeable_id = &"library.edge"
	var stamp := TacticalStampDefinition.new()
	stamp.placeable_id = &"library.stamp"
	library.definitions = [structure, object, edge, stamp]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var entries: Array = session.get_placeables()
	var structure_index := _find_placeable(entries, "library.structure")
	var object_index := _find_placeable(entries, "library.object")
	_expect(structure_index >= 0, "library: integer CELL definition should be discoverable")
	_expect(object_index >= 0, "library: integer OBJECT definition should be discoverable")
	_expect(_find_placeable(entries, "library.edge") < 0, "library: EDGE definition should be skipped")
	_expect(_find_placeable(entries, "library.stamp") < 0, "library: STAMP definition should be skipped")
	if structure_index < 0 or object_index < 0:
		author.free()
		return
	_expect(int(entries[structure_index].get("layer", -1)) == SessionScript.TargetLayer.STRUCTURE, "library: integer target_layer should route to Structure")
	_expect(String(entries[object_index].get("kind", "")) == "object", "library: integer placement_kind OBJECT should route to object")
	_expect(int(entries[object_index].get("layer", -1)) == SessionScript.TargetLayer.OBJECT, "library: object should target Object layer")
	_expect(bool(entries[object_index].get("blocks_movement", false)), "library: object blocks_movement should reach the palette entry")
	_expect(bool(entries[object_index].get("blocks_los", false)), "library: object blocks_los should reach the palette entry")

	session.select_placeable(structure_index)
	session.begin_stroke("library structure")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "library: structure should paint")
	session.finish_stroke(null)
	_expect((author.get_node("StructureGrid") as GridMap).get_cell_item(Vector3i(0, 0, 0)) == 4, "library: structure should be written to StructureGrid")
	session.select_placeable(object_index)
	session.begin_stroke("library object")
	_expect(session.apply_at(Vector3i(1, 0, 0)), "library: object should paint on a Floor cell")
	session.finish_stroke(null)
	var marker := (author.get_node("Objects") as Node).get_child(0) as MapObjectMarker3D
	_expect(marker != null and marker.blocks_movement, "library: placed object should retain blocks_movement")
	_expect(marker != null and marker.blocks_los, "library: placed object should retain blocks_los")
	author.free()


func _test_paint_uses_selected_entry_layer() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"library.authoritative_floor"
	floor_definition.display_name = "Authoritative Floor"
	floor_definition.placement_kind = 0
	floor_definition.target_layer = 0
	floor_definition.mesh_item_id = 1
	library.definitions = [floor_definition]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.select_placeable(0)
	var floor_grid := author.get_node("FloorGrid") as GridMap
	var structure_grid := author.get_node("StructureGrid") as GridMap
	var objects := author.get_node("Objects") as Node
	session.target_layer = SessionScript.TargetLayer.OBJECT
	session.begin_stroke("paint floor while object selected")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "paint: Floor entry should route away from manually selected Object layer")
	session.finish_stroke(null)
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 1, "paint: Floor entry should write FloorGrid")
	_expect(structure_grid.get_cell_item(Vector3i(0, 0, 0)) < 0, "paint: Floor entry should not write StructureGrid")
	_expect(objects.get_child_count() == 0, "paint: Floor entry should not create an object")

	session.target_layer = SessionScript.TargetLayer.STRUCTURE
	session.begin_stroke("paint floor while structure selected")
	_expect(session.apply_at(Vector3i(1, 0, 0)), "paint: Floor entry should keep routing to Floor from Structure")
	session.finish_stroke(null)
	_expect(floor_grid.get_cell_item(Vector3i(1, 0, 0)) == 1, "paint: manual Structure target should not redirect the Floor entry")
	_expect(structure_grid.get_cell_item(Vector3i(1, 0, 0)) < 0, "paint: manual Structure target should remain untouched")
	author.free()


func _test_noop_stroke_does_not_commit() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"library.floor"
	floor_definition.display_name = "Library Floor"
	floor_definition.placement_kind = 0
	floor_definition.target_layer = 0
	floor_definition.mesh_item_id = 0
	library.definitions = [floor_definition]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.select_placeable(0)
	session.begin_stroke("no-op")
	_expect(not session.apply_at(Vector3i(0, 0, 0)), "stroke: painting the existing identical cell should be a no-op")
	var undo_redo := UndoRedo.new()
	_expect(not session.finish_stroke(undo_redo), "stroke: no-op should not report a committed action")
	_expect(not undo_redo.has_undo(), "stroke: no-op should not create an Undo Action")
	undo_redo.free()
	author.free()


func _test_undo_snapshot_call_signature() -> void:
	var author := _make_author()
	var library := TacticalPlaceableLibrary.new()
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"library.undo_floor"
	floor_definition.display_name = "Undo Floor"
	floor_definition.placement_kind = 0
	floor_definition.target_layer = 0
	floor_definition.mesh_item_id = 1
	library.definitions = [floor_definition]
	author.placeable_library = library

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.select_placeable(0)
	session.begin_stroke("undo signature")
	_expect(session.apply_at(Vector3i(0, 0, 0)), "undo: synthetic change should apply")
	var undo_redo := UndoRedo.new()
	_expect(session.finish_stroke(undo_redo), "undo: changed stroke should commit")
	_expect(undo_redo.has_undo(), "undo: generic UndoRedo should contain the action")
	var floor_grid := author.get_node("FloorGrid") as GridMap
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 1, "undo: do snapshot should retain the new item")
	undo_redo.undo()
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 0, "undo: bound snapshot argument should restore the old item")
	undo_redo.redo()
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == 1, "undo: redo should reapply the new item")
	undo_redo.free()
	author.free()


func _test_object_snapshot_includes_facing() -> void:
	var author := _make_author()
	var objects := author.get_node("Objects")
	var marker := MapObjectMarker3D.new()
	marker.object_id = &"rotate_me"
	marker.kind = MapObjectPlacement.Kind.LOOT
	marker.cell = Vector3i(0, 0, 0)
	marker.facing = Vector2i.DOWN
	objects.add_child(marker)

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.target_layer = SessionScript.TargetLayer.OBJECT
	var before: Dictionary = session._capture_snapshot(Vector3i(0, 0, 0))
	marker.facing = Vector2i.RIGHT
	var after: Dictionary = session._capture_snapshot(Vector3i(0, 0, 0))
	_expect(not session._snapshot_equal(before, after), "snapshot: facing change should be undo-visible")
	author.free()


func _test_erase_validation_ignores_paint_selection() -> void:
	var author := _make_author()
	var structure_grid := author.get_node("StructureGrid") as GridMap
	structure_grid.set_cell_item(Vector3i(0, 0, 0), 1)
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.target_layer = SessionScript.TargetLayer.STRUCTURE
	session.selected_placeable.clear()
	var cell := Vector3i(0, 0, 0)
	_expect(not session.can_edit_cell(cell, SessionScript.Tool.PAINT).get("valid", false), "erase: paint should reject without a selected material")
	_expect(session.can_edit_cell(cell, SessionScript.Tool.ERASE).get("valid", false), "erase: in-bounds erase should remain valid without a selected material")
	session.set_tool(SessionScript.Tool.ERASE)
	session.begin_stroke("erase")
	_expect(session.apply_at(cell), "erase: existing structure should be removable")
	session.finish_stroke(null)
	_expect(structure_grid.get_cell_item(cell) < 0, "erase: StructureGrid cell should be cleared")
	author.free()


func _test_next_object_id_scans_existing_markers() -> void:
	var author := _make_author()
	var objects := author.get_node("Objects") as Node
	for object_id in [&"crate_001", &"crate_002", &"crate_004"]:
		var marker := MapObjectMarker3D.new()
		marker.object_id = object_id
		objects.add_child(marker)

	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var first_id: StringName = session._next_object_id("crate")
	_expect(first_id == &"crate_003", "object id: existing IDs should force the first available suffix")
	var new_marker := MapObjectMarker3D.new()
	new_marker.object_id = first_id
	objects.add_child(new_marker)
	var second_id: StringName = session._next_object_id("crate")
	_expect(second_id == &"crate_005", "object id: a newly occupied suffix should be skipped")
	author.free()


func _test_selection_is_deterministic_and_clears_on_floor_change() -> void:
	var author := _make_author()
	author.level_count = 2
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var floor_grid := author.get_node("FloorGrid") as GridMap
	var before_item := floor_grid.get_cell_item(Vector3i(0, 0, 0))
	var empty_cell := Vector3i(0, 0, 0)
	floor_grid.set_cell_item(empty_cell, -1)
	_expect(not session.select_cell(empty_cell), "selection: an empty Floor coordinate should be rejected")
	_expect(session.get_selected_cells().is_empty(), "selection: an empty Floor coordinate must not enter selected_cells")
	_expect(session.get_last_status().get("valid", true) == false and String(session.get_last_status().get("message", "")).contains("Floor"), "selection: empty Floor rejection should expose a clear status reason")
	_expect(floor_grid.get_cell_item(empty_cell) < 0, "selection: rejected selection must not mutate the existing GridMap")
	floor_grid.set_cell_item(empty_cell, before_item)
	_expect(session.select_cell(Vector3i(1, 0, 0)), "selection: single click should select one cell")
	_expect(session.select_cell(Vector3i(0, 0, 0), true, true), "selection: Shift click should extend selection")
	var selected := session.get_selected_cells()
	_expect(selected.size() == 2, "selection: Shift click should keep both selected cells")
	_expect(selected[0] == Vector3i(0, 0, 0) and selected[1] == Vector3i(1, 0, 0), "selection: cells should have deterministic x/z/y ordering")
	_expect(floor_grid.get_cell_item(Vector3i(0, 0, 0)) == before_item, "selection: selecting cells must not modify GridMap")
	_expect(session.select_cell(Vector3i(0, 0, 0), true, true), "selection: Shift click on selected cell should toggle it")
	_expect(session.get_selected_cells().size() == 1 and session.is_cell_selected(Vector3i(1, 0, 0)), "selection: toggled cell should be removed")
	session.set_floor_level(1)
	_expect(session.get_selected_cells().is_empty(), "selection: changing floor should clear cells from the old floor")
	author.free()


func _test_property_override_batch_undo_and_inherit() -> void:
	var author := _make_author()
	var catalog := MapTileCatalog.new()
	var floor_rule := _legacy_rule(0, 0, &"floor")
	floor_rule.walkable = true
	floor_rule.move_cost = 1
	floor_rule.blocks_los = false
	floor_rule.occluder_height = 0.25
	catalog.rules = [floor_rule]
	author.tile_catalog = catalog
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	session.select_cell(Vector3i(0, 0, 0))
	session.select_cell(Vector3i(1, 0, 0), true, false)
	var undo_redo := UndoRedo.new()
	_expect(session.write_property_override(&"MOVE_COST", 3, [], undo_redo), "property: batch write should change selected cells")
	var summary: Dictionary = session.get_selected_property_summary()
	_expect(summary[&"MOVE_COST"].get("state") == "覆盖", "property: batch write should report override state")
	_expect(summary[&"MOVE_COST"].get("value") == 3, "property: batch write should expose the final value")
	_expect(summary[&"MOVE_COST"].get("base") == 1 and summary[&"MOVE_COST"].get("base_display") == "1", "property: summary should expose the common formal-service base value")
	_expect(summary[&"MOVE_COST"].get("override") == 3 and summary[&"MOVE_COST"].get("override_display") == "3", "property: summary should expose the common override value")
	_expect(author.authoring_data != null, "property: formal service should create authoring data on first write")
	_expect(author.authoring_data != null and author.authoring_data.find_cell_override(Vector3i(0, 0, 0)) != null, "property: formal service should persist the first cell override")
	_expect(author.authoring_data != null and author.authoring_data.find_cell_override(Vector3i(1, 0, 0)) != null, "property: formal service should persist the second cell override")
	_expect(undo_redo.has_undo(), "property: batch write should create one generic Undo action")
	undo_redo.undo()
	summary = session.get_selected_property_summary()
	_expect(summary[&"MOVE_COST"].get("state") == "继承", "property: undo should restore inheritance")
	_expect(summary[&"MOVE_COST"].get("value") == 1, "property: undo should restore the inherited value")
	_expect(author.authoring_data == null, "property: undo should restore null authoring_data when the first edit created it")
	undo_redo.redo()
	_expect(session.get_selected_property_summary()[&"MOVE_COST"].get("value") == 3, "property: redo should restore the batch override")
	_expect(author.authoring_data != null and author.authoring_data.find_cell_override(Vector3i(0, 0, 0)) != null and author.authoring_data.find_cell_override(Vector3i(1, 0, 0)) != null, "property: redo should recreate authoring_data and restore both persisted records")
	_expect(not session.write_property_override(&"MOVE_COST", 0), "property: formal service should reject an invalid value")
	_expect(not session.get_last_status().get("valid", true) and String(session.get_last_status().get("message", "")).contains("失败"), "property: rejected service mutation should expose a failure status")
	_expect(session.write_property_override(&"WALKABLE", false, [Vector3i(0, 0, 0)]), "property: single-cell override should succeed")
	summary = session.get_selected_property_summary()
	_expect(summary[&"WALKABLE"].get("state") == "混合", "property: mixed inherited/override cells should show mixed state")
	_expect(summary[&"WALKABLE"].get("mixed"), "property: differing final values should show mixed value")
	_expect(summary[&"WALKABLE"].get("base_display") == "是" and summary[&"WALKABLE"].get("override_display") == "混合", "property: mixed summary should preserve common base and mixed override display")
	_expect(session.clear_property_override(&"WALKABLE", [Vector3i(0, 0, 0)]), "property: restoring one cell should clear only that field override")
	_expect(session.get_selected_property_summary()[&"WALKABLE"].get("state") == "继承", "property: restoring inheritance should return all cells to inherited state")
	undo_redo.free()

	var retained_author := _make_author()
	retained_author.tile_catalog = catalog
	retained_author.authoring_data = TacticalMapAuthoringData.new()
	var retained_session = SessionScript.new()
	retained_session.begin_for_author(retained_author, retained_author)
	retained_session.select_cell(Vector3i(0, 0, 0))
	var retained_undo := UndoRedo.new()
	_expect(retained_session.write_property_override(&"MOVE_COST", 4, [], retained_undo), "property: edit with a pre-existing empty authoring Resource should succeed")
	retained_undo.undo()
	_expect(retained_author.authoring_data != null and retained_author.authoring_data.is_empty(), "property: undo must retain a pre-existing empty authoring Resource")
	retained_undo.redo()
	_expect(retained_author.authoring_data != null and retained_author.authoring_data.find_cell_override(Vector3i(0, 0, 0)) != null, "property: redo must restore the pre-existing Resource override")
	retained_undo.free()
	retained_author.free()
	author.free()


func _test_debug_views_validation_and_focus() -> void:
	var author := _make_author()
	var catalog := MapTileCatalog.new()
	catalog.rules = [_legacy_rule(0, 0, &"floor"), _legacy_rule(1, 1, &"wall")]
	author.tile_catalog = catalog
	var structure_grid := author.get_node("StructureGrid") as GridMap
	structure_grid.set_cell_item(Vector3i(0, 0, 0), 1)
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	for view in range(SessionScript.DebugView.NORMAL, SessionScript.DebugView.VALIDATION + 1):
		session.set_debug_view(view)
		_expect(session.get_debug_view() == view, "debug: view enum should remain stable")
		_expect(not session.debug_view_name().is_empty() and not session.debug_view_legend().is_empty(), "debug: every view should expose a name and legend")
	var inspection := session.inspect_debug_cells()
	_expect(inspection.has("cells"), "debug: formal inspect_all_cells result should expose cells")
	_expect((inspection.get("cells", []) as Array).size() == 2, "debug: formal all-cell inspection should include both Floor cells")
	var diagnostics := session.get_validation_diagnostics()
	for diagnostic in diagnostics:
		_expect(diagnostic is Dictionary and diagnostic.has("severity") and diagnostic.has("message"), "debug: validation entries must remain structured")
	_expect(session.select_cell(Vector3i(0, 0, 0)), "debug: a real Floor cell should be selectable for focus")
	_expect(session.set_debug_focus(Vector3i(1, 0, 0)), "debug: valid Floor cell should accept a debug focus")
	_expect(session.debug_focus_cell == Vector3i(1, 0, 0), "debug: focus state should retain the structured coordinate")
	var floor_grid := author.get_node("FloorGrid") as GridMap
	var old_item := floor_grid.get_cell_item(Vector3i(0, 0, 0))
	floor_grid.set_cell_item(Vector3i(0, 0, 0), -1)
	var empty_cell := Vector3i(0, 0, 0)
	var has_missing_floor_diagnostic := false
	for diagnostic in session.get_validation_diagnostics():
		if diagnostic.get("coordinate", null) == empty_cell:
			has_missing_floor_diagnostic = true
			break
	_expect(has_missing_floor_diagnostic, "debug: missing-Floor coordinate should come from a structured diagnostic")
	_expect(not session.select_cell(empty_cell), "debug: ordinary selection must still reject an empty Floor coordinate")
	_expect(not session.set_debug_focus(Vector3i(0, 0, 0)), "debug: empty Floor coordinate must not become a focus target")
	_expect(session.debug_focus_cell == Vector3i(1, 0, 0), "debug: rejected focus must preserve the previous focus")
	_expect(session.focus_validation_cell(empty_cell), "debug: structured missing-Floor coordinate should be focusable")
	_expect(session.get_debug_focus_cell() == empty_cell, "debug: validation focus should retain a missing-Floor coordinate")
	var validation_records := session.get_debug_cells_for_view(SessionScript.DebugView.VALIDATION)
	var heatmap_records := session.get_debug_cells_for_view(SessionScript.DebugView.WALKABILITY)
	var validation_only_found := false
	var heatmap_missing_found := false
	for record in validation_records:
		if record.get("coordinate", null) == empty_cell:
			validation_only_found = bool(record.get("validation_only", false))
			break
	for record in heatmap_records:
		if record.get("coordinate", null) == empty_cell:
			heatmap_missing_found = true
			break
	_expect(validation_only_found, "debug: Validation view should include the missing-Floor diagnostic record")
	_expect(not heatmap_missing_found, "debug: heatmap views must exclude validation-only coordinates")
	floor_grid.set_cell_item(Vector3i(0, 0, 0), old_item)
	author.free()


func _test_legacy_default_descriptor_constraints() -> void:
	var author := _make_author()
	var legacy_rule := _legacy_rule(0, 1, &"legacy_floor")
	legacy_rule.blocks_los = true
	var catalog := MapTileCatalog.new()
	catalog.rules = [legacy_rule]
	author.tile_catalog = catalog
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var legacy_index := _find_placeable(session.get_placeables(), "catalog:0:1")
	_expect(legacy_index >= 0, "default: legacy catalog entry should be selectable")
	if legacy_index >= 0:
		session.select_placeable(legacy_index)
		var legacy_context := session.get_default_property_context()
		var legacy_descriptor: Dictionary = legacy_context.get("descriptors", {}).get(&"SIGHT_BLOCK", {})
		var legacy_allowed: Array = legacy_descriptor.get("allowed_values", [])
		_expect(legacy_allowed.size() == 2 and is_equal_approx(float(legacy_allowed[0]), 0.0) and is_equal_approx(float(legacy_allowed[1]), 1.0), "default: legacy sight descriptor should expose only 0/1")
		_expect(is_equal_approx(float(legacy_descriptor.get("step", 0.0)), 1.0), "default: legacy sight descriptor should use step 1")
		_expect(not session.write_default_property(&"SIGHT_BLOCK", 0.5), "default: legacy sight mutation must reject fractional values")

	var definition := TacticalCellTileDefinition.new()
	definition.placeable_id = &"formal.sight"
	definition.display_name = "Formal Sight"
	definition.placement_kind = 0
	definition.target_layer = 0
	definition.mesh_item_id = 1
	var library := TacticalPlaceableLibrary.new()
	library.definitions = [definition]
	author.placeable_library = library
	session.begin_for_author(author, author)
	var formal_context := session.get_default_property_context()
	var formal_descriptor: Dictionary = formal_context.get("descriptors", {}).get(&"SIGHT_BLOCK", {})
	_expect(is_equal_approx(float(formal_descriptor.get("step", 0.0)), 0.01), "default: formal definition should restore sight step 0.01")
	_expect(Array(formal_descriptor.get("allowed_values", [])).is_empty(), "default: formal definition should not retain legacy binary choices")
	author.free()


func _test_default_property_service_undo_and_null_restore() -> void:
	var author := _make_author()
	var definition := TacticalCellTileDefinition.new()
	definition.placeable_id = &"default.null_contribution"
	definition.display_name = "Null Contribution"
	definition.placement_kind = 0
	definition.target_layer = 0
	definition.mesh_item_id = 1
	var library := TacticalPlaceableLibrary.new()
	library.definitions = [definition]
	author.placeable_library = library
	var session = SessionScript.new()
	session.begin_for_author(author, author)
	var context := session.get_default_property_context()
	_expect(bool(context.get("available", false)), "default: formal source inspection should mark a cell definition available")
	_expect(bool(context.get("supported", {}).get(&"SIGHT_BLOCK", false)), "default: TacticalCellRules source should support sight blocking")
	_expect(definition.rule_contribution == null, "default: fixture should start without rule_contribution")
	var undo_redo := UndoRedo.new()
	_expect(session.write_default_property(&"MOVE_COST", 4, undo_redo), "default: formal service mutation should succeed")
	_expect(definition.rule_contribution != null and definition.rule_contribution.move_cost == 4, "default: do state should create and write rule_contribution")
	undo_redo.undo()
	_expect(definition.rule_contribution == null, "default: undo must restore a null rule_contribution exactly")
	undo_redo.redo()
	_expect(definition.rule_contribution != null and definition.rule_contribution.move_cost == 4, "default: redo should recreate the contribution")
	var restore_undo := UndoRedo.new()
	_expect(session.restore_default_property(&"MOVE_COST", restore_undo), "default: restore should be a formal undoable action")
	_expect(definition.rule_contribution == null, "default: restore action should return to the captured baseline")
	restore_undo.undo()
	_expect(definition.rule_contribution != null and definition.rule_contribution.move_cost == 4, "default: undoing restore should recover the edited contribution")
	undo_redo.free()
	restore_undo.free()
	author.free()


func _make_author() -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"editor_session_synthetic"
	author.footprint_size = Vector2i(2, 1)
	author.level_count = 1
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	var mesh_library := MeshLibrary.new()
	for item_id in range(5):
		mesh_library.create_item(item_id)
	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = mesh_library
	floor_grid.cell_size = author.cell_dimensions
	floor_grid.set_cell_item(Vector3i(0, 0, 0), 0)
	floor_grid.set_cell_item(Vector3i(1, 0, 0), 0)
	author.add_child(floor_grid)
	var structure_grid := GridMap.new()
	structure_grid.name = "StructureGrid"
	structure_grid.mesh_library = mesh_library
	structure_grid.cell_size = author.cell_dimensions
	author.add_child(structure_grid)
	var objects := Node3D.new()
	objects.name = "Objects"
	author.add_child(objects)
	return author


func _legacy_rule(layer: int, item_id: int, tile_id: StringName) -> MapTileRule:
	var rule := MapTileRule.new()
	rule.layer = layer
	rule.item_id = item_id
	rule.tile_id = tile_id
	return rule


func _find_placeable(entries: Array, placeable_id: String) -> int:
	for index in range(entries.size()):
		if String(entries[index].get("id", "")) == placeable_id:
			return index
	return -1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_EDITOR_SESSION_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_EDITOR_SESSION_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
