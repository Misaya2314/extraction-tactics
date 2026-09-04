@tool
class_name UnitArchetype
extends Resource

## Data-driven unit profile. A spawn may override the default weapon while
## retaining the rest of this archetype's stats.
@export var archetype_id: StringName = &""
@export var display_name: String = ""
@export_range(1, 999, 1) var max_hp: int = 10
@export_range(1, 9, 1) var max_action_points: int = 2
@export_range(1, 99, 1) var move_range: int = 4
@export_range(0, 99, 1) var inner_vision_range: int = 4
@export_range(0, 99, 1) var vision_range: int = 7
@export var default_weapon: WeaponDefinition
@export var default_skills: Array[SkillDefinition] = []

var outer_vision_range: int:
	get:
		return vision_range
	set(value):
		vision_range = value


func is_valid() -> bool:
	return (
		archetype_id != &""
		and not display_name.strip_edges().is_empty()
		and max_hp > 0
		and max_action_points > 0
		and move_range > 0
		and inner_vision_range >= 0
		and vision_range >= inner_vision_range
		and default_weapon != null
		and default_weapon.is_valid()
	)


func validate() -> bool:
	return is_valid()
