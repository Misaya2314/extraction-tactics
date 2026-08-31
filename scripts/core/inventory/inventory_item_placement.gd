class_name InventoryItemPlacement
extends RefCounted

## Position and orientation of an item inside one container. Rotation here is
## the sole authoritative placement state; InventoryItemInstance.rotation is a
## compatibility hint and is never synchronized from this object.

const ItemPlacementSnapshotScript = preload("res://scripts/core/runtime/snapshots/item_placement_snapshot.gd")

var instance: InventoryItemInstance
var container_id: StringName = &""
var anchor: Vector2i = Vector2i.ZERO
var rotation: int = 0

var item: InventoryItemInstance:
	get:
		return instance
	set(value):
		instance = value


func _init(
		new_instance: InventoryItemInstance = null,
		new_anchor: Vector2i = Vector2i.ZERO,
		new_rotation: int = 0,
		new_container_id: Variant = &""
	) -> void:
	instance = new_instance
	anchor = new_anchor
	rotation = ItemDefinition.rotation_to_degrees(new_rotation)
	if new_container_id is StringName or new_container_id is String:
		container_id = StringName(new_container_id)


func get_occupied_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if instance == null or instance.definition == null:
		return result
	for relative_cell in instance.definition.get_rotated_cells(rotation):
		result.append(anchor + relative_cell)
	return result


func contains(cell: Vector2i) -> bool:
	return get_occupied_cells().has(cell)


func is_valid() -> bool:
	return instance != null and instance.is_valid() and container_id != &"" and not get_occupied_cells().is_empty()


func to_snapshot() -> Dictionary:
	return to_snapshot_resource().to_dictionary()


func to_snapshot_resource(override_container_id: StringName = &""):
	var snapshot = ItemPlacementSnapshotScript.new()
	snapshot.instance_id = instance.instance_id if instance != null else &""
	snapshot.container_id = override_container_id if override_container_id != &"" else container_id
	snapshot.anchor = anchor
	snapshot.rotation = rotation
	return snapshot
