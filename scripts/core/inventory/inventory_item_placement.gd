class_name InventoryItemPlacement
extends RefCounted

var instance: InventoryItemInstance
var anchor: Vector2i = Vector2i.ZERO
var rotation: int = 0

var item: InventoryItemInstance:
	get:
		return instance
	set(value):
		instance = value


func _init(new_instance: InventoryItemInstance = null, new_anchor: Vector2i = Vector2i.ZERO, new_rotation: int = 0) -> void:
	instance = new_instance
	anchor = new_anchor
	rotation = ItemDefinition.rotation_to_degrees(new_rotation)
	if instance != null:
		instance.rotation = rotation


func get_occupied_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if instance == null or instance.definition == null:
		return result
	for relative_cell in instance.definition.get_rotated_cells(rotation):
		result.append(anchor + relative_cell)
	return result


func contains(cell: Vector2i) -> bool:
	return get_occupied_cells().has(cell)
