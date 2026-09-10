@tool
extends SkillDefinition

func _init() -> void:
	skill_id = &"tactical_knockback"
	display_name = "定向击退"
	description = "将相邻正方向的敌人推开1格。推入虚空立即坠落死亡；墙体、占位及地图边界会阻止施放。"
	target_type = TargetType.TARGET_UNIT
	ap_cost = 1
	cooldown_turns = 2
	cast_range = 1
	require_los = false

func get_valid_target_cells(actor_cell: Vector3i, grid: Variant) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for direction in GridModel.CARDINAL_DIRECTIONS:
		var cell: Vector3i = actor_cell + direction
		if grid.has_cell(cell) and grid.is_occupied(cell) and not grid.is_movement_blocked(actor_cell, cell):
			cells.append(cell)
	return cells

func execute_skill(request: Variant, context: Variant) -> ActionResult:
	var callback: Callable = context.state.get(&"apply_knockback", Callable())
	if not callback.is_valid():
		return ActionResult.rejected(&"missing_context", request.actor_id, &"", &"skill")
	return callback.call(request)
