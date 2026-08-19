@tool
class_name TacticalPlacementTarget
extends RefCounted

## Viewport hit translated into the shared Vector3i(x, level, z) contract.

var cell: Vector3i = Vector3i.ZERO
var world_position: Vector3 = Vector3.ZERO
var surface_normal: Vector3 = Vector3.UP
var current_level: int = 0
var valid: bool = false
var reason: String = ""


static func invalid(message: String) -> TacticalPlacementTarget:
	var target := TacticalPlacementTarget.new()
	target.valid = false
	target.reason = message
	return target
