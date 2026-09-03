class_name EnvironmentEffectResolver
extends RefCounted

## Pure environment-effect geometry and target filtering.  It accepts plain
## dictionaries so callers can adapt Unit/Environment runtime states without
## giving this class a Node or scene dependency.


static func affected_cells(source_cell: Variant, radius: Variant) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if not source_cell is Vector3i or typeof(radius) != TYPE_INT or int(radius) < 0:
		return result
	var origin: Vector3i = source_cell
	var distance_limit: int = radius
	for x in range(origin.x - distance_limit, origin.x + distance_limit + 1):
		for z in range(origin.z - distance_limit, origin.z + distance_limit + 1):
			if abs(x - origin.x) + abs(z - origin.z) <= distance_limit:
				result.append(Vector3i(x, origin.y, z))
	result.sort_custom(func(first: Vector3i, second: Vector3i) -> bool:
		if first.z != second.z:
			return first.z < second.z
		return first.x < second.x
	)
	return result


static func is_in_area(source_cell: Variant, target_cell: Variant, radius: Variant) -> bool:
	if not source_cell is Vector3i or not target_cell is Vector3i or typeof(radius) != TYPE_INT or int(radius) < 0:
		return false
	var origin: Vector3i = source_cell
	var target: Vector3i = target_cell
	if origin.y != target.y:
		return false
	return abs(origin.x - target.x) + abs(origin.z - target.z) <= int(radius)


static func resolve_area_damage(
		effect: Variant,
		source_cell: Variant,
		candidates: Array
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not effect is ExplosionEffectDefinition or not source_cell is Vector3i:
		return result
	var typed_effect := effect as ExplosionEffectDefinition
	var origin: Vector3i = source_cell
	if not typed_effect.is_valid():
		return result
	var seen_ids: Dictionary = {}
	for candidate_value in candidates:
		var candidate := _candidate_dictionary(candidate_value)
		if candidate.is_empty():
			continue
		var candidate_cell = candidate.get(&"cell", null)
		if not candidate_cell is Vector3i:
			continue
		var typed_candidate_cell: Vector3i = candidate_cell
		if not is_in_area(origin, typed_candidate_cell, typed_effect.radius):
			continue
		if not _affects_candidate(candidate, typed_effect):
			continue
		var raw_id = candidate.get(&"target_id", candidate.get(&"instance_id", candidate.get(&"id", null)))
		if typeof(raw_id) != TYPE_STRING_NAME and typeof(raw_id) != TYPE_STRING:
			continue
		var target_id := StringName(raw_id)
		if target_id == &"":
			continue
		if seen_ids.has(target_id):
			continue
		seen_ids[target_id] = true
		result.append({
			&"target_id": target_id,
			&"cell": typed_candidate_cell,
			&"distance": abs(origin.x - typed_candidate_cell.x) + abs(origin.z - typed_candidate_cell.z),
			&"damage": typed_effect.damage,
			&"effect_id": typed_effect.effect_id,
			&"allow_chain": typed_effect.allow_chain,
			&"target_type": _target_type(candidate),
		})
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get(&"target_id", "")) < String(second.get(&"target_id", ""))
	)
	return result


static func resolve_explosion(
		effect: Variant,
		source_cell: Variant,
		candidates: Array
) -> Array[Dictionary]:
	return resolve_area_damage(effect, source_cell, candidates)


static func resolve(
		effect: Variant,
		source_cell: Variant,
		candidates: Array
) -> Array[Dictionary]:
	return resolve_area_damage(effect, source_cell, candidates)


static func _candidate_dictionary(candidate: Variant) -> Dictionary:
	if candidate is Dictionary:
		return candidate as Dictionary
	if candidate is EnvironmentObjectRuntimeState:
		var state := candidate as EnvironmentObjectRuntimeState
		return {
			&"target_id": state.instance_id,
			&"cell": state.cell,
			&"target_type": &"environment",
			&"active": state.active,
		}
	if typeof(candidate) == TYPE_OBJECT:
		var object_value: Object = candidate
		if object_value.has_method("get_cell") and object_value.has_method("get_stable_instance_id"):
			var object_cell = object_value.call("get_cell")
			var object_id = object_value.call("get_stable_instance_id")
			if object_cell is Vector3i and (typeof(object_id) == TYPE_STRING_NAME or typeof(object_id) == TYPE_STRING):
				return {
					&"target_id": StringName(object_id),
					&"cell": object_cell,
					&"target_type": &"environment",
				}
	return {}


static func _affects_candidate(candidate: Dictionary, effect: ExplosionEffectDefinition) -> bool:
	if candidate.has(&"active") and typeof(candidate[&"active"]) == TYPE_BOOL and not candidate[&"active"]:
		return false
	var target_type := _target_type(candidate)
	if target_type == &"environment":
		return effect.affect_environment_objects
	if target_type == &"player":
		return effect.affect_players
	if target_type == &"enemy":
		return effect.affect_enemies
	return false


static func _target_type(candidate: Dictionary) -> StringName:
	var raw_type = candidate.get(&"target_type", candidate.get(&"kind", null))
	if typeof(raw_type) == TYPE_STRING_NAME or typeof(raw_type) == TYPE_STRING:
		var normalized := String(raw_type).to_lower()
		if normalized.contains("environment") or normalized == "object" or normalized == "barrel":
			return &"environment"
		if normalized.contains("player"):
			return &"player"
		if normalized.contains("enemy"):
			return &"enemy"
	var raw_faction = candidate.get(&"faction", null)
	if typeof(raw_faction) == TYPE_STRING_NAME or typeof(raw_faction) == TYPE_STRING:
		var faction := String(raw_faction).to_lower()
		if faction == "player" or faction == "players":
			return &"player"
		if faction == "enemy" or faction == "enemies":
			return &"enemy"
	return &""
