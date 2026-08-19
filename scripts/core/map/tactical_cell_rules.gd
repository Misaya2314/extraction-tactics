@tool
class_name TacticalCellRules
extends Resource

## Gameplay-neutral cell properties compiled by the map baker.
## These values describe the final cell contract; they do not contain runtime
## occupancy, cover state, or unit state.

@export var walkable: bool = true
@export_range(1, 99, 1) var move_cost: int = 1
@export_range(0.0, 1.0, 0.01) var sight_block: float = 0.0
@export_range(0.0, 1.0, 0.01) var projectile_block: float = 0.0
@export_range(0.0, 20.0, 0.05) var occluder_height: float = 0.0
@export_range(0.0, 99.0, 0.05) var sound_cost: float = 0.0
@export var terrain_tags: PackedStringArray = PackedStringArray()
@export var hazard_id: StringName = &""


func copy_from(other: TacticalCellRules) -> void:
	if other == null:
		return
	walkable = other.walkable
	move_cost = maxi(other.move_cost, 1)
	sight_block = clampf(other.sight_block, 0.0, 1.0)
	projectile_block = clampf(other.projectile_block, 0.0, 1.0)
	occluder_height = maxf(other.occluder_height, 0.0)
	sound_cost = maxf(other.sound_cost, 0.0)
	terrain_tags = other.terrain_tags.duplicate()
	hazard_id = other.hazard_id


func duplicate_rules() -> TacticalCellRules:
	var result := TacticalCellRules.new()
	result.copy_from(self)
	return result


func is_valid() -> bool:
	return move_cost >= 1 \
		and sight_block >= 0.0 and sight_block <= 1.0 \
		and projectile_block >= 0.0 and projectile_block <= 1.0 \
		and occluder_height >= 0.0 and sound_cost >= 0.0


func merge_contribution(contribution: TacticalCellRules, replace_hazard: bool = true) -> void:
	if contribution == null:
		return
	walkable = walkable and contribution.walkable
	move_cost = maxi(move_cost, contribution.move_cost)
	sight_block = maxf(sight_block, contribution.sight_block)
	projectile_block = maxf(projectile_block, contribution.projectile_block)
	occluder_height = maxf(occluder_height, contribution.occluder_height)
	sound_cost = maxf(sound_cost, contribution.sound_cost)
	var merged_tags: Array[String] = []
	for tag in terrain_tags:
		if not merged_tags.has(String(tag)):
			merged_tags.append(String(tag))
	for tag in contribution.terrain_tags:
		if not merged_tags.has(String(tag)):
			merged_tags.append(String(tag))
	merged_tags.sort()
	terrain_tags = PackedStringArray(merged_tags)
	if replace_hazard and contribution.hazard_id != &"":
		hazard_id = contribution.hazard_id

