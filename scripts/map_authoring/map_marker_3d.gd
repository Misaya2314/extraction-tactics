@tool
class_name MapMarker3D
extends Node3D

## Base marker whose logical coordinate stays snapped to its TacticalMapAuthor.

@export var cell: Vector3i = Vector3i.ZERO:
	set(value):
		cell = value
		_snap_to_grid()


func _ready() -> void:
	_snap_to_grid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED:
		_snap_to_grid.call_deferred()


func snap_to_grid() -> void:
	_snap_to_grid()


func _snap_to_grid() -> void:
	if not is_inside_tree():
		return
	var author := _find_author()
	if author == null:
		return
	var target: Vector3 = author.cell_to_local(cell)
	if not position.is_equal_approx(target):
		position = target


func _find_author() -> TacticalMapAuthor:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor is TacticalMapAuthor:
			return cursor
		cursor = cursor.get_parent()
	return null
