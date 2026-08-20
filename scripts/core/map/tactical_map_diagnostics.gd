@tool
class_name TacticalMapDiagnostics
extends RefCounted

## Structured diagnostics shared by the authoring validator and Baker.
## The legacy errors/warnings arrays remain the human-readable compatibility
## surface; each append helper records the matching structured entry once.


static func error(code: StringName, message: String, coordinate: Variant = null) -> Dictionary:
	return _make(&"error", code, message, coordinate)


static func warning(code: StringName, message: String, coordinate: Variant = null) -> Dictionary:
	return _make(&"warning", code, message, coordinate)


static func append_error(errors: Array[String], diagnostics: Array[Dictionary], code: StringName, message: String, coordinate: Variant = null) -> void:
	errors.append(message)
	diagnostics.append(error(code, message, coordinate))


static func append_warning(warnings: Array[String], diagnostics: Array[Dictionary], code: StringName, message: String, coordinate: Variant = null) -> void:
	warnings.append(message)
	diagnostics.append(warning(code, message, coordinate))


static func append_existing(diagnostics: Array[Dictionary], severity: StringName, code: StringName, message: String, coordinate: Variant = null) -> void:
	diagnostics.append(_make(severity, code, message, coordinate))


static func sort_diagnostics(diagnostics: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for diagnostic in diagnostics:
		if diagnostic is Dictionary:
			result.append((diagnostic as Dictionary).duplicate(true))
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			var first_severity := _severity_rank(StringName(first.get(&"severity", &"error")))
			var second_severity := _severity_rank(StringName(second.get(&"severity", &"error")))
			if first_severity != second_severity:
				return first_severity < second_severity
			var first_code := String(first.get(&"code", &""))
			var second_code := String(second.get(&"code", &""))
			if first_code != second_code:
				return first_code < second_code
			var first_has_coordinate := bool(first.get(&"has_coordinate", false))
			var second_has_coordinate := bool(second.get(&"has_coordinate", false))
			if first_has_coordinate != second_has_coordinate:
				return first_has_coordinate
			if first_has_coordinate:
				var first_coordinate: Vector3i = first[&"coordinate"]
				var second_coordinate: Vector3i = second[&"coordinate"]
				if first_coordinate.y != second_coordinate.y:
					return first_coordinate.y < second_coordinate.y
				if first_coordinate.z != second_coordinate.z:
					return first_coordinate.z < second_coordinate.z
				if first_coordinate.x != second_coordinate.x:
					return first_coordinate.x < second_coordinate.x
			return String(first.get(&"message", "")) < String(second.get(&"message", ""))
	)
	return result


static func _make(severity: StringName, code: StringName, message: String, coordinate: Variant) -> Dictionary:
	var has_coordinate := coordinate is Vector3i
	return {
		&"severity": severity,
		&"code": code,
		&"message": message,
		&"has_coordinate": has_coordinate,
		&"coordinate": coordinate if has_coordinate else null,
	}


static func _severity_rank(severity: StringName) -> int:
	return 0 if severity == &"error" else 1
