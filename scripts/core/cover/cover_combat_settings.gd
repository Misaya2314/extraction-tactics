@tool
class_name CoverCombatSettings
extends Resource

## Shared legacy mapping and deterministic damage policy. The settings do not
## contain map edges or runtime state.

@export var legacy_none_profile: TacticalCoverProfile
@export var legacy_half_profile: TacticalCoverProfile
@export var legacy_full_profile: TacticalCoverProfile
@export_range(0, 999, 1) var minimum_damage_after_cover: int = 0
@export var allow_zero_damage: bool = true


func get_profile_for_level(level: int) -> TacticalCoverProfile:
	match level:
		1:
			return legacy_half_profile if legacy_half_profile != null else TacticalCoverProfile.default_for_level(level)
		2:
			return legacy_full_profile if legacy_full_profile != null else TacticalCoverProfile.default_for_level(level)
		_:
			return legacy_none_profile if legacy_none_profile != null else TacticalCoverProfile.default_for_level(0)


func resolve_profile(profile: TacticalCoverProfile, legacy_level: int) -> TacticalCoverProfile:
	if profile != null and profile.is_valid():
		return profile
	if legacy_level >= 0 and legacy_level <= 2:
		var fallback := get_profile_for_level(legacy_level)
		return fallback if fallback != null and fallback.is_valid() else null
	return null


func is_valid() -> bool:
	return minimum_damage_after_cover >= 0 \
		and _profile_is_valid_or_null(legacy_none_profile) \
		and _profile_is_valid_or_null(legacy_half_profile) \
		and _profile_is_valid_or_null(legacy_full_profile)


static func make_default() -> CoverCombatSettings:
	var result := CoverCombatSettings.new()
	result.legacy_none_profile = TacticalCoverProfile.default_for_level(0)
	result.legacy_half_profile = TacticalCoverProfile.default_for_level(1)
	result.legacy_full_profile = TacticalCoverProfile.default_for_level(2)
	return result


static func load_default() -> CoverCombatSettings:
	var resource := load("res://resources/combat/cover_combat_settings.tres") as CoverCombatSettings
	return resource if resource != null else make_default()


static func _profile_is_valid_or_null(profile: TacticalCoverProfile) -> bool:
	return profile == null or profile.is_valid()
