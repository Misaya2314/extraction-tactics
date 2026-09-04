@tool
class_name SprintSkillDefinition
extends SkillDefinition

const ActionResultScript = preload("res://scripts/core/action/action_result.gd")

@export var bonus_movement: int = 3


func _init() -> void:
	skill_id = &"tactical_sprint"
	display_name = "战术冲刺"
	description = "激发机动潜能，立即为自身提供 +3 格临时移动力（本回合内生效）。"
	target_type = TargetType.SELF
	ap_cost = 1
	cooldown_turns = 2
	cast_range = 0
	aoe_radius = 0
	require_los = false


func execute_skill(request: Variant, context: Variant) -> ActionResult:
	var actor_id: StringName = request.actor_id if request != null else &""
	if context != null and context.state is Dictionary:
		var actor = context.state.get(&"actor")
		if actor != null and "temporary_bonus_move" in actor:
			actor.temporary_bonus_move += bonus_movement

	var result := ActionResultScript.accepted(actor_id, actor_id, ap_cost, &"skill")
	result.reason = &"sprint_activated"
	result.metadata[&"bonus_movement"] = bonus_movement
	return result
