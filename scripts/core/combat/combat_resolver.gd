class_name CombatResolver
extends RefCounted

const ActionResultScript = preload("res://scripts/core/action/action_result.gd")


## Resolves a validated必中 attack without depending on scene objects or units.
## Validation failures are returned as an equivalent failure value and are not
## mutated, so callers can safely retain the original validation result.
static func resolve_attack(validation: ActionResult, target_hp: int, damage: int) -> ActionResult:
	if validation == null:
		return ActionResultScript.rejected(&"invalid_action")
	if not validation.success:
		return _copy_result(validation)

	var result := _copy_result(validation)
	var safe_hp: int = maxi(target_hp, 0)
	var safe_damage: int = maxi(damage, 0)
	result.damage = mini(safe_damage, safe_hp)
	result.killed = safe_hp > 0 and result.damage >= safe_hp
	return result


## Applies the actual damage reported by a result and clamps HP at zero.
static func remaining_hp(target_hp: int, result: ActionResult) -> int:
	if result == null or not result.success:
		return maxi(target_hp, 0)
	return maxi(target_hp - maxi(result.damage, 0), 0)


static func _copy_result(source: ActionResult) -> ActionResult:
	var result := ActionResultScript.new()
	result.success = source.success
	result.reason = source.reason
	result.action_type = source.action_type
	result.actor_id = source.actor_id
	result.target_id = source.target_id
	result.ap_cost = source.ap_cost
	result.damage = source.damage
	result.killed = source.killed
	return result
