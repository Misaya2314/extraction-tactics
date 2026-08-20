extends SceneTree

## Property-service tests use only a small synthetic legacy author. They do
## not depend on any production map layout, cell count, or fixed coordinates.

var _failures: Array[String] = []
var _service_signal_count: int = 0
var _resource_signal_count: int = 0


func _init() -> void:
	_test_field_descriptors()
	_test_inspection_uses_baker_authority()
	_test_override_editing_and_snapshots()
	_test_authoring_data_presence_snapshots()
	_test_default_sources_and_all_cells()
	_test_structured_diagnostics()
	_test_save_diagnostics()
	_test_invalid_cells_and_legacy_compatibility()
	_finish()


func _test_field_descriptors() -> void:
	var service := TacticalMapPropertyService.new()
	var descriptors := service.field_descriptors()
	var required := [
		TacticalCellOverride.Field.WALKABLE,
		TacticalCellOverride.Field.MOVE_COST,
		TacticalCellOverride.Field.SIGHT_BLOCK,
		TacticalCellOverride.Field.PROJECTILE_BLOCK,
		TacticalCellOverride.Field.OCCLUDER_HEIGHT,
	]
	for field in required:
		var found := false
		for descriptor in descriptors:
			if int(descriptor[&"bit"]) == field:
				found = true
				_expect(descriptor.has(&"id") and descriptor.has(&"label") and descriptor.has(&"type"), "descriptors: field metadata is complete")
		_expect(found, "descriptors: required field bit %d should be exposed" % field)


func _test_inspection_uses_baker_authority() -> void:
	var author := _make_legacy_author()
	var service := TacticalMapPropertyService.new()
	var coordinates: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(8, 0, 0)]
	var inspected_result := service.inspect_cells(author, coordinates)
	var inspected: Array[Dictionary] = inspected_result[&"cells"]
	_expect(inspected.size() == 3, "inspect: duplicate coordinates should be removed")
	_expect(inspected[0][&"coordinate"] == Vector3i(0, 0, 0), "inspect: coordinates should be stably sorted")
	_expect(inspected[1][&"coordinate"] == Vector3i(1, 0, 0), "inspect: sorted second coordinate should be present")
	_expect(not inspected[2][&"exists"], "inspect: out-of-volume cell should be reported as absent")
	_expect(inspected[0][&"has_floor"] and inspected[0][&"has_structure"], "inspect: Floor and Structure content should be exposed")
	_expect(inspected[0][&"floor"][&"item_id"] == 0 and inspected[0][&"structure"][&"item_id"] == 1, "inspect: legacy content identifiers should retain item IDs")
	_expect(inspected[0][&"floor"][&"source"] == &"legacy_catalog", "inspect: legacy source should be explicit")
	_expect(inspected_result[&"summary"][&"mixed_fields"].has("move_cost"), "inspect: mixed multi-selection should expose differing effective values")

	var baked_result := TacticalMapBaker.build(author)
	_expect(baked_result[&"errors"].is_empty(), "authority: synthetic legacy map should bake")
	for item in inspected:
		if not bool(item[&"exists"]):
			continue
		var baked_cell := _find_cell(baked_result[&"definition"], item[&"coordinate"])
		_expect(baked_cell != null, "authority: inspected existing cell should be in baked definition")
		if baked_cell != null:
			_expect_rules_match(item[&"effective_rules"], baked_cell, "authority: inspect effective rules should match Baker output")

	var catalog: MapTileCatalog = author.tile_catalog
	var floor_rule := catalog.find_rule(MapTileRule.Layer.FLOOR, 0)
	var structure_rule := catalog.find_rule(MapTileRule.Layer.STRUCTURE, 1)
	floor_rule.move_cost = 3
	structure_rule.move_cost = 6
	var changed_defaults := service.inspect_cells(author, [Vector3i(0, 0, 0), Vector3i(1, 0, 0)])
	var changed_first: Dictionary = _inspection_for(changed_defaults[&"cells"], Vector3i(0, 0, 0))
	var changed_second: Dictionary = _inspection_for(changed_defaults[&"cells"], Vector3i(1, 0, 0))
	_expect((changed_first[&"effective_rules"] as TacticalCellRules).move_cost == 6, "authority: legacy structure rule changes should affect unoverridden cell")
	_expect((changed_second[&"effective_rules"] as TacticalCellRules).move_cost == 3, "authority: legacy Floor rule changes should affect unoverridden cell")
	_test_each_field_matches_baker()

	var library_author := _make_legacy_author()
	library_author.tile_catalog = null
	var library := TacticalPlaceableLibrary.new()
	var library_floor := _make_cell_definition(&"property.floor", MapTileRule.Layer.FLOOR, 0, &"library_floor", true, 2, 0.0, 0.0)
	var library_wall := _make_cell_definition(&"property.wall", MapTileRule.Layer.STRUCTURE, 1, &"library_wall", false, 4, 1.0, 1.0)
	library.definitions = [library_floor, library_wall]
	library.item_bindings = [_make_binding(library_floor), _make_binding(library_wall)]
	library_author.placeable_library = library
	var library_before := service.inspect_cells(library_author, [Vector3i(1, 0, 0)])
	_expect((library_before[&"cells"][0][&"effective_rules"] as TacticalCellRules).move_cost == 2, "authority: library contribution should be queryable without Catalog")
	library_floor.rule_contribution.move_cost = 5
	var library_after := service.inspect_cells(library_author, [Vector3i(1, 0, 0)])
	_expect((library_after[&"cells"][0][&"effective_rules"] as TacticalCellRules).move_cost == 5, "authority: default Definition change should affect an unoverridden cell")


func _test_override_editing_and_snapshots() -> void:
	var author := _make_legacy_author()
	var service := TacticalMapPropertyService.new()
	_service_signal_count = 0
	_resource_signal_count = 0
	service.authoring_data_changed.connect(_on_authoring_data_changed)
	author.authoring_data = TacticalMapAuthoringData.new()
	author.authoring_data.changed.connect(_on_resource_changed)

	_expect(service.apply_override_field(author, [Vector3i(1, 0, 0), Vector3i(1, 0, 0)], TacticalCellOverride.Field.MOVE_COST, 7), "override: first explicit field should apply")
	_expect(_service_signal_count == 1 and _resource_signal_count > 0, "override: service and Resource changed signals should fire (service=%d resource=%d)" % [_service_signal_count, _resource_signal_count])
	_expect(not service.apply_override_field(author, [Vector3i(1, 0, 0)], TacticalCellOverride.Field.MOVE_COST, 7), "override: identical value should be a no-op")
	var after_move := service.inspect_cells(author, [Vector3i(0, 0, 0), Vector3i(1, 0, 0)])
	var first: Dictionary = _inspection_for(after_move[&"cells"], Vector3i(0, 0, 0))
	var second: Dictionary = _inspection_for(after_move[&"cells"], Vector3i(1, 0, 0))
	_expect(int(second[&"override_mask"]) == TacticalCellOverride.Field.MOVE_COST, "override: only selected bit should be present")
	_expect((second[&"effective_rules"] as TacticalCellRules).move_cost == 7, "override: effective selected value should be applied")
	_expect((first[&"effective_rules"] as TacticalCellRules).move_cost != 7, "override: single-cell edit must not affect another cell")

	var snapshot := service.capture_override_state(author, [Vector3i(1, 0, 0), Vector3i(0, 0, 0), Vector3i(1, 0, 0)])
	_expect(snapshot.size() == 2 and snapshot[0][&"coordinate"] == Vector3i(0, 0, 0), "snapshot: coordinates should be deduplicated and sorted")
	_expect(not bool(snapshot[0][&"present"]) and bool(snapshot[1][&"present"]), "snapshot: absent and present override states should be distinguishable")
	_expect(service.apply_override_field(author, [Vector3i(0, 0, 0), Vector3i(1, 0, 0)], TacticalCellOverride.Field.OCCLUDER_HEIGHT, 2.0), "override: second field should apply to both selected cells")
	_expect(service.restore_override_state(author, snapshot), "snapshot: restore should report a real change")
	var restored := service.inspect_cells(author, [Vector3i(0, 0, 0), Vector3i(1, 0, 0)])
	var restored_first: Dictionary = _inspection_for(restored[&"cells"], Vector3i(0, 0, 0))
	var restored_second: Dictionary = _inspection_for(restored[&"cells"], Vector3i(1, 0, 0))
	_expect(int(restored_first[&"override_mask"]) == 0, "snapshot: restore should remove an override that was absent in the snapshot")
	_expect(int(restored_second[&"override_mask"]) == TacticalCellOverride.Field.MOVE_COST, "snapshot: restore should preserve the captured mask")
	_expect((restored_second[&"effective_rules"] as TacticalCellRules).move_cost == 7, "snapshot: restore should preserve captured values")

	_expect(service.clear_override_field(author, [Vector3i(1, 0, 0)], TacticalCellOverride.Field.MOVE_COST), "override: clear selected bit should succeed")
	_expect(author.authoring_data.find_cell_override(Vector3i(1, 0, 0)) == null, "override: clearing the final bit should remove the empty record")
	_expect(not service.clear_override_field(author, [Vector3i(1, 0, 0)], TacticalCellOverride.Field.MOVE_COST), "override: clearing an absent bit should be a no-op")

	var auto_author := _make_legacy_author()
	_expect(auto_author.authoring_data == null, "override: synthetic author should begin without authoring data")
	_expect(service.apply_override_field(auto_author, [Vector3i(1, 0, 0)], TacticalCellOverride.Field.SIGHT_BLOCK, 0.5), "override: service should auto-create authoring data")
	_expect(auto_author.authoring_data != null and auto_author.authoring_data.find_cell_override(Vector3i(1, 0, 0)) != null, "override: auto-created state should be stored on author")


func _test_invalid_cells_and_legacy_compatibility() -> void:
	var service := TacticalMapPropertyService.new()
	var null_result := service.inspect_cells(null, [Vector3i.ZERO])
	_expect(not null_result[&"errors"].is_empty(), "invalid: null author should return diagnostics")
	var author := _make_legacy_author()
	var floor_grid: GridMap = author.get_node("FloorGrid")
	floor_grid.set_cell_item(Vector3i(1, 0, 0), -1)
	var no_floor := service.inspect_cells(author, [Vector3i(1, 0, 0)])
	var no_floor_cell: Dictionary = no_floor[&"cells"][0]
	_expect(not bool(no_floor_cell[&"exists"]) and not bool(no_floor_cell[&"has_floor"]), "invalid: missing Floor should be reported as absent")
	_expect(_contains_fragment(no_floor_cell[&"errors"], "no Floor"), "invalid: missing Floor should have a stable diagnostic")
	_expect(not service.apply_override_field(author, [Vector3i(0, 0, 0), Vector3i(1, 0, 0)], TacticalCellOverride.Field.MOVE_COST, 5), "invalid: mixed valid/missing selection should be atomic and rejected")
	_expect(author.authoring_data == null, "invalid: rejected selection must not create authoring data")
	_expect(not service.apply_override_field(author, [Vector3i(99, 0, 0)], TacticalCellOverride.Field.MOVE_COST, 5), "invalid: out-of-volume edit should be rejected")
	_expect(not service.apply_override_field(author, [Vector3i(0, 0, 0)], TacticalCellOverride.Field.MOVE_COST, 0), "invalid: field value outside descriptor range should be rejected")


func _test_authoring_data_presence_snapshots() -> void:
	var service := TacticalMapPropertyService.new()
	var author := _make_legacy_author()
	_service_signal_count = 0
	service.authoring_data_changed.connect(_on_authoring_data_changed)
	var before := service.capture_override_state(author, [Vector3i(1, 0, 0)])
	_expect(not bool(before[0][&"authoring_data_present"]), "snapshot presence: null authoring_data should be captured")
	_expect(service.apply_override_field(author, [Vector3i(1, 0, 0)], TacticalCellOverride.Field.MOVE_COST, 7), "snapshot presence: initial edit should create data")
	var after := service.capture_override_state(author, [Vector3i(1, 0, 0)])
	_expect(bool(after[0][&"authoring_data_present"]) and bool(after[0][&"present"]), "snapshot presence: after state should record created data and override")
	_expect(service.restore_override_state(author, before), "snapshot presence: undo to null state should succeed")
	_expect(author.authoring_data == null, "snapshot presence: undo should restore null authoring_data")
	_expect(service.restore_override_state(author, after), "snapshot presence: redo should succeed from null")
	_expect(author.authoring_data != null and author.authoring_data.find_cell_override(Vector3i(1, 0, 0)) != null, "snapshot presence: redo should recreate authoring_data and override")
	_expect(_service_signal_count >= 3, "snapshot presence: apply/undo/redo should emit service changes")

	var empty_author := _make_legacy_author()
	empty_author.authoring_data = TacticalMapAuthoringData.new()
	var empty_before := service.capture_override_state(empty_author, [Vector3i(1, 0, 0)])
	_expect(bool(empty_before[0][&"authoring_data_present"]) and not bool(empty_before[0][&"present"]), "snapshot presence: empty Resource should be distinguished from null")
	_expect(service.apply_override_field(empty_author, [Vector3i(1, 0, 0)], TacticalCellOverride.Field.SIGHT_BLOCK, 0.5), "snapshot presence: edit on pre-existing empty Resource should succeed")
	_expect(service.restore_override_state(empty_author, empty_before), "snapshot presence: undo on pre-existing empty Resource should succeed")
	_expect(empty_author.authoring_data != null and empty_author.authoring_data.is_empty(), "snapshot presence: pre-existing empty Resource must remain present")

	var retained_author := _make_legacy_author()
	var retained_before := service.capture_override_state(retained_author, [Vector3i(1, 0, 0)])
	_expect(service.apply_override_field(retained_author, [Vector3i(1, 0, 0)], TacticalCellOverride.Field.MOVE_COST, 7), "snapshot presence: retained-data selected edit should succeed")
	_expect(service.apply_override_field(retained_author, [Vector3i(0, 0, 0)], TacticalCellOverride.Field.SIGHT_BLOCK, 0.5), "snapshot presence: retained-data non-selected edit should succeed")
	var retained_edge := TacticalEdgePlacement.new()
	retained_edge.edge_key = TacticalEdgeKey.from_cells(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
	retained_author.authoring_data.edge_placements.append(retained_edge)
	_expect(service.restore_override_state(retained_author, retained_before), "snapshot presence: undo with non-selected data should succeed")
	_expect(retained_author.authoring_data != null, "snapshot presence: non-selected authoring data must not be nulled")
	_expect(retained_author.authoring_data.find_cell_override(Vector3i(0, 0, 0)) != null and not retained_author.authoring_data.edge_placements.is_empty(), "snapshot presence: non-selected override/edge must remain")


func _test_default_sources_and_all_cells() -> void:
	var service := TacticalMapPropertyService.new()
	var author := _make_legacy_author()
	var all_cells := service.inspect_all_cells(author)
	_expect(all_cells[&"cells"].size() == 2, "all cells: should return every valid Floor cell")
	_expect(all_cells[&"cells"][0][&"coordinate"] == Vector3i(0, 0, 0) and all_cells[&"cells"][1][&"coordinate"] == Vector3i(1, 0, 0), "all cells: should use stable coordinate order")
	_expect(all_cells[&"errors"].is_empty(), "all cells: valid synthetic author should have no compile errors")

	var floor_rule: MapTileRule = author.tile_catalog.find_rule(MapTileRule.Layer.FLOOR, 0)
	var legacy_inspection := service.inspect_default_source(floor_rule)
	_expect(legacy_inspection[&"valid"] and legacy_inspection[&"source_kind"] == &"legacy", "default legacy: source should be inspectable")
	var projectile_info: Dictionary = _default_field(legacy_inspection, TacticalCellOverride.Field.PROJECTILE_BLOCK)
	_expect(not projectile_info[&"field_supported"] and String(projectile_info[&"reason"]).contains("no independent projectile_block"), "default legacy: projectile limitation should be explicit")
	var sight_info: Dictionary = _default_field(legacy_inspection, TacticalCellOverride.Field.SIGHT_BLOCK)
	_expect(sight_info[&"field_supported"] and String(sight_info[&"reason"]).contains("only"), "default legacy: sight limitation should be explicit")
	_expect(is_equal_approx(float(sight_info[&"step"]), 1.0), "default legacy: sight descriptor should use binary step")
	_expect(sight_info.get(&"constraint", &"") == &"binary", "default legacy: sight descriptor should expose binary constraint")
	_expect(sight_info.get(&"allowed_values", []).has(0.0) and sight_info.get(&"allowed_values", []).has(1.0), "default legacy: sight descriptor should expose only 0/1 values")
	_expect(not service.apply_default_field(floor_rule, TacticalCellOverride.Field.PROJECTILE_BLOCK, 1.0), "default legacy: unsupported projectile field must not mutate")
	_expect(not service.apply_default_field(floor_rule, TacticalCellOverride.Field.SIGHT_BLOCK, 0.5), "default legacy: partial sight value must be rejected")
	_expect(service.apply_default_field(floor_rule, TacticalCellOverride.Field.SIGHT_BLOCK, 1.0), "default legacy: complete sight block should map to blocks_los")
	_expect(floor_rule.blocks_los, "default legacy: complete sight block should set blocks_los")
	_expect(service.apply_default_field(floor_rule, TacticalCellOverride.Field.SIGHT_BLOCK, 0.0), "default legacy: absent sight block should map back")
	_expect(not floor_rule.blocks_los, "default legacy: zero sight block should clear blocks_los")

	var before_legacy_default := service.capture_default_state(floor_rule)
	_expect(service.apply_default_field(floor_rule, TacticalCellOverride.Field.MOVE_COST, 6), "default legacy: supported field should mutate")
	var before_override := service.apply_override_field(author, [Vector3i(1, 0, 0)], TacticalCellOverride.Field.MOVE_COST, 9)
	_expect(before_override, "default propagation: instance override should apply")
	var propagated := service.inspect_all_cells(author)
	_expect((propagated[&"cells"][0][&"effective_rules"] as TacticalCellRules).move_cost == 6, "default propagation: unoverridden structure cell should see new Floor default")
	_expect((propagated[&"cells"][1][&"effective_rules"] as TacticalCellRules).move_cost == 9, "default propagation: overridden cell should retain explicit value")
	_expect(service.restore_default_state(floor_rule, before_legacy_default), "default legacy: restore should undo the default transaction")

	var formal_author := _make_legacy_author()
	formal_author.tile_catalog = null
	var library := TacticalPlaceableLibrary.new()
	var formal_floor := _make_cell_definition(&"default.floor", MapTileRule.Layer.FLOOR, 0, &"default_floor", true, 2, 0.0, 0.0)
	var formal_wall := _make_cell_definition(&"default.wall", MapTileRule.Layer.STRUCTURE, 1, &"default_wall", false, 4, 1.0, 1.0)
	formal_floor.rule_contribution = null
	library.definitions = [formal_floor, formal_wall]
	library.item_bindings = [_make_binding(formal_floor), _make_binding(formal_wall)]
	formal_author.placeable_library = library
	var formal_inspection := service.inspect_default_source(formal_floor)
	var formal_sight_info: Dictionary = _default_field(formal_inspection, TacticalCellOverride.Field.SIGHT_BLOCK)
	_expect(is_equal_approx(float(formal_sight_info[&"step"]), 0.01), "default definition: formal sight descriptor should retain fractional step")
	_expect(not formal_sight_info.has(&"constraint"), "default definition: formal sight descriptor should not be binary constrained")
	var formal_before := service.capture_default_state(formal_floor)
	_expect(not bool(formal_before[&"rule_contribution_present"]), "default definition: null rule contribution should be captured")
	_expect(service.apply_default_field(formal_floor, TacticalCellOverride.Field.MOVE_COST, 6), "default definition: null rule contribution should auto-create")
	_expect(formal_floor.rule_contribution != null, "default definition: apply should create rule contribution")
	_expect(service.apply_override_field(formal_author, [Vector3i(1, 0, 0)], TacticalCellOverride.Field.MOVE_COST, 8), "default definition: instance override should apply")
	var formal_effective := service.inspect_all_cells(formal_author)
	_expect((formal_effective[&"cells"][0][&"effective_rules"] as TacticalCellRules).move_cost == 6, "default definition: unoverridden cell should use definition default")
	_expect((formal_effective[&"cells"][1][&"effective_rules"] as TacticalCellRules).move_cost == 8, "default definition: instance override should win over definition default")
	_expect(service.restore_default_state(formal_floor, formal_before), "default definition: restore should succeed")
	_expect(formal_floor.rule_contribution == null, "default definition: restore should recover null contribution")


func _test_structured_diagnostics() -> void:
	var author := _make_legacy_author()
	var floor_grid: GridMap = author.get_node("FloorGrid")
	var structure_grid: GridMap = author.get_node("StructureGrid")
	floor_grid.set_cell_item(Vector3i(8, 0, 0), 0)
	floor_grid.set_cell_item(Vector3i(1, 0, 0), -1)
	structure_grid.set_cell_item(Vector3i(8, 0, 0), 1)
	structure_grid.set_cell_item(Vector3i(1, 0, 0), 1)
	var orphan_data := TacticalMapAuthoringData.new()
	var orphan := TacticalCellOverride.new()
	orphan.coordinate = Vector3i(7, 0, 0)
	orphan.override_mask = TacticalCellOverride.Field.MOVE_COST
	orphan.values = TacticalCellRules.new()
	orphan.values.move_cost = 5
	orphan_data.cell_overrides.append(orphan)
	author.authoring_data = orphan_data
	var extraction: MapObjectMarker3D = _find_object_marker(author)
	_expect(extraction != null, "diagnostics: synthetic extraction marker should exist")
	if extraction == null:
		return
	extraction.cell = Vector3i(9, 0, 0)
	var bad_spawn := UnitSpawnMarker3D.new()
	bad_spawn.unit_name = &"BadSpawn"
	bad_spawn.faction = "player"
	bad_spawn.cell = Vector3i(9, 0, 0)
	author.add_child(bad_spawn)
	var duplicate_spawn := UnitSpawnMarker3D.new()
	duplicate_spawn.unit_name = &"DuplicateSpawn"
	duplicate_spawn.faction = "enemy"
	duplicate_spawn.cell = Vector3i(1, 0, 0)
	author.add_child(duplicate_spawn)
	var bad_object := MapObjectMarker3D.new()
	bad_object.object_id = &"BadObject"
	bad_object.kind = MapObjectPlacement.Kind.GENERIC
	bad_object.cell = Vector3i(8, 0, 0)
	author.add_child(bad_object)
	var traversal := TraversalLink3D.new()
	traversal.from_cell = Vector3i(0, 0, 0)
	traversal.to_cell = Vector3i(9, 0, 0)
	author.add_child(traversal)
	var reverse_traversal := TraversalLink3D.new()
	reverse_traversal.from_cell = Vector3i(8, 0, 0)
	reverse_traversal.to_cell = Vector3i(0, 0, 0)
	author.add_child(reverse_traversal)

	var result := TacticalMapBaker.build(author)
	var diagnostics: Array[Dictionary] = result[&"diagnostics"]
	_expect(not result[&"errors"].is_empty(), "diagnostics: invalid synthetic author should have errors")
	_expect(_has_diagnostic(diagnostics, &"TMB-018", Vector3i(8, 0, 0)), "diagnostics: Floor out-of-volume coordinate should be structured")
	_expect(_has_diagnostic(diagnostics, &"TMB-020", Vector3i(1, 0, 0)), "diagnostics: Structure-without-Floor coordinate should be structured")
	_expect(_has_diagnostic(diagnostics, &"TMA-010", Vector3i(7, 0, 0)), "diagnostics: orphan override coordinate should be structured")
	_expect(_has_diagnostic(diagnostics, &"TMB-041", Vector3i(9, 0, 0)), "diagnostics: invalid spawn coordinate should be structured")
	_expect(_has_diagnostic(diagnostics, &"TMB-045", Vector3i(8, 0, 0)), "diagnostics: invalid object coordinate should be structured")
	_expect(_has_diagnostic(diagnostics, &"TMB-046", null), "diagnostics: missing extraction should be non-coordinate diagnostic")
	_expect(_has_diagnostic(diagnostics, &"TMB-048", Vector3i(9, 0, 0)), "diagnostics: missing traversal target should point to target coordinate")
	_expect(_has_diagnostic(diagnostics, &"TMB-048", Vector3i(8, 0, 0)), "diagnostics: missing traversal source should point to source coordinate")
	for diagnostic in diagnostics:
		var message: String = diagnostic[&"message"]
		_expect(result[&"errors"].has(message) or result[&"warnings"].has(message), "diagnostics: every diagnostic message must remain in compatibility arrays")
		if bool(diagnostic[&"has_coordinate"]):
			_expect(diagnostic[&"coordinate"] is Vector3i, "diagnostics: coordinate diagnostics must carry Vector3i")
		else:
			_expect(diagnostic[&"coordinate"] == null, "diagnostics: non-coordinate diagnostics must not expose a coordinate")
	for error_message in result[&"errors"]:
		_expect(_has_diagnostic_message(diagnostics, error_message), "diagnostics: every error text must have a structured counterpart")
	for warning_message in result[&"warnings"]:
		_expect(_has_diagnostic_message(diagnostics, warning_message), "diagnostics: every warning text must have a structured counterpart")
	var repeated: Array[Dictionary] = TacticalMapBaker.build(author)[&"diagnostics"]
	_expect(diagnostics == repeated, "diagnostics: repeated builds must produce stable diagnostic output")
	var service := TacticalMapPropertyService.new()
	var service_diagnostics: Array[Dictionary] = service.validation_diagnostics(author)
	_expect(service_diagnostics == diagnostics, "diagnostics: PropertyService validation entry should use Baker diagnostics")


func _test_save_diagnostics() -> void:
	var invalid_path_author := _make_legacy_author()
	invalid_path_author.output_resource_path = "not_a_res_path.tres"
	var invalid_path_result := TacticalMapBaker.save(invalid_path_author)
	var invalid_path_message := "Output path must be a res:// path ending in .tres."
	_expect(invalid_path_result[&"errors"].has(invalid_path_message), "save diagnostics: invalid path must preserve compatibility error text")
	_expect(_has_diagnostic(invalid_path_result[&"diagnostics"], &"TMB-060", null), "save diagnostics: invalid path must have a structured diagnostic")
	_expect(_has_diagnostic_message(invalid_path_result[&"diagnostics"], invalid_path_message), "save diagnostics: invalid path diagnostic must preserve error text")

	var save_failure_author := _make_legacy_author()
	var missing_directory_path := "res://__tactical_map_property_service_missing_save_dir__/result.tres"
	save_failure_author.output_resource_path = missing_directory_path
	var save_failure_result := TacticalMapBaker.save(save_failure_author)
	var save_failure_errors: Array[String] = save_failure_result[&"errors"]
	_expect(not save_failure_errors.is_empty(), "save diagnostics: ResourceSaver failure must be returned")
	_expect(_has_diagnostic(save_failure_result[&"diagnostics"], &"TMB-061", null), "save diagnostics: ResourceSaver failure must have a structured diagnostic")
	for error_message in save_failure_errors:
		_expect(_has_diagnostic_message(save_failure_result[&"diagnostics"], error_message), "save diagnostics: every save error must have a structured counterpart")
	_expect(not FileAccess.file_exists(missing_directory_path), "save diagnostics: failed save must not leave an output file")


func _test_each_field_matches_baker() -> void:
	var cases := [
		[TacticalCellOverride.Field.WALKABLE, false],
		[TacticalCellOverride.Field.MOVE_COST, 8],
		[TacticalCellOverride.Field.SIGHT_BLOCK, 0.35],
		[TacticalCellOverride.Field.PROJECTILE_BLOCK, 0.65],
		[TacticalCellOverride.Field.OCCLUDER_HEIGHT, 1.75],
	]
	for test_case in cases:
		var author := _make_legacy_author()
		var service := TacticalMapPropertyService.new()
		var field: int = test_case[0]
		var value: Variant = test_case[1]
		_expect(service.apply_override_field(author, [Vector3i(1, 0, 0)], field, value), "authority: each editable field should apply")
		var inspected := service.inspect_cells(author, [Vector3i(1, 0, 0)])
		var baked := TacticalMapBaker.build(author)
		var baked_cell := _find_cell(baked[&"definition"], Vector3i(1, 0, 0))
		_expect(baked_cell != null, "authority: field case should produce a baked cell even when validation reports a blocked spawn")
		_expect_rules_match(inspected[&"cells"][0][&"effective_rules"], baked_cell, "authority: every override field must match Baker output")


func _make_legacy_author() -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"property_service_synthetic"
	author.footprint_size = Vector2i(2, 1)
	author.level_count = 1
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	var mesh_library := MeshLibrary.new()
	mesh_library.create_item(0)
	mesh_library.create_item(1)
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
	structure_grid.set_cell_item(Vector3i(0, 0, 0), 1)
	author.add_child(structure_grid)
	var spawn := UnitSpawnMarker3D.new()
	spawn.unit_name = &"PropertyPlayer"
	spawn.faction = "player"
	spawn.cell = Vector3i(1, 0, 0)
	author.add_child(spawn)
	var extraction := MapObjectMarker3D.new()
	extraction.object_id = &"PropertyExtraction"
	extraction.kind = MapObjectPlacement.Kind.EXTRACTION
	extraction.cell = Vector3i(1, 0, 0)
	author.add_child(extraction)
	var catalog := MapTileCatalog.new()
	catalog.rules = [
		_legacy_rule(MapTileRule.Layer.FLOOR, 0, &"legacy_floor", true, 1, false, 0.0),
		_legacy_rule(MapTileRule.Layer.STRUCTURE, 1, &"legacy_wall", false, 4, true, 1.0),
	]
	author.tile_catalog = catalog
	return author


func _legacy_rule(layer: MapTileRule.Layer, item_id: int, tile_id: StringName, walkable: bool, move_cost: int, blocks_los: bool, height: float) -> MapTileRule:
	var rule := MapTileRule.new()
	rule.layer = layer
	rule.item_id = item_id
	rule.tile_id = tile_id
	rule.walkable = walkable
	rule.move_cost = move_cost
	rule.blocks_los = blocks_los
	rule.occluder_height = height
	return rule


func _make_cell_definition(
	id: StringName,
	layer: MapTileRule.Layer,
	item_id: int,
	tile_id: StringName,
	walkable: bool,
	move_cost: int,
	sight_block: float,
	height: float
) -> TacticalCellTileDefinition:
	var definition := TacticalCellTileDefinition.new()
	definition.placeable_id = id
	definition.target_layer = layer
	definition.mesh_item_id = item_id
	definition.tile_id = tile_id
	definition.rule_contribution = TacticalCellRules.new()
	definition.rule_contribution.walkable = walkable
	definition.rule_contribution.move_cost = move_cost
	definition.rule_contribution.sight_block = sight_block
	definition.rule_contribution.projectile_block = sight_block
	definition.rule_contribution.occluder_height = height
	return definition


func _make_binding(definition: TacticalCellTileDefinition) -> MeshItemBinding:
	var binding := MeshItemBinding.new()
	binding.placeable_id = definition.placeable_id
	binding.target_layer = definition.target_layer
	binding.mesh_item_id = definition.mesh_item_id
	return binding


func _find_cell(definition: TacticalMapDefinition, coordinate: Vector3i) -> MapCellData:
	for cell in definition.cells:
		if cell != null and cell.coordinate == coordinate:
			return cell
	return null


func _find_object_marker(author: TacticalMapAuthor) -> MapObjectMarker3D:
	for child in author.get_children():
		if child is MapObjectMarker3D:
			return child as MapObjectMarker3D
	return null


func _inspection_for(cells: Array[Dictionary], coordinate: Vector3i) -> Dictionary:
	for cell in cells:
		if cell[&"coordinate"] == coordinate:
			return cell
	return {}


func _default_field(result: Dictionary, field: int) -> Dictionary:
	for descriptor in result.get(&"fields", []):
		if int(descriptor[&"field"]) == field:
			return descriptor
	return {}


func _has_diagnostic(diagnostics: Array[Dictionary], code: StringName, coordinate: Variant) -> bool:
	for diagnostic in diagnostics:
		if diagnostic[&"code"] != code:
			continue
		if coordinate == null and not bool(diagnostic[&"has_coordinate"]):
			return true
		if coordinate is Vector3i and bool(diagnostic[&"has_coordinate"]) and diagnostic[&"coordinate"] == coordinate:
			return true
	return false


func _has_diagnostic_message(diagnostics: Array[Dictionary], message: String) -> bool:
	for diagnostic in diagnostics:
		if diagnostic[&"message"] == message:
			return true
	return false


func _expect_rules_match(rules: TacticalCellRules, cell: MapCellData, message: String) -> void:
	_expect(rules != null and cell != null, message)
	if rules == null or cell == null:
		return
	_expect(rules.walkable == cell.walkable, message + " (walkable)")
	_expect(rules.move_cost == cell.move_cost, message + " (move_cost)")
	_expect(is_equal_approx(rules.sight_block, cell.sight_block), message + " (sight_block)")
	_expect(is_equal_approx(rules.projectile_block, cell.projectile_block), message + " (projectile_block)")
	_expect(is_equal_approx(rules.occluder_height, cell.occluder_height), message + " (occluder_height)")


func _contains_fragment(values: Array, fragment: String) -> bool:
	for value in values:
		if String(value).contains(fragment):
			return true
	return false


func _on_authoring_data_changed(_author: TacticalMapAuthor, _coordinates: Array[Vector3i]) -> void:
	_service_signal_count += 1


func _on_resource_changed() -> void:
	_resource_signal_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_PROPERTY_SERVICE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_PROPERTY_SERVICE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
