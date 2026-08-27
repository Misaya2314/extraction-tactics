class_name TacticalEdgeIndex
extends RefCounted

## Runtime lookup for canonical horizontal map edges.
##
## The baked definition remains the serialized source of truth.  This index is
## only a runtime acceleration structure: every query is a dictionary lookup
## by TacticalEdgeKey.key_string(), never a scan over the complete map.

var _edges: Dictionary = {}
var _ordered_keys: Array[String] = []
var _valid: bool = true


func clear() -> void:
	_edges.clear()
	_ordered_keys.clear()
	_valid = true


func configure(edges: Array) -> bool:
	clear()
	if edges == null:
		_valid = false
		return false
	for value in edges:
		if not value is MapEdgeData:
			_valid = false
			continue
		var edge := value as MapEdgeData
		var key := edge.get_key()
		if key == null or not key.is_valid():
			_valid = false
			continue
		var key_string := key.key_string()
		if _edges.has(key_string):
			# A duplicate key is ambiguous. Keep the first serialized edge for a
			# deterministic runtime view, but report the invalid definition.
			_valid = false
			continue
		_edges[key_string] = edge
		_ordered_keys.append(key_string)
	_ordered_keys.sort()
	return _valid


func is_valid() -> bool:
	return _valid


func size() -> int:
	return _edges.size()


func get_edge(cell_a: Vector3i, cell_b: Vector3i) -> MapEdgeData:
	var key := TacticalEdgeKey.from_cells(cell_a, cell_b)
	if key == null or not key.is_valid():
		return null
	return _edges.get(key.key_string(), null) as MapEdgeData


func has_edge(cell_a: Vector3i, cell_b: Vector3i) -> bool:
	return get_edge(cell_a, cell_b) != null


func is_movement_blocked(cell_a: Vector3i, cell_b: Vector3i) -> bool:
	var edge := get_edge(cell_a, cell_b)
	return edge != null and edge.blocks_movement


func get_ordered_keys() -> Array[String]:
	return _ordered_keys.duplicate()
