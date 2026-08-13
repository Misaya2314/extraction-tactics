class_name SquadInventory
extends RefCounted

const DEFAULT_WIDTH: int = 6
const DEFAULT_HEIGHT: int = 8
const NO_FIT: Vector2i = Vector2i(-1, -1)

var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT
var placements: Array[InventoryItemPlacement] = []

var _next_instance_id: int = 1

var capacity: int:
	get:
		return width * height

var used: int:
	get:
		return get_used_capacity()

var free: int:
	get:
		return get_free_capacity()


func _init(initial_width: Variant = DEFAULT_WIDTH, initial_height: Variant = -1) -> void:
	configure(initial_width, initial_height)


func configure(new_width: Variant, new_height: Variant = -1) -> void:
	var dimensions := _coerce_dimensions(new_width, new_height)
	width = dimensions.x
	# One-argument calls retain the old scalar-capacity behavior except for the
	# default width, which naturally maps to the new DEMO 6x8 inventory.
	if dimensions.y < 0:
		height = DEFAULT_HEIGHT if width == DEFAULT_WIDTH else 1
	else:
		height = dimensions.y
	placements.clear()
	_next_instance_id = 1


func get_width() -> int:
	return width


func get_height() -> int:
	return height


func get_dimensions() -> Vector2i:
	return Vector2i(width, height)


func get_capacity() -> int:
	return capacity


func get_used_capacity() -> int:
	var occupied: Dictionary = {}
	for placement in placements:
		if placement == null:
			continue
		for cell in placement.get_occupied_cells():
			occupied[cell] = true
	return occupied.size()


func get_free_capacity() -> int:
	return maxi(capacity - get_used_capacity(), 0)


func get_used() -> int:
	return get_used_capacity()


func get_free() -> int:
	return get_free_capacity()


func can_place(item: Variant, anchor: Vector2i, requested_rotation: int = -1) -> bool:
	var candidate := _coerce_candidate(item)
	if candidate == null or not _definition_is_valid(candidate.definition):
		return false
	# A different object carrying an existing instance ID is a duplicate, even
	# when its proposed cells do not overlap the original placement.
	if candidate.instance_id != &"" and _has_instance_id(candidate.instance_id) and _find_placement_id(candidate) == &"":
		return false
	var rotation := _resolve_rotation(candidate, requested_rotation)
	var ignored_id := _find_placement_id(candidate)
	return _can_place_instance(candidate, anchor, rotation, ignored_id, [])


func place(item: Variant, anchor: Vector2i, requested_rotation: int = -1) -> bool:
	var candidate := _coerce_candidate(item)
	if candidate == null or not _definition_is_valid(candidate.definition):
		return false
	if _find_placement_index(candidate) >= 0 or _has_instance_id(candidate.instance_id):
		return false
	if candidate.instance_id == &"":
		var preview := InventoryItemInstance.new(&"__preview__", candidate.definition, candidate.rotation)
		var preview_rotation := _resolve_rotation(preview, requested_rotation)
		if not _can_place_instance(preview, anchor, preview_rotation, &"", []):
			return false
		candidate = InventoryItemInstance.new(_allocate_instance_id(), candidate.definition, preview_rotation)
	var rotation := _resolve_rotation(candidate, requested_rotation)
	if not _can_place_instance(candidate, anchor, rotation, &"", []):
		return false
	candidate.rotation = rotation
	placements.append(InventoryItemPlacement.new(candidate, anchor, rotation))
	return true


func add(item: Variant) -> bool:
	var fit := find_first_fit(item)
	if fit == NO_FIT:
		return false
	return place(item, fit)


func can_add(item: Variant) -> bool:
	return find_first_fit(item) != NO_FIT


func can_add_items(items: Array) -> bool:
	var planned: Array[InventoryItemPlacement] = []
	var reserved_ids: Dictionary = {}
	for item in items:
		var candidate := _coerce_candidate(item)
		if candidate == null or not _definition_is_valid(candidate.definition):
			return false
		var prepared := _prepare_candidate(candidate, reserved_ids, StringName("__preview_%d" % planned.size()))
		if prepared == null:
			return false
		reserved_ids[prepared.instance_id] = true
		var fit := _find_first_fit_internal(prepared, _resolve_rotation(prepared, -1), planned)
		if fit == NO_FIT:
			return false
		planned.append(InventoryItemPlacement.new(prepared, fit, prepared.rotation))
	return true


func add_items(items: Array) -> bool:
	var planned: Array[InventoryItemPlacement] = []
	var reserved_ids: Dictionary = {}
	for item in items:
		var candidate := _coerce_candidate(item)
		if candidate == null or not _definition_is_valid(candidate.definition):
			return false
		var prepared := _prepare_candidate(candidate, reserved_ids, StringName("__preview_%d" % planned.size()))
		if prepared == null:
			return false
		reserved_ids[prepared.instance_id] = true
		var rotation := _resolve_rotation(prepared, -1)
		var fit := _find_first_fit_internal(prepared, rotation, planned)
		if fit == NO_FIT:
			return false
		planned.append(InventoryItemPlacement.new(prepared, fit, rotation))
	if planned.size() != items.size():
		return false
	for placement in planned:
		if placement.instance.instance_id.begins_with("__preview_"):
			placement.instance.instance_id = _allocate_instance_id()
		placement.instance.rotation = placement.rotation
		placements.append(placement)
	return true


func move(item_or_id: Variant, new_anchor: Vector2i, requested_rotation: int = -1) -> bool:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		return false
	var placement: InventoryItemPlacement = placements[index]
	var instance := placement.instance
	var rotation := placement.rotation if requested_rotation < 0 else ItemDefinition.rotation_to_degrees(requested_rotation)
	if not _can_place_instance(instance, new_anchor, rotation, instance.instance_id, []):
		return false
	placement.anchor = new_anchor
	placement.rotation = rotation
	instance.rotation = rotation
	return true


func move_item(item_or_id: Variant, new_anchor: Vector2i, requested_rotation: int = -1) -> bool:
	return move(item_or_id, new_anchor, requested_rotation)


func can_move(item_or_id: Variant, new_anchor: Vector2i, requested_rotation: int = -1) -> bool:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		return false
	var placement: InventoryItemPlacement = placements[index]
	var rotation := placement.rotation if requested_rotation < 0 else ItemDefinition.rotation_to_degrees(requested_rotation)
	return _can_place_instance(
		placement.instance,
		new_anchor,
		rotation,
		placement.instance.instance_id,
		[]
	)


func rotate(item_or_id: Variant, requested_rotation: int = 90) -> bool:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		return false
	var placement: InventoryItemPlacement = placements[index]
	var rotation := ItemDefinition.rotation_to_degrees(requested_rotation)
	if not _can_place_instance(placement.instance, placement.anchor, rotation, placement.instance.instance_id, []):
		return false
	placement.rotation = rotation
	placement.instance.rotation = rotation
	return true


func rotate_to(item_or_id: Variant, requested_rotation: int) -> bool:
	return rotate(item_or_id, requested_rotation)


func rotate_item(item_or_id: Variant, requested_rotation: int = 90) -> bool:
	return rotate(item_or_id, requested_rotation)


func can_rotate(item_or_id: Variant, requested_rotation: int = 90) -> bool:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		return false
	var placement: InventoryItemPlacement = placements[index]
	var rotation := ItemDefinition.rotation_to_degrees(requested_rotation)
	return _can_place_instance(
		placement.instance,
		placement.anchor,
		rotation,
		placement.instance.instance_id,
		[]
	)


func rotate_by(item_or_id: Variant, delta_rotation: int = 90) -> bool:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		return false
	var placement: InventoryItemPlacement = placements[index]
	return rotate(item_or_id, placement.rotation + delta_rotation)


func remove(item_or_id: Variant, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false
	var indices: Array[int] = []
	if item_or_id is StringName or item_or_id is String:
		var requested_id := _coerce_id(item_or_id)
		# New callers commonly pass an instance ID; retain the old item-ID
		# quantity behavior when no exact instance ID exists.
		for index in range(placements.size()):
			var instance_placement: InventoryItemPlacement = placements[index]
			if instance_placement != null and instance_placement.instance != null and instance_placement.instance.instance_id == requested_id:
				indices.append(index)
				break
		if not indices.is_empty() and quantity > 1:
			return false
		if indices.is_empty():
			for index in range(placements.size()):
				var placement: InventoryItemPlacement = placements[index]
				if placement != null and placement.instance != null and placement.instance.item_id == requested_id:
					indices.append(index)
	else:
		var index := _find_placement_index(item_or_id)
		if index >= 0:
			indices.append(index)
	if indices.size() < quantity:
		return false
	for offset in range(quantity):
		placements.remove_at(indices[indices.size() - 1 - offset])
	return true


func remove_item(item_or_id: Variant) -> bool:
	return remove(item_or_id, 1)


func take(item_or_id: Variant) -> InventoryItemInstance:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		return null
	var placement: InventoryItemPlacement = placements[index]
	var instance := placement.instance
	placements.remove_at(index)
	return instance


func get_item(index: int) -> InventoryItemInstance:
	if index < 0 or index >= placements.size():
		return null
	return placements[index].instance


func get_instance(index: int) -> InventoryItemInstance:
	return get_item(index)


func get_items() -> Array[InventoryItemInstance]:
	var result: Array[InventoryItemInstance] = []
	for placement in placements:
		if placement != null and placement.instance != null:
			result.append(placement.instance)
	return result


func get_placements() -> Array[InventoryItemPlacement]:
	var result: Array[InventoryItemPlacement] = []
	for placement in placements:
		result.append(placement)
	return result


func get_placement(item_or_id: Variant) -> InventoryItemPlacement:
	var index := _find_placement_index(item_or_id)
	return placements[index] if index >= 0 else null


func get_placement_at(cell: Vector2i) -> InventoryItemPlacement:
	for placement in placements:
		if placement != null and placement.contains(cell):
			return placement
	return null


func get_occupied_cells(item_or_id: Variant) -> Array[Vector2i]:
	var placement := get_placement(item_or_id)
	return placement.get_occupied_cells() if placement != null else []


func get_cell_occupant(cell: Vector2i) -> InventoryItemInstance:
	var placement := get_placement_at(cell)
	return placement.instance if placement != null else null


func get_item_at(cell: Vector2i) -> InventoryItemInstance:
	return get_cell_occupant(cell)


func find_first_fit(item: Variant, requested_rotation: int = -1) -> Vector2i:
	var candidate := _coerce_candidate(item)
	if candidate == null or not _definition_is_valid(candidate.definition):
		return NO_FIT
	if candidate.instance_id != &"" and _has_instance_id(candidate.instance_id) and _find_placement_id(candidate) == &"":
		return NO_FIT
	var rotation := _resolve_rotation(candidate, requested_rotation)
	var planned: Array[InventoryItemPlacement] = []
	return _find_first_fit_internal(candidate, rotation, planned)


func get_item_count(item_id: StringName) -> int:
	var count := 0
	for item in get_items():
		if item.item_id == item_id:
			count += 1
	return count


func has_item(item_id: StringName) -> bool:
	return get_item_count(item_id) > 0


func total_value() -> int:
	var result := 0
	for item in get_items():
		result += item.value
	return result


func clear() -> void:
	placements.clear()


func _find_first_fit_internal(candidate: InventoryItemInstance, rotation: int, extra: Array[InventoryItemPlacement]) -> Vector2i:
	for y in range(height):
		for x in range(width):
			var anchor := Vector2i(x, y)
			var ignored_id := _find_placement_id(candidate)
			if _can_place_instance(candidate, anchor, rotation, ignored_id, extra):
				return anchor
	return NO_FIT


func _can_place_instance(candidate: InventoryItemInstance, anchor: Vector2i, rotation: int, ignored_id: StringName, extra: Array[InventoryItemPlacement]) -> bool:
	if candidate == null or not _definition_is_valid(candidate.definition):
		return false
	var cells := candidate.definition.get_rotated_cells(rotation)
	if cells.is_empty():
		return false
	for relative_cell in cells:
		var cell := anchor + relative_cell
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
			return false
		if _cell_is_occupied(cell, ignored_id, extra):
			return false
	return true


func _cell_is_occupied(cell: Vector2i, ignored_id: StringName, extra: Array[InventoryItemPlacement]) -> bool:
	for placement in placements:
		if placement == null or placement.instance == null or placement.instance.instance_id == ignored_id:
			continue
		if placement.contains(cell):
			return true
	for placement in extra:
		if placement != null and placement.contains(cell):
			return true
	return false


func _coerce_candidate(item: Variant) -> InventoryItemInstance:
	if item is InventoryItemInstance:
		return item
	if item is ItemDefinition:
		return InventoryItemInstance.new(&"", item, 0)
	return null


func _prepare_candidate(candidate: InventoryItemInstance, reserved_ids: Dictionary, temporary_id: StringName = &"") -> InventoryItemInstance:
	var result := candidate
	if result.instance_id == &"":
		var generated_id := temporary_id if temporary_id != &"" else &"__preview__"
		result = InventoryItemInstance.new(generated_id, result.definition, result.rotation)
	if _has_instance_id(result.instance_id) or reserved_ids.has(result.instance_id):
		return null
	return result


func _definition_is_valid(definition: ItemDefinition) -> bool:
	return definition != null and definition.is_valid()


func _resolve_rotation(candidate: InventoryItemInstance, requested_rotation: int) -> int:
	return candidate.rotation if requested_rotation < 0 else ItemDefinition.rotation_to_degrees(requested_rotation)


func _find_placement_index(item_or_id: Variant) -> int:
	if item_or_id is InventoryItemPlacement:
		for index in range(placements.size()):
			if placements[index] == item_or_id:
				return index
		return -1
	if item_or_id is StringName or item_or_id is String:
		var requested_id := _coerce_id(item_or_id)
		for index in range(placements.size()):
			if placements[index].instance.instance_id == requested_id:
				return index
		return -1
	if item_or_id is InventoryItemInstance:
		for index in range(placements.size()):
			if placements[index].instance == item_or_id or placements[index].instance.instance_id == item_or_id.instance_id:
				return index
	if item_or_id is ItemDefinition:
		for index in range(placements.size()):
			if placements[index].instance.item_id == item_or_id.item_id:
				return index
	return -1


func _find_placement_id(candidate: InventoryItemInstance) -> StringName:
	for placement in placements:
		if placement != null and placement.instance == candidate:
			return placement.instance.instance_id
	return &""


func _has_instance_id(instance_id: StringName) -> bool:
	if instance_id == &"":
		return false
	for placement in placements:
		if placement != null and placement.instance != null and placement.instance.instance_id == instance_id:
			return true
	return false


func _coerce_id(value: Variant) -> StringName:
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return &""


func _coerce_dimensions(raw_width: Variant, raw_height: Variant) -> Vector2i:
	if raw_width is Vector2i:
		var vector_size: Vector2i = raw_width
		return Vector2i(maxi(vector_size.x, 0), maxi(vector_size.y, 0))
	var parsed_width := DEFAULT_WIDTH
	if raw_width is int:
		parsed_width = maxi(raw_width, 0)
	var parsed_height := -1
	if raw_height is int:
		parsed_height = raw_height if raw_height >= 0 else -1
	return Vector2i(parsed_width, parsed_height)


func _allocate_instance_id() -> StringName:
	var result := StringName("inventory_item_%d" % _next_instance_id)
	_next_instance_id += 1
	return result
