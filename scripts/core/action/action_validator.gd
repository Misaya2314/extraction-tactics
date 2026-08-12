class_name ActionValidator
extends RefCounted

const ActionResultScript = preload("res://scripts/core/action/action_result.gd")


## Validates a movement request. path_length is measured in edges, not nodes.
static func validate_move(current_ap: int, ap_cost: int, path_length: int, max_distance: int, destination_available: bool) -> ActionResult:
	if ap_cost < 0:
		return ActionResultScript.rejected(&"invalid_cost")
	if path_length <= 0 or max_distance < 0 or path_length > max_distance:
		return ActionResultScript.rejected(&"no_path")
	if not destination_available:
		return ActionResultScript.rejected(&"destination_unavailable")
	if current_ap < ap_cost:
		return ActionResultScript.rejected(&"no_ap")
	return ActionResultScript.accepted(&"", &"", ap_cost)


## Validates a basic,必中 attack using Manhattan distance and an externally
## supplied line-of-sight result.
static func validate_attack(actor_id: StringName, target_id: StringName, current_ap: int, ap_cost: int, actor_cell: Vector3i, target_cell: Vector3i, attack_range: int, target_alive: bool, hostile: bool, has_los: bool) -> ActionResult:
	if ap_cost < 0 or attack_range < 0:
		return ActionResultScript.rejected(&"invalid_cost", actor_id, target_id)
	if actor_id == &"" or target_id == &"" or actor_id == target_id:
		return ActionResultScript.rejected(&"invalid_target", actor_id, target_id)
	if not target_alive:
		return ActionResultScript.rejected(&"target_dead", actor_id, target_id)
	if not hostile:
		return ActionResultScript.rejected(&"not_hostile", actor_id, target_id)
	if current_ap < ap_cost:
		return ActionResultScript.rejected(&"no_ap", actor_id, target_id)
	if _manhattan_distance(actor_cell, target_cell) > attack_range:
		return ActionResultScript.rejected(&"out_of_range", actor_id, target_id)
	if not has_los:
		return ActionResultScript.rejected(&"no_los", actor_id, target_id)
	return ActionResultScript.accepted(actor_id, target_id, ap_cost)


static func _manhattan_distance(from_cell: Vector3i, to_cell: Vector3i) -> int:
	return GridVisibility.tactical_distance(from_cell, to_cell)
