class_name DetectionRules
extends RefCounted

const _CARDINAL_FACING: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func is_in_vision_cone(observer: Vector3i, target: Vector3i, facing: Vector2i, vision_range: int, half_angle_degrees: float = 60.0) -> bool:
	if vision_range < 0 or half_angle_degrees < 0.0 or is_nan(half_angle_degrees) or is_inf(half_angle_degrees):
		return false
	if not _CARDINAL_FACING.has(facing):
		return false
	if observer == target:
		return true
	if GridVisibility.tactical_distance(observer, target) > vision_range:
		return false
	var offset := Vector2i(target.x - observer.x, target.z - observer.z)
	if offset == Vector2i.ZERO:
		return true
	var dot_product := facing.x * offset.x + facing.y * offset.y
	var cosine_limit := cos(deg_to_rad(minf(half_angle_degrees, 180.0)))
	var normalized_dot := float(dot_product) / sqrt(float(offset.length_squared()))
	return normalized_dot + 0.000001 >= cosine_limit


static func can_detect(observer: Vector3i, target: Vector3i, facing: Vector2i, vision_range: int, opaque_cells: Dictionary, half_angle_degrees: float = 60.0) -> bool:
	return is_in_vision_cone(observer, target, facing, vision_range, half_angle_degrees) \
		and GridVisibility.has_line_of_sight(observer, target, opaque_cells, vision_range)


static func can_player_see(observer: Vector3i, target: Vector3i, vision_range: int, opaque_cells: Dictionary) -> bool:
	return vision_range >= 0 and GridVisibility.has_line_of_sight(observer, target, opaque_cells, vision_range)
