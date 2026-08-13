class_name InventoryItemInstance
extends RefCounted

var instance_id: StringName = &""
var definition: ItemDefinition

var _rotation: int = 0
var rotation: int:
	get:
		return _rotation
	set(value):
		_rotation = ItemDefinition.rotation_to_degrees(value)

var item_id: StringName:
	get:
		return definition.item_id if definition != null else &""

var display_name: String:
	get:
		return definition.display_name if definition != null else ""

var value: int:
	get:
		return definition.value if definition != null else 0

var slot_size: int:
	get:
		return definition.slot_size if definition != null else 0

var icon: Texture2D:
	get:
		return definition.icon if definition != null else null


func _init(new_instance_id: Variant = &"", new_definition: Variant = null, new_rotation: int = 0) -> void:
	if new_instance_id is ItemDefinition:
		definition = new_instance_id
		if new_definition is StringName or new_definition is String:
			instance_id = StringName(new_definition)
	else:
		if new_instance_id is StringName or new_instance_id is String:
			instance_id = StringName(new_instance_id)
		if new_definition is ItemDefinition:
			definition = new_definition
	rotation = new_rotation


func is_valid() -> bool:
	return instance_id != &"" and definition != null and definition.is_valid()


func get_rotation_degrees() -> int:
	return rotation


func get_rotation_quarters() -> int:
	return ItemDefinition.normalize_rotation(rotation)


func get_occupied_cells() -> Array[Vector2i]:
	if definition == null:
		return []
	return definition.get_rotated_cells(rotation)


func get_shape_size() -> Vector2i:
	if definition == null:
		return Vector2i.ZERO
	return definition.get_shape_size(rotation)


func copy() -> InventoryItemInstance:
	return InventoryItemInstance.new(instance_id, definition, rotation)
