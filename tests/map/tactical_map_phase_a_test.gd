extends SceneTree

## Phase-A tests deliberately use only in-memory definitions and a two-cell
## synthetic author. They do not encode any production-map layout.

var _failures: Array[String] = []


func _init() -> void:
	_test_placeable_contracts()
	_test_rules_override_and_edge_contracts()
	_test_validator_diagnostics()
	_test_grid_schema_compatibility()
	_test_library_first_baker_and_catalog_fallback()
	_test_schema_and_catalog_migration()
	_finish()


func _test_placeable_contracts() -> void:
	var cell := TacticalCellTileDefinition.new()
	cell.placeable_id = &"terrain.floor"
	cell.mesh_item_id = 4
	cell.rule_contribution = TacticalCellRules.new()
	_expect(cell.is_valid(), "placeable: valid cell definition should pass")
	_expect(not TacticalPlaceableDefinition.is_valid_id(&""), "placeable: empty ID should fail")
	_expect(not TacticalPlaceableDefinition.is_valid_id(&"bad/id"), "placeable: slash should fail stable ID validation")

	var edge := TacticalEdgeDefinition.new()
	edge.placeable_id = &"edge.wall"
	_expect(edge.is_valid(), "placeable: edge definition should expose stable identity")
	var object := TacticalObjectDefinition.new()
	object.placeable_id = &"object.crate"
	_expect(object.is_valid(), "placeable: object definition should expose stable identity")
	var stamp := TacticalStampDefinition.new()
	stamp.placeable_id = &"stamp.room"
	_expect(stamp.is_valid(), "placeable: stamp skeleton should be valid without expansion")

	var library := TacticalPlaceableLibrary.new()
	library.definitions.append(cell)
	var binding := MeshItemBinding.new()
	binding.placeable_id = cell.placeable_id
	binding.target_layer = MapTileRule.Layer.FLOOR
	binding.mesh_item_id = cell.mesh_item_id
	library.item_bindings.append(binding)
	_expect(library.find_definition(&"terrain.floor") == cell, "library: stable ID lookup should return definition")
	_expect(library.find_cell_definition(MapTileRule.Layer.FLOOR, 4) == cell, "library: binding should resolve numeric item")
	_expect(TacticalMapValidator.validate_library(library)[&"valid"], "library: minimal library should validate")
	var default_library := load("res://resources/map_tiles/libraries/default_placeable_library.tres") as TacticalPlaceableLibrary
	_expect(default_library != null, "library: default map tile library resource should load")
	if default_library != null:
		_expect(default_library.find_cell_definition(MapTileRule.Layer.STRUCTURE, 2) != null, "library: default wall binding should resolve")
		_expect(TacticalMapValidator.validate_library(default_library)[&"valid"], "library: default map tile library should validate")
	var unbound_cell_library := TacticalPlaceableLibrary.new()
	unbound_cell_library.definitions = [cell]
	var unbound_cell_result := TacticalMapValidator.validate_library(unbound_cell_library)
	_expect(not unbound_cell_result[&"warnings"].is_empty(), "library: unbound Cell definition should warn")
	var non_cell_library := TacticalPlaceableLibrary.new()
	non_cell_library.definitions = [edge, object, stamp]
	var non_cell_result := TacticalMapValidator.validate_library(non_cell_library)
	_expect(non_cell_result[&"warnings"].is_empty(), "library: unbound Edge/Object/Stamp definitions should not warn about MeshItemBinding")


func _test_rules_override_and_edge_contracts() -> void:
	var base := TacticalCellRules.new()
	base.walkable = true
	base.move_cost = 2
	base.sight_block = 0.2
	base.terrain_tags = PackedStringArray(["floor"])
	var structure := TacticalCellRules.new()
	structure.walkable = false
	structure.move_cost = 5
	structure.sight_block = 1.0
	structure.projectile_block = 0.75
	structure.sound_cost = 4.0
	structure.hazard_id = &"alarm"
	structure.terrain_tags = PackedStringArray(["wall"])
	var merged := TacticalRuleMerger.merge(base, structure)
	_expect(not merged.walkable, "rules: walkability should merge with AND")
	_expect(merged.move_cost == 5, "rules: move cost should merge with max")
	_expect(merged.sight_block == 1.0, "rules: sight blocker should merge with max")
	_expect(merged.projectile_block == 0.75 and merged.sound_cost == 4.0, "rules: projectile/sound should merge with max")
	_expect(merged.hazard_id == &"alarm", "rules: non-empty hazard should replace floor default")
	_expect(merged.terrain_tags.has("floor") and merged.terrain_tags.has("wall"), "rules: terrain tags should union")

	var cell_override := TacticalCellOverride.new()
	cell_override.coordinate = Vector3i(0, 0, 0)
	cell_override.override_mask = TacticalCellOverride.Field.MOVE_COST
	cell_override.values = TacticalCellRules.new()
	cell_override.values.move_cost = 9
	var overridden := TacticalRuleMerger.apply_override(merged, cell_override)
	_expect(overridden.move_cost == 9, "override: explicit mask should replace only selected field")
	_expect(overridden.walkable == merged.walkable, "override: unmasked field should inherit")

	var key_a := TacticalEdgeKey.from_cells(Vector3i(1, 0, 0), Vector3i(0, 0, 0))
	var key_b := TacticalEdgeKey.from_cells(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
	_expect(key_a.key_string() == key_b.key_string(), "edge: reversed endpoints should canonicalize")
	_expect(key_a.is_valid(), "edge: adjacent same-level key should validate")
	var placement := TacticalEdgePlacement.new()
	placement.edge_key = key_a
	placement.placeable_id = &"edge.wall"
	placement.rules = TacticalEdgeRules.new()
	var data := TacticalMapAuthoringData.new()
	data.edge_placements.append(placement)
	var validation := TacticalMapValidator.validate_authoring_data(data, Vector2i(2, 1), 1)
	_expect(validation[&"valid"], "edge: minimal authoring data should validate")
	var baked_edge := MapEdgeData.from_placement(placement)
	_expect(baked_edge.key_string() == key_a.key_string(), "edge: baked data should retain canonical key")

	var reverse_key := TacticalEdgeKey.new()
	reverse_key.cell_a = Vector3i(1, 0, 0)
	reverse_key.cell_b = Vector3i(0, 0, 0)
	var reverse_placement := TacticalEdgePlacement.new()
	reverse_placement.edge_key = reverse_key
	reverse_placement.placeable_id = &"edge.cover_test"
	reverse_placement.rules = TacticalEdgeRules.new()
	reverse_placement.rules.cover_a = TacticalEdgeRules.CoverLevel.FULL
	reverse_placement.rules.cover_b = TacticalEdgeRules.CoverLevel.HALF
	var reverse_baked := MapEdgeData.from_placement(reverse_placement)
	_expect(reverse_baked.key_string() == key_a.key_string(), "edge: reversed placement should bake to canonical key")
	_expect(reverse_baked.cover_a == TacticalEdgeRules.CoverLevel.HALF, "edge: cover_a should follow canonical physical endpoint")
	_expect(reverse_baked.cover_b == TacticalEdgeRules.CoverLevel.FULL, "edge: cover_b should follow canonical physical endpoint")


func _test_validator_diagnostics() -> void:
	var first := TacticalObjectDefinition.new()
	first.placeable_id = &"object.duplicate"
	var second := TacticalObjectDefinition.new()
	second.placeable_id = first.placeable_id
	var invalid_library := TacticalPlaceableLibrary.new()
	invalid_library.definitions = [first, second]
	var orphan_binding := MeshItemBinding.new()
	orphan_binding.placeable_id = &"object.missing"
	orphan_binding.mesh_item_id = 3
	invalid_library.item_bindings.append(orphan_binding)
	var library_result := TacticalMapValidator.validate_library(invalid_library)
	_expect(not library_result[&"valid"], "validator: duplicate IDs/orphan bindings should fail")
	_expect(_contains_error(library_result[&"errors"], "Duplicate placeable_id"), "validator: duplicate ID diagnostic should be stable")
	_expect(_contains_error(library_result[&"errors"], "orphan placeable_id"), "validator: orphan binding diagnostic should be stable")

	var duplicate_data := TacticalMapAuthoringData.new()
	var first_override := TacticalCellOverride.new()
	first_override.coordinate = Vector3i(0, 0, 0)
	duplicate_data.cell_overrides.append(first_override)
	var second_override := TacticalCellOverride.new()
	second_override.coordinate = first_override.coordinate
	duplicate_data.cell_overrides.append(second_override)
	var data_result := TacticalMapValidator.validate_authoring_data(duplicate_data)
	_expect(not data_result[&"valid"], "validator: duplicate override coordinate should fail")

	var edge := TacticalEdgePlacement.new()
	edge.edge_key = TacticalEdgeKey.from_cells(Vector3i.ZERO, Vector3i(1, 0, 0))
	edge.placeable_id = &"edge.test"
	duplicate_data.edge_placements = [edge, edge]
	var edge_result := TacticalMapValidator.validate_authoring_data(duplicate_data)
	_expect(_contains_error(edge_result[&"errors"], "Duplicate edge key"), "validator: duplicate canonical edge should fail")
	var schema_result := TacticalMapValidator.validate_schema_version(99)
	_expect(not schema_result[&"valid"], "validator: unsupported map schema should fail")

	var mismatch_definition := _cell_definition(&"cell.mismatch", MapTileRule.Layer.FLOOR, 4, &"mismatch", true, 1, 0.0, 0.0)
	var mismatch_binding := _binding(mismatch_definition)
	mismatch_binding.target_layer = MapTileRule.Layer.STRUCTURE
	var non_cell_definition := TacticalObjectDefinition.new()
	non_cell_definition.placeable_id = &"object.bound"
	var non_cell_binding := MeshItemBinding.new()
	non_cell_binding.placeable_id = non_cell_definition.placeable_id
	non_cell_binding.target_layer = MapTileRule.Layer.FLOOR
	non_cell_binding.mesh_item_id = 8
	var inconsistent_library := TacticalPlaceableLibrary.new()
	inconsistent_library.definitions = [mismatch_definition, non_cell_definition]
	inconsistent_library.item_bindings = [mismatch_binding, non_cell_binding]
	var consistency_result := TacticalMapValidator.validate_library(inconsistent_library)
	_expect(_contains_error(consistency_result[&"errors"], "does not match"), "validator: binding/definition layer-item mismatch should fail")
	_expect(_contains_error(consistency_result[&"errors"], "must reference a Cell definition"), "validator: non-Cell binding target should fail")
	_expect(inconsistent_library.find_cell_definition(MapTileRule.Layer.STRUCTURE, 4) == null, "library: inconsistent binding must not resolve ambiguously")


func _test_grid_schema_compatibility() -> void:
	var legacy_grid := GridModel.new()
	_expect(legacy_grid.configure_from_definition(_schema_definition(1)), "schema: explicit schema 1 should remain loadable")
	var current_grid := GridModel.new()
	_expect(current_grid.configure_from_definition(_schema_definition(2)), "schema: current schema 2 should load")
	var future_grid := GridModel.new()
	_expect(not future_grid.configure_from_definition(_schema_definition(3)), "schema: future schema should be rejected")
	var zero_grid := GridModel.new()
	_expect(not zero_grid.configure_from_definition(_schema_definition(0)), "schema: zero schema should be rejected")
	_expect(not zero_grid.configure_from_definition(null), "schema: null definition should be rejected")


func _test_library_first_baker_and_catalog_fallback() -> void:
	var author := _make_author()
	var catalog := MapTileCatalog.new()
	var legacy_floor := _legacy_rule(MapTileRule.Layer.FLOOR, 0, &"legacy_floor", true, 9, false, 0.0)
	var legacy_wall := _legacy_rule(MapTileRule.Layer.STRUCTURE, 1, &"legacy_wall", false, 1, true, 0.5)
	catalog.rules = [legacy_floor, legacy_wall]
	author.tile_catalog = catalog

	var library := TacticalPlaceableLibrary.new()
	var floor_definition := _cell_definition(&"factory.floor", MapTileRule.Layer.FLOOR, 0, &"library_floor", true, 2, 0.0, 0.0)
	var wall_definition := _cell_definition(&"factory.wall", MapTileRule.Layer.STRUCTURE, 1, &"library_wall", false, 5, 1.0, 1.4)
	var edge_definition := TacticalEdgeDefinition.new()
	edge_definition.placeable_id = &"edge.wall"
	library.definitions = [floor_definition, wall_definition, edge_definition]
	library.item_bindings = [_binding(floor_definition), _binding(wall_definition)]
	author.placeable_library = library

	var override := TacticalCellOverride.new()
	override.coordinate = Vector3i(1, 0, 0)
	override.override_mask = TacticalCellOverride.Field.MOVE_COST
	override.values = TacticalCellRules.new()
	override.values.move_cost = 7
	author.authoring_data = TacticalMapAuthoringData.new()
	author.authoring_data.cell_overrides.append(override)
	var edge_placement := TacticalEdgePlacement.new()
	edge_placement.edge_key = TacticalEdgeKey.from_cells(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
	edge_placement.placeable_id = &"edge.wall"
	edge_placement.rules = TacticalEdgeRules.new()
	author.authoring_data.edge_placements.append(edge_placement)

	var result := TacticalMapBaker.build(author)
	_expect(result[&"errors"].is_empty(), "baker: library-first synthetic map should build")
	var definition: TacticalMapDefinition = result[&"definition"]
	_expect(definition.cells.size() == 2, "baker: synthetic author should produce two cells")
	var first: MapCellData = _find_cell(definition, Vector3i(0, 0, 0))
	var second: MapCellData = _find_cell(definition, Vector3i(1, 0, 0))
	_expect(first != null and not first.walkable, "baker: structure should use library rules")
	_expect(first != null and first.blocks_los and first.occluder_height == 1.4, "baker: library blocker properties should compile")
	_expect(first != null and first.sight_block == 1.0 and first.projectile_block == 1.0, "baker: compiled blocker fields should retain new rules")
	_expect(second != null and second.move_cost == 7, "baker: explicit override should apply after fixed rule merge")
	_expect(definition.edges.size() == 1, "baker: edge placements should compile to MapEdgeData")

	# Remove the structure binding: the old catalog must provide that one item
	# without silently changing the already bound floor definition.
	library.item_bindings = [_binding(floor_definition)]
	var fallback_result := TacticalMapBaker.build(author)
	_expect(fallback_result[&"errors"].is_empty(), "baker: missing binding should fall back when Catalog is present")
	_expect(not fallback_result[&"warnings"].is_empty(), "baker: fallback should be observable as a warning")
	var fallback_definition: TacticalMapDefinition = fallback_result[&"definition"]
	var fallback_first: MapCellData = _find_cell(fallback_definition, Vector3i(0, 0, 0))
	_expect(fallback_first != null and fallback_first.blocks_los and fallback_first.occluder_height == 0.5, "baker: missing binding should use legacy structure rule")

	# An override for a cell absent from the compiled floor set is an error.
	author.authoring_data.cell_overrides[0].coordinate = Vector3i(9, 0, 0)
	var orphan_result := TacticalMapBaker.build(author)
	_expect(_contains_error(orphan_result[&"errors"], "Orphan cell override"), "baker: orphan override should be rejected")


func _test_schema_and_catalog_migration() -> void:
	var old_definition := TacticalMapDefinition.new()
	old_definition.schema_version = TacticalMapDefinition.MIN_SUPPORTED_SCHEMA_VERSION
	var report := TacticalMapMigrator.migration_report(old_definition)
	_expect(report[&"valid"], "migration: legacy schema should be reportable")
	_expect(report[&"changed"], "migration: legacy schema should require an explicit upgrade")
	var migrated := TacticalMapMigrator.migrate_definition(old_definition)
	_expect(migrated != null and migrated.schema_version == TacticalMapDefinition.CURRENT_SCHEMA_VERSION, "migration: upgraded definition should use current schema")
	_expect(migrated != null and migrated.edges.is_empty(), "migration: legacy definition should retain empty optional edges")

	var catalog := MapTileCatalog.new()
	catalog.rules.append(_legacy_rule(MapTileRule.Layer.FLOOR, 3, &"floor_three", true, 1, false, 0.0))
	var migrated_library := TacticalMapMigrator.migrate_catalog(catalog)
	_expect(migrated_library.find_cell_definition(MapTileRule.Layer.FLOOR, 3) != null, "migration: Catalog item should gain stable library binding")


func _make_author() -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"phase_a_synthetic"
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
	spawn.unit_name = &"SyntheticPlayer"
	spawn.faction = "player"
	spawn.cell = Vector3i(1, 0, 0)
	author.add_child(spawn)
	var extraction := MapObjectMarker3D.new()
	extraction.object_id = &"SyntheticExtraction"
	extraction.kind = MapObjectPlacement.Kind.EXTRACTION
	extraction.cell = Vector3i(1, 0, 0)
	author.add_child(extraction)
	return author


func _schema_definition(version: int) -> TacticalMapDefinition:
	var definition := TacticalMapDefinition.new()
	definition.schema_version = version
	definition.footprint_size = Vector2i.ONE
	definition.level_count = 1
	var cell := MapCellData.new()
	cell.coordinate = Vector3i.ZERO
	definition.cells.append(cell)
	return definition


func _cell_definition(
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


func _binding(definition: TacticalCellTileDefinition) -> MeshItemBinding:
	var binding := MeshItemBinding.new()
	binding.placeable_id = definition.placeable_id
	binding.target_layer = definition.target_layer
	binding.mesh_item_id = definition.mesh_item_id
	return binding


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


func _find_cell(definition: TacticalMapDefinition, coordinate: Vector3i) -> MapCellData:
	for cell in definition.cells:
		if cell != null and cell.coordinate == coordinate:
			return cell
	return null


func _contains_error(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if String(error).contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_PHASE_A_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_PHASE_A_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
