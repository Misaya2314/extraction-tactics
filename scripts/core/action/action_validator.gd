class_name ActionValidator
extends RefCounted

const ActionResultScript = preload("res://scripts/core/action/action_result.gd")

const ACTION_MOVE: StringName = &"move"
const ACTION_ATTACK: StringName = &"attack"
const ACTION_INTERACT: StringName = &"interact"
const ACTION_LOOT: StringName = &"loot"

const REASON_INVALID_COST: StringName = &"invalid_cost"
const REASON_INVALID_TARGET: StringName = &"invalid_target"
const REASON_INVALID_CONTAINER: StringName = &"invalid_container"
const REASON_NO_AP: StringName = &"no_ap"
const REASON_OUT_OF_RANGE: StringName = &"out_of_range"
const REASON_TARGET_UNAVAILABLE: StringName = &"target_unavailable"
const REASON_CONTAINER_UNAVAILABLE: StringName = &"container_unavailable"
const REASON_INVENTORY_FULL: StringName = &"inventory_full"


## Validates a movement request. path_length is measured in edges, not nodes.
static func validate_move(current_ap: int, ap_cost: int, path_length: int, max_distance: int, destination_available: bool) -> ActionResult:
	if ap_cost < 0:
		return ActionResultScript.rejected(REASON_INVALID_COST, &"", &"", ACTION_MOVE)
	if path_length <= 0 or max_distance < 0 or path_length > max_distance:
		return ActionResultScript.rejected(&"no_path", &"", &"", ACTION_MOVE)
	if not destination_available:
		return ActionResultScript.rejected(&"destination_unavailable", &"", &"", ACTION_MOVE)
	if current_ap < ap_cost:
		return ActionResultScript.rejected(REASON_NO_AP, &"", &"", ACTION_MOVE)
	return ActionResultScript.accepted(&"", &"", ap_cost, ACTION_MOVE)


## Validates a basic,必中 attack using Manhattan distance and an externally
## supplied line-of-sight result.
static func validate_attack(actor_id: StringName, target_id: StringName, current_ap: int, ap_cost: int, actor_cell: Vector3i, target_cell: Vector3i, attack_range: int, target_alive: bool, hostile: bool, has_los: bool) -> ActionResult:
	if ap_cost < 0 or attack_range < 0:
		return ActionResultScript.rejected(REASON_INVALID_COST, actor_id, target_id, ACTION_ATTACK)
	if actor_id == &"" or target_id == &"" or actor_id == target_id:
		return ActionResultScript.rejected(REASON_INVALID_TARGET, actor_id, target_id, ACTION_ATTACK)
	if not target_alive:
		return ActionResultScript.rejected(&"target_dead", actor_id, target_id, ACTION_ATTACK)
	if not hostile:
		return ActionResultScript.rejected(&"not_hostile", actor_id, target_id, ACTION_ATTACK)
	if current_ap < ap_cost:
		return ActionResultScript.rejected(REASON_NO_AP, actor_id, target_id, ACTION_ATTACK)
	if _manhattan_distance(actor_cell, target_cell) > attack_range:
		return ActionResultScript.rejected(REASON_OUT_OF_RANGE, actor_id, target_id, ACTION_ATTACK)
	if not has_los:
		return ActionResultScript.rejected(&"no_los", actor_id, target_id, ACTION_ATTACK)
	return ActionResultScript.accepted(actor_id, target_id, ap_cost, ACTION_ATTACK)


## Validates an interaction with a map object. The caller supplies object
## validity and availability so this core validator remains scene-agnostic.
static func validate_interact(actor_id: StringName, target_id: StringName, current_ap: int, ap_cost: int, actor_cell: Vector3i, target_cell: Vector3i, interaction_range: int, target_valid: bool = true, target_available: bool = true) -> ActionResult:
	if ap_cost < 0 or interaction_range < 0:
		return ActionResultScript.rejected(REASON_INVALID_COST, actor_id, target_id, ACTION_INTERACT)
	if actor_id == &"" or target_id == &"" or not target_valid:
		return ActionResultScript.rejected(REASON_INVALID_TARGET, actor_id, target_id, ACTION_INTERACT)
	if not target_available:
		return ActionResultScript.rejected(REASON_TARGET_UNAVAILABLE, actor_id, target_id, ACTION_INTERACT)
	if current_ap < ap_cost:
		return ActionResultScript.rejected(REASON_NO_AP, actor_id, target_id, ACTION_INTERACT)
	if _manhattan_distance(actor_cell, target_cell) > interaction_range:
		return ActionResultScript.rejected(REASON_OUT_OF_RANGE, actor_id, target_id, ACTION_INTERACT)
	return ActionResultScript.accepted(actor_id, target_id, ap_cost, ACTION_INTERACT)


## Alias for callers that use the noun form of the action name.
static func validate_interaction(actor_id: StringName, target_id: StringName, current_ap: int, ap_cost: int, actor_cell: Vector3i, target_cell: Vector3i, interaction_range: int, target_valid: bool = true, target_available: bool = true) -> ActionResult:
	return validate_interact(actor_id, target_id, current_ap, ap_cost, actor_cell, target_cell, interaction_range, target_valid, target_available)


## Validates taking loot from a container. `inventory_can_receive` is an
## externally computed capacity check; no inventory implementation is assumed.
static func validate_loot(actor_id: StringName, container_id: StringName, current_ap: int, ap_cost: int, actor_cell: Vector3i, container_cell: Vector3i, interaction_range: int, container_valid: bool = true, container_available: bool = true, inventory_can_receive: bool = true) -> ActionResult:
	if ap_cost < 0 or interaction_range < 0:
		return ActionResultScript.rejected(REASON_INVALID_COST, actor_id, container_id, ACTION_LOOT)
	if actor_id == &"" or container_id == &"" or not container_valid:
		return ActionResultScript.rejected(REASON_INVALID_CONTAINER, actor_id, container_id, ACTION_LOOT)
	if not container_available:
		return ActionResultScript.rejected(REASON_CONTAINER_UNAVAILABLE, actor_id, container_id, ACTION_LOOT)
	if current_ap < ap_cost:
		return ActionResultScript.rejected(REASON_NO_AP, actor_id, container_id, ACTION_LOOT)
	if _manhattan_distance(actor_cell, container_cell) > interaction_range:
		return ActionResultScript.rejected(REASON_OUT_OF_RANGE, actor_id, container_id, ACTION_LOOT)
	if not inventory_can_receive:
		return ActionResultScript.rejected(REASON_INVENTORY_FULL, actor_id, container_id, ACTION_LOOT)
	return ActionResultScript.accepted(actor_id, container_id, ap_cost, ACTION_LOOT)


static func validate_loot_action(actor_id: StringName, container_id: StringName, current_ap: int, ap_cost: int, actor_cell: Vector3i, container_cell: Vector3i, interaction_range: int, container_valid: bool = true, container_available: bool = true, inventory_can_receive: bool = true) -> ActionResult:
	return validate_loot(actor_id, container_id, current_ap, ap_cost, actor_cell, container_cell, interaction_range, container_valid, container_available, inventory_can_receive)


static func _manhattan_distance(from_cell: Vector3i, to_cell: Vector3i) -> int:
	return GridVisibility.tactical_distance(from_cell, to_cell)
