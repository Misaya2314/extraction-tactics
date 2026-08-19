@tool
class_name TacticalEdgeRules
extends Resource

enum CoverLevel {
	NONE,
	HALF,
	FULL,
}

@export var cover_a: CoverLevel = CoverLevel.NONE
@export var cover_b: CoverLevel = CoverLevel.NONE
@export var blocks_movement: bool = false
@export_range(0.0, 1.0, 0.01) var sight_block: float = 0.0
@export_range(0.0, 1.0, 0.01) var projectile_block: float = 0.0
@export_range(0.0, 20.0, 0.05) var height: float = 0.0
@export var destructible: bool = false
@export var runtime_state_id: StringName = &""


func copy_from(other: TacticalEdgeRules) -> void:
	if other == null:
		return
	cover_a = other.cover_a
	cover_b = other.cover_b
	blocks_movement = other.blocks_movement
	sight_block = clampf(other.sight_block, 0.0, 1.0)
	projectile_block = clampf(other.projectile_block, 0.0, 1.0)
	height = maxf(other.height, 0.0)
	destructible = other.destructible
	runtime_state_id = other.runtime_state_id


func duplicate_rules() -> TacticalEdgeRules:
	var result := TacticalEdgeRules.new()
	result.copy_from(self)
	return result


func is_valid() -> bool:
	return cover_a >= CoverLevel.NONE and cover_a <= CoverLevel.FULL \
		and cover_b >= CoverLevel.NONE and cover_b <= CoverLevel.FULL \
		and sight_block >= 0.0 and sight_block <= 1.0 \
		and projectile_block >= 0.0 and projectile_block <= 1.0 \
		and height >= 0.0

