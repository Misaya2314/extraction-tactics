@tool
class_name ExplosionEffectDefinition
extends EnvironmentEffectDefinition

## Deterministic area-damage reaction.  The first implementation uses the
## same-floor Manhattan distance on the X/Z grid; it has no random component.

const EFFECT_KIND: StringName = &"area_damage"

@export_range(0, 64, 1) var radius: int = 1
@export_range(0, 1000000, 1) var damage: int = 5
@export var affect_players: bool = true
@export var affect_enemies: bool = true
@export var affect_environment_objects: bool = true
@export var allow_chain: bool = false


func is_valid() -> bool:
	return get_validation_errors().is_empty()


func get_validation_errors() -> Array[String]:
	var errors := super.get_validation_errors()
	if radius < 0:
		errors.append("Explosion radius cannot be negative.")
	if damage < 0:
		errors.append("Explosion damage cannot be negative.")
	if not affect_players and not affect_enemies and not affect_environment_objects:
		errors.append("Explosion must affect at least one target category.")
	return errors


func get_effect_kind() -> StringName:
	return EFFECT_KIND
