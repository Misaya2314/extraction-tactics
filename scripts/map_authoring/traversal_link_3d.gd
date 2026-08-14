@tool
class_name TraversalLink3D
extends Node3D

@export var from_cell: Vector3i = Vector3i.ZERO
@export var to_cell: Vector3i = Vector3i.ZERO
@export_range(1, 99, 1) var move_cost: int = 1
@export var bidirectional: bool = true
@export var enabled: bool = true
@export var kind: MapTransitionData.Kind = MapTransitionData.Kind.STAIRS


func to_data() -> MapTransitionData:
	var data := MapTransitionData.new()
	data.from_cell = from_cell
	data.to_cell = to_cell
	data.move_cost = move_cost
	data.bidirectional = bidirectional
	data.enabled = enabled
	data.kind = kind
	return data
