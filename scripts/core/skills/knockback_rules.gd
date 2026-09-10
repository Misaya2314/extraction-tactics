extends RefCounted

## Explicit authored void cells are lethal. Missing cells are map boundaries.
static func preview(grid: GridModel, actor_cell: Vector3i, target_cell: Vector3i, void_cells: Dictionary) -> Dictionary:
	var direction := target_cell - actor_cell
	if direction.y != 0 or absi(direction.x) + absi(direction.z) != 1:
		return {&"valid": false, &"reason": &"not_adjacent"}
	if grid.is_movement_blocked(actor_cell, target_cell):
		return {&"valid": false, &"reason": &"blocked_edge"}
	var destination := target_cell + direction
	if not grid.has_cell(destination) or grid.is_movement_blocked(target_cell, destination):
		return {&"valid": false, &"reason": &"blocked_edge"}
	if grid.is_occupied(destination):
		return {&"valid": false, &"reason": &"occupied"}
	var lethal := bool(void_cells.get(destination, false))
	if not lethal and not grid.is_walkable(destination):
		return {&"valid": false, &"reason": &"blocked_cell"}
	return {&"valid": true, &"reason": &"void_fall" if lethal else &"knockback", &"destination": destination, &"lethal": lethal}
