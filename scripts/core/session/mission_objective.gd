class_name MissionObjective
extends RefCounted

## Immutable target membership; progress is derived from authoritative unit HP.
## Undo restores units, so there is no second mutable kill counter to drift.
var target_ids: Array[StringName] = []


func configure(ids: Array[StringName]) -> void:
	target_ids.clear()
	for id in ids:
		if id != &"" and not target_ids.has(id):
			target_ids.append(id)


func progress(units: Dictionary) -> Dictionary:
	var completed := 0
	for id in target_ids:
		var unit = units.get(id)
		# Missing references are not kills: invalid configuration cannot win.
		if is_instance_valid(unit) and not unit.is_alive():
			completed += 1
	return {&"completed": completed, &"total": target_ids.size(),
		&"success": not target_ids.is_empty() and completed == target_ids.size()}
