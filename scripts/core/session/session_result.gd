class_name SessionResult
extends RefCounted

## Terminal outcome for one game session.
##
## `has_value` distinguishes the pre-result empty value from a recorded
## failure, because both have `success == false`.

var has_value: bool = false
var success: bool = false
var reason: StringName = &""


func _init(result_success: bool = false, result_reason: StringName = &"", recorded: bool = false) -> void:
	has_value = recorded
	success = result_success
	reason = result_reason


func is_success() -> bool:
	return has_value and success


func is_failure() -> bool:
	return has_value and not success


func duplicate_result() -> RefCounted:
	var result = get_script().new()
	result.has_value = has_value
	result.success = success
	result.reason = reason
	return result
