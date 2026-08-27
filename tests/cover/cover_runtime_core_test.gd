extends SceneTree

const GridModelScript = preload("res://scripts/core/grid/grid_model.gd")
const GridVisibilityScript = preload("res://scripts/core/perception/grid_visibility.gd")
const TacticalEdgeIndexScript = preload("res://scripts/core/map/tactical_edge_index.gd")
const TacticalLineQueryScript = preload("res://scripts/core/cover/tactical_line_query.gd")
const CoverQueryScript = preload("res://scripts/core/cover/cover_query.gd")
const CoverQueryResultScript = preload("res://scripts/core/cover/cover_query_result.gd")
const CoverResolverScript = preload("res://scripts/core/cover/cover_resolver.gd")
const TacticalCoverProfileScript = preload("res://scripts/core/cover/tactical_cover_profile.gd")
const CoverCombatSettingsScript = preload("res://scripts/core/cover/cover_combat_settings.gd")
const ActionResultScript = preload("res://scripts/core/action/action_result.gd")
const CombatResolverScript = preload("res://scripts/core/combat/combat_resolver.gd")
const PrototypeControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_edge_index_and_movement()
	_test_line_supercover_and_reverse_stability()
	_test_cover_sides_and_corner_choice()
	_test_blocking_and_cross_level()
	_test_independent_blocking_sources()
	_test_damage_and_action_metadata()
	_test_debug_summaries()
	_test_controller_uses_shared_query()
	_finish()


func _test_edge_index_and_movement() -> void:
	var grid = GridModelScript.new(Vector2i(4, 1))
	var blocked := _edge(Vector3i(1, 0, 0), Vector3i(2, 0, 0))
	blocked.blocks_movement = true
	_expect(grid.edge_index.configure([blocked]), "edge: valid edge collection should configure")
	_expect(grid.edge_index.has_edge(blocked.cell_a, blocked.cell_b), "edge: lookup should find canonical edge")
	_expect(grid.edge_index.get_edge(Vector3i(2, 0, 0), Vector3i(1, 0, 0)) == blocked, "edge: reverse lookup should hit the same indexed value")
	_expect(grid.is_movement_blocked(Vector3i(1, 0, 0), Vector3i(2, 0, 0)), "edge: movement flag should be symmetric")
	_expect(not grid.get_neighbors(Vector3i(1, 0, 0)).has(Vector3i(2, 0, 0)), "grid: blocked edge should remove ordinary neighbor")
	_expect(grid.find_path(Vector3i(0, 0, 0), Vector3i(2, 0, 0)).is_empty(), "grid: blocked edge should deny the only direct route")
	_expect(grid.add_transition(Vector3i(1, 0, 0), Vector3i(2, 0, 0), 3, true), "grid: explicit traversal should be accepted across blocked edge")
	_expect(grid.get_edge_cost(Vector3i(1, 0, 0), Vector3i(2, 0, 0)) == 3, "grid: traversal cost should override ordinary edge block")
	_expect(not grid.find_path(Vector3i(0, 0, 0), Vector3i(2, 0, 0)).is_empty(), "grid: explicit traversal should remain traversable")
	var definition := TacticalMapDefinition.new()
	definition.footprint_size = Vector2i(3, 1)
	for x in range(3):
		var cell_data := MapCellData.new()
		cell_data.coordinate = Vector3i(x, 0, 0)
		definition.cells.append(cell_data)
	definition.edges.append(blocked)
	var configured := GridModelScript.new()
	_expect(configured.configure_from_definition(definition), "grid: definition edge list should load into the runtime index")
	_expect(configured.is_movement_blocked(blocked.cell_a, blocked.cell_b), "grid: configured definition edge should affect movement")

	var duplicate := _edge(Vector3i(2, 0, 0), Vector3i(1, 0, 0))
	var index := TacticalEdgeIndexScript.new()
	_expect(not index.configure([blocked, duplicate]), "edge: duplicate canonical keys should be rejected")
	_expect(index.size() == 1, "edge: duplicate rejection should keep one deterministic value")


func _test_line_supercover_and_reverse_stability() -> void:
	var grid = GridModelScript.new(Vector2i(6, 6))
	var edges: Array[MapEdgeData] = []
	var cells := GridVisibilityScript.line_cells(Vector3i(0, 0, 0), Vector3i(5, 0, 5))
	for first_index in range(cells.size()):
		for second_index in range(first_index + 1, mini(first_index + 3, cells.size())):
			var first: Vector3i = cells[first_index]
			var second: Vector3i = cells[second_index]
			if first.y == second.y and absi(first.x - second.x) + absi(first.z - second.z) == 1:
				_add_edge_unique(edges, _edge(first, second))
	_expect(grid.edge_index.configure(edges), "line: all synthetic supercover edges should index")

	var forward := TacticalLineQueryScript.query(Vector3i(0, 0, 0), Vector3i(5, 0, 5), grid)
	var reverse := TacticalLineQueryScript.query(Vector3i(5, 0, 5), Vector3i(0, 0, 0), grid)
	_expect(forward.valid and reverse.valid, "line: forward and reverse traces should be valid")
	_expect(forward.cells_crossed.size() > 2, "line: long diagonal should expose supercover corner cells")
	_expect(_sorted_edge_keys(forward.edges_crossed) == _sorted_edge_keys(reverse.edges_crossed), "line: reverse trace should cover the same edge set")
	_expect(_sorted_cell_keys(forward.cells_crossed) == _sorted_cell_keys(reverse.cells_crossed), "line: reverse trace should cover the same cell set")

	# This edge exists only on the second branch of a corner triple. A query
	# that inspects adjacent array entries alone would miss it.
	var branch_edge := grid.get_edge(Vector3i(1, 0, 0), Vector3i(1, 0, 1))
	_expect(branch_edge != null, "line: corner branch edge should be collected")
	branch_edge.sight_block = 1.0
	branch_edge.projectile_block = 1.0
	var blocked := TacticalLineQueryScript.query(Vector3i(0, 0, 0), Vector3i(5, 0, 5), grid)
	_expect(blocked.los_blocked and blocked.projectile_blocked, "line: sight and projectile flags must both survive on one edge")
	_expect(blocked.sight_blocking_edge_key == branch_edge.key_string() and blocked.projectile_blocking_edge_key == branch_edge.key_string(), "line: one edge must be recorded independently for both blocking channels")
	_expect(blocked.sight_blocking_edge == branch_edge and blocked.projectile_blocking_edge == branch_edge, "line: channel-specific edge objects must be preserved")
	_expect(blocked.blocking_edge_key == branch_edge.key_string(), "line: blocking edge should identify the deterministic branch edge")


func _test_cover_sides_and_corner_choice() -> void:
	var grid = GridModelScript.new(Vector2i(4, 4))
	var settings := CoverCombatSettingsScript.make_default()
	var half := _profile(&"cover.test.half", 1, 0.5)
	var full := _profile(&"cover.test.full", 2, 0.75)
	var edge := _edge(Vector3i(1, 0, 0), Vector3i(2, 0, 0), half, full)
	_expect(grid.edge_index.configure([edge]), "cover: side edge should index")
	var target_side_b := CoverQueryScript.query(Vector3i(0, 0, 0), Vector3i(2, 0, 0), grid, null, settings)
	_expect(target_side_b.cover_profile_id == full.cover_id and target_side_b.target_side == &"b", "cover: target cell_b should use profile_b")
	var target_side_a := CoverQueryScript.query(Vector3i(3, 0, 0), Vector3i(1, 0, 0), grid, null, settings)
	_expect(target_side_a.cover_profile_id == half.cover_id and target_side_a.target_side == &"a", "cover: target cell_a should use profile_a")
	var legacy_edge := _edge(Vector3i(1, 0, 0), Vector3i(2, 0, 0))
	legacy_edge.cover_a = TacticalEdgeRules.CoverLevel.HALF
	legacy_edge.cover_b = TacticalEdgeRules.CoverLevel.FULL
	grid.edge_index.configure([legacy_edge])
	var legacy_result := CoverQueryScript.query(Vector3i(0, 0, 0), Vector3i(2, 0, 0), grid, null, settings)
	_expect(legacy_result.cover_profile_id == settings.legacy_full_profile.cover_id, "cover: legacy cover level should resolve through shared settings")
	var no_edge_result := CoverQueryScript.query(Vector3i(0, 0, 0), Vector3i(3, 0, 0), grid, null, settings)
	_expect(no_edge_result.cover_level == 0 and not no_edge_result.has_cover, "cover: no incoming edge should be NONE")

	var corner_a := _edge(Vector3i(1, 0, 0), Vector3i(1, 0, 1))
	corner_a.cover_profile_b = half
	var corner_b := _edge(Vector3i(0, 0, 1), Vector3i(1, 0, 1))
	corner_b.cover_profile_b = full
	grid.edge_index.configure([corner_a, corner_b])
	var corner_result := CoverQueryScript.query(Vector3i(0, 0, 0), Vector3i(1, 0, 1), grid, null, settings)
	_expect(corner_result.target_incoming_edges.size() == 2, "cover: corner should expose both target incoming edges")
	_expect(corner_result.cover_profile_id == full.cover_id and corner_result.source_edge_key == corner_b.key_string(), "cover: corner should choose strongest reduction deterministically")

	var tie_a := _edge(Vector3i(1, 0, 0), Vector3i(1, 0, 1))
	tie_a.cover_profile_b = half
	var tie_b := _edge(Vector3i(0, 0, 1), Vector3i(1, 0, 1))
	tie_b.cover_profile_b = _profile(&"cover.test.half.alt", 1, 0.5)
	grid.edge_index.configure([tie_b, tie_a])
	var tie_result := CoverQueryScript.query(Vector3i(0, 0, 0), Vector3i(1, 0, 1), grid, null, settings)
	_expect(tie_result.source_edge_key == _min_string(tie_a.key_string(), tie_b.key_string()), "cover: equal strength corner must use canonical key tie-break")


func _test_blocking_and_cross_level() -> void:
	var grid = GridModelScript.new(Vector2i(4, 2))
	var sight_wall := _edge(Vector3i(1, 0, 0), Vector3i(2, 0, 0))
	sight_wall.sight_block = 1.0
	var projectile_wall := _edge(Vector3i(2, 0, 0), Vector3i(3, 0, 0))
	projectile_wall.projectile_block = 1.0
	grid.edge_index.configure([sight_wall, projectile_wall])
	var sight_result := CoverQueryScript.query(Vector3i(0, 0, 0), Vector3i(3, 0, 0), grid)
	_expect(not sight_result.can_attack() and sight_result.los_blocked, "block: full sight edge should reject attack")
	grid.edge_index.configure([projectile_wall])
	var projectile_result := CoverQueryScript.query(Vector3i(2, 0, 0), Vector3i(3, 0, 0), grid)
	_expect(not projectile_result.can_attack() and not projectile_result.los_blocked and projectile_result.projectile_blocked, "block: projectile edge should reject without falsely setting sight")

	var upper_definition := TacticalMapDefinition.new()
	upper_definition.footprint_size = Vector2i(2, 1)
	upper_definition.level_count = 2
	var lower_data := MapCellData.new()
	lower_data.coordinate = Vector3i(0, 0, 0)
	upper_definition.cells.append(lower_data)
	var upper_data := MapCellData.new()
	upper_data.coordinate = Vector3i(0, 1, 0)
	upper_definition.cells.append(upper_data)
	var upper := GridModelScript.new()
	_expect(upper.configure_from_definition(upper_definition), "block: synthetic upper grid should configure")
	var cross := CoverQueryScript.query(Vector3i(0, 0, 0), Vector3i(0, 1, 0), upper)
	_expect(cross.valid and cross.cross_level and cross.cover_level == 0 and cross.reason == &"unsupported_height_relation", "block: cross-level query should safely return explicit NONE")


func _test_independent_blocking_sources() -> void:
	var grid := GridModelScript.new(Vector2i(5, 1))
	var opaque_cell := Vector3i(1, 0, 0)
	var projectile_cell := Vector3i(3, 0, 0)
	grid.set_cell_blockers(projectile_cell, false, true)
	var opaque_cells := {opaque_cell: true}
	var cell_result := TacticalLineQueryScript.query(Vector3i(0, 0, 0), Vector3i(4, 0, 0), grid, null, opaque_cells)
	_expect(cell_result.los_blocked and cell_result.projectile_blocked, "block-source: later projectile cell must still be found after earlier LOS cell")
	_expect(cell_result.sight_blocking_cell == opaque_cell and cell_result.projectile_blocking_cell == projectile_cell, "block-source: LOS/projectile cells must remain independent")
	_expect(cell_result.blocking_cell == opaque_cell, "block-source: legacy blocking cell should keep first deterministic trace source")

	var settings := CoverCombatSettingsScript.make_default()
	var full := _profile(&"cover.debug.blocked_target", 2, 0.75)
	var middle_sight := _edge(Vector3i(1, 0, 0), Vector3i(2, 0, 0))
	middle_sight.sight_block = 1.0
	var target_cover := _edge(Vector3i(3, 0, 0), Vector3i(4, 0, 0), null, full)
	var edge_index := TacticalEdgeIndexScript.new()
	_expect(edge_index.configure([middle_sight, target_cover]), "block-source: synthetic middle and target edges should index")
	var cover_result := CoverQueryScript.query(Vector3i(0, 0, 0), Vector3i(4, 0, 0), grid, edge_index, settings)
	_expect(cover_result.sight_blocking_edge_key == middle_sight.key_string(), "block-source: sight source must be the actual middle blocker")
	_expect(cover_result.projectile_blocking_edge_key.is_empty(), "block-source: projectile source must stay empty when only sight is blocked")
	_expect(cover_result.blocking_edge_key == middle_sight.key_string(), "block-source: legacy edge source must remain the minimum actual blocker")
	_expect(cover_result.source_edge_key == target_cover.key_string(), "block-source: cover source must remain the target incoming edge")
	var blocked_damage: Dictionary = CoverResolverScript.resolve_damage(8, cover_result.profile, settings, cover_result.source_edge)
	var summary: Dictionary = CoverResolverScript.build_debug_summary(cover_result, blocked_damage)
	_expect(summary[&"cover_source_edge"] == target_cover.key_string(), "block-source: summary must label target cover edge separately")
	_expect(summary[&"sight_blocking_edge"] == middle_sight.key_string(), "block-source: summary must label actual sight blocker")
	_expect(summary[&"projectile_blocking_edge"].is_empty(), "block-source: summary must not invent projectile blocker")
	var formatted := CoverResolverScript.format_debug_summary(summary)
	_expect(formatted.contains("cover_edge=%s" % target_cover.key_string()) and formatted.contains("sight_edge=%s" % middle_sight.key_string()), "block-source: formatted output must distinguish cover and obstruction edges")


func _test_damage_and_action_metadata() -> void:
	var settings := CoverCombatSettingsScript.make_default()
	var half := _profile(&"cover.test.half.damage", 1, 0.5)
	var full := _profile(&"cover.test.full.damage", 2, 0.75)
	var none_result: Dictionary = CoverResolverScript.resolve_damage(7, null, settings)
	_expect(none_result[&"effective_damage"] == 7 and none_result[&"prevented_damage"] == 0, "damage: NONE should not reduce damage")
	var half_result: Dictionary = CoverResolverScript.resolve_damage(7, half, settings)
	_expect(half_result[&"effective_damage"] == 4 and half_result[&"prevented_damage"] == 3, "damage: HALF should use roundi(base * (1-ratio))")
	var minimum_settings := CoverCombatSettingsScript.make_default()
	minimum_settings.minimum_damage_after_cover = 3
	minimum_settings.allow_zero_damage = false
	var minimum_result: Dictionary = CoverResolverScript.resolve_damage(2, full, minimum_settings)
	_expect(minimum_result[&"effective_damage"] == 2, "damage: minimum cannot create damage above base")
	var one_damage: Dictionary = CoverResolverScript.resolve_damage(1, full, minimum_settings)
	_expect(one_damage[&"effective_damage"] == 1, "damage: non-zero policy must preserve one damage")

	var metadata := {&"base_damage": 7, &"effective_damage": 4, &"cover_level": 1, &"cover_profile_id": half.cover_id}
	var accepted := ActionResultScript.accepted(&"p", &"e", 1, &"attack", metadata)
	var copied := CombatResolverScript.resolve_attack(accepted, 20, 4)
	_expect(copied.action_type == &"attack" and copied.metadata == metadata, "metadata: CombatResolver copy must preserve action type and metadata")
	copied.metadata[&"effective_damage"] = 99
	_expect(accepted.metadata[&"effective_damage"] == 4, "metadata: copy must not alias source dictionary")


func _test_debug_summaries() -> void:
	var settings := CoverCombatSettingsScript.make_default()
	var half := _profile(&"cover.debug.half", 1, 0.5)
	var full := _profile(&"cover.debug.full", 2, 0.75)
	var edge := _edge(Vector3i(1, 0, 0), Vector3i(2, 0, 0), half, full)

	var none_query := CoverQueryResultScript.new()
	none_query.valid = true
	var none_damage: Dictionary = CoverResolverScript.resolve_damage(7, null, settings)
	var none_summary: Dictionary = CoverResolverScript.build_debug_summary(none_query, none_damage)
	_expect(none_summary[&"cover_level_name"] == &"NONE", "debug: no cover should have NONE label")
	_expect(none_summary[&"cover_profile_id"] == &"cover.none", "debug: no cover should use stable none profile")
	_expect(none_summary[&"damage_reduction_percent"] == 0, "debug: no cover should report zero reduction")
	_expect(none_summary[&"base_damage"] == 7 and none_summary[&"prevented_damage"] == 0 and none_summary[&"effective_damage"] == 7, "debug: no cover damage values should be complete")

	var half_query := CoverQueryResultScript.new()
	half_query.valid = true
	half_query.has_cover = true
	half_query.cover_level = 1
	half_query.cover_profile_id = half.cover_id
	half_query.profile = half
	half_query.damage_reduction_ratio = half.damage_reduction_ratio
	half_query.source_edge = edge
	half_query.source_edge_key = edge.key_string()
	var half_damage: Dictionary = CoverResolverScript.resolve_damage(7, half, settings, edge)
	var half_summary: Dictionary = CoverResolverScript.build_debug_summary(half_query, half_damage)
	_expect(half_summary[&"cover_level_name"] == &"HALF" and half_summary[&"cover_profile_id"] == half.cover_id, "debug: half cover should expose level and profile")
	_expect(half_summary[&"damage_reduction_percent"] == 50 and half_summary[&"base_damage"] == 7 and half_summary[&"prevented_damage"] == 3 and half_summary[&"effective_damage"] == 4, "debug: half cover should expose damage breakdown")
	_expect(half_summary[&"source_edge_key"] == edge.key_string(), "debug: half cover should expose source edge")

	var full_query := CoverQueryResultScript.new()
	full_query.valid = true
	full_query.has_cover = true
	full_query.cover_level = 2
	full_query.cover_profile_id = full.cover_id
	full_query.profile = full
	full_query.damage_reduction_ratio = full.damage_reduction_ratio
	var full_damage: Dictionary = CoverResolverScript.resolve_damage(8, full, settings)
	var full_summary: Dictionary = CoverResolverScript.build_debug_summary(full_query, full_damage)
	_expect(full_summary[&"cover_level_name"] == &"FULL" and full_summary[&"damage_reduction_percent"] == 75, "debug: full cover should expose stronger reduction")
	_expect(full_summary[&"base_damage"] == 8 and full_summary[&"prevented_damage"] == 6 and full_summary[&"effective_damage"] == 2, "debug: full cover should expose final damage")

	var blocked_query := CoverQueryResultScript.new()
	blocked_query.valid = true
	blocked_query.los_blocked = true
	blocked_query.projectile_blocked = true
	blocked_query.block_reason = &"projectile_blocked"
	blocked_query.source_edge = edge
	var blocked_damage: Dictionary = CoverResolverScript.resolve_damage(5, null, settings, edge)
	var blocked_summary: Dictionary = CoverResolverScript.build_debug_summary(blocked_query, blocked_damage)
	_expect(blocked_summary[&"los_block_reason"] == &"sight_blocked" and blocked_summary[&"projectile_block_reason"] == &"projectile_blocked", "debug: blocked summary should retain independent LOS and projectile reasons")
	_expect(blocked_summary[&"source_edge_key"] == edge.key_string(), "debug: blocked summary should retain source edge")
	var formatted := CoverResolverScript.format_debug_summary(blocked_summary)
	_expect(formatted.contains("projectile_blocked") and formatted.contains("sight_blocked") and formatted.contains(edge.key_string()), "debug: formatted summary should be traceable in Output")


func _test_controller_uses_shared_query() -> void:
	var grid = GridModelScript.new(Vector2i(3, 1))
	var wall := _edge(Vector3i(1, 0, 0), Vector3i(2, 0, 0))
	wall.projectile_block = 1.0
	grid.edge_index.configure([wall])
	var controller := PrototypeControllerScript.new()
	controller.grid = grid
	controller.cover_combat_settings = CoverCombatSettingsScript.make_default()
	var query := controller.query_attack_cover(Vector3i(0, 0, 0), Vector3i(2, 0, 0))
	_expect(query.projectile_blocked and not query.can_attack(), "controller: public attack query must use shared edge projectile rules")
	_expect(not controller.can_attack_line(Vector3i(0, 0, 0), Vector3i(2, 0, 0), 1), "controller: attack range must reject an out-of-range target")
	_expect(not controller.can_attack_line(Vector3i(0, 0, 0), Vector3i(2, 0, 0), 2), "controller: attack line must reject the same projectile-blocked target")
	controller.free()


func _edge(
	cell_a: Vector3i,
	cell_b: Vector3i,
	profile_a: TacticalCoverProfile = null,
	profile_b: TacticalCoverProfile = null
) -> MapEdgeData:
	var result := MapEdgeData.new()
	var key := TacticalEdgeKey.from_cells(cell_a, cell_b)
	result.cell_a = key.cell_a
	result.cell_b = key.cell_b
	result.cover_profile_a = profile_a
	result.cover_profile_b = profile_b
	return result


func _profile(profile_id: StringName, level: int, ratio: float) -> TacticalCoverProfile:
	var result := TacticalCoverProfileScript.new()
	result.cover_id = profile_id
	result.display_name = String(profile_id)
	result.cover_level = level
	result.damage_reduction_ratio = ratio
	return result


func _add_edge_unique(edges: Array[MapEdgeData], edge: MapEdgeData) -> void:
	for existing in edges:
		if existing.key_string() == edge.key_string():
			return
	edges.append(edge)


func _sorted_edge_keys(edges: Array[MapEdgeData]) -> Array[String]:
	var result: Array[String] = []
	for edge in edges:
		result.append(edge.key_string())
	result.sort()
	return result


func _sorted_cell_keys(cells: Array[Vector3i]) -> Array[String]:
	var result: Array[String] = []
	for cell in cells:
		result.append("%d,%d,%d" % [cell.x, cell.y, cell.z])
	result.sort()
	return result


func _min_string(first: String, second: String) -> String:
	return first if first < second else second


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("COVER_RUNTIME_CORE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("COVER_RUNTIME_CORE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
