class_name SquadInventory
extends RefCounted

## Shared squad inventory. Grid placement is authoritative for anchor/rotation;
## item creation and hydration are delegated to ItemInstanceFactory.

const DEFAULT_WIDTH: int = 6
const DEFAULT_HEIGHT: int = 8
const DEFAULT_INVENTORY_ID: StringName = &"squad_inventory"
const NO_FIT: Vector2i = Vector2i(-1, -1)
const InventorySnapshotScript = preload("res://scripts/core/runtime/snapshots/inventory_snapshot.gd")
const InventoryItemInstanceScript = preload("res://scripts/core/inventory/inventory_item_instance.gd")

var inventory_id: StringName = DEFAULT_INVENTORY_ID
var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT
var placements: Array[InventoryItemPlacement] = []

var _instance_factory
var last_reason_code: StringName = &""

var capacity: int:
	get:
		return width * height

var used: int:
	get:
		return get_used_capacity()

var free: int:
	get:
		return get_free_capacity()


func _init(initial_width: Variant = DEFAULT_WIDTH, initial_height: Variant = -1, third: Variant = null, fourth: Variant = null) -> void:
	configure(initial_width, initial_height)
	if third is StringName or third is String:
		inventory_id = StringName(third)
	elif third != null:
		set_instance_factory(third)
	if fourth is StringName or fourth is String:
		inventory_id = StringName(fourth)
	elif fourth != null:
		set_instance_factory(fourth)


func configure(new_width: Variant, new_height: Variant = -1, new_inventory_id: Variant = &"", new_factory = null) -> void:
	var dimensions := _coerce_dimensions(new_width, new_height)
	_release_all_items()
	width = dimensions.x
	height = DEFAULT_HEIGHT if dimensions.y < 0 and width == DEFAULT_WIDTH else (1 if dimensions.y < 0 else dimensions.y)
	placements.clear()
	last_reason_code = &"configured"
	if (new_inventory_id is StringName or new_inventory_id is String) and StringName(new_inventory_id) != &"":
		inventory_id = StringName(new_inventory_id)
	elif new_inventory_id != &"" and new_inventory_id != null:
		set_instance_factory(new_inventory_id)
	if new_factory != null:
		set_instance_factory(new_factory)


func set_instance_factory(new_factory) -> bool:
	if new_factory == null:
		_instance_factory = null
		return true
	if typeof(new_factory) != TYPE_OBJECT or not new_factory.has_method("create") or not new_factory.has_method("hydrate"):
		last_reason_code = &"invalid_instance_factory"
		return false
	_instance_factory = new_factory
	last_reason_code = &"factory_configured"
	return true


func get_instance_factory():
	return _instance_factory


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


func can_place(item: Variant, anchor: Vector2i, requested_rotation: int = -1, allow_owned: bool = false) -> bool:
	var candidate: InventoryItemInstance = _coerce_query_candidate(item)
	if candidate == null or not _definition_is_valid(candidate.definition):
		return false
	var existing_index := _find_placement_index(candidate)
	if candidate.is_owned() and not allow_owned:
		if existing_index < 0 or candidate.get_owner_id() != _owner_key():
			return false
	if candidate.instance_id != &"" and _has_instance_id(candidate.instance_id):
		if existing_index < 0 or placements[existing_index].instance != candidate:
			return false
	var rotation := _resolve_rotation(candidate, requested_rotation)
	var ignored_id: StringName = placements[existing_index].instance.instance_id if existing_index >= 0 else &""
	return _can_place_instance(candidate, anchor, rotation, ignored_id, [])


func place(item: Variant, anchor: Vector2i, requested_rotation: int = -1, allow_owned: bool = false) -> bool:
	var candidate: InventoryItemInstance = _coerce_query_candidate(item)
	if candidate == null or not _definition_is_valid(candidate.definition):
		last_reason_code = &"invalid_definition"
		return false
	var existing_index := _find_placement_index(candidate)
	if existing_index >= 0 or (candidate.instance_id != &"" and _has_instance_id(candidate.instance_id)):
		last_reason_code = &"duplicate_instance_id"
		return false
	if candidate.is_owned() and not allow_owned:
		last_reason_code = &"ownership_conflict"
		return false
	var rotation := _resolve_rotation(candidate, requested_rotation)
	if not _can_place_instance(candidate, anchor, rotation, &"", []):
		last_reason_code = &"invalid_placement"
		return false
	var generator_state = null
	var created_instance := false
	if candidate.instance_id == &"":
		generator_state = _capture_factory_state()
		candidate = _create_instance(candidate.definition)
		if candidate == null or candidate.instance_id == &"" or _has_instance_id(candidate.instance_id):
			_discard_instance(candidate)
			_restore_factory_state(generator_state)
			last_reason_code = &"duplicate_instance_id" if candidate != null and candidate.instance_id != &"" else &"instance_creation_failed"
			return false
		created_instance = true
		if not _can_place_instance(candidate, anchor, rotation, &"", []):
			_discard_instance(candidate)
			_restore_factory_state(generator_state)
			last_reason_code = &"invalid_placement"
			return false
	var placement := InventoryItemPlacement.new(candidate, anchor, rotation, inventory_id)
	if not placement.is_valid():
		if created_instance:
			_discard_instance(candidate)
		_restore_factory_state(generator_state)
		last_reason_code = &"invalid_placement"
		return false
	if candidate.is_owned() or not candidate.claim_owner(_owner_key()):
		if created_instance:
			_discard_instance(candidate)
		_restore_factory_state(generator_state)
		last_reason_code = &"ownership_conflict"
		return false
	placements.append(placement)
	last_reason_code = &"ok"
	return true


func add(item: Variant) -> bool:
	var fit := find_first_fit(item)
	if fit == NO_FIT:
		last_reason_code = &"no_fit"
		return false
	return place(item, fit)


func can_add(item: Variant) -> bool:
	if item is ItemDefinition and _instance_factory == null:
		return false
	return find_first_fit(item) != NO_FIT


func can_add_items(items: Array, allow_owned: bool = false) -> bool:
	if items == null:
		return false
	var planned: Variant = _plan_items(items, false, allow_owned)
	return planned != null


func add_items(items: Array, allow_owned: bool = false) -> bool:
	if items == null:
		return false
	var generator_state = _capture_factory_state()
	var planned: Variant = _plan_items(items, true, allow_owned)
	if planned == null:
		return false
	var resolved_placements: Array[InventoryItemPlacement] = []
	var created_instances: Array[InventoryItemInstance] = []
	var resolved_ids: Dictionary = {}
	for entry in planned:
		var candidate: InventoryItemInstance = entry[&"instance"]
		if bool(entry[&"needs_creation"]):
			candidate = _create_instance(entry[&"definition"])
			if candidate == null:
				_discard_instances(created_instances)
				_restore_factory_state(generator_state)
				return false
			created_instances.append(candidate)
		if candidate.instance_id == &"" or _has_instance_id(candidate.instance_id) or resolved_ids.has(candidate.instance_id):
			_discard_instances(created_instances)
			_restore_factory_state(generator_state)
			return false
		resolved_ids[candidate.instance_id] = true
		var placement := InventoryItemPlacement.new(candidate, entry[&"anchor"], entry[&"rotation"], inventory_id)
		if not placement.is_valid():
			_release_claimed_instances(resolved_placements)
			_discard_instances(created_instances)
			_restore_factory_state(generator_state)
			return false
		resolved_placements.append(placement)
	if resolved_placements.size() != items.size():
		_release_claimed_instances(resolved_placements)
		_discard_instances(created_instances)
		_restore_factory_state(generator_state)
		return false
	for placement in resolved_placements:
		if placement.instance == null or placement.instance.is_owned() or not placement.instance.claim_owner(_owner_key()):
			_release_claimed_instances(resolved_placements)
			_discard_instances(created_instances)
			_restore_factory_state(generator_state)
			last_reason_code = &"ownership_conflict"
			return false
	for placement in resolved_placements:
		placements.append(placement)
	last_reason_code = &"ok"
	return true


func move(item_or_id: Variant, new_anchor: Vector2i, requested_rotation: int = -1) -> bool:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		last_reason_code = &"missing_instance"
		return false
	var placement: InventoryItemPlacement = placements[index]
	var rotation := placement.rotation if requested_rotation < 0 else ItemDefinition.rotation_to_degrees(requested_rotation)
	if not _can_place_instance(placement.instance, new_anchor, rotation, placement.instance.instance_id, []):
		last_reason_code = &"invalid_placement"
		return false
	placement.anchor = new_anchor
	placement.rotation = rotation
	last_reason_code = &"ok"
	return true


func move_item(item_or_id: Variant, new_anchor: Vector2i, requested_rotation: int = -1) -> bool:
	return move(item_or_id, new_anchor, requested_rotation)


func can_move(item_or_id: Variant, new_anchor: Vector2i, requested_rotation: int = -1) -> bool:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		return false
	var placement: InventoryItemPlacement = placements[index]
	var rotation := placement.rotation if requested_rotation < 0 else ItemDefinition.rotation_to_degrees(requested_rotation)
	return _can_place_instance(placement.instance, new_anchor, rotation, placement.instance.instance_id, [])


func rotate(item_or_id: Variant, requested_rotation: int = 90) -> bool:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		last_reason_code = &"missing_instance"
		return false
	var placement: InventoryItemPlacement = placements[index]
	var rotation := ItemDefinition.rotation_to_degrees(requested_rotation)
	if not _can_place_instance(placement.instance, placement.anchor, rotation, placement.instance.instance_id, []):
		last_reason_code = &"invalid_placement"
		return false
	placement.rotation = rotation
	last_reason_code = &"ok"
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
	return _can_place_instance(placement.instance, placement.anchor, rotation, placement.instance.instance_id, [])


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
		for index in range(placements.size()):
			var instance_placement: InventoryItemPlacement = placements[index]
			if instance_placement != null and instance_placement.instance != null and instance_placement.instance.instance_id == requested_id:
				indices.append(index)
				break
		if indices.is_empty():
			for index in range(placements.size()):
				var placement: InventoryItemPlacement = placements[index]
				if placement != null and placement.instance != null and placement.instance.item_id == requested_id:
					indices.append(index)
		else:
			if quantity > 1:
				return false
	else:
		var index := _find_placement_index(item_or_id)
		if index >= 0:
			indices.append(index)
	if indices.size() < quantity:
		return false
	for offset in range(quantity):
		var removed: InventoryItemPlacement = placements[indices[indices.size() - 1 - offset]]
		placements.remove_at(indices[indices.size() - 1 - offset])
		_release_instance_owner(removed.instance)
	last_reason_code = &"ok"
	return true


func remove_item(item_or_id: Variant) -> bool:
	return remove(item_or_id, 1)


func take(item_or_id: Variant) -> InventoryItemInstance:
	var index := _find_placement_index(item_or_id)
	if index < 0:
		return null
	var placement: InventoryItemPlacement = placements[index]
	var instance := placement.instance
	if instance == null or (instance.is_owned() and instance.get_owner_id() != _owner_key()):
		last_reason_code = &"ownership_conflict"
		return null
	placements.remove_at(index)
	_release_instance_owner(instance)
	last_reason_code = &"ok"
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
	var placement: InventoryItemPlacement = get_placement(item_or_id)
	return placement.get_occupied_cells() if placement != null else []


func get_cell_occupant(cell: Vector2i) -> InventoryItemInstance:
	var placement: InventoryItemPlacement = get_placement_at(cell)
	return placement.instance if placement != null else null


func get_item_at(cell: Vector2i) -> InventoryItemInstance:
	return get_cell_occupant(cell)


func find_first_fit(item: Variant, requested_rotation: int = -1, allow_owned: bool = false) -> Vector2i:
	var candidate: InventoryItemInstance = _coerce_query_candidate(item)
	if candidate == null or not _definition_is_valid(candidate.definition):
		return NO_FIT
	if candidate.instance_id == &"" and _instance_factory == null:
		return NO_FIT
	var existing_index := _find_placement_index(candidate)
	if candidate.is_owned() and not allow_owned:
		if existing_index < 0 or candidate.get_owner_id() != _owner_key():
			return NO_FIT
	if candidate.instance_id != &"" and _has_instance_id(candidate.instance_id):
		if existing_index < 0 or placements[existing_index].instance != candidate:
			return NO_FIT
	var rotation := _resolve_rotation(candidate, requested_rotation)
	return _find_first_fit_internal(candidate, rotation, [])


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
	_release_all_items()
	placements.clear()
	last_reason_code = &"cleared"


func to_snapshot() -> Dictionary:
	return to_snapshot_resource().to_dictionary()


func to_snapshot_resource():
	var snapshot = InventorySnapshotScript.new()
	snapshot.inventory_id = inventory_id
	snapshot.width = width
	snapshot.height = height
	var seen: Dictionary = {}
	for placement in placements:
		if placement == null or placement.instance == null:
			continue
		var item_id := placement.instance.instance_id
		if not seen.has(item_id):
			snapshot.items.append(placement.instance.to_snapshot_resource())
			seen[item_id] = true
		snapshot.placements.append(placement.to_snapshot_resource(inventory_id))
	return snapshot


static func from_snapshot(snapshot: Variant, registry: Variant, factory: Variant):
	var result := SquadInventory.new()
	if not result.hydrate_from_snapshot(snapshot, registry, factory):
		return null
	return result


func hydrate_from_snapshot(snapshot: Variant, registry: Variant, factory: Variant) -> bool:
	var typed_snapshot = _coerce_inventory_snapshot(snapshot)
	if typed_snapshot == null or not typed_snapshot.is_valid():
		last_reason_code = &"invalid_snapshot"
		return false
	if factory == null or typeof(factory) != TYPE_OBJECT or not factory.has_method("hydrate"):
		last_reason_code = &"missing_instance_factory"
		return false
	var generator_state = _capture_factory_state_for(factory)
	var restored_by_id: Dictionary = {}
	var restored_instances: Array[InventoryItemInstance] = []
	for item_snapshot in typed_snapshot.items:
		var restored = factory.call("hydrate", item_snapshot, registry)
		if not restored is InventoryItemInstance or not restored.is_valid(registry):
			_discard_instances_for(factory, restored_instances)
			_restore_factory_state_for(factory, generator_state)
			last_reason_code = &"missing_definition"
			return false
		if restored_by_id.has(restored.instance_id):
			_discard_instance_for(factory, restored)
			_discard_instances_for(factory, restored_instances)
			_restore_factory_state_for(factory, generator_state)
			last_reason_code = &"duplicate_instance_id"
			return false
		restored_by_id[restored.instance_id] = restored
		restored_instances.append(restored)
	var probe := SquadInventory.new(typed_snapshot.width, typed_snapshot.height, typed_snapshot.inventory_id, factory)
	for placement_snapshot in typed_snapshot.placements:
		var restored_item = restored_by_id.get(placement_snapshot.instance_id)
		if restored_item == null or not probe.place(restored_item, placement_snapshot.anchor, placement_snapshot.rotation):
			_discard_instances_for(factory, restored_instances)
			_restore_factory_state_for(factory, generator_state)
			last_reason_code = &"invalid_placement"
			return false
	if probe.placements.size() != restored_by_id.size():
		_discard_instances_for(factory, restored_instances)
		_restore_factory_state_for(factory, generator_state)
		last_reason_code = &"invalid_snapshot"
		return false
	_release_all_items()
	width = probe.width
	height = probe.height
	inventory_id = probe.inventory_id
	placements = probe.placements
	_instance_factory = factory
	last_reason_code = &"hydrated"
	return true


func _find_first_fit_internal(candidate: InventoryItemInstance, rotation: int, extra: Array) -> Vector2i:
	for y in range(height):
		for x in range(width):
			var anchor := Vector2i(x, y)
			var ignored_id := _find_placement_id(candidate)
			if _can_place_instance(candidate, anchor, rotation, ignored_id, extra):
				return anchor
	return NO_FIT


func _can_place_instance(candidate: InventoryItemInstance, anchor: Vector2i, rotation: int, ignored_id: StringName, extra: Array) -> bool:
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


func _cell_is_occupied(cell: Vector2i, ignored_id: StringName, extra: Array) -> bool:
	for placement in placements:
		if placement == null or placement.instance == null or placement.instance.instance_id == ignored_id:
			continue
		if placement.contains(cell):
			return true
	for placement in extra:
		if placement != null and placement.contains(cell):
			return true
	return false


func _coerce_query_candidate(item: Variant):
	if item is InventoryItemInstance:
		return item
	if item is ItemDefinition:
		# A definition query has no runtime identity. Keeping this temporary
		# candidate ID empty ensures place()/add() must obtain a real ID from the
		# injected factory instead of accidentally persisting a sentinel object.
		return InventoryItemInstanceScript.new(&"", item, 0)
	return null


func _create_instance(definition: ItemDefinition):
	if _instance_factory == null or typeof(_instance_factory) != TYPE_OBJECT or not _instance_factory.has_method("create"):
		last_reason_code = &"missing_instance_factory"
		return null
	var result = _instance_factory.call("create", definition)
	if not result is InventoryItemInstance or not result.is_valid():
		last_reason_code = &"instance_creation_failed"
		return null
	return result


func _plan_items(items: Array, require_factory: bool, allow_owned: bool = false) -> Variant:
	var planned: Array = []
	var reserved_ids: Dictionary = {}
	for index in range(items.size()):
		var value = items[index]
		var candidate: InventoryItemInstance = _coerce_query_candidate(value)
		if candidate == null or not _definition_is_valid(candidate.definition):
			return [] if items.is_empty() else null
		var needs_creation := value is ItemDefinition or candidate.instance_id == &""
		if needs_creation and _instance_factory == null:
			return null
		if candidate.is_owned() and not allow_owned:
			return null
		if not needs_creation and (candidate.instance_id == &"" or _has_instance_id(candidate.instance_id) or reserved_ids.has(candidate.instance_id)):
			return null
		var rotation := _resolve_rotation(candidate, -1)
		var fit := _find_first_fit_internal(candidate, rotation, _placements_from_plan(planned))
		if fit == NO_FIT:
			return null
		var planned_id: StringName = candidate.instance_id if not needs_creation else StringName("__planned_%d" % index)
		reserved_ids[planned_id] = true
		planned.append({
			&"instance": candidate if not needs_creation else null,
			&"definition": candidate.definition,
			&"needs_creation": needs_creation,
			&"anchor": fit,
			&"rotation": rotation,
			&"planned_id": planned_id,
		})
	return planned


func _placements_from_plan(planned: Array) -> Array[InventoryItemPlacement]:
	var result: Array[InventoryItemPlacement] = []
	for entry in planned:
		var candidate: InventoryItemInstance = entry[&"instance"]
		if candidate == null:
			candidate = InventoryItemInstanceScript.new(entry[&"planned_id"], entry[&"definition"], entry[&"rotation"])
		result.append(InventoryItemPlacement.new(candidate, entry[&"anchor"], entry[&"rotation"], inventory_id))
	return result


func _capture_factory_state():
	if _instance_factory != null and _instance_factory.has_method("capture_generator_state"):
		return _instance_factory.call("capture_generator_state")
	return null


func _restore_factory_state(state) -> void:
	if state != null and _instance_factory != null and _instance_factory.has_method("restore_generator_state"):
		_instance_factory.call("restore_generator_state", state)


func _capture_factory_state_for(factory):
	if factory != null and typeof(factory) == TYPE_OBJECT and factory.has_method("capture_generator_state"):
		return factory.call("capture_generator_state")
	return null


func _restore_factory_state_for(factory, state) -> void:
	if state != null and factory != null and typeof(factory) == TYPE_OBJECT and factory.has_method("restore_generator_state"):
		factory.call("restore_generator_state", state)


func _owner_key() -> StringName:
	return StringName("inventory:" + String(inventory_id))


func _release_instance_owner(instance: InventoryItemInstance) -> void:
	if instance == null or not instance.is_owned():
		return
	if instance.get_owner_id() == _owner_key():
		instance.release_owner(_owner_key())


func _release_all_items() -> void:
	for placement in placements:
		if placement != null:
			_release_instance_owner(placement.instance)


func _release_claimed_instances(resolved_placements: Array) -> void:
	for placement in resolved_placements:
		if placement is InventoryItemPlacement and placement.instance != null:
			if placement.instance.get_owner_id() == _owner_key():
				placement.instance.release_owner(_owner_key())


func _discard_instance(instance: Variant) -> void:
	_discard_instance_for(_instance_factory, instance)


func _discard_instances(instances: Array) -> void:
	_discard_instances_for(_instance_factory, instances)


func _discard_instance_for(factory: Variant, instance: Variant) -> void:
	if factory == null or instance == null or typeof(factory) != TYPE_OBJECT or not factory.has_method("discard_instance"):
		return
	factory.call("discard_instance", instance)


func _discard_instances_for(factory: Variant, instances: Array) -> void:
	for instance in instances:
		_discard_instance_for(factory, instance)


func _definition_is_valid(definition: ItemDefinition) -> bool:
	return definition != null and definition.is_valid()


func _resolve_rotation(candidate: InventoryItemInstance, requested_rotation: int) -> int:
	if requested_rotation >= 0:
		return ItemDefinition.rotation_to_degrees(requested_rotation)
	var existing_index := _find_placement_index(candidate)
	if existing_index >= 0:
		return placements[existing_index].rotation
	return candidate.rotation


func _find_placement_index(item_or_id: Variant) -> int:
	if item_or_id is InventoryItemPlacement:
		for index in range(placements.size()):
			if placements[index] == item_or_id:
				return index
		return -1
	if item_or_id is StringName or item_or_id is String:
		var requested_id := _coerce_id(item_or_id)
		for index in range(placements.size()):
			if placements[index].instance != null and placements[index].instance.instance_id == requested_id:
				return index
		return -1
	if item_or_id is InventoryItemInstance:
		for index in range(placements.size()):
			if placements[index].instance == item_or_id:
				return index
			if item_or_id.instance_id != &"" and placements[index].instance.instance_id == item_or_id.instance_id:
				return index
	if item_or_id is ItemDefinition:
		for index in range(placements.size()):
			if placements[index].instance.item_id == item_or_id.item_id:
				return index
	return -1


func _find_placement_id(candidate: InventoryItemInstance) -> StringName:
	var index := _find_placement_index(candidate)
	return placements[index].instance.instance_id if index >= 0 else &""


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


func _coerce_inventory_snapshot(value: Variant):
	if value is InventorySnapshot:
		return value
	if value is Dictionary:
		return InventorySnapshotScript.from_dictionary(value)
	return null


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
