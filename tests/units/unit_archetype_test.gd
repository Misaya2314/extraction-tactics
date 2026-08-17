extends SceneTree

const UnitArchetypeScript = preload("res://scripts/core/units/unit_archetype.gd")
const PLAYER_ALPHA: UnitArchetype = preload("res://resources/units/player_alpha.tres")
const PLAYER_BRAVO: UnitArchetype = preload("res://resources/units/player_bravo.tres")
const RIFLEMAN: UnitArchetype = preload("res://resources/units/rifleman.tres")
const ASSAULT: UnitArchetype = preload("res://resources/units/assault.tres")

var _failures: Array[String] = []


func _init() -> void:
	_test_resources()
	_test_validation()
	_finish()


func _test_resources() -> void:
	for archetype in [PLAYER_ALPHA, PLAYER_BRAVO, RIFLEMAN, ASSAULT]:
		_expect(archetype != null and archetype.is_valid(), "archetype: authored resource should be valid")
	_expect(PLAYER_ALPHA.default_weapon.weapon_id != PLAYER_BRAVO.default_weapon.weapon_id, "archetype: players should have different defaults")
	_expect(RIFLEMAN.move_range != ASSAULT.move_range, "archetype: enemy movement should differ")
	_expect(RIFLEMAN.vision_range != ASSAULT.vision_range, "archetype: enemy vision should differ")
	_expect(RIFLEMAN.max_hp != ASSAULT.max_hp, "archetype: enemy HP should differ")


func _test_validation() -> void:
	var missing_id := UnitArchetypeScript.new()
	missing_id.display_name = "Missing ID"
	_expect(not missing_id.is_valid(), "archetype: missing ID should be invalid")
	var missing_weapon := UnitArchetypeScript.new()
	missing_weapon.archetype_id = &"missing_weapon"
	missing_weapon.display_name = "Missing Weapon"
	_expect(not missing_weapon.validate(), "archetype: missing default weapon should be invalid")
	var invalid_hp := UnitArchetypeScript.new()
	invalid_hp.archetype_id = &"invalid_hp"
	invalid_hp.display_name = "Invalid HP"
	invalid_hp.max_hp = 0
	invalid_hp.default_weapon = PLAYER_ALPHA.default_weapon
	_expect(not invalid_hp.is_valid(), "archetype: zero HP should be invalid")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("UNIT_ARCHETYPE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("UNIT_ARCHETYPE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
