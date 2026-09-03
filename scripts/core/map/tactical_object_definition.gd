@tool
class_name TacticalObjectDefinition
extends TacticalPlaceableDefinition

## Stable object palette entry. Runtime object state remains in the session.

@export var object_kind: StringName = &"generic"
@export var category: StringName = &"对象"
@export_multiline var description: String = ""
@export var scene: PackedScene
@export var footprint: Vector3i = Vector3i.ONE
@export var blocks_movement: bool = false
@export var blocks_los: bool = false
@export var loot_table: LootTableDefinition
@export var loot_seed: int = -1
@export var targetable: bool = false
@export var damageable: bool = false
@export_range(0, 1000000, 1) var max_hp: int = 0
## Effects are Resources so existing object Definitions remain loadable even
## when no environment effect is configured.  Runtime state never lives here.
@export var on_destroy_effects: Array[Resource] = []


func _init() -> void:
	placement_kind = PlacementKind.OBJECT


func is_valid() -> bool:
	if not super.is_valid() \
		or placement_kind != PlacementKind.OBJECT \
		or footprint.x <= 0 or footprint.y <= 0 or footprint.z <= 0:
		return false
	if max_hp < 0 or (damageable and max_hp <= 0):
		return false
	for effect in on_destroy_effects:
		if effect == null or not effect.has_method("is_valid") or not bool(effect.call("is_valid")):
			return false
	return true


func get_configuration_errors() -> Array[String]:
	var errors: Array[String] = []
	if not super.is_valid():
		errors.append("TacticalObjectDefinition base identity is invalid.")
	if placement_kind != PlacementKind.OBJECT:
		errors.append("TacticalObjectDefinition placement_kind must be OBJECT.")
	if footprint.x <= 0 or footprint.y <= 0 or footprint.z <= 0:
		errors.append("TacticalObjectDefinition footprint must be positive.")
	if max_hp < 0 or (damageable and max_hp <= 0):
		errors.append("Damageable objects require a positive max_hp.")
	for effect in on_destroy_effects:
		if effect == null or not effect.has_method("is_valid"):
			errors.append("on_destroy_effects contains an invalid effect reference.")
		elif not bool(effect.call("is_valid")):
			errors.append("on_destroy_effects contains an invalid effect Definition.")
	return errors
