@tool
class_name MissionDefinition
extends Resource

## 数据驱动的关卡任务资产。

@export var mission_id: StringName = &"mission"
@export var title: String = "任务目标"
@export_multiline var briefing: String = ""
@export var steps: Array[Resource] = []


func is_valid() -> bool:
	if mission_id == &"":
		return false
	for step in steps:
		if step == null or not step.is_valid():
			return false
	return true


func get_step_count() -> int:
	return steps.size()


func get_step(index: int) -> Resource:
	if index >= 0 and index < steps.size():
		return steps[index]
	return null
