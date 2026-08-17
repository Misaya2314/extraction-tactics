class_name ActionRequest
extends RefCounted

## Data-only request passed through the unified action pipeline.
##
## `payload` contains action-specific validation and execution data. It is
## intentionally a Dictionary so the core remains independent of Nodes,
## units, maps, and inventory implementations.

var action_type: StringName = &""
var actor_id: StringName = &""
var target_id: StringName = &""
var ap_cost: int = 0
var payload: Dictionary = {}
var metadata: Dictionary = {}


func _init(
		new_action_type: StringName = &"",
		new_actor_id: StringName = &"",
		new_target_id: StringName = &"",
		new_ap_cost: int = 0,
		new_payload: Variant = null,
		new_metadata: Variant = null
) -> void:
	action_type = new_action_type
	actor_id = new_actor_id
	target_id = new_target_id
	ap_cost = new_ap_cost
	if new_payload is Dictionary:
		payload = new_payload.duplicate()
	if new_metadata is Dictionary:
		metadata = new_metadata.duplicate()


static func create(
		new_action_type: StringName,
		new_actor_id: StringName = &"",
		new_target_id: StringName = &"",
		new_ap_cost: int = 0,
		new_payload: Variant = null,
		new_metadata: Variant = null
):
	var request_script = load("res://scripts/core/action/action_request.gd")
	return request_script.new(
		new_action_type,
		new_actor_id,
		new_target_id,
		new_ap_cost,
		new_payload,
		new_metadata
	)


func duplicate_request():
	var request_script = load("res://scripts/core/action/action_request.gd")
	return request_script.new(
		action_type,
		actor_id,
		target_id,
		ap_cost,
		payload,
		metadata
	)
