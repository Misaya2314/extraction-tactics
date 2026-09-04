@tool
class_name GrenadeSkillDefinition
extends SkillDefinition

const ActionResultScript = preload("res://scripts/core/action/action_result.gd")

@export var damage: int = 4


func _init() -> void:
	skill_id = &"tactical_grenade"
	display_name = "破片手雷"
	description = "投掷一枚战术破片手雷，对目标区域3x3范围内的所有单位和环境物体造成4点范围伤害。"
	target_type = TargetType.TARGET_CELL
	ap_cost = 1
	cooldown_turns = 2
	cast_range = 5
	aoe_radius = 1
	require_los = false


func execute_skill(request: Variant, context: Variant) -> ActionResult:
	var actor_id: StringName = request.actor_id if request != null else &""
	var payload: Dictionary = request.payload if request != null and request.payload is Dictionary else {}
	var target_cell: Vector3i = payload.get(&"target_cell", Vector3i.ZERO)
	var affected_units: Array = []
	var destroyed_objects: Array = []

	# If the context provides a callback or registry to query units/objects at cells:
	if context != null and context.state is Dictionary:
		var units_query = context.state.get(&"units_query")
		if units_query is Callable and units_query.is_valid():
			var candidates = units_query.call(target_cell, aoe_radius)
			if candidates is Array:
				for unit in candidates:
					if unit != null and unit.has_method("take_damage"):
						var applied = unit.take_damage(damage)
						affected_units.append({&"id": unit.unit_id if "unit_id" in unit else &"", &"damage": applied})
					elif unit != null and unit.has_method("apply_damage"):
						unit.apply_damage(damage)
						affected_units.append({&"id": unit.instance_id if "instance_id" in unit else &"", &"damage": damage})

		var env_query = context.state.get(&"env_query")
		var resolve_destruction = context.state.get(&"resolve_env_destruction")
		if env_query is Callable and env_query.is_valid():
			var objects = env_query.call(target_cell, aoe_radius)
			if objects is Array:
				for obj in objects:
					if obj != null and obj.has_method("apply_damage"):
						var res = obj.apply_damage(damage)
						if res != null and "success" in res and res.success:
							if obj.destroyed and resolve_destruction is Callable and resolve_destruction.is_valid():
								resolve_destruction.call(obj)
							destroyed_objects.append(obj.instance_id if "instance_id" in obj else &"")
					elif obj != null and obj.has_method("take_damage"):
						obj.take_damage(damage)
						destroyed_objects.append(obj.get_placement_id() if obj.has_method("get_placement_id") else &"")

	var result := ActionResultScript.accepted(actor_id, &"", ap_cost, &"skill")
	result.reason = &"grenade_exploded"
	result.metadata[&"target_cell"] = target_cell
	result.metadata[&"affected_units"] = affected_units
	result.metadata[&"destroyed_objects"] = destroyed_objects
	result.damage = damage
	return result
