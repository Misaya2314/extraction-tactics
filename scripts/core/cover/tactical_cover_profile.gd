@tool
class_name TacticalCoverProfile
extends Resource

## Reusable cover content. Spatial side/orientation and physical edge rules
## remain owned by TacticalEdgeRules; this resource only describes the cover
## type and its deterministic damage reduction.

@export var cover_id: StringName = &"cover.none"
@export var display_name: String = "None"
## Kept as an int to avoid a script-class cycle with TacticalEdgeRules. The
## public numeric contract is NONE=0, HALF=1, FULL=2.
@export_enum("NONE", "HALF", "FULL") var cover_level: int = 0
@export_range(0.0, 1.0, 0.01) var damage_reduction_ratio: float = 0.0
@export var debug_color: Color = Color(0.65, 0.65, 0.65, 1.0)
@export var tags: PackedStringArray = PackedStringArray()


func is_valid() -> bool:
	return TacticalPlaceableDefinition.is_valid_id(cover_id) \
		and cover_level >= 0 \
		and cover_level <= 2 \
		and damage_reduction_ratio >= 0.0 \
		and damage_reduction_ratio <= 1.0


func validation_warnings() -> Array[String]:
	var warnings: Array[String] = []
	if cover_level == 0 and not is_zero_approx(damage_reduction_ratio):
		warnings.append("Profile '%s' is NONE but has non-zero damage reduction." % cover_id)
	elif cover_level != 0 and is_zero_approx(damage_reduction_ratio):
		warnings.append("Profile '%s' is %s but has zero damage reduction." % [cover_id, get_level_name()])
	return warnings


func get_level_name() -> StringName:
	return [&"none", &"half", &"full"][clampi(cover_level, 0, 2)]


func semantic_key() -> String:
	var sorted_tags: Array[String] = []
	for tag in tags:
		sorted_tags.append(String(tag))
	sorted_tags.sort()
	return "%s|%s|%d|%.6f|%s|%s" % [
		cover_id,
		display_name,
		int(cover_level),
		damage_reduction_ratio,
		debug_color.to_html(true),
		";".join(sorted_tags),
	]


func duplicate_profile() -> TacticalCoverProfile:
	var result := TacticalCoverProfile.new()
	result.cover_id = cover_id
	result.display_name = display_name
	result.cover_level = cover_level
	result.damage_reduction_ratio = damage_reduction_ratio
	result.debug_color = debug_color
	result.tags = tags.duplicate()
	return result


static func default_for_level(level: int) -> TacticalCoverProfile:
	var result := TacticalCoverProfile.new()
	result.cover_level = clampi(level, 0, 2)
	match result.cover_level:
		1:
			result.cover_id = &"cover.half"
			result.display_name = "Half Cover"
			result.damage_reduction_ratio = 0.5
			result.debug_color = Color(0.95, 0.72, 0.18, 1.0)
		2:
			result.cover_id = &"cover.full"
			result.display_name = "Full Cover"
			result.damage_reduction_ratio = 0.75
			result.debug_color = Color(0.82, 0.28, 0.22, 1.0)
		_:
			result.cover_id = &"cover.none"
			result.display_name = "None"
			result.damage_reduction_ratio = 0.0
			result.debug_color = Color(0.65, 0.65, 0.65, 1.0)
	return result
