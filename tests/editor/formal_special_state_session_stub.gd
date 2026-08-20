extends TacticalMapEditSession

## Test-only Session double for the formal special-edit state contract.  It
## deliberately exposes no map data and lets Dock tests drive the two states
## that the real Session reports while a connection/patrol stroke is active.

var formal_state: Dictionary = {}


func get_special_edit_state() -> Dictionary:
	return formal_state.duplicate(true)
