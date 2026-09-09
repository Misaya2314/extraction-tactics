extends SceneTree

## Level integration check: registry, routes, Art ownership and mission exit.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var author: TacticalMapAuthor = load("res://scenes/maps/gym.tscn").instantiate()
	root.add_child(author)
	var bake := TacticalMapBaker.build(author)
	expect(bake[&"errors"].is_empty(), "Gym must bake without errors")
	var definition: TacticalMapDefinition = load("res://resources/maps/gym.tres")
	expect(definition.cells.size() == (bake[&"definition"] as TacticalMapDefinition).cells.size(), "Baked cell count must match author scene")
	expect(author.get_node("ArtDecorations").get_child_count() >= 5, "Art groups must be present in saved scene")
	for node in author.get_node("ArtDecorations").find_children("*", "CollisionObject3D", true, false):
		expect(false, "Art cannot add unbaked collisions: %s" % node.name)
	author.free()
	var scene = load("res://scenes/main/gym_demo.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	expect(scene.units_by_id.size() == 9, "All three players and six enemies must instantiate through registry")
	expect(scene.encounter_members.size() == 3, "Three encounter groups must load")
	var grid: GridModel = scene.grid
	for target in [Vector3i(8,0,16), Vector3i(13,0,17), Vector3i(13,0,8), Vector3i(13,0,14)]:
		expect(not grid.find_path(Vector3i(5,0,2), target).is_empty(), "Required route must be reachable: %s" % target)
	# Place a player at interaction points to test the real action/settlement path;
	# this deliberately does not simulate combat or measure human play duration.
	var player = scene._unit_by_name(&"突击手·阿尔法")
	if not is_instance_valid(player):
		expect(false, "Player must be available")
	else:
		scene._select_unit(player)
		grid.vacate(player.grid_cell, player.unit_id)
		player.grid_cell = Vector3i(8,0,16)
		grid.occupy(player.grid_cell, player.unit_id)
		expect(scene.interact_with_objective(&"gym_terminal").success, "Terminal must accept an adjacent player")
		expect(scene.mission_tracker.are_all_main_steps_completed(), "Terminal must complete this map's mission")
		grid.vacate(player.grid_cell, player.unit_id)
		player.grid_cell = Vector3i(13,0,17)
		grid.occupy(player.grid_cell, player.unit_id)
		expect(scene.begin_extraction_prompt(&"gym_exit").success, "Exit must open settlement confirmation")
		expect(scene.confirm_extraction().success, "Exit must complete settlement")
		expect(scene.session_manager.is_success(), "Session must finish successfully")
	print("GYM LEVEL: ", "PASS" if failures.is_empty() else failures)
	scene.free()
	quit(0 if failures.is_empty() else 1)
