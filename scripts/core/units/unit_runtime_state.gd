class_name UnitRuntimeState
extends RuntimeInstance

## Pure runtime state for a unit. It has no Node or presentation dependency.
## RuntimeInstance owns the shared identity fields; definition_id is the
## archetype ID for this domain.

const DEFINITION_TYPE: StringName = &"unit_archetype"
const CURRENT_STATE_VERSION: int = 1
const DEFAULT_FACING: Vector2i = Vector2i(0, 1)
const DEFAULT_CELL: Vector3i = Vector3i.ZERO
## This metadata key is intentionally runtime-only.  The native Object ID
## stored in it identifies the live owner, but is never persisted in a
## snapshot.  Keeping the owner on the WeaponInstance also avoids a global
## strong-reference table and lets destruction release ownership safely.
const WEAPON_OWNER_META: StringName = &"_unit_runtime_state_owner"
const UnitStateSnapshotScript = preload("res://scripts/core/runtime/snapshots/unit_state_snapshot.gd")

## State change signals are the only bridge a View needs.  Snapshot hydration
## assigns fields directly and deliberately emits none of these signals.
signal health_changed(current: int, maximum: int)
signal action_points_changed(current: int, maximum: int)
signal cell_changed(previous: Vector3i, current: Vector3i)
signal facing_changed(previous: Vector2i, current: Vector2i)
signal weapon_changed(previous: WeaponInstance, current: WeaponInstance)
signal alive_changed(alive: bool)
signal died

var archetype: UnitArchetype
var faction: StringName = &""
var current_hp: int = 0
var current_action_points: int = 0
var cell: Vector3i = DEFAULT_CELL
var facing: Vector2i = DEFAULT_FACING
var inventory_id: StringName = &""
var alive: bool = false
var state_version: int = CURRENT_STATE_VERSION
var last_operation_reason: StringName = &""

var _weapon_instance: WeaponInstance
var _weapon_instance_id: StringName = &""
var _ownership_token: int = 0


func _init(
	new_instance_id: Variant = &"",
	new_archetype: Variant = null,
	new_faction: Variant = &"",
	new_cell: Variant = DEFAULT_CELL,
	new_facing: Variant = DEFAULT_FACING,
	new_weapon_instance: Variant = null,
	new_inventory_id: Variant = &"",
) -> void:
	var resolved_instance_id := _coerce_string_name(new_instance_id)
	var resolved_archetype: UnitArchetype = null
	if new_instance_id is UnitArchetype:
		resolved_archetype = new_instance_id as UnitArchetype
		resolved_instance_id = _coerce_string_name(new_archetype)
	elif new_archetype is UnitArchetype:
		resolved_archetype = new_archetype as UnitArchetype

	var resolved_archetype_id: StringName = resolved_archetype.archetype_id if resolved_archetype != null else &""
	super(resolved_instance_id, DEFINITION_TYPE, resolved_archetype_id)
	_ownership_token = get_instance_id()

	archetype = resolved_archetype
	faction = _coerce_string_name(new_faction)
	if new_cell is Vector3i:
		cell = new_cell
	if new_facing is Vector2i:
		facing = new_facing
	inventory_id = _coerce_string_name(new_inventory_id)

	current_hp = max_hp
	current_action_points = max_action_points
	alive = archetype != null and archetype.is_valid() and current_hp > 0

	if new_weapon_instance is WeaponInstance:
		var initial_weapon: WeaponInstance = new_weapon_instance as WeaponInstance
		if initial_weapon.is_valid() and _claim_weapon_ownership(initial_weapon):
			_weapon_instance = initial_weapon
		else:
			last_operation_reason = &"weapon_already_owned" if initial_weapon.is_valid() else &"invalid_weapon_instance"
	elif new_weapon_instance != null:
		last_operation_reason = &"invalid_weapon_instance"
	_sync_weapon_instance_id()


func _notification(what: int) -> void:
	## RefCounted instances receive NOTIFICATION_PREDELETE before their final
	## release.  No signal is emitted here: teardown must not call Views or
	## controllers, it only releases the live weapon ownership marker.
	if what == NOTIFICATION_PREDELETE:
		# Do this inline instead of calling another script method.  During the
		# final RefCounted notification Godot may already have detached the
		# script call surface, while the Object metadata is still available.
		var target: WeaponInstance = _weapon_instance
		if target != null and target.has_meta(WEAPON_OWNER_META):
			var recorded_owner = target.get_meta(WEAPON_OWNER_META, 0)
			if typeof(recorded_owner) == TYPE_INT and int(recorded_owner) == _ownership_token:
				target.remove_meta(WEAPON_OWNER_META)


## Alias used by the unit domain while RuntimeInstance.definition_id remains
## the shared identity field.
var archetype_id: StringName:
	get:
		return definition_id
	set(value):
		definition_id = _coerce_string_name(value)


var weapon_instance: WeaponInstance:
	get:
		return _weapon_instance
	set(value):
		if value == null:
			unequip()
		else:
			equip(value)


var weapon_instance_id: StringName:
	get:
		return _weapon_instance_id
	set(value):
		var candidate_id := _coerce_string_name(value)
		if value != &"" and candidate_id == &"":
			_reject(&"invalid_weapon_instance_id")
			return
		if candidate_id == &"":
			if _weapon_instance != null:
				_reject(&"weapon_instance_required")
				return
			_weapon_instance_id = &""
			return
		if _weapon_instance == null or candidate_id != _weapon_instance.instance_id:
			_reject(&"weapon_instance_id_mismatch")
			return
		_weapon_instance_id = candidate_id


var max_hp: int:
	get:
		return archetype.max_hp if archetype != null else 0


var max_action_points: int:
	get:
		return archetype.max_action_points if archetype != null else 0


var move_range: int:
	get:
		return archetype.move_range if archetype != null else 0


var vision_range: int:
	get:
		return archetype.vision_range if archetype != null else 0


func is_valid(registry: Variant = null) -> bool:
	return (
		is_valid_identity()
		and definition_type == DEFINITION_TYPE
		and archetype != null
		and archetype.is_valid()
		and archetype.archetype_id == archetype_id
		and _definition_is_resolved(registry)
		and faction != &""
		and is_valid_cell(cell)
		and is_valid_facing(facing)
		and current_hp >= 0
		and current_hp <= max_hp
		and current_action_points >= 0
		and current_action_points <= max_action_points
		and alive == (current_hp > 0)
		and state_version == CURRENT_STATE_VERSION
		and _weapon_state_is_consistent(registry)
	)


func validate() -> bool:
	return is_valid()


func get_definition_id() -> StringName:
	return definition_id


func get_definition_type() -> StringName:
	return definition_type


func get_definition_key() -> DefinitionKey:
	return definition_key()


func get_max_hp() -> int:
	return max_hp


func get_max_action_points() -> int:
	return max_action_points


func get_move_range() -> int:
	return move_range


func get_vision_range() -> int:
	return vision_range


func get_cell() -> Vector3i:
	return cell


func get_facing() -> Vector2i:
	return facing


func get_weapon_instance() -> WeaponInstance:
	return weapon_instance


func get_inventory_id() -> StringName:
	return inventory_id


func get_last_operation_reason() -> StringName:
	return last_operation_reason


func apply_damage(amount: int) -> bool:
	if amount < 0:
		return _reject(&"invalid_damage")
	if not alive:
		return _reject(&"not_alive")
	if amount == 0:
		last_operation_reason = &"no_change"
		return true
	var was_alive := alive
	current_hp = maxi(0, current_hp - amount)
	if current_hp == 0:
		alive = false
	health_changed.emit(current_hp, max_hp)
	if was_alive and not alive:
		alive_changed.emit(false)
		died.emit()
	return _accept(&"damaged")


func heal(amount: int) -> bool:
	if amount <= 0:
		return _reject(&"invalid_heal")
	if not alive:
		return _reject(&"not_alive")
	if current_hp >= max_hp:
		return _reject(&"at_max_hp")
	current_hp = mini(max_hp, current_hp + amount)
	health_changed.emit(current_hp, max_hp)
	return _accept(&"healed")


func spend_ap(cost: int) -> bool:
	if cost <= 0:
		return _reject(&"invalid_ap_cost")
	if not alive:
		return _reject(&"not_alive")
	if cost > current_action_points:
		return _reject(&"insufficient_ap")
	current_action_points -= cost
	action_points_changed.emit(current_action_points, max_action_points)
	return _accept(&"ap_spent")


func spend_action_points(cost: int) -> bool:
	return spend_ap(cost)


func reset_ap() -> bool:
	if archetype == null or not archetype.is_valid():
		return _reject(&"invalid_archetype")
	if not alive:
		return _reject(&"not_alive")
	if current_action_points == max_action_points:
		last_operation_reason = &"no_change"
		return true
	current_action_points = max_action_points
	action_points_changed.emit(current_action_points, max_action_points)
	return _accept(&"ap_reset")


func reset_action_points() -> bool:
	return reset_ap()


func set_cell(new_cell: Variant) -> bool:
	if not is_valid_cell(new_cell):
		return _reject(&"invalid_cell")
	if not alive:
		return _reject(&"not_alive")
	var typed_cell: Vector3i = new_cell
	if cell == typed_cell:
		last_operation_reason = &"no_change"
		return false
	var previous_cell := cell
	cell = typed_cell
	cell_changed.emit(previous_cell, cell)
	return _accept(&"cell_set")


func move_to(new_cell: Variant) -> bool:
	return set_cell(new_cell)


func move_to_cell(new_cell: Variant) -> bool:
	return set_cell(new_cell)


func set_facing(new_facing: Variant) -> bool:
	if not is_valid_facing(new_facing):
		return _reject(&"invalid_facing")
	var typed_facing: Vector2i = new_facing
	if facing == typed_facing:
		last_operation_reason = &"no_change"
		return false
	var previous_facing := facing
	facing = typed_facing
	facing_changed.emit(previous_facing, facing)
	return _accept(&"facing_set")


func equip(new_weapon_instance: Variant) -> bool:
	if not new_weapon_instance is WeaponInstance:
		return _reject(&"invalid_weapon_instance")
	var typed_weapon: WeaponInstance = new_weapon_instance
	if not typed_weapon.is_valid():
		return _reject(&"invalid_weapon_instance")
	if weapon_instance == typed_weapon:
		last_operation_reason = &"no_change"
		return false
	if not _claim_weapon_ownership(typed_weapon):
		return _reject(&"weapon_already_owned")
	var previous_weapon := weapon_instance
	if previous_weapon != null and not _release_weapon_ownership(previous_weapon):
		# Claiming the replacement happened first, so an inconsistent old
		# ownership marker must not leave either weapon partially transferred.
		_release_weapon_ownership(typed_weapon)
		return _reject(&"weapon_ownership_corrupt")
	_weapon_instance = typed_weapon
	_sync_weapon_instance_id()
	weapon_changed.emit(previous_weapon, weapon_instance)
	return _accept(&"weapon_equipped")


func equip_weapon(new_weapon_instance: Variant) -> bool:
	return equip(new_weapon_instance)


func unequip() -> bool:
	if weapon_instance == null and weapon_instance_id == &"":
		last_operation_reason = &"no_change"
		return false
	var previous_weapon := weapon_instance
	if previous_weapon != null and not _release_weapon_ownership(previous_weapon):
		return _reject(&"weapon_ownership_corrupt")
	_weapon_instance = null
	_weapon_instance_id = &""
	weapon_changed.emit(previous_weapon, null)
	return _accept(&"weapon_unequipped")


func set_inventory_id(new_inventory_id: Variant) -> bool:
	var typed_id := _coerce_string_name(new_inventory_id)
	if new_inventory_id != &"" and typed_id == &"":
		return _reject(&"invalid_inventory_id")
	if inventory_id == typed_id:
		last_operation_reason = &"no_change"
		return false
	inventory_id = typed_id
	return _accept(&"inventory_set")


func to_snapshot() -> Dictionary:
	## Match RuntimeInstance's generic dictionary snapshot API. The typed DTO
	## helper remains available for state hydration and domain callers.
	var payload := to_snapshot_resource().to_dictionary()
	payload[&"definition_type"] = definition_type
	return payload


func to_snapshot_resource() -> UnitStateSnapshot:
	var snapshot: UnitStateSnapshot = UnitStateSnapshotScript.new()
	snapshot.instance_id = instance_id
	snapshot.archetype_id = archetype_id
	snapshot.faction = faction
	snapshot.current_hp = current_hp
	snapshot.current_action_points = current_action_points
	snapshot.cell = cell
	snapshot.facing = facing
	snapshot.weapon_instance_id = weapon_instance_id
	snapshot.inventory_id = inventory_id
	snapshot.alive = alive
	snapshot.state_version = state_version
	return snapshot


static func from_snapshot(
	snapshot: Variant,
	resolved_archetype: UnitArchetype,
	resolved_weapon_instance: WeaponInstance = null,
) -> UnitRuntimeState:
	var result := UnitRuntimeState.new()
	if not result.hydrate_from_snapshot(snapshot, resolved_archetype, resolved_weapon_instance):
		return null
	return result


func hydrate_from_snapshot(
	snapshot: Variant,
	resolved_archetype: UnitArchetype,
	resolved_weapon_instance: WeaponInstance = null,
) -> bool:
	## Validate every value first, then assign directly. Hydration cannot emit
	## damage, death, reward, AI or presentation side effects.
	var typed_snapshot: UnitStateSnapshot = _coerce_snapshot(snapshot)
	if typed_snapshot == null:
		return _reject(&"invalid_snapshot")
	var validation_reason := _validate_snapshot(typed_snapshot, resolved_archetype, resolved_weapon_instance)
	if validation_reason != &"":
		return _reject(validation_reason)
	if resolved_weapon_instance != null and not _claim_weapon_ownership(resolved_weapon_instance):
		return _reject(&"weapon_already_owned")
	var previous_weapon := _weapon_instance
	if previous_weapon != null and previous_weapon != resolved_weapon_instance and not _release_weapon_ownership(previous_weapon):
		if resolved_weapon_instance != null:
			_release_weapon_ownership(resolved_weapon_instance)
		return _reject(&"weapon_ownership_corrupt")

	archetype = resolved_archetype
	definition_id = typed_snapshot.archetype_id
	instance_id = typed_snapshot.instance_id
	faction = typed_snapshot.faction
	current_hp = typed_snapshot.current_hp
	current_action_points = typed_snapshot.current_action_points
	cell = typed_snapshot.cell
	facing = typed_snapshot.facing
	inventory_id = typed_snapshot.inventory_id
	alive = typed_snapshot.alive
	_weapon_instance = resolved_weapon_instance
	_weapon_instance_id = typed_snapshot.weapon_instance_id
	state_version = typed_snapshot.state_version
	last_operation_reason = &"hydrated"
	return true


static func is_valid_cell(candidate: Variant) -> bool:
	if not candidate is Vector3i:
		return false
	return true


static func is_valid_facing(candidate: Variant) -> bool:
	if not candidate is Vector2i:
		return false
	var typed_facing: Vector2i = candidate
	return (
		typed_facing == Vector2i(0, -1)
		or typed_facing == Vector2i(-1, 0)
		or typed_facing == Vector2i(0, 1)
		or typed_facing == Vector2i(1, 0)
	)


func _validate_snapshot(
	snapshot: UnitStateSnapshot,
	resolved_archetype: UnitArchetype,
	resolved_weapon_instance: WeaponInstance,
) -> StringName:
	if snapshot == null or not snapshot.is_valid():
		return &"invalid_snapshot"
	if resolved_archetype == null or not resolved_archetype.is_valid():
		return &"invalid_archetype"
	if snapshot.archetype_id != resolved_archetype.archetype_id:
		return &"archetype_mismatch"
	if snapshot.current_hp > resolved_archetype.max_hp:
		return &"invalid_hp"
	if snapshot.current_action_points > resolved_archetype.max_action_points:
		return &"invalid_ap"
	if snapshot.weapon_instance_id == &"":
		if resolved_weapon_instance != null:
			return &"weapon_mismatch"
	else:
		if resolved_weapon_instance == null or not resolved_weapon_instance.is_valid():
			return &"missing_weapon_instance"
		if resolved_weapon_instance.instance_id != snapshot.weapon_instance_id:
			return &"weapon_mismatch"
	return &""


func _weapon_state_is_consistent(registry: Variant = null) -> bool:
	if weapon_instance_id == &"":
		return weapon_instance == null
	return (
		weapon_instance != null
		and weapon_instance.is_valid(registry)
		and weapon_instance.instance_id == weapon_instance_id
		and _is_weapon_owned_by_self(weapon_instance)
	)


static func _coerce_snapshot(value: Variant) -> UnitStateSnapshot:
	if value is UnitStateSnapshot:
		return value as UnitStateSnapshot
	if value is Dictionary:
		return UnitStateSnapshotScript.from_dictionary(value)
	return null


func _definition_is_resolved(registry: Variant) -> bool:
	if registry == null:
		return true
	if typeof(registry) != TYPE_OBJECT:
		return false
	if registry is RuntimeInstanceRegistry:
		return false
	if registry.has_method("resolve"):
		var resolved = registry.call("resolve", DEFINITION_TYPE, archetype_id)
		return resolved is UnitArchetype and (resolved as UnitArchetype).archetype_id == archetype_id
	if registry.has_method("contains"):
		return bool(registry.call("contains", DEFINITION_TYPE, archetype_id))
	return false


func _sync_weapon_instance_id() -> void:
	_weapon_instance_id = _weapon_instance.instance_id if _weapon_instance != null else &""


func _claim_weapon_ownership(weapon: WeaponInstance) -> bool:
	if weapon == null:
		return false
	if weapon.has_meta(WEAPON_OWNER_META):
		var recorded_owner = weapon.get_meta(WEAPON_OWNER_META, 0)
		if typeof(recorded_owner) != TYPE_INT:
			return false
		if int(recorded_owner) != _ownership_token:
			return false
	weapon.set_meta(WEAPON_OWNER_META, _ownership_token)
	return true


func _is_weapon_owned_by_self(weapon: WeaponInstance) -> bool:
	if weapon == null or not weapon.has_meta(WEAPON_OWNER_META):
		return false
	var recorded_owner = weapon.get_meta(WEAPON_OWNER_META, 0)
	return typeof(recorded_owner) == TYPE_INT and int(recorded_owner) == _ownership_token


func _release_weapon_ownership(weapon: WeaponInstance = null) -> bool:
	var target := weapon if weapon != null else _weapon_instance
	if target == null or not target.has_meta(WEAPON_OWNER_META):
		return true
	var recorded_owner = target.get_meta(WEAPON_OWNER_META, 0)
	if typeof(recorded_owner) != TYPE_INT or int(recorded_owner) != _ownership_token:
		return false
	target.remove_meta(WEAPON_OWNER_META)
	return true


func _accept(reason: StringName) -> bool:
	last_operation_reason = reason
	return true


func _reject(reason: StringName) -> bool:
	last_operation_reason = reason
	return false


func _coerce_string_name(value: Variant) -> StringName:
	if value is StringName or value is String:
		return StringName(value)
	return &""
