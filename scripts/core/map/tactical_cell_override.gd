@tool
class_name TacticalCellOverride
extends Resource

## Explicit per-cell override. A field is inherited unless its bit is set;
## sentinel values are never used to mean "inherit".

enum Field {
	WALKABLE = 1,
	MOVE_COST = 2,
	SIGHT_BLOCK = 4,
	PROJECTILE_BLOCK = 8,
	OCCLUDER_HEIGHT = 16,
	SOUND_COST = 32,
	TERRAIN_TAGS = 64,
	HAZARD_ID = 128,
}

const ALL_FIELDS: int = Field.WALKABLE | Field.MOVE_COST | Field.SIGHT_BLOCK | Field.PROJECTILE_BLOCK \
	| Field.OCCLUDER_HEIGHT | Field.SOUND_COST | Field.TERRAIN_TAGS | Field.HAZARD_ID

@export var coordinate: Vector3i = Vector3i.ZERO
@export_flags("Walkable", "Move Cost", "Sight Block", "Projectile Block", "Occluder Height", "Sound Cost", "Terrain Tags", "Hazard ID") var override_mask: int = 0
@export var values: TacticalCellRules


func has_override(field: Field) -> bool:
	return (override_mask & int(field)) != 0


func is_empty() -> bool:
	return override_mask == 0


func is_valid() -> bool:
	return override_mask >= 0 and (override_mask & ~ALL_FIELDS) == 0 \
		and (override_mask == 0 or (values != null and values.is_valid()))
