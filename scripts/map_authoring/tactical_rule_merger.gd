@tool
class_name TacticalRuleMerger
extends RefCounted

## One deterministic rule authority for legacy Catalog rules, placeable
## contributions, and explicit overrides.


static func from_legacy(rule: MapTileRule) -> TacticalCellRules:
	var result := TacticalCellRules.new()
	if rule == null:
		return result
	result.walkable = rule.walkable
	result.move_cost = maxi(rule.move_cost, 1)
	result.sight_block = 1.0 if rule.blocks_los else 0.0
	result.occluder_height = maxf(rule.occluder_height, 0.0)
	if rule.tile_id != &"":
		result.terrain_tags = PackedStringArray([String(rule.tile_id)])
	return result


static func merge(base: TacticalCellRules, contribution: TacticalCellRules) -> TacticalCellRules:
	var result := TacticalCellRules.new()
	if base != null:
		result.copy_from(base)
	result.merge_contribution(contribution)
	return result


static func apply_override(base: TacticalCellRules, cell_override: TacticalCellOverride) -> TacticalCellRules:
	var result := TacticalCellRules.new()
	if base != null:
		result.copy_from(base)
	if cell_override == null or cell_override.values == null:
		return result
	var values := cell_override.values
	if cell_override.has_override(TacticalCellOverride.Field.WALKABLE):
		result.walkable = values.walkable
	if cell_override.has_override(TacticalCellOverride.Field.MOVE_COST):
		result.move_cost = maxi(values.move_cost, 1)
	if cell_override.has_override(TacticalCellOverride.Field.SIGHT_BLOCK):
		result.sight_block = clampf(values.sight_block, 0.0, 1.0)
	if cell_override.has_override(TacticalCellOverride.Field.PROJECTILE_BLOCK):
		result.projectile_block = clampf(values.projectile_block, 0.0, 1.0)
	if cell_override.has_override(TacticalCellOverride.Field.OCCLUDER_HEIGHT):
		result.occluder_height = maxf(values.occluder_height, 0.0)
	if cell_override.has_override(TacticalCellOverride.Field.SOUND_COST):
		result.sound_cost = maxf(values.sound_cost, 0.0)
	if cell_override.has_override(TacticalCellOverride.Field.TERRAIN_TAGS):
		result.terrain_tags = values.terrain_tags.duplicate()
	if cell_override.has_override(TacticalCellOverride.Field.HAZARD_ID):
		result.hazard_id = values.hazard_id
	return result


static func to_map_cell_data(coordinate: Vector3i, rules: TacticalCellRules, terrain_id: StringName = &"floor", cover_mask: int = 0) -> MapCellData:
	var result := MapCellData.new()
	result.coordinate = coordinate
	result.terrain_id = terrain_id
	result.cover_mask = cover_mask
	if rules == null:
		return result
	result.walkable = rules.walkable
	result.move_cost = maxi(rules.move_cost, 1)
	# MapCellData is the legacy binary LOS contract. Any non-zero new blocker
	# remains conservative when compiled into that representation.
	result.blocks_los = rules.sight_block > 0.0
	result.occluder_height = maxf(rules.occluder_height, 0.0)
	result.sight_block = clampf(rules.sight_block, 0.0, 1.0)
	result.projectile_block = clampf(rules.projectile_block, 0.0, 1.0)
	result.sound_cost = maxf(rules.sound_cost, 0.0)
	result.terrain_tags = rules.terrain_tags.duplicate()
	result.hazard_id = rules.hazard_id
	return result
