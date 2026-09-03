extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/main/prototype_unit.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/main/prototype_main.tscn")
const ASSAULT_RIFLE: WeaponDefinition = preload("res://resources/weapons/assault_rifle.tres")
const UnitRuntimeStateScript = preload("res://scripts/core/units/unit_runtime_state.gd")
const UnitArchetypeScript = preload("res://scripts/core/units/unit_archetype.gd")
const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_audio_resources_loaded()
	await _test_unit_scene_audio_nodes()
	await _test_shoot_sound()
	await _test_move_sound()
	await _test_hit_sound()
	await _test_death_sound()
	await _test_discover_sound()
	await _test_enemy_attack_feedback_duration()
	await _test_attack_audio_order()
	_test_audio_outside_tree_safe()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("UNIT_AUDIO_FEEDBACK_TEST: PASS")
		quit(0)
	else:
		print("UNIT_AUDIO_FEEDBACK_TEST: FAIL (%d failure(s))" % _failures.size())
		quit(1)


func _test_audio_resources_loaded() -> void:
	var shoot: AudioStream = load("res://assets/audio/sfx/laserShoot.wav")
	var hit: AudioStream = load("res://assets/audio/sfx/hit.wav")
	var die: AudioStream = load("res://assets/audio/sfx/die.wav")
	var move: AudioStream = load("res://assets/audio/sfx/move.wav")
	var discover: AudioStream = load("res://assets/audio/sfx/discover.wav")

	_expect(shoot != null, "resource: laserShoot.wav should load")
	_expect(hit != null, "resource: hit.wav should load")
	_expect(die != null, "resource: die.wav should load")
	_expect(move != null, "resource: move.wav should load")
	_expect(discover != null, "resource: discover.wav should load")

	if shoot != null:
		_expect(shoot.get_length() > 0.0, "resource: laserShoot.wav duration should be positive")
	if hit != null:
		_expect(hit.get_length() > 0.0, "resource: hit.wav duration should be positive")
	if die != null:
		_expect(die.get_length() > 0.0, "resource: die.wav duration should be positive")
	if move != null:
		_expect(move.get_length() > 0.0, "resource: move.wav duration should be positive")
	if discover != null:
		_expect(discover.get_length() > 0.0, "resource: discover.wav duration should be positive")


func _test_unit_scene_audio_nodes() -> void:
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	_expect(unit != null, "scene: prototype_unit.tscn should instantiate")
	if unit == null:
		return

	get_root().add_child(unit)
	await process_frame

	_expect(unit.shoot_sfx != null, "unit: shoot_sfx export should be assigned")
	_expect(unit.hit_sfx != null, "unit: hit_sfx export should be assigned")
	_expect(unit.death_sfx != null, "unit: death_sfx export should be assigned")
	_expect(unit.move_sfx != null, "unit: move_sfx export should be assigned")

	var audio_shoot := unit.get_node_or_null("AudioShoot") as AudioStreamPlayer3D
	var audio_hit := unit.get_node_or_null("AudioHit") as AudioStreamPlayer3D
	var audio_death := unit.get_node_or_null("AudioDeath") as AudioStreamPlayer3D
	var audio_move := unit.get_node_or_null("AudioMove") as AudioStreamPlayer3D

	_expect(audio_shoot != null, "scene: AudioShoot node should exist")
	_expect(audio_hit != null, "scene: AudioHit node should exist")
	_expect(audio_death != null, "scene: AudioDeath node should exist")
	_expect(audio_move != null, "scene: AudioMove node should exist")

	if audio_shoot != null:
		_expect(audio_shoot.stream != null, "scene: AudioShoot stream should be assigned")
		_expect(audio_shoot.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED, "scene: AudioShoot attenuation should be DISABLED")
	if audio_hit != null:
		_expect(audio_hit.stream != null, "scene: AudioHit stream should be assigned")
		_expect(audio_hit.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED, "scene: AudioHit attenuation should be DISABLED")
	if audio_death != null:
		_expect(audio_death.stream != null, "scene: AudioDeath stream should be assigned")
		_expect(audio_death.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED, "scene: AudioDeath attenuation should be DISABLED")
		_expect(audio_death.process_mode == Node.PROCESS_MODE_ALWAYS, "scene: AudioDeath process_mode should be PROCESS_MODE_ALWAYS")
	if audio_move != null:
		_expect(audio_move.stream != null, "scene: AudioMove stream should be assigned")
		_expect(audio_move.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED, "scene: AudioMove attenuation should be DISABLED")

	unit.queue_free()
	await process_frame


func _create_test_unit(hp: int = 10) -> PrototypeUnit:
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	var archetype := UnitArchetypeScript.new()
	archetype.archetype_id = &"audio_test_archetype"
	archetype.display_name = "Audio Tester"
	archetype.max_hp = hp
	archetype.max_action_points = 2
	archetype.move_range = 4
	archetype.inner_vision_range = 4
	archetype.vision_range = 7
	archetype.default_weapon = ASSAULT_RIFLE

	var weapon_instance := WeaponInstanceScript.new(&"audio:weapon:1", ASSAULT_RIFLE)
	var state := UnitRuntimeStateScript.new(
		&"audio:unit:1",
		archetype,
		&"player",
		Vector3i.ZERO,
		weapon_instance
	)
	unit.bind_runtime_state(state, Color.WHITE)
	get_root().add_child(unit)
	return unit


func _test_shoot_sound() -> void:
	var unit := _create_test_unit(10)
	await process_frame

	unit.play_attack_feedback()
	await process_frame

	_expect(unit.audio_shoot != null and unit.audio_shoot.playing, "shoot: AudioShoot should play on attack feedback")
	unit.queue_free()
	await process_frame


func _test_move_sound() -> void:
	var unit := _create_test_unit(10)
	await process_frame

	var points: Array[Vector3] = [Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)]
	unit.move_along_world_path.call_deferred(points, Vector3i(2, 0, 0))
	await process_frame

	_expect(unit.audio_move != null and unit.audio_move.playing, "move: AudioMove should play when moving")
	unit.queue_free()
	await process_frame


func _test_hit_sound() -> void:
	var unit := _create_test_unit(10)
	await process_frame

	unit.take_damage(3)
	await process_frame

	_expect(unit.audio_hit != null and unit.audio_hit.playing, "hit: AudioHit should play on non-lethal damage")
	_expect(unit.audio_death == null or not unit.audio_death.playing, "hit: AudioDeath must not play on non-lethal damage")
	unit.queue_free()
	await process_frame


func _test_death_sound() -> void:
	var unit := _create_test_unit(10)
	await process_frame

	unit.take_damage(10)
	await process_frame

	_expect(unit.audio_death != null and unit.audio_death.playing, "death: AudioDeath should play on lethal damage")
	unit.queue_free()
	await process_frame


func _test_discover_sound() -> void:
	var controller := MAIN_SCENE.instantiate() as PrototypeController
	root.add_child(controller)
	await process_frame

	_expect(controller.discover_sfx != null, "discover: discover_sfx should be assigned on controller")
	_expect(controller.audio_discover != null, "discover: AudioDiscover node should exist in PrototypeMain scene")

	controller.play_discover_sound()
	await process_frame

	_expect(controller.audio_discover != null and controller.audio_discover.playing, "discover: AudioDiscover should be playing after play_discover_sound")

	controller.queue_free()
	await process_frame


func _test_enemy_attack_feedback_duration() -> void:
	var player_unit := _create_test_unit(10)
	await process_frame
	player_unit.play_attack_feedback()
	_expect(is_equal_approx(player_unit.last_attack_feedback_duration, ASSAULT_RIFLE.attack_feedback_profile.total_duration()), "timing: player feedback duration should not be scaled")
	player_unit.queue_free()
	await process_frame

	var enemy_unit := UNIT_SCENE.instantiate() as PrototypeUnit
	var archetype := UnitArchetypeScript.new()
	archetype.archetype_id = &"enemy_audio_test"
	archetype.display_name = "Enemy Audio Tester"
	archetype.max_hp = 10
	archetype.max_action_points = 2
	archetype.move_range = 4
	archetype.inner_vision_range = 4
	archetype.vision_range = 7
	archetype.default_weapon = ASSAULT_RIFLE
	var weapon_inst := WeaponInstanceScript.new(&"audio:enemy_weapon:1", ASSAULT_RIFLE)
	var state := UnitRuntimeStateScript.new(
		&"audio:enemy_unit:1",
		archetype,
		&"enemy",
		Vector3i.ZERO,
		weapon_inst
	)
	enemy_unit.bind_runtime_state(state, Color.WHITE)
	get_root().add_child(enemy_unit)
	await process_frame

	enemy_unit.play_attack_feedback()
	var expected_enemy_duration := ASSAULT_RIFLE.attack_feedback_profile.total_duration() * enemy_unit.enemy_attack_feedback_multiplier
	_expect(is_equal_approx(enemy_unit.last_attack_feedback_duration, expected_enemy_duration), "timing: enemy feedback duration should be scaled by multiplier")
	enemy_unit.queue_free()
	await process_frame


func _test_attack_audio_order() -> void:
	var attacker := _create_test_unit(10)
	var target := _create_test_unit(10)
	await process_frame

	# Phase 1: Damage resolved at data layer with play_audio=false (mimicking _handle_attack_action)
	target.take_damage(3, false)
	await process_frame
	_expect(not target.audio_hit.playing, "order: hit sound must NOT play during data resolution before shot")

	# Phase 2: Attacker fires weapon (trigger pull)
	attacker.play_attack_feedback()
	await process_frame
	_expect(attacker.audio_shoot.playing, "order: shoot sound MUST play first when attack feedback begins")
	_expect(not target.audio_hit.playing, "order: hit sound must still NOT be playing immediately as gun fires")

	# Phase 3: Projectile impact (simulating _schedule_attack_impact)
	target.play_hit_sound()
	await process_frame
	_expect(target.audio_hit.playing, "order: hit sound plays on projectile impact after shoot sound")

	attacker.queue_free()
	target.queue_free()
	await process_frame


func _test_audio_outside_tree_safe() -> void:
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	# Must not throw when called outside scene tree
	unit.play_shoot_sound()
	unit.play_hit_sound()
	unit.play_death_sound()
	unit.play_move_sound()
	unit.free()
