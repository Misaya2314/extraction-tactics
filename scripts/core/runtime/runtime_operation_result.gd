class_name RuntimeOperationResult
extends RefCounted

## Stable result contract for runtime identity operations. Callers must inspect
## success/reason_code instead of relying on silent fallback values.

var success: bool = false
var reason_code: StringName = &""
var message: String = ""
var value: Variant = null
var related_id: StringName = &""


static func succeeded(result_value: Variant = null, result_message: String = "", result_related_id: StringName = &"") -> RuntimeOperationResult:
	var result := RuntimeOperationResult.new()
	result.success = true
	result.reason_code = &"ok"
	result.message = result_message
	result.value = result_value
	result.related_id = result_related_id
	return result


static func failed(code: StringName, result_message: String = "", result_value: Variant = null, result_related_id: StringName = &"") -> RuntimeOperationResult:
	var result := RuntimeOperationResult.new()
	result.success = false
	result.reason_code = code
	result.message = result_message
	result.value = result_value
	result.related_id = result_related_id
	return result


func is_success() -> bool:
	return success


func as_dictionary() -> Dictionary:
	return {
		&"success": success,
		&"reason_code": reason_code,
		&"message": message,
		&"value": value,
		&"related_id": related_id,
	}
