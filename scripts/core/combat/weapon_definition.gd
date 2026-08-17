@tool
class_name WeaponDefinition
extends Resource

## Data-only weapon contract used by PrototypeUnit and map spawn data.
## Keeping combat numbers here makes authored units and runtime attacks share
## one source of truth.
@export var weapon_id: StringName = &""
@export var display_name: String = ""
@export_range(1, 999, 1) var damage: int = 1
@export_range(1, 99, 1) var range: int = 1
@export_range(1, 9, 1) var ap_cost: int = 1
@export var attack_feedback_profile: WeaponAttackFeedbackProfile


func is_valid() -> bool:
	return (
		weapon_id != &""
		and not display_name.strip_edges().is_empty()
		and damage > 0
		and range > 0
		and ap_cost > 0
	)


func validate() -> bool:
	return is_valid()


func get_summary() -> String:
	return "%s | 伤害 %d | 射程 %d | AP %d" % [display_name, damage, range, ap_cost]
