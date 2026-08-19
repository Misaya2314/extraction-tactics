@tool
class_name MapCellData
extends Resource

## Stable, baked description of one standable tactical surface.
## Coordinate convention: Vector3i(x, level, z).

@export var coordinate: Vector3i = Vector3i.ZERO
@export var walkable: bool = true
@export_range(1, 99, 1) var move_cost: int = 1
@export var blocks_los: bool = false
@export_range(0.0, 20.0, 0.05) var occluder_height: float = 0.0
@export var terrain_id: StringName = &"floor"
@export_flags("North", "East", "South", "West") var cover_mask: int = 0
## Phase-A compiled rule fields. The legacy fields above remain the runtime
## compatibility surface used by existing GridModel/LOS code.
@export_range(0.0, 1.0, 0.01) var sight_block: float = 0.0
@export_range(0.0, 1.0, 0.01) var projectile_block: float = 0.0
@export_range(0.0, 99.0, 0.05) var sound_cost: float = 0.0
@export var terrain_tags: PackedStringArray = PackedStringArray()
@export var hazard_id: StringName = &""


func copy_from(other: MapCellData) -> void:
	coordinate = other.coordinate
	walkable = other.walkable
	move_cost = maxi(other.move_cost, 1)
	blocks_los = other.blocks_los
	occluder_height = maxf(other.occluder_height, 0.0)
	terrain_id = other.terrain_id
	cover_mask = other.cover_mask
	sight_block = clampf(other.sight_block, 0.0, 1.0)
	projectile_block = clampf(other.projectile_block, 0.0, 1.0)
	sound_cost = maxf(other.sound_cost, 0.0)
	terrain_tags = other.terrain_tags.duplicate()
	hazard_id = other.hazard_id
