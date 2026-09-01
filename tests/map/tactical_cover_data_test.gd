extends SceneTree

## Pure cover data-contract checks. No production map scene or fixed layout is
## loaded; the only content resources used are the reusable cover definitions.

var _failures: Array[String] = []


func _init() -> void:
	_test_profiles_and_settings()
	_test_edge_profile_compatibility()
	_test_local_contribution_and_content()
	_test_baker_rotation_contract()
	_test_baker_structure_derivation()
	_test_internal_structure_edges()
	_test_baker_merge_precedence()
	_test_profile_warning_consumption()
	_test_four_way_cover_runtime()
	_test_schema_contract()
	_test_baker_save_preserves_existing_uid()
	_finish()


func _test_profiles_and_settings() -> void:
	var none := load("res://resources/combat/cover_profiles/cover_none.tres") as TacticalCoverProfile
	var half := load("res://resources/combat/cover_profiles/cover_half.tres") as TacticalCoverProfile
	var full := load("res://resources/combat/cover_profiles/cover_full.tres") as TacticalCoverProfile
	var settings := load("res://resources/combat/cover_combat_settings.tres") as CoverCombatSettings
	_expect(none != null and half != null and full != null and settings != null, "profiles: default resources should load")
	if none == null or half == null or full == null or settings == null:
		return
	_expect(none.cover_id == &"cover.none" and none.cover_level == 0 and is_zero_approx(none.damage_reduction_ratio), "profiles: NONE contract")
	_expect(half.cover_id == &"cover.half" and half.cover_level == 1 and is_equal_approx(half.damage_reduction_ratio, 0.5), "profiles: HALF contract")
	_expect(full.cover_id == &"cover.full" and full.cover_level == 2 and is_equal_approx(full.damage_reduction_ratio, 0.75), "profiles: FULL contract")
	_expect(settings.is_valid(), "settings: default mapping should validate")
	_expect(settings.get_profile_for_level(0) == none and settings.get_profile_for_level(1) == half and settings.get_profile_for_level(2) == full, "settings: legacy levels should map to profiles")


func _test_edge_profile_compatibility() -> void:
	var none := load("res://resources/combat/cover_profiles/cover_none.tres") as TacticalCoverProfile
	var half := load("res://resources/combat/cover_profiles/cover_half.tres") as TacticalCoverProfile
	var full := load("res://resources/combat/cover_profiles/cover_full.tres") as TacticalCoverProfile
	var rules := TacticalEdgeRules.new()
	rules.cover_a = TacticalEdgeRules.CoverLevel.FULL
	rules.cover_b = TacticalEdgeRules.CoverLevel.HALF
	rules.cover_profile_a = full
	rules.cover_profile_b = half
	var copied := rules.duplicate_rules()
	_expect(copied.cover_profile_a == full and copied.cover_profile_b == half, "edge rules: profile references should copy")
	_expect(copied.semantic_key() == rules.semantic_key(), "edge rules: duplicate semantic key should be stable")

	var reversed_key := TacticalEdgeKey.new()
	reversed_key.cell_a = Vector3i(1, 0, 0)
	reversed_key.cell_b = Vector3i(0, 0, 0)
	var placement := TacticalEdgePlacement.new()
	placement.edge_key = reversed_key
	placement.placeable_id = &"edge.cover.test"
	placement.rules = rules
	var baked := MapEdgeData.from_placement(placement)
	_expect(baked.cell_a == Vector3i(0, 0, 0) and baked.cell_b == Vector3i(1, 0, 0), "edge data: placement should canonicalize endpoints")
	_expect(baked.cover_profile_a == half and baked.cover_profile_b == full, "edge data: reversed placement should swap profiles")
	_expect(baked.source_type == &"explicit" and baked.source_placeable_id == placement.placeable_id, "edge data: explicit provenance")
	_expect(baked.resolve_profile(0) == half and baked.resolve_profile(1) == full, "edge data: profile query should preserve physical sides")
	_expect(none != null, "edge data: NONE resource should remain loadable")


func _test_local_contribution_and_content() -> void:
	var low_cover := load("res://resources/map_tiles/definitions/structure/low_cover.tres") as TacticalCellTileDefinition
	var wall := load("res://resources/map_tiles/definitions/structure/wall.tres") as TacticalCellTileDefinition
	_expect(low_cover != null and low_cover.is_valid(), "content: LowCover definition with edge contribution should validate")
	_expect(wall != null and wall.is_valid(), "content: Wall definition with edge contribution should validate")
	if low_cover == null or wall == null:
		return
	_expect(low_cover.edge_contributions.size() == 4, "content: LowCover should expose all four local edges")
	_expect(wall.edge_contributions.size() == 4, "content: Wall should expose all four local edges")
	var low_directions: Array[int] = []
	for low_edge in low_cover.edge_contributions:
		low_directions.append(int(low_edge.local_direction))
		_expect(low_edge.edge_rules.cover_profile_b == load("res://resources/combat/cover_profiles/cover_half.tres"), "content: LowCover neighbor side should be HALF")
	_expect(low_directions == [
		TacticalLocalEdgeContribution.LocalDirection.NORTH,
		TacticalLocalEdgeContribution.LocalDirection.EAST,
		TacticalLocalEdgeContribution.LocalDirection.SOUTH,
		TacticalLocalEdgeContribution.LocalDirection.WEST,
	], "content: LowCover local edges should be North/East/South/West")
	var wall_directions: Array[int] = []
	for wall_edge in wall.edge_contributions:
		wall_directions.append(int(wall_edge.local_direction))
		_expect(wall_edge.edge_rules.blocks_movement and wall_edge.edge_rules.sight_block == 1.0 and wall_edge.edge_rules.projectile_block == 1.0, "content: Wall edge should retain physical blocking")
		_expect(wall_edge.edge_rules.cover_profile_b == load("res://resources/combat/cover_profiles/cover_full.tres"), "content: Wall neighbor side should be FULL")
	_expect(wall_directions == [
		TacticalLocalEdgeContribution.LocalDirection.NORTH,
		TacticalLocalEdgeContribution.LocalDirection.EAST,
		TacticalLocalEdgeContribution.LocalDirection.SOUTH,
		TacticalLocalEdgeContribution.LocalDirection.WEST,
	], "content: Wall local edges should cover N/E/S/W")

	var mesh_library := load("res://resources/map_tiles/mesh_libraries/default_mesh_library.tres") as MeshLibrary
	_expect(mesh_library != null and mesh_library.get_item_mesh(3) != null and mesh_library.get_item_mesh_transform(3).basis.is_finite(), "content: actual MeshLibrary LowCover item should be inspectable")
	if mesh_library != null:
		var mesh := mesh_library.get_item_mesh(3)
		var raw_aabb := mesh.get_aabb()
		var item_transform := mesh_library.get_item_mesh_transform(3)
		var raw_long_axis := Vector3(0, 0, 1) if raw_aabb.size.z > raw_aabb.size.x else Vector3(1, 0, 0)
		var transformed_long_axis := item_transform.basis * raw_long_axis
		_expect(raw_aabb.size.z > raw_aabb.size.x, "content: scanner-low raw mesh should be long on local Z")
		_expect(absf(transformed_long_axis.x) > absf(transformed_long_axis.z), "content: MeshLibrary item transform should rotate raw long axis onto X")
		var shapes: Array = mesh_library.get_item_shapes(3)
		_expect(not shapes.is_empty() and shapes[0] is BoxShape3D, "content: LowCover item should expose a BoxShape3D")
		if not shapes.is_empty() and shapes[0] is BoxShape3D:
			var shape := shapes[0] as BoxShape3D
			_expect(shape.size.x > shape.size.z, "content: LowCover collision long axis should be X")
		print("TACTICAL_COVER_MESH_ORIENTATION: item3_transform=%s raw_aabb=%s transformed_long_axis=%s shape=%s" % [item_transform, raw_aabb, transformed_long_axis, shapes[0].size if shapes[0] is BoxShape3D else Vector3.ZERO])
		var wall_mesh := mesh_library.get_item_mesh(2)
		var wall_raw_aabb := wall_mesh.get_aabb() if wall_mesh != null else AABB()
		var wall_transform := mesh_library.get_item_mesh_transform(2)
		var wall_x_axis := wall_transform.basis * Vector3.RIGHT
		var wall_z_axis := wall_transform.basis * Vector3.BACK
		_expect(wall_mesh != null and wall_transform.basis.is_finite(), "content: actual MeshLibrary Wall item should be inspectable")
		_expect(absf(wall_x_axis.x) > absf(wall_x_axis.z) and absf(wall_z_axis.z) > absf(wall_z_axis.x), "content: Wall item transform should not swap its horizontal axes")
		var wall_shapes: Array = mesh_library.get_item_shapes(2)
		_expect(not wall_shapes.is_empty() and wall_shapes[0] is BoxShape3D, "content: Wall item should expose a BoxShape3D")
		if not wall_shapes.is_empty() and wall_shapes[0] is BoxShape3D:
			var wall_shape := wall_shapes[0] as BoxShape3D
			_expect(is_equal_approx(wall_shape.size.x, wall_shape.size.z), "content: Wall collision has no unique horizontal long axis")
		print("TACTICAL_COVER_MESH_ORIENTATION: item2_transform=%s raw_aabb=%s horizontal_axes=(%s,%s) shape=%s" % [wall_transform, wall_raw_aabb, wall_x_axis, wall_z_axis, wall_shapes[0].size if wall_shapes[0] is BoxShape3D else Vector3.ZERO])


func _test_schema_contract() -> void:
	_expect(TacticalMapDefinition.CURRENT_SCHEMA_VERSION == 3, "schema: current version should be 3")
	var fresh_definition := TacticalMapDefinition.new()
	_expect(fresh_definition.schema_version == TacticalMapDefinition.MIN_SUPPORTED_SCHEMA_VERSION, "schema: a fresh definition should use the legacy baseline until Baker explicitly stamps it")
	_expect(TacticalMapDefinition.is_schema_version_supported(1), "schema: version 1 remains supported")
	_expect(TacticalMapDefinition.is_schema_version_supported(2), "schema: version 2 remains supported")
	_expect(TacticalMapDefinition.is_schema_version_supported(3), "schema: version 3 is supported")
	_expect(not TacticalMapDefinition.is_schema_version_supported(4), "schema: future version should be rejected")
	var author := _make_synthetic_cover_author(0.0)
	var baked := TacticalMapBaker.build(author)
	var baked_definition := baked.get(&"definition", null) as TacticalMapDefinition
	_expect(baked_definition != null and baked_definition.schema_version == TacticalMapDefinition.CURRENT_SCHEMA_VERSION, "schema: Baker output should be explicitly stamped with the current version")
	var temporary_path := "res://.godot/tactical_map_definition_schema_test.tres"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	if baked_definition != null:
		var save_error := ResourceSaver.save(baked_definition, temporary_path)
		_expect(save_error == OK, "schema: Baker output should save to the temporary schema fixture")
		var serialized_file := FileAccess.open(temporary_path, FileAccess.READ)
		var serialized_text := serialized_file.get_as_text() if serialized_file != null else ""
		if serialized_file != null:
			serialized_file.close()
		_expect(serialized_text.contains("schema_version = 3"), "schema: serialized Baker output should explicitly retain schema_version = 3")
		var reloaded := ResourceLoader.load(temporary_path) as TacticalMapDefinition
		_expect(reloaded != null and reloaded.schema_version == TacticalMapDefinition.CURRENT_SCHEMA_VERSION, "schema: reloaded Baker output should remain current")
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	author.free()


func _test_baker_save_preserves_existing_uid() -> void:
	var temporary_path := "res://.godot/tactical_map_uid_overwrite_test.tres"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var seed_definition := TacticalMapDefinition.new()
	var seed_save_error := ResourceSaver.save(seed_definition, temporary_path)
	_expect(seed_save_error == OK, "uid: temporary existing resource should save")
	if seed_save_error != OK:
		return
	var original_uid := ResourceUID.create_id()
	var seed_uid_error := ResourceSaver.set_uid(temporary_path, original_uid)
	_expect(seed_uid_error == OK, "uid: temporary fixture should register its original UID")
	if seed_uid_error == OK:
		if ResourceUID.has_id(original_uid):
			ResourceUID.set_id(original_uid, temporary_path)
		else:
			ResourceUID.add_id(original_uid, temporary_path)
	var registered_uid := ResourceLoader.get_resource_uid(temporary_path)
	_expect(registered_uid == original_uid, "uid: fixture UID should be visible through ResourceLoader")

	var author := _make_synthetic_cover_author(0.0)
	author.output_resource_path = temporary_path
	var result := TacticalMapBaker.save(author)
	_expect((result.get(&"errors", []) as Array).is_empty(), "uid: overwriting a valid fixture should succeed")
	var preserved_uid := ResourceLoader.get_resource_uid(temporary_path)
	_expect(preserved_uid == original_uid, "uid: Baker overwrite must preserve the existing registered UID")
	var file := FileAccess.open(temporary_path, FileAccess.READ)
	var serialized_text := file.get_as_text() if file != null else ""
	if file != null:
		file.close()
	_expect(serialized_text.contains(ResourceUID.id_to_text(original_uid)), "uid: overwritten resource should serialize the original UID")
	author.free()
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))


func _test_baker_rotation_contract() -> void:
	var expected := [
		[Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)],
		[Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
		[Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0)],
		[Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)],
	]
	var angles := [0.0, 90.0, 180.0, 270.0]
	for index in range(angles.size()):
		var basis := Basis(Vector3.UP, deg_to_rad(angles[index]))
		for local_direction in range(4):
			var direction := TacticalMapBaker._rotated_local_edge_direction(local_direction, basis)
			_expect(direction == expected[index][local_direction], "baker: local direction %d at %d degrees should map to %s, got %s" % [local_direction, int(angles[index]), expected[index][local_direction], direction])


func _test_baker_structure_derivation() -> void:
	var expected := [Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0)]
	var angles := [0.0, 90.0, 180.0, 270.0]
	for index in range(angles.size()):
		var author := _make_synthetic_cover_author(angles[index])
		var result: Dictionary = TacticalMapBaker.build(author)
		_expect((result[&"errors"] as Array).is_empty(), "baker: synthetic %d degree structure map should build" % int(angles[index]))
		var definition := result[&"definition"] as TacticalMapDefinition
		var derived: MapEdgeData = null
		if definition != null:
			for edge in definition.edges:
				if edge != null and edge.source_type == &"structure_derived":
					derived = edge
					break
		_expect(derived != null, "baker: %d degree structure should derive one Edge" % int(angles[index]))
		if derived != null:
			var source_is_a := derived.cell_a == derived.source_cell
			var derived_direction := derived.cell_b - derived.cell_a if source_is_a else derived.cell_a - derived.cell_b
			_expect(derived_direction == expected[index], "baker: %d degree derived direction should be %s, got %s" % [int(angles[index]), expected[index], derived_direction])
			var source_profile := derived.cover_profile_a if source_is_a else derived.cover_profile_b
			var neighbor_profile := derived.cover_profile_b if source_is_a else derived.cover_profile_a
			_expect(source_profile != null and source_profile.cover_level == 0, "baker: source side should retain NONE at %d degrees" % int(angles[index]))
			_expect(neighbor_profile != null and neighbor_profile.cover_level == 1, "baker: neighbor side should retain HALF at %d degrees" % int(angles[index]))
		_expect(author.authoring_data == null, "baker: derived %d degree edge must not create authoring data" % int(angles[index]))
		author.free()


func _make_synthetic_cover_author(angle_degrees: float) -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.map_id = &"synthetic_cover_rotation"
	author.level_count = 1
	author.footprint_size = Vector2i(3, 3)
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	var mesh_library := MeshLibrary.new()
	mesh_library.create_item(0)
	mesh_library.create_item(1)
	var floor_definition := TacticalCellTileDefinition.new()
	floor_definition.placeable_id = &"synthetic.floor"
	floor_definition.target_layer = MapTileRule.Layer.FLOOR
	floor_definition.mesh_item_id = 0
	floor_definition.rule_contribution = TacticalCellRules.new()
	var structure_definition := TacticalCellTileDefinition.new()
	structure_definition.placeable_id = &"synthetic.low_cover"
	structure_definition.target_layer = MapTileRule.Layer.STRUCTURE
	structure_definition.mesh_item_id = 1
	var structure_rules := TacticalCellRules.new()
	structure_rules.walkable = false
	structure_definition.rule_contribution = structure_rules
	var contribution := TacticalLocalEdgeContribution.new()
	contribution.local_direction = TacticalLocalEdgeContribution.LocalDirection.NORTH
	var edge_rules := TacticalEdgeRules.new()
	edge_rules.cover_a = TacticalEdgeRules.CoverLevel.NONE
	edge_rules.cover_b = TacticalEdgeRules.CoverLevel.HALF
	edge_rules.cover_profile_a = load("res://resources/combat/cover_profiles/cover_none.tres")
	edge_rules.cover_profile_b = load("res://resources/combat/cover_profiles/cover_half.tres")
	contribution.edge_rules = edge_rules
	structure_definition.edge_contributions = [contribution]
	var library := TacticalPlaceableLibrary.new()
	library.definitions = [floor_definition, structure_definition]
	var floor_binding := MeshItemBinding.new()
	floor_binding.placeable_id = floor_definition.placeable_id
	floor_binding.target_layer = MapTileRule.Layer.FLOOR
	floor_binding.mesh_item_id = floor_definition.mesh_item_id
	var structure_binding := MeshItemBinding.new()
	structure_binding.placeable_id = structure_definition.placeable_id
	structure_binding.target_layer = MapTileRule.Layer.STRUCTURE
	structure_binding.mesh_item_id = structure_definition.mesh_item_id
	library.item_bindings = [floor_binding, structure_binding]
	author.placeable_library = library
	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = mesh_library
	floor_grid.cell_size = author.cell_dimensions
	for cell in [Vector3i.ZERO, Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]:
		floor_grid.set_cell_item(cell, 0)
	author.add_child(floor_grid)
	var structure_grid := GridMap.new()
	structure_grid.name = "StructureGrid"
	structure_grid.mesh_library = mesh_library
	structure_grid.cell_size = author.cell_dimensions
	var basis := Basis(Vector3.UP, deg_to_rad(angle_degrees))
	var orientation := structure_grid.get_orthogonal_index_from_basis(basis)
	structure_grid.set_cell_item(Vector3i.ZERO, 1, orientation)
	author.add_child(structure_grid)
	var spawn := UnitSpawnMarker3D.new()
	spawn.unit_name = &"SyntheticPlayer"
	spawn.faction = &"player"
	spawn.cell = Vector3i(0, 0, -1)
	author.add_child(spawn)
	var extraction := MapObjectMarker3D.new()
	extraction.object_id = &"SyntheticExtraction"
	extraction.kind = MapObjectPlacement.Kind.EXTRACTION
	extraction.cell = spawn.cell
	author.add_child(extraction)
	return author


func _test_internal_structure_edges() -> void:
	var low_cover := load("res://resources/map_tiles/definitions/structure/low_cover.tres") as TacticalCellTileDefinition
	var wall := load("res://resources/map_tiles/definitions/structure/wall.tres") as TacticalCellTileDefinition
	if low_cover == null or wall == null:
		return
	var source_cell := Vector3i.ZERO
	var neighbor_cell := Vector3i(0, 0, -1)
	var blocked_cells := {
		source_cell: _test_cell_data(source_cell, false),
		neighbor_cell: _test_cell_data(neighbor_cell, false),
	}
	var low_candidates := [
		_test_structure_candidate(source_cell, low_cover, low_cover.edge_contributions[0]),
		_test_structure_candidate(neighbor_cell, low_cover, low_cover.edge_contributions[2]),
	]
	var low_result := _collect_test_edges(null, low_candidates, 0, blocked_cells)
	_expect((low_result[&"definition"].edges as Array).is_empty(), "baker: adjacent LowCover Structures should not emit an internal Edge")
	_expect(not _contains_text(low_result[&"errors"], "TMB-068"), "baker: adjacent LowCover Structures should not conflict")
	var wall_candidates := [
		_test_structure_candidate(source_cell, wall, wall.edge_contributions[0]),
		_test_structure_candidate(neighbor_cell, wall, wall.edge_contributions[2]),
	]
	var wall_result := _collect_test_edges(null, wall_candidates, 0, blocked_cells)
	_expect((wall_result[&"definition"].edges as Array).is_empty(), "baker: adjacent Wall Structures should not emit an internal Edge")
	_expect(not _contains_text(wall_result[&"errors"], "TMB-068"), "baker: adjacent Wall Structures should not conflict")

	var walkable_neighbor := {
		source_cell: _test_cell_data(source_cell, false),
		neighbor_cell: _test_cell_data(neighbor_cell, true),
	}
	var exposed_result := _collect_test_edges(null, [
		_test_structure_candidate(source_cell, low_cover, low_cover.edge_contributions[0]),
	], 0, walkable_neighbor)
	var exposed_edges: Array = exposed_result[&"definition"].edges
	_expect(exposed_edges.size() == 1, "baker: Structure with a walkable neighbor should still emit an Edge")
	if exposed_edges.size() == 1:
		var exposed_edge: MapEdgeData = exposed_edges[0]
		var source_is_a := exposed_edge.cell_a == exposed_edge.source_cell
		var source_profile := exposed_edge.cover_profile_a if source_is_a else exposed_edge.cover_profile_b
		var neighbor_profile := exposed_edge.cover_profile_b if source_is_a else exposed_edge.cover_profile_a
		_expect(source_profile.cover_level == 0 and neighbor_profile.cover_level == 1, "baker: exposed Structure Edge should retain source NONE and neighbor HALF")

	var all_walkable_neighbors := {
		source_cell: _test_cell_data(source_cell, false),
		Vector3i(0, 0, -1): _test_cell_data(Vector3i(0, 0, -1), true),
		Vector3i(1, 0, 0): _test_cell_data(Vector3i(1, 0, 0), true),
		Vector3i(0, 0, 1): _test_cell_data(Vector3i(0, 0, 1), true),
		Vector3i(-1, 0, 0): _test_cell_data(Vector3i(-1, 0, 0), true),
	}
	var all_four_candidates: Array = []
	for contrib in low_cover.edge_contributions:
		all_four_candidates.append(_test_structure_candidate(source_cell, low_cover, contrib))
	var all_four_result := _collect_test_edges(null, all_four_candidates, 0, all_walkable_neighbors)
	var all_four_edges: Array = all_four_result[&"definition"].edges
	_expect(all_four_edges.size() == 4, "baker: LowCover surrounded by walkable cells should emit all four edges")
	for edge in all_four_edges:
		var edge_data := edge as MapEdgeData
		var source_is_a := edge_data.cell_a == edge_data.source_cell
		var source_profile := edge_data.cover_profile_a if source_is_a else edge_data.cover_profile_b
		var neighbor_profile := edge_data.cover_profile_b if source_is_a else edge_data.cover_profile_a
		_expect(source_profile.cover_level == 0 and neighbor_profile.cover_level == 1, "baker: all four LowCover edges should have neighbor HALF cover")


func _test_cell_data(coordinate: Vector3i, walkable: bool) -> MapCellData:
	var result := MapCellData.new()
	result.coordinate = coordinate
	result.walkable = walkable
	return result


func _test_structure_candidate(source_cell: Vector3i, definition: TacticalCellTileDefinition, contribution: TacticalLocalEdgeContribution) -> Dictionary:
	return {
		&"source_cell": source_cell,
		&"item_id": definition.mesh_item_id,
		&"placeable_id": definition.placeable_id,
		&"contribution": contribution,
		&"basis": Basis.IDENTITY,
	}


func _test_baker_merge_precedence() -> void:
	var source_cell := Vector3i.ZERO
	var north_cell := Vector3i(0, 0, -1)
	var structure_contribution := TacticalLocalEdgeContribution.new()
	structure_contribution.local_direction = TacticalLocalEdgeContribution.LocalDirection.NORTH
	structure_contribution.edge_rules = _test_edge_rules(0, 1)
	var structure_candidate := {
		&"source_cell": source_cell,
		&"item_id": 11,
		&"placeable_id": &"synthetic.structure",
		&"contribution": structure_contribution,
		&"basis": Basis.IDENTITY,
	}
	var explicit := TacticalEdgePlacement.new()
	explicit.edge_key = TacticalEdgeKey.from_cells(source_cell, north_cell)
	explicit.placeable_id = &"synthetic.explicit"
	explicit.rules = _test_edge_rules(2, 0)
	var data := TacticalMapAuthoringData.new()
	data.edge_placements.append(explicit)
	var collected := _collect_test_edges(data, [structure_candidate], 1)
	var edges: Array = collected[&"definition"].edges
	_expect(edges.size() == 1 and edges[0].source_type == &"explicit", "baker: explicit Edge should outrank Structure and legacy mask")
	_expect((collected[&"errors"] as Array).is_empty(), "baker: higher-priority merge should not error")
	_expect(data.edge_placements.size() == 1, "baker: merge must not write derived edges into authoring data")
	_expect(_contains_text(collected[&"diagnostics"], "TMB-062"), "baker: lower-priority override should be diagnosed")

	var duplicate_a := TacticalEdgePlacement.new()
	duplicate_a.edge_key = explicit.edge_key
	duplicate_a.placeable_id = &"synthetic.same"
	duplicate_a.rules = _test_edge_rules(1, 0)
	var duplicate_b := TacticalEdgePlacement.new()
	duplicate_b.edge_key = explicit.edge_key
	duplicate_b.placeable_id = duplicate_a.placeable_id
	duplicate_b.rules = _test_edge_rules(1, 0)
	var duplicate_data := TacticalMapAuthoringData.new()
	duplicate_data.edge_placements = [duplicate_a, duplicate_b]
	var duplicate_result := _collect_test_edges(duplicate_data, [], 0)
	_expect((duplicate_result[&"definition"].edges as Array).size() == 1, "baker: equivalent same-priority edges should deduplicate")
	_expect((duplicate_result[&"errors"] as Array).is_empty(), "baker: equivalent same-priority edges should not error")
	_expect(_contains_text(duplicate_result[&"diagnostics"], "TMB-066"), "baker: equivalent same-priority edges should report deduplication")

	var conflict_a := TacticalEdgePlacement.new()
	conflict_a.edge_key = explicit.edge_key
	conflict_a.placeable_id = &"synthetic.conflict.a"
	conflict_a.rules = _test_edge_rules(1, 0)
	var conflict_b := TacticalEdgePlacement.new()
	conflict_b.edge_key = explicit.edge_key
	conflict_b.placeable_id = &"synthetic.conflict.b"
	conflict_b.rules = _test_edge_rules(2, 0)
	var conflict_data := TacticalMapAuthoringData.new()
	conflict_data.edge_placements = [conflict_b, conflict_a]
	var conflict_result := _collect_test_edges(conflict_data, [], 0)
	_expect(not (conflict_result[&"errors"] as Array).is_empty(), "baker: conflicting same-priority edges should error")
	_expect(_contains_text(conflict_result[&"errors"], "TMB-068"), "baker: conflict should use the stable TMB-068 code")

	var legacy_result := _collect_test_edges(null, [], 1)
	var legacy_edges: Array = legacy_result[&"definition"].edges
	_expect(legacy_edges.size() == 1 and legacy_edges[0].source_type == &"legacy_cover_mask", "baker: legacy cover mask should derive an Edge")
	if legacy_edges.size() == 1:
		var legacy_edge: MapEdgeData = legacy_edges[0]
		var legacy_source_is_a := legacy_edge.cell_a == legacy_edge.source_cell
		var legacy_source_profile := legacy_edge.cover_profile_a if legacy_source_is_a else legacy_edge.cover_profile_b
		var legacy_neighbor_profile := legacy_edge.cover_profile_b if legacy_source_is_a else legacy_edge.cover_profile_a
		_expect(legacy_source_profile.cover_level == 1 and legacy_neighbor_profile.cover_level == 0, "baker: legacy mask should map source HALF and neighbor NONE")

	var invalid_definition := TacticalMapDefinition.new()
	var invalid_cell := MapCellData.new()
	invalid_cell.coordinate = Vector3i.ZERO
	invalid_definition.cells.append(invalid_cell)
	var invalid_edge := MapEdgeData.new()
	invalid_edge.cell_a = Vector3i.ZERO
	invalid_edge.cell_b = Vector3i.ZERO
	invalid_definition.edges.append(invalid_edge)
	var invalid_errors: Array[String] = []
	var invalid_warnings: Array[String] = []
	var invalid_diagnostics: Array[Dictionary] = []
	TacticalMapBaker._validate_definition(invalid_definition, invalid_errors, invalid_warnings, invalid_diagnostics)
	_expect(_contains_text(invalid_errors, "TMB-067"), "baker: non-adjacent Edge validation should use TMB-067")


func _test_profile_warning_consumption() -> void:
	var none_warning := TacticalCoverProfile.new()
	none_warning.cover_id = &"synthetic.none.warning"
	none_warning.cover_level = 0
	none_warning.damage_reduction_ratio = 0.25
	var half_warning := TacticalCoverProfile.new()
	half_warning.cover_id = &"synthetic.half.warning"
	half_warning.cover_level = 1
	half_warning.damage_reduction_ratio = 0.0
	_expect(none_warning.validation_warnings().size() == 1, "profile: NONE non-zero reduction should expose one warning")
	_expect(half_warning.validation_warnings().size() == 1, "profile: HALF zero reduction should expose one warning")
	var rules := TacticalEdgeRules.new()
	rules.cover_profile_a = none_warning
	rules.cover_profile_b = half_warning
	rules.cover_a = TacticalEdgeRules.CoverLevel.NONE
	rules.cover_b = TacticalEdgeRules.CoverLevel.HALF
	var placement := TacticalEdgePlacement.new()
	placement.edge_key = TacticalEdgeKey.from_cells(Vector3i.ZERO, Vector3i(1, 0, 0))
	placement.placeable_id = &"synthetic.profile.warning"
	placement.rules = rules
	var data := TacticalMapAuthoringData.new()
	data.edge_placements.append(placement)
	var collected := _collect_test_edges(data, [], 0)
	_expect((collected[&"errors"] as Array).is_empty(), "profile: semantic warnings should not make a valid profile an error")
	_expect((collected[&"warnings"] as Array).size() == 2, "profile: Baker should consume both profile semantic warnings")
	_expect(_contains_text(collected[&"warnings"], "TMB-065"), "profile: Baker warning should use stable TMB-065 code")
	var warning_diagnostics := 0
	for diagnostic in collected[&"diagnostics"]:
		if diagnostic is Dictionary and diagnostic.get(&"code", &"") == &"TMB-065":
			warning_diagnostics += 1
	_expect(warning_diagnostics == 2, "profile: both TMB-065 warnings should be structured diagnostics")


func _test_four_way_cover_runtime() -> void:
	var low_cover := load("res://resources/map_tiles/definitions/structure/low_cover.tres") as TacticalCellTileDefinition
	if low_cover == null:
		return
	var center_cell := Vector3i(1, 0, 1)
	var cells: Dictionary = {}
	for x in range(3):
		for z in range(3):
			var coord := Vector3i(x, 0, z)
			var cell_data := _test_cell_data(coord, coord != center_cell)
			cells[coord] = cell_data
	var candidates: Array = []
	for contrib in low_cover.edge_contributions:
		candidates.append(_test_structure_candidate(center_cell, low_cover, contrib))
	var result := _collect_test_edges(null, candidates, 0, cells)
	var definition: TacticalMapDefinition = result[&"definition"]
	_expect(definition != null and definition.edges.size() == 4, "runtime 4-way: definition should contain 4 edges")
	if definition == null:
		return
	for x in range(3):
		for z in range(3):
			definition.cells.append(cells[Vector3i(x, 0, z)])
	definition.footprint_size = Vector2i(3, 3)
	definition.level_count = 1
	var grid := GridModel.new()
	_expect(grid.configure_from_definition(definition), "runtime 4-way: grid should configure from definition")

	var settings := CoverCombatSettings.load_default()
	# 1. Target North (1, 0, 0), Attacker South (1, 0, 2)
	var query_north := CoverQuery.query(Vector3i(1, 0, 2), Vector3i(1, 0, 0), grid, null, settings)
	_expect(query_north.has_cover and query_north.cover_level == 1 and query_north.cover_profile_id == &"cover.half", "runtime 4-way: target at North should have HALF cover")

	# 2. Target East (2, 0, 1), Attacker West (0, 0, 1)
	var query_east := CoverQuery.query(Vector3i(0, 0, 1), Vector3i(2, 0, 1), grid, null, settings)
	_expect(query_east.has_cover and query_east.cover_level == 1 and query_east.cover_profile_id == &"cover.half", "runtime 4-way: target at East should have HALF cover")

	# 3. Target South (1, 0, 2), Attacker North (1, 0, 0)
	var query_south := CoverQuery.query(Vector3i(1, 0, 0), Vector3i(1, 0, 2), grid, null, settings)
	_expect(query_south.has_cover and query_south.cover_level == 1 and query_south.cover_profile_id == &"cover.half", "runtime 4-way: target at South should have HALF cover")

	# 4. Target West (0, 0, 1), Attacker East (2, 0, 1)
	var query_west := CoverQuery.query(Vector3i(2, 0, 1), Vector3i(0, 0, 1), grid, null, settings)
	_expect(query_west.has_cover and query_west.cover_level == 1 and query_west.cover_profile_id == &"cover.half", "runtime 4-way: target at West should have HALF cover")


func _collect_test_edges(
	data: TacticalMapAuthoringData,
	structure_candidates: Array,
	cover_mask: int,
	extra_cells: Dictionary = {},
	base_walkable: bool = true
) -> Dictionary:
	var author := TacticalMapAuthor.new()
	author.authoring_data = data
	var cell := MapCellData.new()
	cell.coordinate = Vector3i.ZERO
	cell.cover_mask = cover_mask
	cell.walkable = base_walkable
	var cells := {cell.coordinate: cell}
	var floor_content := {cell.coordinate: {&"placeable_id": &"synthetic.floor"}}
	for coordinate in extra_cells:
		cells[coordinate] = extra_cells[coordinate]
		floor_content[coordinate] = {&"placeable_id": &"synthetic.floor"}
	var definition := TacticalMapDefinition.new()
	var cell_compile := {
		&"cells": cells,
		&"floor_content": floor_content,
		&"structure_edge_candidates": structure_candidates,
	}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var diagnostics: Array[Dictionary] = []
	TacticalMapBaker._collect_edges(author, cell_compile, definition, errors, warnings, diagnostics)
	author.free()
	return {
		&"definition": definition,
		&"errors": errors,
		&"warnings": warnings,
		&"diagnostics": diagnostics,
	}


func _test_edge_rules(source_level: int, neighbor_level: int) -> TacticalEdgeRules:
	var result := TacticalEdgeRules.new()
	result.cover_a = source_level
	result.cover_b = neighbor_level
	result.cover_profile_a = load("res://resources/combat/cover_profiles/cover_%s.tres" % ["none", "half", "full"][source_level])
	result.cover_profile_b = load("res://resources/combat/cover_profiles/cover_%s.tres" % ["none", "half", "full"][neighbor_level])
	return result


func _contains_text(values: Array, text: String) -> bool:
	for value in values:
		if value is Dictionary and (str(value.get(&"code", "")).contains(text) or str(value.get(&"message", "")).contains(text)):
			return true
		if str(value).contains(text):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_COVER_DATA_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_COVER_DATA_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
