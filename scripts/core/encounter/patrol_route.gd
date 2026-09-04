class_name PatrolRoute
extends RefCounted

## Sparse waypoint patrol route.
##
## Waypoints are key turning points (typically 2-4 per circuit).  Cells between
## waypoints are filled by pathfinding in EnemyTacticalAI, so no dense per-cell
## authoring is required.  `current()` is the waypoint the unit is anchored to
## and pathfinds toward; `advance()` moves to the next waypoint and arms its
## dwell counter.

const INVALID_CELL := Vector3i(-1, -1, -1)

var _points: Array[Vector3i] = []
var _dwell_ticks: Array[int] = []
var _current_index: int = 0
var _direction: int = 1
var _loop: bool = true
var _dwell_remaining: int = 0


func configure(points: Array[Vector3i], loop: bool = true, dwell_ticks: Array[int] = []) -> void:
	_points.clear()
	_dwell_ticks.clear()
	_loop = loop
	_current_index = 0
	_direction = 1
	_dwell_remaining = 0

	for index in range(points.size()):
		var point := points[index]
		if _points.is_empty() or _points[_points.size() - 1] != point:
			_points.append(point)
			_dwell_ticks.append(maxi(int(dwell_ticks[index]) if index < dwell_ticks.size() else 0, 0))

	# Manually closed circuits (A -> B -> C -> D -> A) carry a redundant
	# trailing waypoint.  With loop enabled the AI would arrive at it and then
	# advance onto the identical first waypoint, spending an idle tick on the
	# same cell every circuit.  Strip the seam duplicate unless the author
	# explicitly armed a dwell on it (an intentional seam pause).
	if _loop and _points.size() > 1 \
		and _points[0] == _points[_points.size() - 1] \
		and _dwell_ticks[_dwell_ticks.size() - 1] == 0:
		_points.pop_back()
		_dwell_ticks.pop_back()

	_dwell_remaining = _dwell_at(_current_index) if not _points.is_empty() else 0


## The waypoint the unit is currently anchored to and should move toward.
func current() -> Vector3i:
	if _points.is_empty():
		return INVALID_CELL
	return _points[_current_index]


## The waypoint after the current one (advance() destination).
func peek_next() -> Vector3i:
	if _points.is_empty():
		return INVALID_CELL
	if _points.size() == 1:
		return _points[0]

	var next_index := _current_index + _direction
	if _loop:
		next_index = posmod(next_index, _points.size())
	else:
		if next_index >= _points.size() or next_index < 0:
			next_index = _current_index - _direction
		next_index = clampi(next_index, 0, _points.size() - 1)
	return _points[next_index]


## Moves to the next waypoint and arms its dwell counter.
func advance() -> Vector3i:
	if _points.is_empty() or _points.size() == 1:
		return current()

	var next_index := _current_index + _direction
	if _loop:
		_current_index = posmod(next_index, _points.size())
	else:
		if next_index >= _points.size() or next_index < 0:
			_direction *= -1
			next_index = _current_index + _direction
		_current_index = clampi(next_index, 0, _points.size() - 1)

	_dwell_remaining = _dwell_at(_current_index)
	return current()


## Idle ticks remaining at the current waypoint.
func dwell_remaining() -> int:
	return _dwell_remaining


## Consumes one idle tick at the current waypoint.  Returns the new remaining.
func spend_dwell_tick() -> int:
	_dwell_remaining = maxi(_dwell_remaining - 1, 0)
	return _dwell_remaining


## Re-anchors the route to the waypoint nearest `from_cell` (Manhattan
## distance).  Used to seamlessly rejoin the patrol loop after an
## investigation ends without findings.
func set_nearest_waypoint(from_cell: Vector3i) -> int:
	if _points.is_empty():
		return -1
	var nearest_index := 0
	var nearest_distance := _manhattan(from_cell, _points[0])
	for index in range(1, _points.size()):
		var distance := _manhattan(from_cell, _points[index])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	_current_index = nearest_index
	_dwell_remaining = _dwell_at(_current_index)
	return nearest_index


func reset() -> void:
	_current_index = 0
	_direction = 1
	_dwell_remaining = _dwell_at(_current_index) if not _points.is_empty() else 0


func is_empty() -> bool:
	return _points.is_empty()


## Configured dwell ticks per waypoint (parallel to _points).
func get_dwell_ticks() -> Array[int]:
	return _dwell_ticks.duplicate()


func get_point_count() -> int:
	return _points.size()


func _dwell_at(index: int) -> int:
	if index < 0 or index >= _dwell_ticks.size():
		return 0
	return maxi(int(_dwell_ticks[index]), 0)


func _manhattan(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)