class_name ActionExecutionContext
extends RefCounted

## Scene-agnostic dependencies for ActionExecutor.
##
## Handlers receive `(request, context)` and may return void/null, bool,
## ActionResult, or a Dictionary containing `success`, `reason`, `damage`,
## and `killed`. Handlers must not spend AP themselves. AP is committed once
## by the executor after the handler succeeds.

var current_ap: int = 0
var state: Dictionary = {}
var ap_committer: Callable = Callable()

var _handlers: Dictionary = {}
var _commit_count: int = 0
var _last_commit_cost: int = 0


func _init(initial_ap: int = 0, initial_state: Variant = null) -> void:
	current_ap = maxi(initial_ap, 0)
	if initial_state is Dictionary:
		state = initial_state.duplicate()


func set_ap_committer(callback: Callable) -> void:
	ap_committer = callback


func set_ap_commit_handler(callback: Callable) -> void:
	set_ap_committer(callback)


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


func has_handler(action_type: StringName) -> bool:
	return get_handler(action_type).is_valid()


func commit_ap(cost: int) -> bool:
	if cost < 0 or current_ap < cost:
		return false
	if cost == 0:
		return true

	if ap_committer.is_valid():
		var callback_result = ap_committer.call(cost)
		if callback_result is bool and not callback_result:
			return false

	current_ap -= cost
	_commit_count += 1
	_last_commit_cost = cost
	return true


func get_commit_count() -> int:
	return _commit_count


func get_last_commit_cost() -> int:
	return _last_commit_cost
