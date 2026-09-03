extends SceneTree

const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const TacticalEdgeIndexScript = preload("res://scripts/core/map/tactical_edge_index.gd")
const TacticalEdgeKeyScript = preload("res://scripts/core/map/tactical_edge_key.gd")
const TacticalEdgeRulesScript = preload("res://scripts/core/map/tactical_edge_rules.gd")
const MapEdgeDataScript = preload("res://scripts/core/map/map_edge_data.gd")
const TacticalCoverProfileScript = preload("res://scripts/core/cover/tactical_cover_profile.gd")
const CoverCombatSettingsScript = preload("res://scripts/core/cover/cover_combat_settings.gd")
const TacticalStepOutScript = preload("res://scripts/core/cover/tactical_step_out.gd")
const PrototypeControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_hugging_full_cover()
	_test_step_out_line_of_sight()
	_test_blocked_and_occupied_candidate()
	_test_best_flanking_candidate()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("STEP_OUT_MECHANIC_TEST: PASS")
		quit(0)
	else:
		print("STEP_OUT_MECHANIC_TEST: FAIL (%d errors)" % _failures.size())
		for failure in _failures:
			print(" - %s" % failure)
		quit(1)


func _edge(cell_a: Vector3i, cell_b: Vector3i, full_cover: bool = false, blocks_move: bool = false) -> MapEdgeData:
	var result := MapEdgeDataScript.new()
	var key := TacticalEdgeKeyScript.from_cells(cell_a, cell_b)
	result.cell_a = key.cell_a
	result.cell_b = key.cell_b
	if full_cover:
		result.cover_a = TacticalEdgeRulesScript.CoverLevel.FULL
		result.cover_b = TacticalEdgeRulesScript.CoverLevel.FULL
		result.projectile_block = 1.0
		result.sight_block = 1.0
	result.blocks_movement = blocks_move
	return result


func _test_hugging_full_cover() -> void:
	var grid = GridModelScript.new(Vector2i(3, 3))
	var full_wall := _edge(Vector3i(1, 0, 1), Vector3i(1, 0, 0), true, true)
	grid.edge_index.configure([full_wall])

	_expect(TacticalStepOutScript.is_hugging_full_cover(Vector3i(1, 0, 1), grid), "step_out: unit adjacent to full wall should be hugging full cover")
	_expect(not TacticalStepOutScript.is_hugging_full_cover(Vector3i(0, 0, 2), grid), "step_out: unit far from wall should not be hugging cover")

	# Half cover only
	var half_wall := _edge(Vector3i(0, 0, 0), Vector3i(0, 0, 1), false, false)
	half_wall.cover_a = TacticalEdgeRulesScript.CoverLevel.HALF
	half_wall.cover_b = TacticalEdgeRulesScript.CoverLevel.HALF
	grid.edge_index.configure([half_wall])
	_expect(not TacticalStepOutScript.is_hugging_full_cover(Vector3i(0, 0, 0), grid), "step_out: half cover alone should not qualify as hugging full cover")


func _test_step_out_line_of_sight() -> void:
	# Grid layout: 4x4
	# Attacker at (1, 0, 2)
	# Full wall between (1, 0, 2) and (1, 0, 1)
	# Target at (1, 0, 0)
	# Direct shot from (1, 0, 2) to (1, 0, 0) is blocked by the wall
	# Adjacent cell (2, 0, 2) is free and has clear LOS to (1, 0, 0)
	var grid = GridModelScript.new(Vector2i(4, 4))
	var wall := _edge(Vector3i(1, 0, 2), Vector3i(1, 0, 1), true, true)
	grid.edge_index.configure([wall])

	var controller := PrototypeControllerScript.new()
	controller.grid = grid
	controller.cover_combat_settings = CoverCombatSettingsScript.make_default()

	var direct_query := controller.query_attack_cover(Vector3i(1, 0, 2), Vector3i(1, 0, 0), false)
	_expect(not direct_query.can_attack(), "step_out: direct shot should be blocked by wall")

	var step_query := controller.query_attack_cover(Vector3i(1, 0, 2), Vector3i(1, 0, 0), true)
	_expect(step_query.can_attack(), "step_out: step-out query should find valid shot")
	_expect(step_query.is_step_out, "step_out: is_step_out flag should be true")
	_expect(step_query.step_out_cell == Vector3i(0, 0, 2) or step_query.step_out_cell == Vector3i(2, 0, 2), "step_out: should step out to an adjacent unblocked tile")
	_expect(step_query.original_attacker_cell == Vector3i(1, 0, 2), "step_out: original_attacker_cell should be recorded")

	_expect(controller.can_attack_line(Vector3i(1, 0, 2), Vector3i(1, 0, 0), 4), "step_out: can_attack_line should return true via step-out")
	_expect(not controller.can_attack_line(Vector3i(1, 0, 2), Vector3i(1, 0, 0), 1), "step_out: can_attack_line should respect range limit")

	controller.free()


func _test_blocked_and_occupied_candidate() -> void:
	var grid = GridModelScript.new(Vector2i(3, 3))
	# Attacker at (1, 0, 1). Block wall to the north (1, 0, 0)
	var wall_north := _edge(Vector3i(1, 0, 1), Vector3i(1, 0, 0), true, true)
	# Walls blocking east (2, 0, 1) and south (1, 0, 2)
	var wall_east := _edge(Vector3i(1, 0, 1), Vector3i(2, 0, 1), true, true)
	var wall_south := _edge(Vector3i(1, 0, 1), Vector3i(1, 0, 2), true, true)
	grid.edge_index.configure([wall_north, wall_east, wall_south])

	# Only west (0, 0, 1) is open. Let’s occupy it with an ally!
	grid.occupy(Vector3i(0, 0, 1), &"ally_unit")

	var controller := PrototypeControllerScript.new()
	controller.grid = grid
	controller.cover_combat_settings = CoverCombatSettingsScript.make_default()

	var target := Vector3i(1, 0, -1)
	var blocked_query := controller.query_attack_cover(Vector3i(1, 0, 1), target, true)
	_expect(not blocked_query.can_attack(), "step_out: when all open tiles are occupied, step out must fail")

	# Vacate ally
	grid.vacate(Vector3i(0, 0, 1), &"ally_unit")
	# Target now at (0, 0, 0)
	var clear_query := controller.query_attack_cover(Vector3i(1, 0, 1), Vector3i(0, 0, 0), true)
	_expect(clear_query.can_attack() and clear_query.is_step_out, "step_out: after vacating tile, step out should succeed")
	_expect(clear_query.step_out_cell == Vector3i(0, 0, 1), "step_out: step out cell should be the west tile")

	controller.free()


func _test_best_flanking_candidate() -> void:
	var grid = GridModelScript.new(Vector2i(5, 5))
	# Attacker at (2, 0, 2), wall to north (2, 0, 1)
	var wall := _edge(Vector3i(2, 0, 2), Vector3i(2, 0, 1), true, true)
	# Target at (1, 0, 0).
	# Target has a cover edge on its south (1, 0, 0) <-> (1, 0, 1)
	var target_cover := _edge(Vector3i(1, 0, 0), Vector3i(1, 0, 1), false, false)
	target_cover.cover_a = TacticalEdgeRulesScript.CoverLevel.FULL
	target_cover.cover_b = TacticalEdgeRulesScript.CoverLevel.FULL

	grid.edge_index.configure([wall, target_cover])

	var controller := PrototypeControllerScript.new()
	controller.grid = grid
	controller.cover_combat_settings = CoverCombatSettingsScript.make_default()

	var result := controller.query_attack_cover(Vector3i(2, 0, 2), Vector3i(1, 0, 0), true)
	_expect(result.can_attack(), "step_out: should find attack line")
	_expect(result.is_step_out, "step_out: result should be step out")

	controller.free()
