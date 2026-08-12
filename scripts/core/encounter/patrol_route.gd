class_name PatrolRoute
extends RefCounted

const INVALID_CELL := Vector3i(-1, -1, -1)

var _points: Array[Vector3i] = []
var _current_index: int = 0
var _direction: int = 1
var _loop: bool = true


func configure(points: Array[Vector3i], loop: bool = true) -> void:
	_points.clear()
	_loop = loop
	_current_index = 0
	_direction = 1

	for point in points:
		if _points.is_empty() or _points[_points.size() - 1] != point:
			_points.append(point)


func current() -> Vector3i:
	if _points.is_empty():
		return INVALID_CELL
	return _points[_current_index]


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

	return current()


func reset() -> void:
	_current_index = 0
	_direction = 1


func is_empty() -> bool:
	return _points.is_empty()
