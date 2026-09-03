@tool
class_name EnvironmentEffectDefinition
extends Resource

## Static configuration for one environment reaction.  Effects never own
## runtime HP, activation or target state; those belong to an instance/state.

@export var effect_id: StringName = &""
@export var display_name: String = ""
@export var enabled: bool = true


func is_valid() -> bool:
	return is_valid_id(effect_id)


func get_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if not is_valid_id(effect_id):
		errors.append("Environment effect requires a stable effect_id.")
	return errors


static func is_valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING_NAME and typeof(value) != TYPE_STRING:
		return false
	var text := String(value).strip_edges()
	if text.is_empty():
		return false
	for character in [" ", "\t", "\r", "\n", "/", "\\", ":"]:
		if text.contains(character):
			return false
	return true
