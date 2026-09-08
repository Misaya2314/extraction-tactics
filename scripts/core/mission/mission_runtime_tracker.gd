class_name MissionRuntimeTracker
extends RefCounted

## 运行时任务跟踪器，管理当前战局中的目标推进、交互与完成状态。

const MissionDefinitionScript = preload("res://scripts/core/mission/mission_definition.gd")
const MissionStepDefinitionScript = preload("res://scripts/core/mission/mission_step_definition.gd")

var definition: Resource = null
var interacted_objects: Dictionary = {}
var step_completed: Dictionary = {}


func configure(mission_def: Resource) -> void:
	definition = mission_def
	interacted_objects.clear()
	step_completed.clear()
	if definition != null:
		for step in definition.steps:
			if step != null and step.step_id != &"":
				step_completed[step.step_id] = false


func record_interaction(object_id: StringName, definition_id: StringName = &"") -> bool:
	if object_id == &"" and definition_id == &"":
		return false
	var changed := false
	if object_id != &"" and not bool(interacted_objects.get(object_id, false)):
		interacted_objects[object_id] = true
		changed = true
	if definition_id != &"" and not bool(interacted_objects.get(definition_id, false)):
		interacted_objects[definition_id] = true
		changed = true
	if not changed:
		return false
	_evaluate_steps()
	return true


func is_object_interacted(object_id: StringName, definition_id: StringName = &"") -> bool:
	if object_id != &"" and bool(interacted_objects.get(object_id, false)):
		return true
	if definition_id != &"" and bool(interacted_objects.get(definition_id, false)):
		return true
	return false


func update_elimination_progress(units_by_id: Dictionary) -> void:
	if definition == null:
		return
	for step in definition.steps:
		if step == null or step.step_type != MissionStepDefinitionScript.StepType.ELIMINATE_TARGETS:
			continue
		if bool(step_completed.get(step.step_id, false)):
			continue
		var all_dead := true
		for target_id in step.target_ids:
			var unit = units_by_id.get(target_id)
			if is_instance_valid(unit) and unit.has_method("is_alive") and bool(unit.call("is_alive")):
				all_dead = false
				break
		if all_dead and not step.target_ids.is_empty():
			step_completed[step.step_id] = true


func _evaluate_steps() -> void:
	if definition == null:
		return
	for step in definition.steps:
		if step == null:
			continue
		if step.step_type == MissionStepDefinitionScript.StepType.INTERACT_OBJECT:
			if bool(interacted_objects.get(step.target_id, false)):
				step_completed[step.step_id] = true


func is_step_completed(step_id: StringName) -> bool:
	return bool(step_completed.get(step_id, false))


func are_all_main_steps_completed() -> bool:
	if definition == null:
		return true
	for step in definition.steps:
		if step == null:
			continue
		if not step.is_optional and not bool(step_completed.get(step.step_id, false)):
			return false
	return true


func get_completed_step_count() -> int:
	var count := 0
	for completed in step_completed.values():
		if bool(completed):
			count += 1
	return count


func get_total_step_count() -> int:
	return definition.steps.size() if definition != null else 0


func get_hud_text() -> String:
	if definition == null or definition.steps.is_empty():
		return "暂无任务"
	for step in definition.steps:
		if step == null:
			continue
		if not bool(step_completed.get(step.step_id, false)):
			var prefix := "[可选] " if step.is_optional else ""
			return "目标：%s%s" % [prefix, step.description if not step.description.is_empty() else String(step.step_id)]
	return "任务已达成 · 前往撤离点撤离"


func get_summary() -> Dictionary:
	var completed_list: Array[String] = []
	var pending_list: Array[String] = []
	if definition != null:
		for step in definition.steps:
			if step == null:
				continue
			var desc: String = step.description if not step.description.is_empty() else String(step.step_id)
			if bool(step_completed.get(step.step_id, false)):
				completed_list.append(desc)
			else:
				pending_list.append(desc)
	return {
		&"has_mission": definition != null and not definition.steps.is_empty(),
		&"title": definition.title if definition != null else "自由行动",
		&"all_completed": are_all_main_steps_completed(),
		&"completed_steps": completed_list,
		&"pending_steps": pending_list,
	}


func capture_state() -> Dictionary:
	return {
		&"interacted_objects": interacted_objects.duplicate(),
		&"step_completed": step_completed.duplicate(),
	}


func restore_state(snapshot: Dictionary) -> void:
	if snapshot.has(&"interacted_objects") and snapshot[&"interacted_objects"] is Dictionary:
		interacted_objects = (snapshot[&"interacted_objects"] as Dictionary).duplicate()
	else:
		interacted_objects.clear()
	if snapshot.has(&"step_completed") and snapshot[&"step_completed"] is Dictionary:
		step_completed = (snapshot[&"step_completed"] as Dictionary).duplicate()
	else:
		step_completed.clear()
