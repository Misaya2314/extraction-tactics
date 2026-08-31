class_name InventoryItemInstance
extends RuntimeInstance

## Runtime identity for one concrete item. ItemDefinition is shared content and
## is never mutated by this class. Placement owns the authoritative rotation;
## the compatibility rotation property below is only a legacy display hint.

const DEFINITION_TYPE: StringName = &"item"
const ItemInstanceSnapshotScript = preload("res://scripts/core/runtime/snapshots/item_instance_snapshot.gd")
const ItemDefinitionKeyScript = preload("res://scripts/core/content/definition_key.gd")

var definition: ItemDefinition

var _legacy_rotation_degrees: int = 0
var _owner_id: StringName = &""
var rotation: int:
	get:
		return _legacy_rotation_degrees
	set(value):
		_legacy_rotation_degrees = ItemDefinition.rotation_to_degrees(value)

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
	var resolved_instance_id: StringName = &""
	var resolved_definition: ItemDefinition = null
	if new_instance_id is ItemDefinition:
		resolved_definition = new_instance_id as ItemDefinition
		resolved_instance_id = _coerce_string_name(new_definition)
	else:
		resolved_instance_id = _coerce_string_name(new_instance_id)
		if new_definition is ItemDefinition:
			resolved_definition = new_definition as ItemDefinition
	var resolved_definition_id: StringName = resolved_definition.item_id if resolved_definition != null else &""
	super(resolved_instance_id, DEFINITION_TYPE, resolved_definition_id)
	definition = resolved_definition
	rotation = new_rotation


func is_valid(registry: Variant = null) -> bool:
	return (
		is_valid_identity()
		and definition_type == DEFINITION_TYPE
		and definition != null
		and definition.is_valid()
		and definition_id == definition.item_id
		and _definition_is_resolved(registry)
	)


func validate(registry: Variant = null) -> bool:
	return is_valid(registry)


func get_definition_id() -> StringName:
	return definition_id


func get_definition_type() -> StringName:
	return definition_type


func get_definition_key():
	return definition_key()


func get_owner_id() -> StringName:
	## Ownership is runtime-only metadata. It is intentionally absent from the
	## item snapshot because a Placement/Container snapshot is the authority for
	## where the item belongs.
	return _owner_id


func is_owned() -> bool:
	return _owner_id != &""


func claim_owner(owner_id: StringName) -> bool:
	if owner_id == &"":
		return false
	if _owner_id != &"" and _owner_id != owner_id:
		return false
	_owner_id = owner_id
	return true


func release_owner(owner_id: StringName) -> bool:
	if owner_id == &"" or _owner_id != owner_id:
		return false
	_owner_id = &""
	return true


func bind_definition(resolved_definition: Variant) -> bool:
	## Hydration may bind the resolved Resource only when its stable ID matches.
	if not resolved_definition is ItemDefinition:
		return false
	var typed_definition: ItemDefinition = resolved_definition as ItemDefinition
	if not typed_definition.is_valid() or (definition_id != &"" and definition_id != typed_definition.item_id):
		return false
	definition = typed_definition
	definition_type = DEFINITION_TYPE
	definition_id = typed_definition.item_id
	return true


func get_rotation_degrees() -> int:
	return rotation


func get_rotation_quarters() -> int:
	return ItemDefinition.normalize_rotation(rotation)


func get_occupied_cells(requested_rotation: int = -1) -> Array[Vector2i]:
	if definition == null:
		return []
	var effective_rotation := rotation if requested_rotation < 0 else ItemDefinition.rotation_to_degrees(requested_rotation)
	return definition.get_rotated_cells(effective_rotation)


func get_shape_size(requested_rotation: int = -1) -> Vector2i:
	if definition == null:
		return Vector2i.ZERO
	var effective_rotation := rotation if requested_rotation < 0 else ItemDefinition.rotation_to_degrees(requested_rotation)
	return definition.get_shape_size(effective_rotation)


func to_snapshot() -> Dictionary:
	return to_snapshot_resource().to_dictionary()


func to_snapshot_resource():
	var snapshot = ItemInstanceSnapshotScript.new()
	snapshot.instance_id = instance_id
	snapshot.definition_type = definition_type
	snapshot.definition_id = definition_id
	return snapshot


static func from_snapshot(snapshot: Variant, registry: Variant):
	var result := InventoryItemInstance.new()
	if not result.hydrate_from_snapshot(snapshot, registry):
		return null
	return result


func hydrate_from_snapshot(snapshot: Variant, registry: Variant) -> bool:
	var typed_snapshot = _coerce_snapshot(snapshot)
	if typed_snapshot == null or not typed_snapshot.is_valid():
		return false
	if registry == null or typeof(registry) != TYPE_OBJECT or (not registry.has_method("resolve_key") and not registry.has_method("resolve")):
		return false
	if typed_snapshot.definition_type != DEFINITION_TYPE:
		return false
	var definition_key := ItemDefinitionKeyScript.new(typed_snapshot.definition_type, typed_snapshot.definition_id)
	if not definition_key.is_valid():
		return false
	var resolved = registry.call("resolve_key", definition_key) if registry.has_method("resolve_key") else registry.call("resolve", definition_key.definition_type, definition_key.definition_id)
	if not resolved is ItemDefinition or not (resolved as ItemDefinition).is_valid():
		return false
	var typed_definition: ItemDefinition = resolved as ItemDefinition
	if typed_definition.item_id != typed_snapshot.definition_id:
		return false
	if not RuntimeInstance._is_valid_instance_id(typed_snapshot.instance_id):
		return false
	instance_id = typed_snapshot.instance_id
	definition_type = DEFINITION_TYPE
	definition_id = typed_snapshot.definition_id
	definition = typed_definition
	_legacy_rotation_degrees = 0
	return true


func clone_as_new(new_instance_id: StringName) -> InventoryItemInstance:
	if not is_valid() or not RuntimeInstance._is_valid_instance_id(new_instance_id):
		return null
	return InventoryItemInstance.new(new_instance_id, definition)


func _definition_is_resolved(registry: Variant) -> bool:
	if registry == null:
		return true
	if typeof(registry) != TYPE_OBJECT or (not registry.has_method("resolve_key") and not registry.has_method("resolve") and not registry.has_method("contains")):
		return false
	var definition_key := ItemDefinitionKeyScript.new(DEFINITION_TYPE, definition_id)
	var resolved = null
	if registry.has_method("resolve_key"):
		resolved = registry.call("resolve_key", definition_key)
		return resolved is ItemDefinition and (resolved as ItemDefinition).item_id == definition_id
	if registry.has_method("resolve"):
		resolved = registry.call("resolve", definition_key.definition_type, definition_key.definition_id)
		return resolved is ItemDefinition and (resolved as ItemDefinition).item_id == definition_id
	return bool(registry.call("contains", DEFINITION_TYPE, definition_id))


static func _coerce_snapshot(value: Variant):
	if value is ItemInstanceSnapshot:
		return value
	if value is Dictionary:
		return ItemInstanceSnapshotScript.from_dictionary(value)
	return null


static func _coerce_string_name(value: Variant) -> StringName:
	if value is StringName or value is String:
		return StringName(value)
	return &""
