extends SceneTree

const AUTHOR_SCENE: PackedScene = preload("res://scenes/map_authoring/prototype_map_authoring.tscn")
const BAKED_DEFINITION: TacticalMapDefinition = preload("res://resources/maps/prototype_map.tres")
const SUPPLY_TABLE: LootTableDefinition = preload("res://resources/loot/loot_table_supply.tres")
const WAREHOUSE_TABLE: LootTableDefinition = preload("res://resources/loot/loot_table_warehouse.tres")
const OUTPOST_TABLE: LootTableDefinition = preload("res://resources/loot/loot_table_outpost.tres")
const HIGH_VALUE_TABLE: LootTableDefinition = preload("res://resources/loot/loot_table_high_value.tres")

var _failures: Array[String] = []


func _init() -> void:
	_test_generic_loot_validation()
	var author := AUTHOR_SCENE.instantiate() as TacticalMapAuthor
	get_root().add_child(author)
	var result := TacticalMapBaker.build(author)
	var errors: Array[String] = result[&"errors"]
	var definition: TacticalMapDefinition = result[&"definition"]
	_expect(errors.is_empty(), "baker: prototype author scene should validate: %s" % [errors])
	_expect(definition.cells.size() == 129, "baker: two-level floor grid should bake 129 standable surfaces")
	_expect(definition.transitions.size() == 1, "baker: explicit stairs should bake as one transition")
	_expect(definition.spawns.size() == 4, "baker: all unit spawn markers should bake")
	_expect(definition.objects.size() == 7, "baker: gameplay object markers should bake")
	_expect(definition.get_extraction_cells() == [Vector3i(11, 0, 8)], "baker: extraction marker should retain its full coordinate")
	_test_loot_contract(definition)
	_test_non_loot_objects_unchanged(definition)
	_expect(_signature(definition) == _signature(BAKED_DEFINITION), "baker: checked-in resource should match the authoring scene")
	var model := GridModel.new()
	_expect(model.configure_from_definition(definition), "baker: baked resource should initialize GridModel")
	_expect(model.has_cell(Vector3i(9, 0, 1)) and model.has_cell(Vector3i(9, 1, 1)), "baker: stacked floor surfaces should both exist")
	_expect(model.find_path(Vector3i(7, 0, 1), Vector3i(8, 1, 1)) == [Vector3i(7, 0, 1), Vector3i(8, 1, 1)], "baker: stairs should connect their endpoints")
	author.queue_free()
	await process_frame
	_finish()


func _signature(definition: TacticalMapDefinition) -> String:
	var rows: Array[String] = []
	for cell in definition.cells:
		rows.append("C:%s:%s:%d:%s:%d" % [cell.coordinate, cell.walkable, cell.move_cost, cell.blocks_los, cell.cover_mask])
	for transition in definition.transitions:
		rows.append("T:%s:%s:%d:%s" % [transition.from_cell, transition.to_cell, transition.move_cost, transition.bidirectional])
	for spawn in definition.spawns:
		rows.append("S:%s:%s:%s:%s" % [spawn.unit_name, spawn.faction, spawn.cell, spawn.patrol_route_id])
	for placement in definition.objects:
		var table_id := placement.loot_table.table_id if placement.loot_table != null else &""
		rows.append("O:%s:%d:%s:%s:%s:%s:%d" % [placement.object_id, placement.kind, placement.cell, placement.blocks_movement, placement.blocks_los, table_id, placement.loot_seed])
	return "\n".join(rows)


func _test_loot_contract(definition: TacticalMapDefinition) -> void:
	var expected := {
		&"loot_1": {&"table": SUPPLY_TABLE, &"seed": 101},
		&"loot_2": {&"table": WAREHOUSE_TABLE, &"seed": 202},
		&"loot_3": {&"table": OUTPOST_TABLE, &"seed": 303},
		&"loot_high": {&"table": HIGH_VALUE_TABLE, &"seed": 404},
	}
	var seen: Dictionary = {}
	for placement in definition.objects:
		if placement.kind != MapObjectPlacement.Kind.LOOT:
			_expect(placement.loot_table == null, "baker: non-LOOT objects should not require a LootTableDefinition")
			continue
		seen[placement.object_id] = true
		_expect(expected.has(placement.object_id), "baker: unexpected Loot object %s" % placement.object_id)
		if not expected.has(placement.object_id):
			continue
		var contract: Dictionary = expected[placement.object_id]
		var expected_table: LootTableDefinition = contract[&"table"]
		_expect(placement.loot_table != null and placement.loot_table.is_valid(), "baker: %s should have a valid LootTableDefinition" % placement.object_id)
		_expect(placement.loot_table != null and placement.loot_table.table_id == expected_table.table_id, "baker: %s table mapping" % placement.object_id)
		_expect(placement.loot_table != null and placement.loot_table.resource_path == expected_table.resource_path, "baker: %s should preserve the Loot table resource reference" % placement.object_id)
		_expect(placement.loot_seed == contract[&"seed"], "baker: %s stable loot seed" % placement.object_id)
	_expect(seen.size() == expected.size(), "baker: all four Loot objects should be present")


func _test_non_loot_objects_unchanged(definition: TacticalMapDefinition) -> void:
	var expected := {
		&"extraction": {&"kind": MapObjectPlacement.Kind.EXTRACTION, &"cell": Vector3i(11, 0, 8), &"blocks": false},
		&"barrel_1": {&"kind": MapObjectPlacement.Kind.EXPLOSIVE, &"cell": Vector3i(3, 0, 7), &"blocks": true},
		&"barrel_2": {&"kind": MapObjectPlacement.Kind.EXPLOSIVE, &"cell": Vector3i(10, 0, 2), &"blocks": true},
	}
	for placement in definition.objects:
		if not expected.has(placement.object_id):
			continue
		var contract: Dictionary = expected[placement.object_id]
		_expect(placement.kind == contract[&"kind"], "baker: %s kind should remain unchanged" % placement.object_id)
		_expect(placement.cell == contract[&"cell"], "baker: %s cell should remain unchanged" % placement.object_id)
		_expect(placement.blocks_movement == contract[&"blocks"], "baker: %s movement blocking should remain unchanged" % placement.object_id)
		_expect(placement.loot_table == null and placement.loot_seed == -1, "baker: %s should remain without Loot configuration" % placement.object_id)


func _test_generic_loot_validation() -> void:
	var missing_table := _minimal_definition()
	var missing_placement := MapObjectPlacement.new()
	missing_placement.object_id = &"missing_loot"
	missing_placement.kind = MapObjectPlacement.Kind.LOOT
	missing_placement.cell = Vector3i.ZERO
	missing_table.objects.append(missing_placement)
	var missing_errors: Array[String] = []
	var missing_warnings: Array[String] = []
	TacticalMapBaker._validate_definition(missing_table, missing_errors, missing_warnings)
	_expect(_contains_message(missing_errors, "requires a LootTableDefinition"), "baker: generic LOOT validation rejects missing table")

	var invalid_table := _minimal_definition()
	var invalid_placement := MapObjectPlacement.new()
	invalid_placement.object_id = &"invalid_loot"
	invalid_placement.kind = MapObjectPlacement.Kind.LOOT
	invalid_placement.cell = Vector3i.ZERO
	var invalid_loot_table := LootTableDefinition.new()
	invalid_loot_table.table_id = &"invalid_table"
	invalid_loot_table.random_draw_count = 1
	invalid_placement.loot_table = invalid_loot_table
	invalid_table.objects.append(invalid_placement)
	var invalid_errors: Array[String] = []
	var invalid_warnings: Array[String] = []
	TacticalMapBaker._validate_definition(invalid_table, invalid_errors, invalid_warnings)
	_expect(_contains_message(invalid_errors, "invalid LootTableDefinition"), "baker: generic LOOT validation rejects invalid table")

	var non_loot := _minimal_definition()
	var non_loot_placement := MapObjectPlacement.new()
	non_loot_placement.object_id = &"decorative_object"
	non_loot_placement.kind = MapObjectPlacement.Kind.GENERIC
	non_loot_placement.cell = Vector3i.ZERO
	non_loot_placement.loot_table = SUPPLY_TABLE
	non_loot.objects.append(non_loot_placement)
	var non_loot_errors: Array[String] = []
	var non_loot_warnings: Array[String] = []
	TacticalMapBaker._validate_definition(non_loot, non_loot_errors, non_loot_warnings)
	_expect(not _contains_message(non_loot_errors, "loot_table"), "baker: non-LOOT table mismatch is not an error")
	_expect(_contains_message(non_loot_warnings, "will be ignored"), "baker: non-LOOT table mismatch produces a warning")


func _minimal_definition() -> TacticalMapDefinition:
	var definition := TacticalMapDefinition.new()
	definition.map_id = &"generic_validation"
	definition.footprint_size = Vector2i.ONE
	definition.level_count = 1
	var cell := MapCellData.new()
	cell.coordinate = Vector3i.ZERO
	cell.walkable = true
	cell.move_cost = 1
	definition.cells.append(cell)
	var spawn := MapSpawnData.new()
	spawn.unit_name = &"player"
	spawn.faction = &"player"
	spawn.cell = Vector3i.ZERO
	definition.spawns.append(spawn)
	var extraction := MapObjectPlacement.new()
	extraction.object_id = &"extraction"
	extraction.kind = MapObjectPlacement.Kind.EXTRACTION
	extraction.cell = Vector3i.ZERO
	definition.objects.append(extraction)
	return definition


func _contains_message(messages: Array[String], fragment: String) -> bool:
	for message in messages:
		if message.contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MAP_BAKER_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("MAP_BAKER_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
