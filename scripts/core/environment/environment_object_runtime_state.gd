class_name EnvironmentObjectRuntimeState
extends RuntimeInstance

## Runtime state for one map environment object.  The TacticalObjectDefinition
## reference is read-only configuration; mutable HP and lifecycle flags live
## only on this RefCounted instance and in its pure-data snapshot.

const DEFINITION_TYPE: StringName = &"placeable"
const SNAPSHOT_SCHEMA_VERSION: int = 1
const RuntimeOperationResultScript = preload("res://scripts/core/runtime/runtime_operation_result.gd")

var definition: TacticalObjectDefinition
var placement_id: StringName = &""
var cell: Vector3i = Vector3i.ZERO
var facing: Vector2i = Vector2i.DOWN
var current_hp: int = 0
var active: bool = false
var destroyed: bool = false
var destroy_effect_triggered: bool = false
var state_version: int = SNAPSHOT_SCHEMA_VERSION

## Compatibility/readability alias.  `destroy_effect_triggered` is the one
## stored authority; this property does not create a second state value.
var effect_triggered: bool:
	get:
		return destroy_effect_triggered
	set(value):
		destroy_effect_triggered = value


func _init(
		new_instance_id: Variant = &"",
		new_definition: Variant = null,
		new_placement: Variant = null
) -> void:
	var instance_token := _strict_string_name(new_instance_id)
	var resolved_definition := new_definition as TacticalObjectDefinition
	var resolved_definition_id: StringName = resolved_definition.placeable_id if resolved_definition != null else &""
	super(instance_token, DEFINITION_TYPE, resolved_definition_id)
	if resolved_definition != null and new_placement is MapObjectPlacement:
		configure_from_placement(resolved_definition, new_placement as MapObjectPlacement)


func configure_from_placement(
		resolved_definition: TacticalObjectDefinition,
		placement: MapObjectPlacement
) -> bool:
	if resolved_definition == null or not resolved_definition.is_valid() or placement == null:
		return false
	if not _is_valid_token(placement.object_id):
		return false
	if placement.definition_id != &"" and placement.definition_id != resolved_definition.placeable_id:
		return false
	if not configure_identity(instance_id, DEFINITION_TYPE, resolved_definition.placeable_id):
		return false
	definition = resolved_definition
	placement_id = placement.object_id
	cell = placement.cell
	facing = placement.facing
	current_hp = resolved_definition.max_hp if resolved_definition.damageable else 0
	active = true
	destroyed = false
	destroy_effect_triggered = false
	state_version = SNAPSHOT_SCHEMA_VERSION
	return true


func get_definition() -> TacticalObjectDefinition:
	return definition


func get_placement_id() -> StringName:
	return placement_id


func get_cell() -> Vector3i:
	return cell


func is_damageable() -> bool:
	return definition != null and definition.damageable and definition.max_hp > 0


func can_receive_damage() -> bool:
	return active and not destroyed and is_damageable()


func is_alive() -> bool:
	return active and not destroyed


func get_max_hp() -> int:
	return definition.max_hp if definition != null else 0


func get_destroy_effects() -> Array[Resource]:
	var result: Array[Resource] = []
	if definition == null:
		return result
	for effect in definition.on_destroy_effects:
		if effect != null:
			result.append(effect)
	return result


func is_valid(registry: Variant = null) -> bool:
	return (
		is_valid_identity()
		and definition_type == DEFINITION_TYPE
		and definition != null
		and definition.is_valid()
		and definition.placeable_id == definition_id
		and _is_valid_token(placement_id)
		and state_version == SNAPSHOT_SCHEMA_VERSION
		and current_hp >= 0
		and current_hp <= get_max_hp()
		and active == not destroyed
		and (not destroy_effect_triggered or destroyed)
		and (not definition.damageable or get_max_hp() > 0)
		and _definition_is_resolved(registry)
	)


func apply_damage(amount: Variant) -> RuntimeOperationResult:
	if typeof(amount) != TYPE_INT:
		return _failed(&"invalid_damage", "Environment damage must be an integer.")
	var damage_amount: int = amount
	if damage_amount < 0:
		return _failed(&"invalid_damage", "Environment damage cannot be negative.")
	if destroyed or not active:
		return _failed(&"already_destroyed", "The environment object is no longer active.", {&"current_hp": current_hp})
	if not is_damageable():
		return _failed(&"not_damageable", "The environment object cannot receive damage.")
	if damage_amount == 0:
		return _state_result(&"no_change", 0, false)
	var previous_hp := current_hp
	current_hp = maxi(0, current_hp - damage_amount)
	var destroyed_now := current_hp == 0
	if destroyed_now:
		active = false
		destroyed = true
	return _state_result(&"destroyed" if destroyed_now else &"damaged", previous_hp - current_hp, destroyed_now)


func take_damage(amount: Variant) -> RuntimeOperationResult:
	return apply_damage(amount)


## Mark the configured ON_DESTROYED reaction as dispatched.  This is separate
## from setting `destroyed`, so a caller can resolve and apply the pure effect
## rules before recording the one-shot trigger.
func trigger_destroy_effects() -> bool:
	if not destroyed or destroy_effect_triggered:
		return false
	destroy_effect_triggered = true
	return true


func mark_destroy_effect_triggered() -> bool:
	return trigger_destroy_effects()


func consume_destroy_effect_trigger() -> bool:
	return trigger_destroy_effects()


func to_snapshot() -> Dictionary:
	return {
		&"schema_version": SNAPSHOT_SCHEMA_VERSION,
		&"instance_id": instance_id,
		&"definition_type": definition_type,
		&"definition_id": definition_id,
		&"placement_id": placement_id,
		&"cell": cell,
		&"facing": facing,
		&"current_hp": current_hp,
		&"active": active,
		&"destroyed": destroyed,
		&"effect_triggered": destroy_effect_triggered,
	}


static func from_snapshot(
		snapshot: Variant,
		resolved_definition: TacticalObjectDefinition,
		registry: Variant = null
) -> EnvironmentObjectRuntimeState:
	var result := EnvironmentObjectRuntimeState.new()
	if not result.hydrate_from_snapshot(snapshot, resolved_definition, registry):
		return null
	return result


func hydrate_from_snapshot(
		snapshot: Variant,
		resolved_definition: TacticalObjectDefinition,
		registry: Variant = null
) -> bool:
	var values := _validated_snapshot_values(snapshot, resolved_definition, registry)
	if values.is_empty():
		return false
	definition = resolved_definition
	instance_id = values[&"instance_id"]
	definition_type = DEFINITION_TYPE
	definition_id = resolved_definition.placeable_id
	placement_id = values[&"placement_id"]
	cell = values[&"cell"]
	facing = values[&"facing"]
	current_hp = values[&"current_hp"]
	active = values[&"active"]
	destroyed = values[&"destroyed"]
	destroy_effect_triggered = values[&"effect_triggered"]
	state_version = SNAPSHOT_SCHEMA_VERSION
	return true


func _validated_snapshot_values(
		snapshot: Variant,
		resolved_definition: TacticalObjectDefinition,
		registry: Variant
) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY or resolved_definition == null or not resolved_definition.is_valid():
		return {}
	var data: Dictionary = snapshot
	for key in [
		&"schema_version", &"instance_id", &"definition_type", &"definition_id",
		&"placement_id", &"cell", &"facing", &"current_hp", &"active",
		&"destroyed", &"effect_triggered"
	]:
		if not data.has(key):
			return {}
	if typeof(data[&"schema_version"]) != TYPE_INT or int(data[&"schema_version"]) != SNAPSHOT_SCHEMA_VERSION:
		return {}
	for key in [&"instance_id", &"definition_type", &"definition_id", &"placement_id"]:
		if typeof(data[key]) != TYPE_STRING_NAME:
			return {}
	if typeof(data[&"cell"]) != TYPE_VECTOR3I or typeof(data[&"facing"]) != TYPE_VECTOR2I:
		return {}
	if typeof(data[&"current_hp"]) != TYPE_INT:
		return {}
	for key in [&"active", &"destroyed", &"effect_triggered"]:
		if typeof(data[key]) != TYPE_BOOL:
			return {}
	var candidate_id: StringName = data[&"instance_id"]
	var candidate_type: StringName = data[&"definition_type"]
	var candidate_definition_id: StringName = data[&"definition_id"]
	var candidate_placement_id: StringName = data[&"placement_id"]
	if not _is_valid_token(candidate_id) or not _is_valid_token(candidate_placement_id):
		return {}
	if candidate_type != DEFINITION_TYPE or candidate_definition_id != resolved_definition.placeable_id:
		return {}
	if registry != null and not _registry_resolves(registry, candidate_definition_id, resolved_definition):
		return {}
	var hp: int = data[&"current_hp"]
	var is_active: bool = data[&"active"]
	var is_destroyed: bool = data[&"destroyed"]
	if hp < 0 or hp > resolved_definition.max_hp:
		return {}
	if is_destroyed and (is_active or hp != 0):
		return {}
	if not is_destroyed and not is_active:
		return {}
	if data[&"effect_triggered"] and not is_destroyed:
		return {}
	if not resolved_definition.damageable and hp != 0:
		return {}
	return {
		&"instance_id": candidate_id,
		&"placement_id": candidate_placement_id,
		&"cell": data[&"cell"],
		&"facing": data[&"facing"],
		&"current_hp": hp,
		&"active": is_active,
		&"destroyed": is_destroyed,
		&"effect_triggered": data[&"effect_triggered"],
	}


func _definition_is_resolved(registry: Variant) -> bool:
	if registry == null:
		return true
	return _registry_resolves(registry, definition_id, definition)


static func _registry_resolves(registry: Variant, candidate_id: StringName, expected: TacticalObjectDefinition) -> bool:
	if typeof(registry) != TYPE_OBJECT:
		return false
	if registry.has_method("resolve"):
		var resolved = registry.call("resolve", DEFINITION_TYPE, candidate_id)
		return resolved == expected or (resolved is TacticalObjectDefinition and (resolved as TacticalObjectDefinition).placeable_id == candidate_id)
	if registry.has_method("contains"):
		return bool(registry.call("contains", DEFINITION_TYPE, candidate_id))
	return false


func _state_result(reason: StringName, damage_done: int, destroyed_now: bool) -> RuntimeOperationResult:
	return RuntimeOperationResultScript.succeeded({
		&"damage": damage_done,
		&"current_hp": current_hp,
		&"destroyed_now": destroyed_now,
		&"effect_pending": destroyed_now and not destroy_effect_triggered,
	}, "Environment object state updated.", instance_id)


func _failed(code: StringName, message: String, result_value: Variant = null) -> RuntimeOperationResult:
	return RuntimeOperationResultScript.failed(code, message, result_value, instance_id)


static func _strict_string_name(value: Variant) -> StringName:
	return value if typeof(value) == TYPE_STRING_NAME else &""


static func _is_valid_token(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING_NAME:
		return false
	var text := String(value).strip_edges()
	if text.is_empty():
		return false
	for character in ["\t", "\r", "\n", "/", "\\"]:
		if text.contains(character):
			return false
	return true
