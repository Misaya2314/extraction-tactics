class_name ActionResult
extends RefCounted

## Immutable-by-convention result value shared by action validation and execution.
## Callers may inspect or copy these fields; factory methods provide the stable
## accepted/rejected construction path used by the core systems.

var success: bool = false
var reason: StringName = &""
var action_type: StringName = &""
var actor_id: StringName = &""
var target_id: StringName = &""
var ap_cost: int = 0
var damage: int = 0
var killed: bool = false
## Stable, optional result diagnostics.  Core action callers may ignore it;
## combat/presentation layers use it for cover and damage breakdowns.
var metadata: Dictionary = {}


static func accepted(
	actor_id: StringName,
	target_id: StringName = &"",
	ap_cost: int = 0,
	action_type: StringName = &"",
	metadata: Dictionary = {}
) -> ActionResult:
	var result := ActionResult.new()
	result.success = true
	result.reason = &"accepted"
	result.action_type = action_type
	result.actor_id = actor_id
	result.target_id = target_id
	result.ap_cost = ap_cost
	result.metadata = metadata.duplicate(true)
	return result


static func rejected(
	reason: StringName,
	actor_id: StringName = &"",
	target_id: StringName = &"",
	action_type: StringName = &"",
	metadata: Dictionary = {}
) -> ActionResult:
	var result := ActionResult.new()
	result.success = false
	result.reason = reason
	result.action_type = action_type
	result.actor_id = actor_id
	result.target_id = target_id
	result.metadata = metadata.duplicate(true)
	return result
