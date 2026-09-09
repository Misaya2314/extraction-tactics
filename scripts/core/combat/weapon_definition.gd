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
@export_range(0, 99, 1) var full_damage_range: int = 0
@export_range(1, 999, 1) var minimum_damage: int = 1
@export var attack_feedback_profile: WeaponAttackFeedbackProfile
@export var world_model_scene: PackedScene
@export var world_model_position: Vector3 = Vector3.ZERO
@export var world_model_rotation_degrees: Vector3 = Vector3.ZERO
@export var world_model_scale: Vector3 = Vector3.ONE
@export var muzzle_position: Vector3 = Vector3(0.0, 0.0, 0.78)


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
	var summary := "%s | 伤害 %d | 射程 %d | AP %d" % [display_name, damage, range, ap_cost]
	if full_damage_range > 0 and full_damage_range < range:
		summary += " | %d 格内满伤，最远 %d 伤害" % [full_damage_range, minimum_damage]
	return summary


func damage_at_distance(distance: int) -> int:
	if distance < 0 or distance > range:
		return 0
	if full_damage_range <= 0 or full_damage_range >= range or distance <= full_damage_range:
		return damage
	var fraction := float(distance - full_damage_range) / float(range - full_damage_range)
	return roundi(lerpf(float(damage), float(clampi(minimum_damage, 1, damage)), fraction))
