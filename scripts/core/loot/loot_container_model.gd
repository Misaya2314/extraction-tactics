class_name LootContainerModel
extends RefCounted

## Runtime ownership model for a Loot container. Item instances are created by
## an injected ItemInstanceFactory and are moved by identity, never copied.

const NO_FIT: Vector2i = Vector2i(-1, -1)
const LootContainerSnapshotScript = preload("res://scripts/core/runtime/snapshots/loot_container_snapshot.gd")

var container_id: StringName = &""
var opened: bool = false
var depleted: bool = true

var _items: Array[InventoryItemInstance] = []
var _instance_factory
var last_reason_code: StringName = &""


func _init(new_instance_factory = null) -> void:
	if new_instance_factory != null:
		set_instance_factory(new_instance_factory)


func set_instance_factory(new_instance_factory) -> bool:
	if new_instance_factory == null:
		_instance_factory = null
		return true
	if typeof(new_instance_factory) != TYPE_OBJECT or not new_instance_factory.has_method("create") or not new_instance_factory.has_method("hydrate"):
		last_reason_code = &"invalid_instance_factory"
		return false
	_instance_factory = new_instance_factory
	last_reason_code = &"factory_configured"
	return true


func get_instance_factory():
	return _instance_factory


func initialize(
		new_container_id: StringName,
		table: LootTableDefinition,
		random_seed: int = -1,
		rng: RandomNumberGenerator = null,
		instance_factory = null
	) -> bool:
	var factory = instance_factory if instance_factory != null else _instance_factory
	if new_container_id == &"" or table == null or not table.is_valid():
		last_reason_code = &"invalid_loot_table"
		return false
	if factory == null or typeof(factory) != TYPE_OBJECT or not factory.has_method("create") or not factory.has_method("hydrate"):
		last_reason_code = &"missing_instance_factory"
		return false
	var generated: Array[ItemDefinition] = table.generate_contents(random_seed, rng)
	var generator_state = _capture_factory_state(factory)
	var created: Array[InventoryItemInstance] = []
	for definition in generated:
		if definition == null or not definition.is_valid():
			_discard_instances_for(factory, created)
			_restore_factory_state(factory, generator_state)
			last_reason_code = &"invalid_loot_definition"
			return false
		var instance = factory.call("create", definition)
		if not instance is InventoryItemInstance or not instance.is_valid() or _contains_id(created, instance.instance_id):
			_discard_instance_for(factory, instance)
			_discard_instances_for(factory, created)
			_restore_factory_state(factory, generator_state)
			last_reason_code = &"instance_creation_failed"
			return false
		created.append(instance)
	for instance in created:
		if instance == null or instance.is_owned() or not instance.claim_owner(_owner_key_for(new_container_id)):
			_release_claimed_instances(created, new_container_id)
			_discard_instances_for(factory, created)
			_restore_factory_state(factory, generator_state)
			last_reason_code = &"ownership_conflict"
			return false
	_release_all_items()
	container_id = new_container_id
	_items = created
	_instance_factory = factory
	opened = false
	depleted = _items.is_empty()
	last_reason_code = &"ok"
	return true


func initialize_from_table(
		new_container_id: StringName,
		table: LootTableDefinition,
		random_seed: int = -1,
		rng: RandomNumberGenerator = null,
		instance_factory = null
	) -> bool:
	return initialize(new_container_id, table, random_seed, rng, instance_factory)


func open() -> bool:
	if container_id == &"" or depleted:
		last_reason_code = &"container_unavailable"
		return false
	opened = true
	last_reason_code = &"ok"
	return true


func is_opened() -> bool:
	return opened


func is_depleted() -> bool:
	return depleted


func get_item_count() -> int:
	return _items.size()


func get_item(index: int) -> InventoryItemInstance:
	if index < 0 or index >= _items.size():
		return null
	return _items[index]


func get_instances() -> Array[InventoryItemInstance]:
	return _items.duplicate()


func get_contents_instances() -> Array[InventoryItemInstance]:
	return get_instances()


func get_items() -> Array[InventoryItemInstance]:
	return get_instances()


func get_contents() -> Array[ItemDefinition]:
	return get_item_definitions()


func view_contents() -> Array[ItemDefinition]:
	if not depleted:
		opened = true
	return get_contents()


func transfer_to_inventory_at(index: int, inventory: SquadInventory, anchor: Vector2i, requested_rotation: int = -1) -> bool:
	if inventory == null or depleted or index < 0 or index >= _items.size():
		last_reason_code = &"invalid_transfer"
		return false
	var item := _items[index]
	if item == null or (item.is_owned() and item.get_owner_id() != _owner_key()) or not inventory.can_place(item, anchor, requested_rotation, true):
		last_reason_code = &"invalid_destination"
		return false
	# Remove first, then commit to the destination. If the destination rejects
	# despite the preflight, restore the exact source slot and identity.
	if not item.claim_owner(_owner_key()):
		last_reason_code = &"ownership_conflict"
		return false
	_items.remove_at(index)
	item.release_owner(_owner_key())
	if not inventory.place(item, anchor, requested_rotation):
		item.claim_owner(_owner_key())
		_items.insert(index, item)
		last_reason_code = &"destination_rejected"
		return false
	opened = true
	depleted = _items.is_empty()
	last_reason_code = &"ok"
	return true


func transfer_to_inventory(index: int, inventory: SquadInventory) -> bool:
	if inventory == null or depleted or index < 0 or index >= _items.size():
		return false
	var item := _items[index]
	var anchor := inventory.find_first_fit(item, -1, true)
	if anchor == NO_FIT:
		last_reason_code = &"invalid_destination"
		return false
	return transfer_to_inventory_at(index, inventory, anchor)


func transfer_all_to_inventory(inventory: SquadInventory) -> bool:
	if inventory == null or depleted or _items.is_empty():
		last_reason_code = &"invalid_transfer"
		return false
	if not inventory.can_add_items(_items, true):
		last_reason_code = &"invalid_destination"
		return false
	for item in _items:
		if item == null or (item.is_owned() and item.get_owner_id() != _owner_key()) or not item.claim_owner(_owner_key()):
			for claimed in _items:
				if claimed != null and claimed.get_owner_id() == _owner_key():
					claimed.release_owner(_owner_key())
			last_reason_code = &"ownership_conflict"
			return false
	for item in _items:
		item.release_owner(_owner_key())
	if not inventory.add_items(_items):
		for item in _items:
			if item != null:
				item.claim_owner(_owner_key())
		last_reason_code = &"destination_rejected"
		return false
	_items.clear()
	opened = true
	depleted = true
	last_reason_code = &"ok"
	return true


func transfer_from_inventory(item_or_id: Variant, inventory: SquadInventory) -> bool:
	if container_id == &"":
		last_reason_code = &"container_uninitialized"
		return false
	if inventory == null:
		last_reason_code = &"invalid_source"
		return false
	var placement = inventory.get_placement(item_or_id)
	if placement == null or placement.instance == null:
		last_reason_code = &"invalid_source"
		return false
	var item: InventoryItemInstance = placement.instance
	if _contains_id(_items, item.instance_id):
		last_reason_code = &"duplicate_ownership"
		return false
	# A placement is only a valid source when its item is still owned by that
	# inventory.  Rejecting corrupted ownership before take() keeps the
	# operation atomic and makes the rollback path below defensive rather than
	# a normal way to repair an already-invalid source.
	var source_owner := StringName("inventory:" + String(inventory.inventory_id))
	if item.is_owned() and item.get_owner_id() != source_owner:
		last_reason_code = &"source_ownership_conflict"
		return false
	var taken = inventory.take(item)
	if taken == null:
		last_reason_code = &"source_rejected"
		return false
	if not taken.claim_owner(_owner_key()):
		var restored: bool = inventory.place(taken, placement.anchor, placement.rotation)
		last_reason_code = &"ownership_conflict" if restored else &"rollback_failed"
		return false
	_items.append(taken)
	opened = true
	depleted = false
	last_reason_code = &"ok"
	return true


func to_snapshot() -> Dictionary:
	return to_snapshot_resource().to_dictionary()


func to_snapshot_resource():
	var snapshot = LootContainerSnapshotScript.new()
	snapshot.container_id = container_id
	snapshot.opened = opened
	snapshot.depleted = depleted
	for item in _items:
		if item != null:
			snapshot.items.append(item.to_snapshot_resource())
	return snapshot


static func from_snapshot(snapshot: Variant, registry: Variant, factory: Variant):
	var result := LootContainerModel.new(factory)
	if not result.hydrate_from_snapshot(snapshot, registry, factory):
		return null
	return result


func hydrate_from_snapshot(snapshot: Variant, registry: Variant, factory: Variant) -> bool:
	var typed_snapshot = _coerce_snapshot(snapshot)
	if typed_snapshot == null or not typed_snapshot.is_valid():
		last_reason_code = &"invalid_snapshot"
		return false
	if factory == null or typeof(factory) != TYPE_OBJECT or not factory.has_method("hydrate"):
		last_reason_code = &"missing_instance_factory"
		return false
	var generator_state = _capture_factory_state(factory)
	var restored: Array[InventoryItemInstance] = []
	for item_snapshot in typed_snapshot.items:
		var item = factory.call("hydrate", item_snapshot, registry)
		if not item is InventoryItemInstance or not item.is_valid(registry) or _contains_id(restored, item.instance_id):
			_discard_instance_for(factory, item)
			_discard_instances_for(factory, restored)
			_restore_factory_state(factory, generator_state)
			last_reason_code = &"missing_definition"
			return false
		restored.append(item)
	var target_owner := _owner_key_for(typed_snapshot.container_id)
	for item in restored:
		if item == null or item.is_owned() or not item.claim_owner(target_owner):
			_release_claimed_instances(restored, typed_snapshot.container_id)
			_discard_instances_for(factory, restored)
			_restore_factory_state(factory, generator_state)
			last_reason_code = &"ownership_conflict"
			return false
	_release_all_items()
	container_id = typed_snapshot.container_id
	opened = typed_snapshot.opened
	depleted = typed_snapshot.depleted
	_items = restored
	_instance_factory = factory
	last_reason_code = &"hydrated"
	return true


func get_item_definitions() -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	for item in _items:
		if item != null:
			result.append(item.definition)
	return result


func _coerce_snapshot(value: Variant):
	if value is LootContainerSnapshot:
		return value
	if value is Dictionary:
		return LootContainerSnapshotScript.from_dictionary(value)
	return null


func _capture_factory_state(factory):
	if factory != null and factory.has_method("capture_generator_state"):
		return factory.call("capture_generator_state")
	return null


func _restore_factory_state(factory, state) -> void:
	if state != null and factory != null and factory.has_method("restore_generator_state"):
		factory.call("restore_generator_state", state)


func _contains_id(items: Array, wanted_id: StringName) -> bool:
	if wanted_id == &"":
		return false
	for item in items:
		if item != null and item.instance_id == wanted_id:
			return true
	return false


func _owner_key() -> StringName:
	return _owner_key_for(container_id)


func _owner_key_for(id: StringName) -> StringName:
	return StringName("loot:" + String(id))


func _release_all_items() -> void:
	for item in _items:
		if item != null and item.get_owner_id() == _owner_key():
			item.release_owner(_owner_key())


func _release_claimed_instances(items: Array, owner_container_id: StringName) -> void:
	var owner := _owner_key_for(owner_container_id)
	for item in items:
		if item != null and item.get_owner_id() == owner:
			item.release_owner(owner)


func _discard_instance_for(factory: Variant, instance: Variant) -> void:
	if factory == null or instance == null or typeof(factory) != TYPE_OBJECT or not factory.has_method("discard_instance"):
		return
	factory.call("discard_instance", instance)


func _discard_instances_for(factory: Variant, instances: Array) -> void:
	for instance in instances:
		_discard_instance_for(factory, instance)
