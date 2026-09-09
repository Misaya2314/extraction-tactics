extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var rifle := load("res://resources/weapons/assault_rifle.tres") as WeaponDefinition
	var shotgun := load("res://resources/weapons/shotgun.tres") as WeaponDefinition
	assert(shotgun.damage_at_distance(2) > rifle.damage_at_distance(2))
	assert(shotgun.damage_at_distance(5) < rifle.damage_at_distance(5))
	assert(shotgun.damage_at_distance(6) == 0)
	assert(rifle.damage_at_distance(1) == rifle.damage_at_distance(8))
	var controller := PrototypeController.new()
	controller.grid = GridModel.new(Vector2i(10, 10))
	controller.cover_combat_settings = CoverCombatSettings.make_default()
	var actor := preload("res://scenes/main/prototype_unit.tscn").instantiate() as PrototypeUnit
	root.add_child(actor)
	actor.configure(Vector3i.ZERO, &"player", Color.CYAN, null, shotgun)
	assert(controller.weapon_damage_at(actor, Vector3i.ZERO, Vector3i(0, 0, 5)) == 2)
	var director := CombatPresentationDirector.new()
	root.add_child(director)
	director.mode = CombatPresentationDirector.Mode.OFF
	for weapon in [rifle, shotgun]:
		actor.configure(Vector3i.ZERO, &"player", Color.CYAN, null, weapon)
		var ap := actor.current_action_points
		var count := actor.attack_feedback_play_count
		director.begin({0: actor}, null)
		await director.play(actor, Vector3(0, 0, 4))
		assert(actor.attack_feedback_play_count - count == weapon.attack_feedback_profile.burst_count)
		assert(actor.current_action_points == ap, "burst presentation must never charge AP")
		assert(not actor.is_attack_feedback_playing)
	controller.free()
	director.free()
	actor.free()
	await process_frame
	print("WEAPON_ROLES_TEST: PASS")
	quit()
