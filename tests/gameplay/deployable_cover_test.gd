extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var scene = load("res://scenes/main/gym_demo.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.combat_presentation.mode = 2
	var actor: PrototypeUnit = scene._unit_by_name(&"破门手·布拉沃")
	var shooter: PrototypeUnit = scene._unit_by_name(&"突击手·阿尔法")
	scene._select_unit(actor)
	check(scene.squad_inventory.get_item_count(&"portable_cover_device") == 2,"Gym provisions exactly two shared items")
	check(not scene.deploy_cover(Vector3i(8,0,10)).success,"Cannot deploy remotely or onto void")
	check(not scene.deploy_cover(shooter.grid_cell).success,"Cannot deploy onto a unit")
	check(actor.current_action_points == 2 and scene.squad_inventory.get_item_count(&"portable_cover_device") == 2,"Rejected placement consumes nothing")
	var cell := Vector3i(7,0,3)
	actor.set_action_points(0)
	check(not scene.deploy_cover(cell).success and scene.squad_inventory.get_item_count(&"portable_cover_device") == 2,"No AP rejects before consuming inventory")
	actor.reset_action_points()
	check(scene.deploy_cover(cell).success,"Deploy adjacent cover")
	var id: StringName = scene.deployed_cover_ids.keys()[0]
	var state: EnvironmentObjectRuntimeState = scene.environment_objects_by_placement_id[id]
	check(actor.current_action_points == 1 and scene.squad_inventory.get_item_count(&"portable_cover_device") == 1,"Deployment consumes AP and real item")
	check(not scene.grid.is_walkable(cell),"Deployed cover blocks movement")
	check(scene.grid.edge_index.has_edge(cell,Vector3i(7,0,2)),"Cover edge follows facing")
	check(not scene.grid.edge_index.has_edge(cell,Vector3i(6,0,3)),"Flank has no cover edge")
	var edge: MapEdgeData = scene.grid.edge_index.get_edge(cell,actor.grid_cell)
	var profile: TacticalCoverProfile = edge.resolve_profile(0 if edge.cell_a == actor.grid_cell else 1,scene.cover_combat_settings)
	check(profile.cover_level == 1,"Adjacent soldier receives half cover")
	var incoming = scene.query_attack_cover(Vector3i(7,0,5),actor.grid_cell)
	check(incoming.profile.cover_level == 1,"Actual attack query receives deployed protection")
	var shot: ActionResult = await scene.attack_environment_object(shooter,state)
	check(shot.success and state.current_hp == 4,"Rifle shot damages barricade without self-protection")
	shot = await scene.attack_environment_object(shooter,state)
	check(shot.success and state.destroyed and scene.grid.is_walkable(cell),"Second rifle shot destroys and opens path")
	check(not scene.grid.edge_index.has_edge(cell,Vector3i(7,0,2)),"Destruction removes cover edge")
	scene._perform_undo(false)
	check(state.current_hp == 4 and state.active and not scene.grid.is_walkable(cell),"Undo destruction restores HP and blocking")
	check(scene.environment_views_by_placement_id[id].visible,"Undo destruction restores visual")
	scene._perform_undo(true)
	check(scene.deployed_cover_ids.is_empty() and scene.grid.is_walkable(cell),"Undo deployment removes object")
	check(scene.squad_inventory.get_item_count(&"portable_cover_device") == 2 and actor.current_action_points == 2,"Undo returns device and AP")
	scene._select_unit(actor)
	scene.deploy_facing = Vector2i.RIGHT
	check(scene.deploy_cover(cell).success,"Can deploy again after undo without registry conflict")
	check(scene.grid.edge_index.has_edge(cell,Vector3i(6,0,3)) and not scene.grid.edge_index.has_edge(cell,Vector3i(7,0,2)),"Rotated deployment rotates protection")
	scene._perform_undo(false)
	check(scene.squad_inventory.get_item_count(&"portable_cover_device") == 2 and scene.deployed_cover_ids.is_empty(),"Undo deployment alone returns item and removes runtime state")
	scene._select_unit(actor)
	check(scene.deploy_cover(cell).success,"Redeploy after step undo")
	check(scene.deploy_cover(Vector3i(6,0,2)).success,"Second device deploys")
	actor.reset_action_points()
	check(scene.squad_inventory.get_item_count(&"portable_cover_device") == 0,"Turn AP reset does not refill items")
	check(not scene.deploy_cover(Vector3i(8,0,2)).success and actor.current_action_points == 2,"Empty inventory rejects without AP")
	# Existing grenade effect must damage authored destructible cover too.
	var fixed_cover: EnvironmentObjectRuntimeState = scene.environment_objects_by_placement_id[&"breakable_cover_10"]
	for unit: PrototypeUnit in [shooter,scene._unit_by_name(&"支援手·查理")]:
		unit.reset_action_points()
		var request = preload("res://scripts/core/action/action_request.gd").new(&"skill",unit.unit_id,&"",1,{&"slot_index":0,&"target_cell":fixed_cover.cell})
		check(scene._execute_runtime_action(request,unit).success,"Grenade resolves against map cover")
	check(fixed_cover.destroyed and scene.grid.is_walkable(fixed_cover.cell),"Grenades destroy authored cover and open path")
	print("DEPLOYABLE COVER: ","PASS" if failures.is_empty() else failures)
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
