extends SceneTree

const Rules = preload("res://scripts/core/skills/knockback_rules.gd")
const Request = preload("res://scripts/core/action/action_request.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func place(scene: Node, unit: PrototypeUnit, cell: Vector3i) -> void:
	scene.grid.vacate(unit.grid_cell, unit.unit_id)
	unit.grid_cell = cell
	scene.grid.occupy(cell, unit.unit_id)
	unit.global_position = scene.grid.cell_to_world(cell)
	unit.visible = true

func cast(scene: Node, actor: PrototypeUnit, cell: Vector3i) -> ActionResult:
	return scene._execute_runtime_action(Request.new(&"skill",actor.unit_id,&"",1,{&"slot_index":0,&"target_cell":cell}),actor)

func run() -> void:
	var grid := GridModel.new(Vector2i(5,5))
	check(Rules.preview(grid,Vector3i(1,0,2),Vector3i(2,0,2),{}).get(&"destination") == Vector3i(3,0,2), "Straight push destination")
	check(not Rules.preview(grid,Vector3i(1,0,1),Vector3i(2,0,2),{}).get(&"valid"), "Diagonal push rejected")
	check(not Rules.preview(grid,Vector3i(3,0,2),Vector3i(4,0,2),{}).get(&"valid"), "Missing cell is not void")
	grid.occupy(Vector3i(3,0,2),&"blocker")
	check(not Rules.preview(grid,Vector3i(1,0,2),Vector3i(2,0,2),{Vector3i(3,0,2):true}).get(&"valid"), "Occupied destination rejected even if tagged void")
	grid.vacate(Vector3i(3,0,2))
	check(Rules.preview(grid,Vector3i(1,0,2),Vector3i(2,0,2),{Vector3i(3,0,2):true}).get(&"lethal"), "Explicit void is lethal")
	var edge := MapEdgeData.new()
	edge.cell_a = Vector3i(2,0,2)
	edge.cell_b = Vector3i(3,0,2)
	edge.blocks_movement = true
	grid.edge_index.configure([edge])
	check(not Rules.preview(grid,Vector3i(1,0,2),Vector3i(2,0,2),{Vector3i(3,0,2):true}).get(&"valid"), "Wall edge prevents pushing through it into void")
	var author: TacticalMapAuthor = load("res://scenes/maps/gym.tscn").instantiate()
	root.add_child(author)
	var editor_session = preload("res://addons/tactical_map_editor/editing/map_edit_session.gd").new()
	check(editor_session.begin_for_author(author,author), "Editor binds gym")
	var has_void := false
	for entry in editor_session.get_placeables():
		if entry.get("definition") != null and entry["definition"].placeable_id == &"tile.floor.void" and entry.get("layer") == 0:
			has_void = true
	check(has_void,"Void available as Floor paint in editor")
	editor_session = null
	author.free()
	var scene = load("res://scenes/main/gym_demo.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var actor: PrototypeUnit = scene._unit_by_name(&"破门手·布拉沃")
	var target: PrototypeUnit = scene._unit_by_name(&"货场守卫")
	check(not scene.grid.is_walkable(Vector3i(8,0,10)), "Void excluded from ordinary movement")
	check(scene.grid.find_path(Vector3i(8,0,12),Vector3i(8,0,10)).is_empty(), "Cannot path into void")
	place(scene, actor, Vector3i(8,0,12))
	place(scene, target, Vector3i(8,0,11))
	scene._select_unit(actor)
	var ap := actor.current_action_points
	var hp := target.current_hp
	var preview: Dictionary = scene.preview_knockback(actor,target.grid_cell)
	check(preview.get(&"lethal",false), "Actual map preview predicts fall")
	check(actor.current_action_points == ap and target.current_hp == hp, "Preview is read only")
	var result := cast(scene,actor,target.grid_cell)
	check(result.success and result.killed and not target.is_alive(), "Fall kills full health target")
	check(not scene.grid.is_occupied(Vector3i(8,0,11)) and not scene.grid.is_occupied(Vector3i(8,0,10)), "Fall releases occupancy")
	check(actor.current_action_points == ap-1 and actor.runtime_state.get_skill(0).current_cooldown > 0, "Skill charges AP and cooldown")
	check(not cast(scene,actor,Vector3i(8,0,11)).success and actor.current_action_points == ap-1,"Cooldown prevents repeat cast")
	# Presentation must run even though the target has already died logically.
	await scene._play_knockback(result)
	check(not target.visible, "Fallen target is hidden after animation")
	scene._perform_undo(false)
	check(target.is_alive() and target.current_hp == hp and target.grid_cell == Vector3i(8,0,11), "Undo restores fallen target")
	check(scene.grid.get_occupant(target.grid_cell) == target.unit_id, "Undo restores occupancy")
	check(actor.current_action_points == ap and actor.runtime_state.get_skill(0).current_cooldown == 0, "Undo restores AP and cooldown")
	# Blocked landing must neither charge AP nor mutate target.
	place(scene,actor,Vector3i(2,0,5))
	place(scene,target,Vector3i(2,0,4))
	# Push toward south perimeter is open; this is the nonlethal control.
	result = cast(scene,actor,target.grid_cell)
	check(result.success and target.grid_cell == Vector3i(2,0,3) and target.current_hp == hp, "Ordinary push moves without damage")
	scene._perform_undo(false)
	place(scene,actor,Vector3i(2,0,3))
	place(scene,target,Vector3i(3,0,3))
	var blocker: PrototypeUnit = scene._unit_by_name(&"突击手·阿尔法")
	place(scene,blocker,Vector3i(4,0,3))
	result = cast(scene,actor,target.grid_cell)
	check(not result.success and actor.current_action_points == ap, "Occupied destination rejects without AP")
	check(actor.runtime_state.get_skill(0).current_cooldown == 0, "Rejected push has no cooldown")
	place(scene,actor,Vector3i(8,0,12))
	place(scene,target,Vector3i(8,0,11))
	target.visible = false
	check(not cast(scene,actor,target.grid_cell).success,"Cannot target undiscovered enemy")
	target.visible = true
	scene._select_unit(actor)
	await scene._cast_skill_at_cell(actor,actor.runtime_state.get_skill(0),0,target.grid_cell)
	check(not target.is_alive() and not target.visible and not scene.input_locked,"Full skill input path finishes fall and unlocks input")
	scene._perform_undo(false)
	check(target.is_alive() and target.visible,"Undo after full presentation revives visible target")
	await create_timer(1.0).timeout
	print("KNOCKBACK VOID: ", "PASS" if failures.is_empty() else failures)
	scene.free()
	quit(0 if failures.is_empty() else 1)
