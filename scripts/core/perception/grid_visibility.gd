class_name GridVisibility
extends RefCounted

## Deterministic supercover LOS projected on X/Z, with each emitted sample
## assigned an interpolated logical level. Opaque keys are full Vector3i cells,
## so stacked floors no longer collide in the visibility map.


static func line_cells(start: Vector3i, target: Vector3i) -> Array[Vector3i]:
	var horizontal := _line_cells_2d(Vector2i(start.x, start.z), Vector2i(target.x, target.z))
	var cells: Array[Vector3i] = []
	var denominator := maxi(horizontal.size() - 1, 1)
	for index in range(horizontal.size()):
		var point := horizontal[index]
		var level := roundi(lerpf(float(start.y), float(target.y), float(index) / float(denominator)))
		var cell := Vector3i(point.x, level, point.y)
		if cells.is_empty() or cells[-1] != cell:
			cells.append(cell)
	if cells.is_empty():
		cells.append(start)
	cells[0] = start
	cells[-1] = target
	return cells


static func has_line_of_sight(start: Vector3i, target: Vector3i, opaque_cells: Dictionary, max_range: int = -1) -> bool:
	if max_range < -1:
		return false
	if max_range >= 0 and tactical_distance(start, target) > max_range:
		return false
	var cells := line_cells(start, target)
	for index in range(1, cells.size() - 1):
		if opaque_cells.has(cells[index]):
			return false
	return true


static func visible_cells(origin: Vector3i, footprint_size: Vector2i, level_count: int, vision_range: int, opaque_cells: Dictionary) -> Array[Vector3i]:
	var visible: Array[Vector3i] = []
	if vision_range < 0 or footprint_size.x <= 0 or footprint_size.y <= 0 or level_count <= 0:
		return visible
	for level in range(level_count):
		for z in range(footprint_size.y):
			for x in range(footprint_size.x):
				var cell := Vector3i(x, level, z)
				if tactical_distance(origin, cell) <= vision_range and has_line_of_sight(origin, cell, opaque_cells, vision_range):
					visible.append(cell)
	return visible


## Current demo rule: one tile of level difference costs one range unit.
static func tactical_distance(start: Vector3i, target: Vector3i) -> int:
	return absi(target.x - start.x) + absi(target.z - start.z) + absi(target.y - start.y)


static func _line_cells_2d(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x := start.x
	var y := start.y
	var delta_x := target.x - start.x
	var delta_y := target.y - start.y
	var step_x := signi(delta_x)
	var step_y := signi(delta_y)
	var absolute_x := absi(delta_x)
	var absolute_y := absi(delta_y)
	cells.append(Vector2i(x, y))
	if absolute_x == 0 and absolute_y == 0:
		return cells
	var travelled_x := 0
	var travelled_y := 0
	while x != target.x or y != target.y:
		var comparison_x := (1 + 2 * travelled_x) * absolute_y
		var comparison_y := (1 + 2 * travelled_y) * absolute_x
		if comparison_x == comparison_y:
			var corner_x := Vector2i(x + step_x, y)
			var corner_y := Vector2i(x, y + step_y)
			if cells[-1] != corner_x:
				cells.append(corner_x)
			if cells[-1] != corner_y:
				cells.append(corner_y)
			x += step_x
			y += step_y
			travelled_x += 1
			travelled_y += 1
			var diagonal := Vector2i(x, y)
			if cells[-1] != diagonal:
				cells.append(diagonal)
		elif comparison_x < comparison_y:
			x += step_x
			travelled_x += 1
			cells.append(Vector2i(x, y))
		else:
			y += step_y
			travelled_y += 1
			cells.append(Vector2i(x, y))
	return cells
