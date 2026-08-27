class_name CoverResolver
extends RefCounted

## Pure deterministic damage calculation.  It has no Node/HP dependency and
## therefore can be used by the runtime attack handler and unit tests alike.
static func resolve_damage(
	base_damage: int,
	cover: Variant = null,
	settings: CoverCombatSettings = null,
	source_edge: MapEdgeData = null
) -> Dictionary:
	var safe_base := maxi(base_damage, 0)
	var profile: TacticalCoverProfile
	if cover is TacticalCoverProfile:
		profile = cover as TacticalCoverProfile
	elif cover is CoverQueryResult:
		var query_result := cover as CoverQueryResult
		profile = query_result.profile
		if source_edge == null:
			source_edge = query_result.source_edge
	var ratio := 0.0
	var level := 0
	var profile_id: StringName = &"cover.none"
	if profile != null:
		ratio = clampf(profile.damage_reduction_ratio, 0.0, 1.0)
		level = clampi(profile.cover_level, 0, 2)
		profile_id = profile.cover_id
	var effective := roundi(float(safe_base) * (1.0 - ratio))
	var minimum := settings.minimum_damage_after_cover if settings != null else 0
	var allow_zero := settings.allow_zero_damage if settings != null else true
	effective = maxi(effective, minimum)
	if safe_base > 0 and not allow_zero:
		effective = maxi(effective, 1)
	effective = clampi(effective, 0, safe_base)
	return {
		&"base_damage": safe_base,
		&"effective_damage": effective,
		&"prevented_damage": maxi(safe_base - effective, 0),
		&"cover_level": level,
		&"cover_profile_id": profile_id,
		&"source_edge_key": "" if source_edge == null else source_edge.key_string(),
		&"cover_source_edge_key": "" if source_edge == null else source_edge.key_string(),
		&"cover_source_edge": "" if source_edge == null else source_edge.key_string(),
	}


static func resolve(
	base_damage: int,
	cover: Variant = null,
	settings: CoverCombatSettings = null,
	source_edge: MapEdgeData = null
) -> Dictionary:
	return resolve_damage(base_damage, cover, settings, source_edge)


## Builds the stable data consumed by presentation/debug layers.  The
## calculation remains pure and does not inspect Nodes or mutate the query.
static func build_debug_summary(
	cover_result: CoverQueryResult,
	damage: Dictionary = {}
) -> Dictionary:
	if cover_result == null:
		return {
			&"cover_level": 0,
			&"cover_level_name": &"NONE",
			&"has_cover": false,
			&"cover_profile_id": &"cover.none",
			&"damage_reduction_ratio": 0.0,
			&"damage_reduction_percent": 0,
			&"base_damage": int(damage.get(&"base_damage", 0)),
			&"prevented_damage": int(damage.get(&"prevented_damage", 0)),
			&"effective_damage": int(damage.get(&"effective_damage", 0)),
			&"source_edge_key": String(damage.get(&"source_edge_key", "")),
			&"cover_source_edge": String(damage.get(&"cover_source_edge", damage.get(&"source_edge_key", ""))),
			&"cover_source_edge_key": String(damage.get(&"cover_source_edge_key", damage.get(&"source_edge_key", ""))),
			&"sight_blocking_cell": Vector3i(-1, -1, -1),
			&"projectile_blocking_cell": Vector3i(-1, -1, -1),
			&"blocking_cell": Vector3i(-1, -1, -1),
			&"sight_blocking_edge": "",
			&"projectile_blocking_edge": "",
			&"sight_blocking_edge_key": "",
			&"projectile_blocking_edge_key": "",
			&"blocking_edge_key": "",
			&"los_blocked": false,
			&"projectile_blocked": false,
			&"los_block_reason": &"",
			&"projectile_block_reason": &"",
			&"block_reason": &"",
			&"reason": &"",
		}
	return cover_result.get_debug_summary(damage)


static func debug_summary(
	cover_result: CoverQueryResult,
	damage: Dictionary = {}
) -> Dictionary:
	return build_debug_summary(cover_result, damage)


## Deterministic human-readable form for Output and lightweight HUD text.
## The dictionary form above remains the machine-readable contract.
static func format_debug_summary(summary: Dictionary) -> String:
	var level_name := String(summary.get(&"cover_level_name", &"NONE"))
	var profile_id := String(summary.get(&"cover_profile_id", &"cover.none"))
	var reduction_percent := int(summary.get(&"damage_reduction_percent", 0))
	var base_damage := int(summary.get(&"base_damage", 0))
	var prevented_damage := int(summary.get(&"prevented_damage", 0))
	var effective_damage := int(summary.get(&"effective_damage", 0))
	var cover_source_edge_key := String(summary.get(&"cover_source_edge", summary.get(&"source_edge_key", "")))
	var sight_blocking_edge_key := String(summary.get(&"sight_blocking_edge", summary.get(&"sight_blocking_edge_key", "")))
	var projectile_blocking_edge_key := String(summary.get(&"projectile_blocking_edge", summary.get(&"projectile_blocking_edge_key", "")))
	var los_reason := String(summary.get(&"los_block_reason", ""))
	var projectile_reason := String(summary.get(&"projectile_block_reason", ""))
	var block_reason := String(summary.get(&"block_reason", ""))
	var query_reason := String(summary.get(&"reason", ""))
	return "cover=%s profile=%s reduction=%d%% base=%d prevented=%d effective=%d cover_edge=%s sight_edge=%s projectile_edge=%s los=%s projectile=%s block=%s reason=%s" % [
		level_name,
		profile_id,
		reduction_percent,
		base_damage,
		prevented_damage,
		effective_damage,
		"-" if cover_source_edge_key.is_empty() else cover_source_edge_key,
		"-" if sight_blocking_edge_key.is_empty() else sight_blocking_edge_key,
		"-" if projectile_blocking_edge_key.is_empty() else projectile_blocking_edge_key,
		"-" if los_reason.is_empty() else los_reason,
		"-" if projectile_reason.is_empty() else projectile_reason,
		"-" if block_reason.is_empty() else block_reason,
		"-" if query_reason.is_empty() else query_reason,
	]
