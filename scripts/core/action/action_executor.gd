class_name ActionExecutor
extends RefCounted

## Unified request -> validation -> execution -> AP commit -> result pipeline.
##
## The executor owns the transaction boundary. Registered handlers perform
## domain changes but never spend AP; the context's AP committer is called only
## after validation and execution have both succeeded.

const ActionResultScript = preload("res://scripts/core/action/action_result.gd")
const ActionValidatorScript = preload("res://scripts/core/action/action_validator.gd")
const ActionRequestScript = preload("res://scripts/core/action/action_request.gd")
const ActionExecutionContextScript = preload("res://scripts/core/action/action_execution_context.gd")
const CombatResolverScript = preload("res://scripts/core/combat/combat_resolver.gd")

const ACTION_MOVE: StringName = &"move"
const ACTION_ATTACK: StringName = &"attack"
const ACTION_INTERACT: StringName = &"interact"
const ACTION_LOOT: StringName = &"loot"

const REASON_INVALID_REQUEST: StringName = &"invalid_request"
const REASON_INVALID_CONTEXT: StringName = &"invalid_context"
const REASON_UNKNOWN_ACTION: StringName = &"unknown_action"
const REASON_NO_HANDLER: StringName = &"no_handler"
const REASON_EXECUTION_FAILED: StringName = &"execution_failed"
const REASON_AP_COMMIT_FAILED: StringName = &"ap_commit_failed"

const KEY_PATH: StringName = &"path"
const KEY_PATH_LENGTH: StringName = &"path_length"
const KEY_MAX_DISTANCE: StringName = &"max_distance"
const KEY_DESTINATION_AVAILABLE: StringName = &"destination_available"
const KEY_ACTOR_CELL: StringName = &"actor_cell"
const KEY_TARGET_CELL: StringName = &"target_cell"
const KEY_ATTACK_RANGE: StringName = &"attack_range"
const KEY_TARGET_ALIVE: StringName = &"target_alive"
const KEY_HOSTILE: StringName = &"hostile"
const KEY_HAS_LOS: StringName = &"has_los"
const KEY_TARGET_HP: StringName = &"target_hp"
const KEY_DAMAGE: StringName = &"damage"
const KEY_INTERACTION_RANGE: StringName = &"interaction_range"
const KEY_TARGET_VALID: StringName = &"target_valid"
const KEY_TARGET_AVAILABLE: StringName = &"target_available"
const KEY_CONTAINER_VALID: StringName = &"container_valid"
const KEY_CONTAINER_AVAILABLE: StringName = &"container_available"
const KEY_INVENTORY_CAN_RECEIVE: StringName = &"inventory_can_receive"

var _handlers: Dictionary = {}


func register_handler(action_type: StringName, handler: Callable) -> void:
	if action_type == &"":
		return
	if handler.is_valid():
		_handlers[action_type] = handler
	else:
		_handlers.erase(action_type)


func set_handler(action_type: StringName, handler: Callable) -> void:
	register_handler(action_type, handler)


func unregister_handler(action_type: StringName) -> void:
	_handlers.erase(action_type)


func get_handler(action_type: StringName) -> Callable:
	var handler = _handlers.get(action_type, Callable())
	return handler if handler is Callable else Callable()


func execute(request: Variant, context: Variant) -> ActionResult:
	if request == null:
		return ActionResultScript.rejected(REASON_INVALID_REQUEST)
	if not _is_known_action(request.action_type):
		return _rejected(request, REASON_UNKNOWN_ACTION)
	if context == null:
		return _rejected(request, REASON_INVALID_CONTEXT)

	var validation := _validate(request, context)
	validation = _with_request_metadata(validation, request)
	if not validation.success:
		return validation

	var execution := _execute_handler(request, context, validation)
	if not execution.success:
		return _with_request_metadata(execution, request, validation.ap_cost)

	if not context.commit_ap(validation.ap_cost):
		return _rejected(request, REASON_AP_COMMIT_FAILED, validation.ap_cost)

	return _with_request_metadata(execution, request, validation.ap_cost)


func execute_action(request: Variant, context: Variant) -> ActionResult:
	return execute(request, context)


func _validate(request: Variant, context: Variant) -> ActionResult:
	var payload: Dictionary = request.payload if request.payload is Dictionary else {}
	match request.action_type:
		ACTION_MOVE:
			var path_length := _path_length(payload)
			var max_distance := _payload_int(payload, KEY_MAX_DISTANCE, path_length)
			var destination_available := _payload_bool(payload, KEY_DESTINATION_AVAILABLE, true)
			return ActionValidatorScript.validate_move(
				context.current_ap,
				request.ap_cost,
				path_length,
				max_distance,
				destination_available
			)
		ACTION_ATTACK:
			return ActionValidatorScript.validate_attack(
				request.actor_id,
				request.target_id,
				context.current_ap,
				request.ap_cost,
				_as_vector3i(payload.get(KEY_ACTOR_CELL, Vector3i.ZERO)),
				_as_vector3i(payload.get(KEY_TARGET_CELL, Vector3i.ZERO)),
				_payload_int(payload, KEY_ATTACK_RANGE, 0),
				_payload_bool(payload, KEY_TARGET_ALIVE, true),
				_payload_bool(payload, KEY_HOSTILE, true),
				_payload_bool(payload, KEY_HAS_LOS, true)
			)
		ACTION_INTERACT:
			return ActionValidatorScript.validate_interact(
				request.actor_id,
				request.target_id,
				context.current_ap,
				request.ap_cost,
				_as_vector3i(payload.get(KEY_ACTOR_CELL, Vector3i.ZERO)),
				_as_vector3i(payload.get(KEY_TARGET_CELL, Vector3i.ZERO)),
				_payload_int(payload, KEY_INTERACTION_RANGE, 0),
				_payload_bool(payload, KEY_TARGET_VALID, true),
				_payload_bool(payload, KEY_TARGET_AVAILABLE, true)
			)
		ACTION_LOOT:
			return ActionValidatorScript.validate_loot(
				request.actor_id,
				request.target_id,
				context.current_ap,
				request.ap_cost,
				_as_vector3i(payload.get(KEY_ACTOR_CELL, Vector3i.ZERO)),
				_as_vector3i(payload.get(KEY_TARGET_CELL, Vector3i.ZERO)),
				_payload_int(payload, KEY_INTERACTION_RANGE, 0),
				_payload_bool(payload, KEY_CONTAINER_VALID, true),
				_payload_bool(payload, KEY_CONTAINER_AVAILABLE, true),
				_payload_bool(payload, KEY_INVENTORY_CAN_RECEIVE, true)
			)
	return ActionResultScript.rejected(REASON_UNKNOWN_ACTION)


func _execute_handler(request: Variant, context: Variant, validation: ActionResult) -> ActionResult:
	var handler := get_handler(request.action_type)
	if not handler.is_valid():
		handler = context.get_handler(request.action_type)

	if handler.is_valid():
		var raw_result = handler.call(request, context)
		return _coerce_execution_result(raw_result, request)

	if request.action_type == ACTION_ATTACK and request.payload.has(KEY_TARGET_HP) and request.payload.has(KEY_DAMAGE):
		return CombatResolverScript.resolve_attack(
			validation,
			_payload_int(request.payload, KEY_TARGET_HP, 0),
			_payload_int(request.payload, KEY_DAMAGE, 0)
		)

	return ActionResultScript.rejected(REASON_NO_HANDLER, request.actor_id, request.target_id, request.action_type)


func _coerce_execution_result(raw_result: Variant, request: Variant) -> ActionResult:
	if raw_result is ActionResult:
		return _copy_result(raw_result)
	if raw_result is Dictionary:
		var dictionary_result: Dictionary = raw_result
		var success := _dictionary_bool(dictionary_result, &"success", true)
		if not success:
			return ActionResultScript.rejected(
				_dictionary_string_name(dictionary_result, &"reason", REASON_EXECUTION_FAILED),
				request.actor_id,
				request.target_id,
				request.action_type
			)
		var accepted := ActionResultScript.accepted(request.actor_id, request.target_id, request.ap_cost, request.action_type)
		accepted.reason = _dictionary_string_name(dictionary_result, &"reason", &"accepted")
		accepted.damage = _dictionary_int(dictionary_result, KEY_DAMAGE, 0)
		accepted.killed = _dictionary_bool(dictionary_result, &"killed", false)
		return accepted
	if raw_result is bool and not raw_result:
		return ActionResultScript.rejected(REASON_EXECUTION_FAILED, request.actor_id, request.target_id, request.action_type)
	# A void callback is a successful execution by convention; handlers that
	# need to reject must return false or an unsuccessful ActionResult.
	return ActionResultScript.accepted(request.actor_id, request.target_id, request.ap_cost, request.action_type)


func _with_request_metadata(source: ActionResult, request: Variant, fallback_cost: int = -2147483648) -> ActionResult:
	var result := _copy_result(source)
	result.action_type = request.action_type
	result.actor_id = request.actor_id
	result.target_id = request.target_id
	result.ap_cost = request.ap_cost if fallback_cost == -2147483648 else fallback_cost
	if result.reason == &"" and result.success:
		result.reason = &"accepted"
	return result


func _rejected(request: Variant, reason: StringName, cost: int = -2147483648) -> ActionResult:
	var result := ActionResultScript.rejected(reason, request.actor_id, request.target_id, request.action_type)
	result.ap_cost = request.ap_cost if cost == -2147483648 else cost
	return result


func _copy_result(source: ActionResult) -> ActionResult:
	if source == null:
		return ActionResultScript.rejected(REASON_EXECUTION_FAILED)
	var result := ActionResultScript.new()
	result.success = source.success
	result.reason = source.reason
	result.action_type = source.action_type
	result.actor_id = source.actor_id
	result.target_id = source.target_id
	result.ap_cost = source.ap_cost
	result.damage = source.damage
	result.killed = source.killed
	return result


func _is_known_action(action_type: StringName) -> bool:
	return action_type == ACTION_MOVE or action_type == ACTION_ATTACK or action_type == ACTION_INTERACT or action_type == ACTION_LOOT


func _path_length(payload: Dictionary) -> int:
	if payload.has(KEY_PATH_LENGTH):
		return _payload_int(payload, KEY_PATH_LENGTH, 0)
	if payload.has(KEY_PATH):
		var path = payload[KEY_PATH]
		if path is Array:
			return maxi(path.size() - 1, 0)
		if path is PackedVector2Array or path is PackedVector3Array:
			return maxi(path.size() - 1, 0)
	return 0


func _payload_int(payload: Dictionary, key: StringName, fallback: int) -> int:
	var value = payload.get(key, fallback)
	if value is int or value is float:
		return int(value)
	return fallback


func _payload_bool(payload: Dictionary, key: StringName, fallback: bool) -> bool:
	var value = payload.get(key, fallback)
	return value if value is bool else fallback


func _as_vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Vector2i:
		return Vector3i(value.x, 0, value.y)
	if value is Vector3:
		return Vector3i(roundi(value.x), roundi(value.y), roundi(value.z))
	if value is Vector2:
		return Vector3i(roundi(value.x), 0, roundi(value.y))
	return Vector3i.ZERO


func _dictionary_bool(dictionary: Dictionary, key: StringName, fallback: bool) -> bool:
	var value = dictionary.get(key, fallback)
	return value if value is bool else fallback


func _dictionary_int(dictionary: Dictionary, key: StringName, fallback: int) -> int:
	var value = dictionary.get(key, fallback)
	if value is int or value is float:
		return int(value)
	return fallback


func _dictionary_string_name(dictionary: Dictionary, key: StringName, fallback: StringName) -> StringName:
	var value = dictionary.get(key, fallback)
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return fallback
