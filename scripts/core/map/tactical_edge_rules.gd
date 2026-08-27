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
## New data-driven cover references. Null remains valid for legacy edges and
## is resolved through CoverCombatSettings using cover_a/cover_b.
@export var cover_profile_a: TacticalCoverProfile
@export var cover_profile_b: TacticalCoverProfile
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
	cover_profile_a = other.cover_profile_a
	cover_profile_b = other.cover_profile_b
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


func resolve_profile(side: int, settings = null) -> TacticalCoverProfile:
	var legacy_level := cover_a if side == 0 else cover_b
	var authored_profile := cover_profile_a if side == 0 else cover_profile_b
	if authored_profile != null and authored_profile.is_valid():
		return authored_profile
	if settings != null and settings.has_method("resolve_profile"):
		return settings.resolve_profile(authored_profile, legacy_level)
	return TacticalCoverProfile.default_for_level(int(legacy_level))


func semantic_key() -> String:
	return "%d|%d|%s|%s|%s|%.6f|%.6f|%.6f|%s|%s" % [
		int(cover_a),
		int(cover_b),
		_profile_key(cover_profile_a),
		_profile_key(cover_profile_b),
		blocks_movement,
		sight_block,
		projectile_block,
		height,
		destructible,
		runtime_state_id,
	]


func is_valid() -> bool:
	return cover_a >= CoverLevel.NONE and cover_a <= CoverLevel.FULL \
		and cover_b >= CoverLevel.NONE and cover_b <= CoverLevel.FULL \
		and (cover_profile_a == null or cover_profile_a.is_valid()) \
		and (cover_profile_b == null or cover_profile_b.is_valid()) \
		and sight_block >= 0.0 and sight_block <= 1.0 \
		and projectile_block >= 0.0 and projectile_block <= 1.0 \
		and height >= 0.0


static func _profile_key(profile: TacticalCoverProfile) -> String:
	return "" if profile == null else profile.semantic_key()
