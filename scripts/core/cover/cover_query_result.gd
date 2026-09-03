class_name CoverQueryResult
extends RefCounted

## Cover/line result shared by player, AI and attack presentation/debugging.

var valid: bool = false
var reason: StringName = &""
var attacker_cell: Vector3i = Vector3i(-1, -1, -1)
var target_cell: Vector3i = Vector3i(-1, -1, -1)
var cross_level: bool = false
var cells_crossed: Array[Vector3i] = []
var edges_crossed: Array[MapEdgeData] = []
var target_incoming_edges: Array[MapEdgeData] = []
## Alias used by the editor/debug contract for the corner candidates.
var candidate_edges: Array[MapEdgeData] = []
var los_blocked: bool = false
var projectile_blocked: bool = false
var block_reason: StringName = &""
var sight_blocking_cell: Vector3i = Vector3i(-1, -1, -1)
var projectile_blocking_cell: Vector3i = Vector3i(-1, -1, -1)
var sight_blocking_edge: MapEdgeData
var projectile_blocking_edge: MapEdgeData
var sight_blocking_edge_key: String = ""
var projectile_blocking_edge_key: String = ""
## Compatibility aggregate copied from TacticalLineQueryResult.
var blocking_cell: Vector3i = Vector3i(-1, -1, -1)
var blocking_edge: MapEdgeData
var blocking_edge_key: String = ""
var has_cover: bool = false
var cover_level: int = 0
var cover_profile_id: StringName = &"cover.none"
var profile: TacticalCoverProfile
var damage_reduction_ratio: float = 0.0
var reduction_ratio: float = 0.0
var source_edge: MapEdgeData
var source_edge_key: String = ""
var target_side: StringName = &""
var is_step_out: bool = false
var step_out_cell: Vector3i = Vector3i(-1, -1, -1)
var original_attacker_cell: Vector3i = Vector3i(-1, -1, -1)


static func cover_level_name(level: int) -> StringName:
	match clampi(level, 0, 2):
		1:
			return &"HALF"
		2:
			return &"FULL"
		_:
			return &"NONE"


## Stable, presentation-neutral diagnostic data for logs, HUDs and tests.
## Damage values are supplied by CoverResolver.resolve_damage(); keeping the
## two inputs separate makes this result useful even before damage is rolled.
func get_debug_summary(damage: Dictionary = {}) -> Dictionary:
	var base_damage := int(damage.get(&"base_damage", 0))
	var effective_damage := int(damage.get(&"effective_damage", 0))
	var prevented_damage := int(damage.get(&"prevented_damage", maxi(base_damage - effective_damage, 0)))
	var resolved_profile_id: StringName = damage.get(&"cover_profile_id", cover_profile_id)
	var cover_source_edge_key := String(damage.get(&"cover_source_edge", damage.get(&"source_edge_key", source_edge_key)))
	if cover_source_edge_key.is_empty() and source_edge != null:
		cover_source_edge_key = source_edge.key_string()
	var resolved_sight_blocking_edge_key := sight_blocking_edge_key
	if resolved_sight_blocking_edge_key.is_empty() and sight_blocking_edge != null:
		resolved_sight_blocking_edge_key = sight_blocking_edge.key_string()
	var resolved_projectile_blocking_edge_key := projectile_blocking_edge_key
	if resolved_projectile_blocking_edge_key.is_empty() and projectile_blocking_edge != null:
		resolved_projectile_blocking_edge_key = projectile_blocking_edge.key_string()
	var resolved_blocking_edge_key := blocking_edge_key
	if resolved_blocking_edge_key.is_empty() and blocking_edge != null:
		resolved_blocking_edge_key = blocking_edge.key_string()
	var resolved_block_reason: StringName = block_reason
	if resolved_block_reason == &"":
		if los_blocked:
			resolved_block_reason = &"sight_blocked"
		elif projectile_blocked:
			resolved_block_reason = &"projectile_blocked"
	return {
		&"cover_level": clampi(cover_level, 0, 2),
		&"cover_level_name": cover_level_name(cover_level),
		&"has_cover": has_cover,
		&"cover_profile_id": resolved_profile_id,
		&"damage_reduction_ratio": damage_reduction_ratio,
		&"damage_reduction_percent": roundi(damage_reduction_ratio * 100.0),
		&"base_damage": base_damage,
		&"prevented_damage": prevented_damage,
		&"effective_damage": effective_damage,
		# `source_edge_key` remains the old cover-source alias.  The explicit
		# keys below prevent it from being confused with an obstruction edge.
		&"source_edge_key": cover_source_edge_key,
		&"cover_source_edge": cover_source_edge_key,
		&"cover_source_edge_key": cover_source_edge_key,
		&"sight_blocking_cell": sight_blocking_cell,
		&"projectile_blocking_cell": projectile_blocking_cell,
		&"blocking_cell": blocking_cell,
		&"sight_blocking_edge": resolved_sight_blocking_edge_key,
		&"projectile_blocking_edge": resolved_projectile_blocking_edge_key,
		&"sight_blocking_edge_key": resolved_sight_blocking_edge_key,
		&"projectile_blocking_edge_key": resolved_projectile_blocking_edge_key,
		&"blocking_edge_key": resolved_blocking_edge_key,
		&"los_blocked": los_blocked,
		&"projectile_blocked": projectile_blocked,
		&"los_block_reason": &"sight_blocked" if los_blocked else &"",
		&"projectile_block_reason": &"projectile_blocked" if projectile_blocked else &"",
		&"block_reason": resolved_block_reason,
		&"reason": reason,
		&"is_step_out": is_step_out,
		&"step_out_cell": step_out_cell,
		&"original_attacker_cell": original_attacker_cell,
	}


func debug_summary(damage: Dictionary = {}) -> Dictionary:
	return get_debug_summary(damage)


func can_attack() -> bool:
	return valid and not los_blocked and not projectile_blocked


func is_blocked() -> bool:
	return los_blocked or projectile_blocked
