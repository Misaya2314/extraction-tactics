extends SceneTree

## Synthetic editor-session regression coverage for the one-spawn-per-cell
## contract.  No production map scene or generated map resource is loaded.

const SessionScript := preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")

const CELL := Vector3i(0, 0, 0)
const PLAYER_CELL := Vector3i(1, 0, 0)

var _failures: Array[String] = []


func _init() -> void:
	_test_empty_and_same_configuration_noop()
	_test_default_color_configuration_noop_and_faction_replace()
	_test_different_configuration_replaces_and_roundtrips()
	_test_legacy_duplicates_normalize_and_roundtrip()
	_test_erase_removes_all_legacy_duplicates()
	_test_baker_keeps_duplicate_validator_guard()
	_finish()


func _test_empty_and_same_configuration_noop() -> void:
	var author := _make_author()
	var session = _new_spawn_session(author, _spawn_entry("enemy", "encounter.alpha"))
	_expect(_paint_once(session, session.placeables[0], CELL), "spawn: empty cell should create one marker")
	_expect(_spawn_count(author, CELL) == 1, "spawn: first paint should create exactly one marker")

	var same_entry: Dictionary = _spawn_entry("enemy", "encounter.alpha")
	_expect(not _paint_once(session, same_entry, CELL), "spawn: same configuration on the same cell should be a no-op")
	_expect(_spawn_count(author, CELL) == 1, "spawn: same configuration should leave one marker")
	author.free()


func _test_default_color_configuration_noop_and_faction_replace() -> void:
	var author := _make_author()
	var enemy_entry: Dictionary = _spawn_entry("enemy", "encounter.default_enemy", false)
	var session = _new_spawn_session(author, enemy_entry)
	_expect(_paint_once(session, enemy_entry, CELL), "spawn defaults: enemy without visual_color should create a marker")
	_expect(_spawn_count(author, CELL) == 1, "spawn defaults: enemy baseline should occupy one slot")
	var enemy_marker := _spawn_at(author, CELL)
	_expect(enemy_marker != null and enemy_marker.visual_color.is_equal_approx(Color("ff5b5b")), "spawn defaults: omitted enemy visual_color should use the enemy default")

	var noop_undo := UndoRedo.new()
	_expect(not _paint_once(session, _spawn_entry("enemy", "encounter.default_enemy", false), CELL, noop_undo), "spawn defaults: repeated omitted enemy color should be a no-op")
	_expect(_spawn_count(author, CELL) == 1, "spawn defaults: repeated omitted enemy color should leave one marker")
	_expect(not noop_undo.has_undo(), "spawn defaults: a no-op with UndoRedo must not create an Undo Action")
	noop_undo.free()

	var player_entry: Dictionary = _spawn_entry("player", "encounter.default_player", false)
	_expect(_paint_once(session, player_entry, CELL), "spawn defaults: different faction should replace the default enemy")
	_expect(_spawn_count(author, CELL) == 1, "spawn defaults: faction replacement should leave one marker")
	var player_marker := _spawn_at(author, CELL)
	_expect(player_marker != null and player_marker.faction == "player", "spawn defaults: faction replacement should apply player configuration")
	_expect(player_marker != null and player_marker.visual_color.is_equal_approx(Color("4f9dff")), "spawn defaults: omitted player visual_color should use the player default")
	author.free()


func _test_different_configuration_replaces_and_roundtrips() -> void:
	var author := _make_author()
	var first_entry: Dictionary = _spawn_entry("enemy", "encounter.alpha")
	var second_entry: Dictionary = _spawn_entry("enemy", "encounter.bravo")
	var session = _new_spawn_session(author, first_entry)
	_expect(_paint_once(session, first_entry, CELL), "spawn replace: baseline marker should be created")

	var undo_redo := UndoRedo.new()
	_expect(_paint_once(session, second_entry, CELL, undo_redo), "spawn replace: different configuration should replace the marker")
	_expect(_spawn_count(author, CELL) == 1, "spawn replace: replacement should leave one marker")
	_expect(_spawn_at(author, CELL).encounter_id == &"encounter.bravo", "spawn replace: replacement configuration should be applied")
	_expect(undo_redo.has_undo(), "spawn replace: replacement should create one Undo Action")
	undo_redo.undo()
	_expect(_spawn_count(author, CELL) == 1, "spawn replace: undo should leave one baseline marker")
	_expect(_spawn_at(author, CELL).encounter_id == &"encounter.alpha", "spawn replace: undo should restore the baseline configuration")
	undo_redo.redo()
	_expect(_spawn_count(author, CELL) == 1, "spawn replace: redo should leave one replacement marker")
	_expect(_spawn_at(author, CELL).encounter_id == &"encounter.bravo", "spawn replace: redo should restore the replacement configuration")
	undo_redo.free()
	author.free()


func _test_legacy_duplicates_normalize_and_roundtrip() -> void:
	var author := _make_author()
	_add_spawn(author, "LegacyA", "enemy", "encounter.legacy")
	_add_spawn(author, "LegacyB", "enemy", "encounter.legacy")
	_expect(_spawn_count(author, CELL) == 2, "spawn normalize: fixture should start with legacy duplicates")

	var session = _new_spawn_session(author, _spawn_entry("enemy", "encounter.legacy"))
	var undo_redo := UndoRedo.new()
	_expect(_paint_once(session, session.placeables[0], CELL, undo_redo), "spawn normalize: drawing over duplicates should mutate the cell")
	_expect(_spawn_count(author, CELL) == 1, "spawn normalize: drawing should canonicalize legacy duplicates to one")
	_expect(undo_redo.has_undo(), "spawn normalize: canonicalization should create one Undo Action")
	undo_redo.undo()
	_expect(_spawn_count(author, CELL) == 2, "spawn normalize: undo should restore the legacy duplicate snapshot")
	undo_redo.redo()
	_expect(_spawn_count(author, CELL) == 1, "spawn normalize: redo should canonicalize duplicates again")
	undo_redo.free()
	author.free()


func _test_erase_removes_all_legacy_duplicates() -> void:
	var author := _make_author()
	_add_spawn(author, "EraseA", "enemy", "encounter.erase")
	_add_spawn(author, "EraseB", "enemy", "encounter.erase")
	_add_spawn(author, "EraseC", "player", "encounter.erase")
	var session = _new_spawn_session(author, _spawn_entry("enemy", "encounter.erase"))
	session.set_tool(SessionScript.Tool.ERASE)
	session.set_target_layer(SessionScript.TargetLayer.SPAWNER)
	session.begin_stroke("erase duplicate spawns")
	_expect(session.apply_at(CELL), "spawn erase: erase should accept a cell with legacy duplicates")
	_expect(session.finish_stroke(null), "spawn erase: removing duplicates should be a real mutation")
	_expect(_spawn_count(author, CELL) == 0, "spawn erase: erase should remove every marker on the cell")
	author.free()


func _test_baker_keeps_duplicate_validator_guard() -> void:
	var author := _make_author()
	_add_spawn(author, "ValidatorA", "enemy", "encounter.validator")
	_add_spawn(author, "ValidatorB", "enemy", "encounter.validator")
	_add_spawn(author, "ValidatorPlayer", "player", "encounter.validator", PLAYER_CELL)

	var raw_result: Dictionary = TacticalMapBaker.build(author)
	_expect(_contains_text(raw_result.get(&"errors", []), "Multiple units spawn"), "baker: raw duplicate spawns must retain the validator error")
	_expect(_has_diagnostic_code(raw_result.get(&"diagnostics", []), &"TMB-043"), "baker: raw duplicate spawns must retain the structured diagnostic")

	var session = _new_spawn_session(author, _spawn_entry("enemy", "encounter.validator"))
	_expect(_paint_once(session, session.placeables[0], CELL), "baker: editor paint should normalize the duplicate cell")
	var normalized_result: Dictionary = TacticalMapBaker.build(author)
	_expect(not _contains_text(normalized_result.get(&"errors", []), "Multiple units spawn"), "baker: editor-normalized result must not report duplicate spawns")
	_expect(not _has_diagnostic_code(normalized_result.get(&"diagnostics", []), &"TMB-043"), "baker: editor-normalized result must not contain duplicate-spawn diagnostics")
	author.free()


func _new_spawn_session(author: TacticalMapAuthor, entry: Dictionary):
	var session = SessionScript.new()
	_expect(bool(session.begin_for_author(author, author)), "session: synthetic author should bind")
	session.placeables = [entry.duplicate(true)]
	session.select_placeable(0)
	session.set_tool(SessionScript.Tool.PAINT)
	return session


func _paint_once(session, entry: Dictionary, cell: Vector3i, undo_redo: UndoRedo = null) -> bool:
	session.placeables = [entry.duplicate(true)]
	session.select_placeable(0)
	session.set_tool(SessionScript.Tool.PAINT)
	session.begin_stroke("paint spawn")
	var applied: bool = session.apply_at(cell)
	var committed: bool = session.finish_stroke(undo_redo)
	return applied and committed


func _make_author() -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"spawn_uniqueness_synthetic"
	author.footprint_size = Vector2i(2, 1)
	author.level_count = 1
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	var mesh_library := MeshLibrary.new()
	mesh_library.create_item(0)
	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = mesh_library
	floor_grid.cell_size = author.cell_dimensions
	floor_grid.set_cell_item(CELL, 0)
	floor_grid.set_cell_item(PLAYER_CELL, 0)
	author.add_child(floor_grid)
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	author.add_child(spawns)
	var catalog := MapTileCatalog.new()
	var floor_rule := MapTileRule.new()
	floor_rule.layer = MapTileRule.Layer.FLOOR
	floor_rule.item_id = 0
	floor_rule.tile_id = &"synthetic.floor"
	floor_rule.walkable = true
	floor_rule.move_cost = 1
	catalog.rules = [floor_rule]
	author.tile_catalog = catalog
	return author


func _spawn_entry(faction: String, encounter_id: String, include_visual_color: bool = true) -> Dictionary:
	var entry := {
		&"id": "synthetic.spawn.%s.%s" % [faction, encounter_id],
		&"label": "Synthetic Spawn",
		&"kind": "spawn",
		&"layer": SessionScript.TargetLayer.SPAWNER,
		&"faction": faction,
		&"encounter_id": StringName(encounter_id),
		&"patrol_route_id": &"",
		&"archetype": null,
		&"weapon": null,
		&"visual_color": Color("ff5b5b") if faction == "enemy" else Color("4f9dff"),
	}
	if not include_visual_color:
		entry.erase(&"visual_color")
	return entry


func _add_spawn(author: TacticalMapAuthor, name: String, faction: String, encounter_id: String, cell: Vector3i = CELL) -> UnitSpawnMarker3D:
	var root := author.get_node("Spawns") as Node3D
	var marker := UnitSpawnMarker3D.new()
	marker.name = name
	marker.unit_name = StringName(name)
	marker.faction = faction
	marker.encounter_id = StringName(encounter_id)
	marker.cell = cell
	root.add_child(marker)
	return marker


func _spawn_markers(author: TacticalMapAuthor) -> Array[UnitSpawnMarker3D]:
	var result: Array[UnitSpawnMarker3D] = []
	var root := author.get_node("Spawns") as Node
	for child in root.get_children():
		if child is UnitSpawnMarker3D:
			result.append(child as UnitSpawnMarker3D)
	return result


func _spawn_count(author: TacticalMapAuthor, cell: Vector3i) -> int:
	var count := 0
	for marker in _spawn_markers(author):
		if marker.cell == cell:
			count += 1
	return count


func _spawn_at(author: TacticalMapAuthor, cell: Vector3i) -> UnitSpawnMarker3D:
	for marker in _spawn_markers(author):
		if marker.cell == cell:
			return marker
	return null


func _contains_text(values: Variant, needle: String) -> bool:
	if values is Array:
		for value in values:
			if String(value).contains(needle):
				return true
	return false


func _has_diagnostic_code(values: Variant, code: StringName) -> bool:
	if values is Array:
		for value in values:
			if value is Dictionary and StringName(String(value.get(&"code", &""))) == code:
				return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_SPAWN_UNIQUENESS_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_SPAWN_UNIQUENESS_TEST: FAIL (%d)" % _failures.size())
	quit(1)
