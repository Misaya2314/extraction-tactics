@tool
class_name TacticalMapAuthor
extends Node3D

@export var map_id: StringName = &"tactical_map"
@export var footprint_size: Vector2i = Vector2i(12, 10)
@export_range(1, 32, 1) var level_count: int = 2
@export var cell_dimensions: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		cell_dimensions = value
		_sync_grid_settings()
@export var grid_origin: Vector3 = Vector3.ZERO
@export var tile_catalog: MapTileCatalog
@export_file("*.tres") var output_resource_path: String = "res://resources/maps/tactical_map.tres"
@export_tool_button("Validate Map") var validate_action: Callable = validate_map
@export_tool_button("Bake Map") var bake_action: Callable = bake_map
@export_tool_button("Snap Markers") var snap_action: Callable = snap_markers


func _ready() -> void:
	_sync_grid_settings()


func cell_to_local(cell: Vector3i) -> Vector3:
	# Keep authoring markers on the exact same centre contract as the GridMap
	# tiles. With the validated identity transform, map_to_local() is the
	# canonical conversion and includes the half-cell offset on X/Y/Z.
	var floor_grid := get_node_or_null("FloorGrid") as GridMap
	if floor_grid != null:
		return grid_origin + floor_grid.map_to_local(cell)
	return grid_origin + Vector3(
		(float(cell.x) + 0.5) * cell_dimensions.x,
		(float(cell.y) + 0.5) * cell_dimensions.y,
		(float(cell.z) + 0.5) * cell_dimensions.z
	)


func validate_map() -> Dictionary:
	var result := TacticalMapBaker.build(self)
	_report(result, false)
	return result


func bake_map() -> Dictionary:
	var result := TacticalMapBaker.save(self)
	_report(result, true)
	return result


func snap_markers() -> void:
	for node in _descendants():
		if node is MapMarker3D:
			(node as MapMarker3D).snap_to_grid()


func _sync_grid_settings() -> void:
	if not is_inside_tree():
		return
	for node_name in [&"FloorGrid", &"StructureGrid", &"DecorationGrid"]:
		var grid := get_node_or_null(NodePath(String(node_name))) as GridMap
		if grid != null and cell_dimensions.x > 0.0 and cell_dimensions.y > 0.0 and cell_dimensions.z > 0.0:
			grid.cell_size = cell_dimensions


func _report(result: Dictionary, was_bake: bool) -> void:
	var errors: Array[String] = result[&"errors"]
	var warnings: Array[String] = result[&"warnings"]
	for warning in warnings:
		push_warning("Map validation: %s" % warning)
	for error in errors:
		push_error("Map validation: %s" % error)
	if errors.is_empty():
		var verb := "baked to %s" % output_resource_path if was_bake else "validated"
		print("TACTICAL_MAP: %s (%d cells, %d transitions, %d spawns, %d objects)" % [
			verb,
			(result[&"definition"] as TacticalMapDefinition).cells.size(),
			(result[&"definition"] as TacticalMapDefinition).transitions.size(),
			(result[&"definition"] as TacticalMapDefinition).spawns.size(),
			(result[&"definition"] as TacticalMapDefinition).objects.size(),
		])


func _descendants() -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = []
	for child in get_children():
		pending.append(child)
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result
