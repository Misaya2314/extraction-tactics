class_name SkillInstance
extends RuntimeInstance

## Pure runtime state for an equipped skill.
## Owns stable instance identity, cooldown turns, and available charges.

const DEFINITION_TYPE: StringName = &"skill"
const DEFAULT_STATE_VERSION: int = 1

var definition: SkillDefinition
var current_cooldown: int = 0
var current_charges: int = 0
var state_version: int = DEFAULT_STATE_VERSION
var last_operation_reason: StringName = &""


func _init(new_instance_id: Variant = &"", new_definition: Variant = null) -> void:
	var resolved_id := _coerce_string_name(new_instance_id)
	var resolved_def: SkillDefinition = null
	if new_instance_id is SkillDefinition:
		resolved_def = new_instance_id as SkillDefinition
		resolved_id = _coerce_string_name(new_definition)
	elif new_definition is SkillDefinition:
		resolved_def = new_definition as SkillDefinition

	var resolved_def_id: StringName = resolved_def.skill_id if resolved_def != null else &""
	super(resolved_id, DEFINITION_TYPE, resolved_def_id)
	definition = resolved_def
	if definition != null:
		current_charges = definition.max_charges


static func create(new_instance_id: StringName, new_definition: SkillDefinition) -> SkillInstance:
	return SkillInstance.new(new_instance_id, new_definition)


func is_valid(registry: Variant = null) -> bool:
	return (
		is_valid_identity()
		and definition_type == DEFINITION_TYPE
		and definition != null
		and definition.is_valid()
		and definition_id == definition.skill_id
		and state_version == DEFAULT_STATE_VERSION
		and current_cooldown >= 0
		and current_charges >= 0
		and _definition_is_resolved(registry)
	)


func validate() -> bool:
	return is_valid()


func is_ready() -> bool:
	if current_cooldown > 0:
		return false
	if definition != null and definition.max_charges > 0 and current_charges <= 0:
		return false
	return true


func trigger_cooldown() -> void:
	if definition != null:
		current_cooldown = definition.cooldown_turns
		if definition.max_charges > 0:
			current_charges = maxi(0, current_charges - 1)


func on_turn_started() -> void:
	if current_cooldown > 0:
		current_cooldown -= 1


func reset_cooldown() -> void:
	current_cooldown = 0


func get_tooltip_text() -> String:
	if definition != null:
		return definition.get_tooltip_text(current_cooldown)
	return ""


func to_snapshot_dict() -> Dictionary:
	return {
		&"instance_id": String(instance_id),
		&"definition_id": String(definition_id),
		&"current_cooldown": current_cooldown,
		&"current_charges": current_charges,
		&"state_version": state_version,
	}


static func from_snapshot_dict(data: Dictionary, resolved_def: SkillDefinition) -> SkillInstance:
	if data == null or resolved_def == null:
		return null
	var inst := SkillInstance.new(StringName(data.get(&"instance_id", &"")), resolved_def)
	inst.current_cooldown = int(data.get(&"current_cooldown", 0))
	inst.current_charges = int(data.get(&"current_charges", 0))
	inst.state_version = int(data.get(&"state_version", DEFAULT_STATE_VERSION))
	return inst


func _definition_is_resolved(registry: Variant) -> bool:
	if registry == null:
		return true
	if typeof(registry) != TYPE_OBJECT:
		return false
	if registry.has_method("resolve"):
		var resolved = registry.call("resolve", DEFINITION_TYPE, definition_id)
		return resolved is SkillDefinition and (resolved as SkillDefinition).skill_id == definition_id
	if registry.has_method("contains"):
		return bool(registry.call("contains", DEFINITION_TYPE, definition_id))
	return false


static func _coerce_string_name(value: Variant) -> StringName:
	if value is StringName or value is String:
		return StringName(value)
	return &""
