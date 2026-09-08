@tool
class_name MissionStepDefinition
extends Resource

## 单个任务目标步骤定义。

enum StepType {
	INTERACT_OBJECT = 0,
	ELIMINATE_TARGETS = 1,
}

@export var step_id: StringName = &"step"
@export var description: String = ""
@export var step_type: StepType = StepType.INTERACT_OBJECT
## 关联的目标物体 ID（当 step_type 为 INTERACT_OBJECT 时）
@export var target_id: StringName = &""
## 关联的目标敌人 spawn_id 数组（当 step_type 为 ELIMINATE_TARGETS 时）
@export var target_ids: Array[StringName] = []
## 是否为可选目标（次要目标）
@export var is_optional: bool = false


func is_valid() -> bool:
	if step_id == &"":
		return false
	match step_type:
		StepType.INTERACT_OBJECT:
			return target_id != &""
		StepType.ELIMINATE_TARGETS:
			return not target_ids.is_empty()
	return false
