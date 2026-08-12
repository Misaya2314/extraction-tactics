extends SceneTree

const AUTHOR_SCENE: PackedScene = preload("res://scenes/map_authoring/prototype_map_authoring.tscn")
const BAKED_DEFINITION: TacticalMapDefinition = preload("res://resources/maps/prototype_map.tres")

var _failures: Array[String] = []


func _init() -> void:
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
		rows.append("O:%s:%d:%s:%s:%s" % [placement.object_id, placement.kind, placement.cell, placement.blocks_movement, placement.blocks_los])
	return "\n".join(rows)


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
