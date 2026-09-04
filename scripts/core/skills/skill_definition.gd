@tool
class_name SkillDefinition
extends Resource

## Data-only base skill contract.
## Concrete skills can extend this resource or configure its targeting and action numbers.

enum TargetType {
	SELF = 0,
	TARGET_CELL = 1,
	TARGET_UNIT = 2,
}

@export var skill_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D

@export_group("Economy & Cooldown")
@export_range(0, 9, 1) var ap_cost: int = 1
@export_range(0, 99, 1) var cooldown_turns: int = 2
@export_range(0, 99, 1) var max_charges: int = 0

@export_group("Targeting & Area")
@export var target_type: TargetType = TargetType.TARGET_CELL
@export_range(0, 99, 1) var cast_range: int = 4
@export_range(0, 10, 1) var aoe_radius: int = 0
@export var require_los: bool = true


func is_valid() -> bool:
	return (
		skill_id != &""
		and not display_name.strip_edges().is_empty()
		and ap_cost >= 0
		and cooldown_turns >= 0
		and cast_range >= 0
		and aoe_radius >= 0
	)


func validate() -> bool:
	return is_valid()


func get_summary() -> String:
	var cd_text := "无CD" if cooldown_turns <= 0 else "%d回合CD" % cooldown_turns
	return "%s | AP %d | %s | 射程 %d" % [display_name, ap_cost, cd_text, cast_range]


func get_tooltip_text(current_cooldown: int = 0) -> String:
	var lines: Array[String] = []
	lines.append("【%s】" % display_name)

	var details: Array[String] = []
	details.append("消耗: %d AP" % ap_cost)
	if cooldown_turns > 0:
		details.append("基础冷却: %d 回合" % cooldown_turns)
	else:
		details.append("无冷却")

	if target_type == TargetType.SELF:
		details.append("目标: 自身")
	elif target_type == TargetType.TARGET_CELL:
		details.append("射程: %d 格" % cast_range)
		if aoe_radius > 0:
			var span := aoe_radius * 2 + 1
			details.append("范围: %dx%d" % [span, span])
		else:
			details.append("范围: 单格")
	elif target_type == TargetType.TARGET_UNIT:
		details.append("目标: 单位 (射程 %d 格)" % cast_range)

	lines.append(" | ".join(details))

	if not description.strip_edges().is_empty():
		lines.append(description.strip_edges())

	if current_cooldown > 0:
		lines.append("状态: 冷却中 (剩余 %d 回合)" % current_cooldown)
	else:
		lines.append("状态: 准备就绪")

	return "\n".join(lines)


## Virtual method: calculate valid target cells for controller highlight.
func get_valid_target_cells(actor_cell: Vector3i, grid: Variant) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if target_type == TargetType.SELF:
		result.append(actor_cell)
		return result

	if grid == null:
		return result

	var candidate_cells: Array[Vector3i] = []
	if grid.has_method("get_cells_in_manhattan_range"):
		candidate_cells = grid.get_cells_in_manhattan_range(actor_cell, cast_range)
	elif grid.has_method("has_cell"):
		for dx in range(-cast_range, cast_range + 1):
			var rem := cast_range - absi(dx)
			for dz in range(-rem, rem + 1):
				for dy in range(-1, 2):
					var c := Vector3i(actor_cell.x + dx, actor_cell.y + dy, actor_cell.z + dz)
					if grid.has_cell(c):
						candidate_cells.append(c)

	for cell in candidate_cells:
		if cell == actor_cell and target_type != TargetType.SELF:
			continue
		if require_los and grid.has_method("has_line_of_sight"):
			if not grid.has_line_of_sight(actor_cell, cell):
				continue
		result.append(cell)
	return result


## Virtual method: override in specific skills to perform effects.
func execute_skill(request: Variant, context: Variant) -> ActionResult:
	return ActionResult.rejected(&"not_implemented", request.actor_id if request != null else &"", &"", &"skill")
