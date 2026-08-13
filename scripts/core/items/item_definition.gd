@tool
class_name ItemDefinition
extends Resource

enum Kind {
	MATERIAL,
	CONSUMABLE,
	VALUABLE,
	CHIP,
}

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.MATERIAL
@export_range(0, 999999999, 1) var value: int = 0
@export var icon: Texture2D
@export var shape_cells: Array[Vector2i] = [Vector2i.ZERO]:
	set(value):
		shape_cells = _normalize_cells(value)

# Compatibility aliases for callers that prefer the shorter shape terminology.
var cells: Array[Vector2i]:
	get:
		return get_shape_cells()
	set(value):
		set_shape_cells(value)

var shape_mask: Array[Vector2i]:
	get:
		return get_shape_cells()
	set(value):
		set_shape_cells(value)

var shape: Array[Vector2i]:
	get:
		return get_shape_cells()
	set(value):
		set_shape_cells(value)

# slot_size remains readable for older UI and gameplay code, but its value is
# always derived from the canonical mask. Assignments are intentionally ignored.
var slot_size: int:
	get:
		return get_shape_cells().size()
	set(_value):
		pass


func is_valid() -> bool:
	if shape_cells.is_empty():
		return false
	for raw_cell in shape_cells:
		if not (raw_cell is Vector2i):
			return false
	var normalized := _normalize_cells(shape_cells)
	return (
		item_id != &""
		and not display_name.strip_edges().is_empty()
		and kind >= Kind.MATERIAL
		and kind <= Kind.CHIP
		and value >= 0
		and not normalized.is_empty()
	)


func validate() -> bool:
	return is_valid()


func set_shape_cells(value: Variant) -> void:
	shape_cells = _normalize_cells(value)


func normalize_shape() -> void:
	shape_cells = _normalize_cells(shape_cells)


func get_shape_cells() -> Array[Vector2i]:
	return _normalize_cells(shape_cells)


func get_rotated_cells(rotation: int = 0) -> Array[Vector2i]:
	var source := get_shape_cells()
	var quarter_turns := normalize_rotation(rotation)
	var rotated: Array[Vector2i] = []
	for cell in source:
		var transformed := cell
		match quarter_turns:
			1:
				transformed = Vector2i(-cell.y, cell.x)
			2:
				transformed = Vector2i(-cell.x, -cell.y)
			3:
				transformed = Vector2i(cell.y, -cell.x)
		rotated.append(transformed)
	return _normalize_cells(rotated)


func get_rotated_shape(rotation: int = 0) -> Array[Vector2i]:
	return get_rotated_cells(rotation)


func get_occupied_cells(rotation: int = 0) -> Array[Vector2i]:
	return get_rotated_cells(rotation)


func get_shape_mask(rotation: int = 0) -> Array[Vector2i]:
	return get_rotated_cells(rotation)


func get_shape_size(rotation: int = 0) -> Vector2i:
	var rotated := get_rotated_cells(rotation)
	if rotated.is_empty():
		return Vector2i.ZERO
	var max_x := 0
	var max_y := 0
	for cell in rotated:
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	return Vector2i(max_x + 1, max_y + 1)


func get_rotated_size(rotation: int = 0) -> Vector2i:
	return get_shape_size(rotation)


func get_dimensions(rotation: int = 0) -> Vector2i:
	return get_shape_size(rotation)


func get_width(rotation: int = 0) -> int:
	return get_shape_size(rotation).x


func get_height(rotation: int = 0) -> int:
	return get_shape_size(rotation).y


func get_slot_size() -> int:
	return get_shape_cells().size()


static func normalize_rotation(rotation: int) -> int:
	if abs(rotation) >= 4 and posmod(rotation, 90) == 0:
		return posmod(rotation / 90, 4)
	return posmod(rotation, 4)


static func rotation_to_degrees(rotation: int) -> int:
	return normalize_rotation(rotation) * 90


static func _normalize_cells(raw_cells: Variant) -> Array[Vector2i]:
	var unique: Dictionary = {}
	if not raw_cells is Array:
		return []
	for raw_cell in raw_cells:
		if not (raw_cell is Vector2i):
			continue
		var cell: Vector2i = raw_cell
		unique[cell] = true
	if unique.is_empty():
		return []

	var min_x := 2147483647
	var min_y := 2147483647
	for cell in unique.keys():
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)

	var normalized: Array[Vector2i] = []
	for cell in unique.keys():
		normalized.append(Vector2i(cell.x - min_x, cell.y - min_y))
	normalized.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return normalized
