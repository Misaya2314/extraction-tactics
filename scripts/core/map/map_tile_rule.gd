@tool
class_name MapTileRule
extends Resource

enum Layer {
	FLOOR,
	STRUCTURE,
}

@export var layer: Layer = Layer.FLOOR
@export var item_id: int = -1
@export var tile_id: StringName = &"tile"
@export var walkable: bool = true
@export_range(1, 99, 1) var move_cost: int = 1
@export var blocks_los: bool = false
@export_range(0.0, 20.0, 0.05) var occluder_height: float = 0.0
@export_flags("North", "East", "South", "West") var cover_mask: int = 0

