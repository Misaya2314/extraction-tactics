extends SceneTree

const WeaponDefinitionScript = preload("res://scripts/core/combat/weapon_definition.gd")
const ASSAULT_RIFLE: WeaponDefinition = preload("res://resources/weapons/assault_rifle.tres")
const SHOTGUN: WeaponDefinition = preload("res://resources/weapons/shotgun.tres")
const CARBINE: WeaponDefinition = preload("res://resources/weapons/carbine.tres")

var _failures: Array[String] = []


func _init() -> void:
	_test_resources()
	_test_validation()
	_finish()


func _test_resources() -> void:
	for weapon in [ASSAULT_RIFLE, SHOTGUN, CARBINE]:
		_expect(weapon != null and weapon.is_valid(), "weapon: authored resource should be valid")
	_expect(ASSAULT_RIFLE.damage != SHOTGUN.damage, "weapon: rifle and shotgun damage should differ")
	_expect(ASSAULT_RIFLE.range != SHOTGUN.range, "weapon: rifle and shotgun range should differ")
	_expect(SHOTGUN.damage == 5 and SHOTGUN.range == 3 and SHOTGUN.ap_cost == 1, "weapon: shotgun should use authored damage 5, range 3, and one AP")
	_expect(CARBINE.range > ASSAULT_RIFLE.range, "weapon: carbine should have the longest range")
	_expect(ASSAULT_RIFLE.get_summary().contains("突击步枪"), "weapon: summary should expose display name")


func _test_validation() -> void:
	var missing_id := WeaponDefinitionScript.new()
	missing_id.display_name = "Missing ID"
	_expect(not missing_id.is_valid(), "weapon: missing ID should be invalid")
	var bad_damage := WeaponDefinitionScript.new()
	bad_damage.weapon_id = &"bad_damage"
	bad_damage.display_name = "Bad Damage"
	bad_damage.damage = 0
	_expect(not bad_damage.validate(), "weapon: zero damage should be invalid")
	var bad_range := WeaponDefinitionScript.new()
	bad_range.weapon_id = &"bad_range"
	bad_range.display_name = "Bad Range"
	bad_range.range = 0
	_expect(not bad_range.is_valid(), "weapon: zero range should be invalid")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("WEAPON_DEFINITION_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WEAPON_DEFINITION_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
