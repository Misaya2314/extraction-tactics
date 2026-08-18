extends SceneTree

const WeaponDefinitionScript = preload("res://scripts/core/combat/weapon_definition.gd")
const ASSAULT_RIFLE: WeaponDefinition = preload("res://resources/weapons/assault_rifle.tres")
const SHOTGUN: WeaponDefinition = preload("res://resources/weapons/shotgun.tres")
const CARBINE: WeaponDefinition = preload("res://resources/weapons/carbine.tres")

var _failures: Array[String] = []


func _init() -> void:
	_test_resources()
	_test_world_models()
	_test_validation()
	_finish()


func _test_resources() -> void:
	for weapon in [ASSAULT_RIFLE, SHOTGUN, CARBINE]:
		_expect(weapon != null and weapon.is_valid(), "weapon: authored resource should be valid")
	_expect(ASSAULT_RIFLE.damage != SHOTGUN.damage, "weapon: rifle and shotgun damage should differ")
	_expect(ASSAULT_RIFLE.range != SHOTGUN.range, "weapon: rifle and shotgun range should differ")
	_expect(SHOTGUN.damage == 5 and SHOTGUN.range == 3 and SHOTGUN.ap_cost == 1, "weapon: shotgun should use authored damage 5, range 3, and one AP")
	_expect(CARBINE.range > ASSAULT_RIFLE.range, "weapon: carbine should have the longest range")
	_expect(ASSAULT_RIFLE.attack_feedback_profile != null, "weapon: assault rifle should have feedback profile")
	_expect(CARBINE.attack_feedback_profile != null, "weapon: carbine should have feedback profile")
	_expect(SHOTGUN.attack_feedback_profile != null, "weapon: shotgun should have feedback profile")
	_expect(ASSAULT_RIFLE.attack_feedback_profile.profile_id == &"rifle", "weapon: assault rifle should use rifle feedback")
	_expect(CARBINE.attack_feedback_profile.profile_id == &"rifle", "weapon: carbine should share rifle feedback")
	_expect(SHOTGUN.attack_feedback_profile.profile_id == &"shotgun", "weapon: shotgun should use shotgun feedback")
	_expect(SHOTGUN.attack_feedback_profile.recoil_distance > ASSAULT_RIFLE.attack_feedback_profile.recoil_distance, "weapon: shotgun recoil should be stronger")
	_expect(SHOTGUN.attack_feedback_profile.total_duration() > ASSAULT_RIFLE.attack_feedback_profile.total_duration(), "weapon: shotgun feedback should last longer")
	_expect(ASSAULT_RIFLE.get_summary().contains("突击步枪"), "weapon: summary should expose display name")


func _test_world_models() -> void:
	var expected_paths := {
		&"assault_rifle": "res://kenney_blaster-kit_2.1/Models/GLB format/blaster-e.glb",
		&"carbine": "res://kenney_blaster-kit_2.1/Models/GLB format/blaster-n.glb",
		&"shotgun": "res://kenney_blaster-kit_2.1/Models/GLB format/blaster-l.glb",
	}
	for weapon in [ASSAULT_RIFLE, CARBINE, SHOTGUN]:
		_expect(weapon.world_model_scene != null, "weapon: %s should have a world model" % weapon.weapon_id)
		if weapon.world_model_scene != null:
			_expect(
				weapon.world_model_scene.resource_path == expected_paths[weapon.weapon_id],
				"weapon: %s should use its authored Kenney model" % weapon.weapon_id
			)
	_expect(ASSAULT_RIFLE.world_model_scene != CARBINE.world_model_scene, "weapon: rifle and carbine models should differ")
	_expect(CARBINE.world_model_scene != SHOTGUN.world_model_scene, "weapon: carbine and shotgun models should differ")
	_expect(is_equal_approx(ASSAULT_RIFLE.world_model_scale.x, 0.55), "weapon: assault rifle model scale should be authored")
	_expect(is_equal_approx(CARBINE.world_model_position.z, 0.36), "weapon: carbine model position should be authored")
	_expect(is_equal_approx(SHOTGUN.world_model_scale.x, 1.35), "weapon: shotgun model scale should be authored")
	_expect(is_equal_approx(ASSAULT_RIFLE.muzzle_position.z, 0.78), "weapon: muzzle position should be data driven")


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
