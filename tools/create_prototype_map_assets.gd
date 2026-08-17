extends SceneTree

const OUTPUT_LIBRARY := "res://assets/prototype/grid/prototype_mesh_library.tres"
const OUTPUT_CATALOG := "res://assets/prototype/grid/prototype_tile_catalog.tres"
const OUTPUT_DEFINITION := "res://resources/maps/prototype_map.tres"
const OUTPUT_AUTHOR_SCENE := "res://scenes/map_authoring/prototype_map_authoring.tscn"
const SKIP_GRID_ASSET_SAVE_FLAG := "--skip-grid-asset-save"
const LOOT_TABLE_SUPPLY: LootTableDefinition = preload("res://resources/loot/loot_table_supply.tres")
const LOOT_TABLE_WAREHOUSE: LootTableDefinition = preload("res://resources/loot/loot_table_warehouse.tres")
const LOOT_TABLE_OUTPOST: LootTableDefinition = preload("res://resources/loot/loot_table_outpost.tres")
const LOOT_TABLE_HIGH_VALUE: LootTableDefinition = preload("res://resources/loot/loot_table_high_value.tres")
const WEAPON_ASSAULT_RIFLE: WeaponDefinition = preload("res://resources/weapons/assault_rifle.tres")
const WEAPON_SHOTGUN: WeaponDefinition = preload("res://resources/weapons/shotgun.tres")
const WEAPON_CARBINE: WeaponDefinition = preload("res://resources/weapons/carbine.tres")
const ARCHETYPE_PLAYER_ALPHA: UnitArchetype = preload("res://resources/units/player_alpha.tres")
const ARCHETYPE_PLAYER_BRAVO: UnitArchetype = preload("res://resources/units/player_bravo.tres")
const ARCHETYPE_RIFLEMAN: UnitArchetype = preload("res://resources/units/rifleman.tres")
const ARCHETYPE_ASSAULT: UnitArchetype = preload("res://resources/units/assault.tres")


func _init() -> void:
	var library := _create_library()
	if not OS.get_cmdline_user_args().has(SKIP_GRID_ASSET_SAVE_FLAG):
		if ResourceSaver.save(library, OUTPUT_LIBRARY) != OK:
			push_error("Failed to save prototype MeshLibrary")
			quit(1)
			return
	var catalog := _create_catalog()
	if not OS.get_cmdline_user_args().has(SKIP_GRID_ASSET_SAVE_FLAG):
		if ResourceSaver.save(catalog, OUTPUT_CATALOG) != OK:
			push_error("Failed to save prototype tile catalog")
			quit(1)
			return
	var author := _create_author_scene(library, catalog)
	var bake_result := TacticalMapBaker.build(author)
	if not (bake_result[&"errors"] as Array[String]).is_empty():
		for error in bake_result[&"errors"]:
			push_error(error)
		quit(1)
		return
	if ResourceSaver.save(bake_result[&"definition"], OUTPUT_DEFINITION) != OK:
		push_error("Failed to save prototype map definition")
		quit(1)
		return
	var packed := PackedScene.new()
	if packed.pack(author) != OK or ResourceSaver.save(packed, OUTPUT_AUTHOR_SCENE) != OK:
		push_error("Failed to save prototype authoring scene")
		quit(1)
		return
	print("PROTOTYPE_MAP_ASSETS: PASS")
	quit(0)


func _create_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	_add_mesh_item(library, 0, "Floor", _box_mesh(Vector3(2.0, 0.2, 2.0), "res://assets/prototype/materials/ground.tres"), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.1, 0.0)), Vector3(2.0, 0.2, 2.0))
	_add_mesh_item(library, 1, "FloorAlt", _box_mesh(Vector3(2.0, 0.2, 2.0), "res://assets/prototype/materials/ground_alt.tres"), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.1, 0.0)), Vector3(2.0, 0.2, 2.0))
	_add_mesh_item(library, 2, "Wall", _box_mesh(Vector3(2.0, 1.6, 2.0), "res://assets/prototype/materials/wall.tres"), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0)), Vector3(2.0, 1.6, 2.0))
	_add_mesh_item(library, 3, "LowCover", _box_mesh(Vector3(1.6, 0.7, 0.55), "res://assets/prototype/materials/low_cover.tres"), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, 0.0)), Vector3(1.6, 0.7, 0.55))
	return library


func _add_mesh_item(library: MeshLibrary, id: int, name: String, mesh: Mesh, transform: Transform3D, shape_size: Vector3) -> void:
	library.create_item(id)
	library.set_item_name(id, name)
	library.set_item_mesh(id, mesh)
	library.set_item_mesh_transform(id, transform)
	var shape := BoxShape3D.new()
	shape.size = shape_size
	library.set_item_shapes(id, [shape, transform])


func _box_mesh(size: Vector3, material_path: String) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = load(material_path)
	return mesh


func _create_catalog() -> MapTileCatalog:
	var catalog := MapTileCatalog.new()
	catalog.rules.append(_rule(MapTileRule.Layer.FLOOR, 0, &"floor", true, 1, false, 0.0, 0))
	catalog.rules.append(_rule(MapTileRule.Layer.FLOOR, 1, &"floor_alt", true, 1, false, 0.0, 0))
	catalog.rules.append(_rule(MapTileRule.Layer.STRUCTURE, 2, &"wall", false, 1, true, 1.6, 0))
	catalog.rules.append(_rule(MapTileRule.Layer.STRUCTURE, 3, &"low_cover", false, 1, false, 0.7, 1))
	return catalog


func _rule(layer: MapTileRule.Layer, item_id: int, tile_id: StringName, walkable: bool, cost: int, blocks_los: bool, height: float, cover: int) -> MapTileRule:
	var rule := MapTileRule.new()
	rule.layer = layer
	rule.item_id = item_id
	rule.tile_id = tile_id
	rule.walkable = walkable
	rule.move_cost = cost
	rule.blocks_los = blocks_los
	rule.occluder_height = height
	rule.cover_mask = cover
	return rule


func _create_author_scene(library: MeshLibrary, catalog: MapTileCatalog) -> TacticalMapAuthor:
	var author := TacticalMapAuthor.new()
	author.name = "PrototypeMapAuthoring"
	author.map_id = &"prototype_map"
	author.footprint_size = Vector2i(12, 10)
	author.level_count = 2
	author.cell_dimensions = Vector3(2.0, 2.0, 2.0)
	author.tile_catalog = catalog
	author.output_resource_path = OUTPUT_DEFINITION

	var floor_grid := GridMap.new()
	floor_grid.name = "FloorGrid"
	floor_grid.mesh_library = library
	floor_grid.cell_size = author.cell_dimensions
	floor_grid.collision_layer = 1
	floor_grid.collision_mask = 0
	_add_owned(author, floor_grid)
	for z in range(10):
		for x in range(12):
			floor_grid.set_cell_item(Vector3i(x, 0, z), (x + z) % 2)
	# A small upper platform demonstrates stacked X/Z surfaces.
	for z in range(0, 3):
		for x in range(8, 11):
			floor_grid.set_cell_item(Vector3i(x, 1, z), (x + z) % 2)

	var structure_grid := GridMap.new()
	structure_grid.name = "StructureGrid"
	structure_grid.mesh_library = library
	structure_grid.cell_size = author.cell_dimensions
	structure_grid.collision_layer = 2
	structure_grid.collision_mask = 0
	_add_owned(author, structure_grid)
	for cell in [
		Vector3i(4, 0, 1), Vector3i(4, 0, 2), Vector3i(4, 0, 3),
		Vector3i(4, 0, 5), Vector3i(4, 0, 6), Vector3i(4, 0, 7),
		Vector3i(8, 0, 3), Vector3i(8, 0, 4), Vector3i(8, 0, 5),
	]:
		structure_grid.set_cell_item(cell, 2)
	for cell in [Vector3i(2, 0, 4), Vector3i(6, 0, 2), Vector3i(6, 0, 6), Vector3i(9, 0, 7)]:
		structure_grid.set_cell_item(cell, 3)

	var decoration_grid := GridMap.new()
	decoration_grid.name = "DecorationGrid"
	decoration_grid.mesh_library = library
	decoration_grid.cell_size = author.cell_dimensions
	decoration_grid.collision_layer = 2
	decoration_grid.collision_mask = 0
	_add_owned(author, decoration_grid)
	for x in range(12):
		decoration_grid.set_cell_item(Vector3i(x, 0, -1), 2)
		decoration_grid.set_cell_item(Vector3i(x, 0, 10), 2)
	for z in range(10):
		decoration_grid.set_cell_item(Vector3i(-1, 0, z), 2)
		decoration_grid.set_cell_item(Vector3i(12, 0, z), 2)

	var objects := Node3D.new()
	objects.name = "Objects"
	_add_owned(author, objects)
	_add_object_marker(author, objects, &"extraction", MapObjectPlacement.Kind.EXTRACTION, Vector3i(11, 0, 8), "res://scenes/prototype/environment/prototype_extraction_marker.tscn", false, false)
	_add_object_marker(author, objects, &"loot_1", MapObjectPlacement.Kind.LOOT, Vector3i(1, 0, 3), "res://scenes/prototype/environment/prototype_loot_crate.tscn", true, false, LOOT_TABLE_SUPPLY, 101)
	_add_object_marker(author, objects, &"loot_2", MapObjectPlacement.Kind.LOOT, Vector3i(7, 0, 4), "res://scenes/prototype/environment/prototype_loot_crate.tscn", true, false, LOOT_TABLE_WAREHOUSE, 202)
	_add_object_marker(author, objects, &"loot_3", MapObjectPlacement.Kind.LOOT, Vector3i(10, 0, 6), "res://scenes/prototype/environment/prototype_loot_crate.tscn", true, false, LOOT_TABLE_OUTPOST, 303)
	_add_object_marker(author, objects, &"loot_high", MapObjectPlacement.Kind.LOOT, Vector3i(10, 1, 1), "res://scenes/prototype/environment/prototype_loot_crate.tscn", true, false, LOOT_TABLE_HIGH_VALUE, 404)
	_add_object_marker(author, objects, &"barrel_1", MapObjectPlacement.Kind.EXPLOSIVE, Vector3i(3, 0, 7), "res://scenes/prototype/environment/prototype_explosive_barrel.tscn", true, false)
	_add_object_marker(author, objects, &"barrel_2", MapObjectPlacement.Kind.EXPLOSIVE, Vector3i(10, 0, 2), "res://scenes/prototype/environment/prototype_explosive_barrel.tscn", true, false)

	var spawns := Node3D.new()
	spawns.name = "Spawns"
	_add_owned(author, spawns)
	_add_spawn_marker(author, spawns, &"PlayerAlpha", &"player", Vector3i(1, 0, 1), Color("4f9dff"), Vector2i.DOWN, &"", ARCHETYPE_PLAYER_ALPHA, WEAPON_ASSAULT_RIFLE)
	_add_spawn_marker(author, spawns, &"PlayerBravo", &"player", Vector3i(2, 0, 1), Color("6cadff"), Vector2i.DOWN, &"", ARCHETYPE_PLAYER_BRAVO, WEAPON_SHOTGUN)
	_add_spawn_marker(author, spawns, &"EnemyScout", &"enemy", Vector3i(7, 0, 2), Color("ef5b5b"), Vector2i.LEFT, &"scout_patrol", ARCHETYPE_RIFLEMAN, WEAPON_CARBINE, &"warehouse")
	_add_spawn_marker(author, spawns, &"EnemyRifleman_2", &"enemy", Vector3i(7, 0, 1), Color("e76565"), Vector2i.LEFT, &"rifleman_patrol", ARCHETYPE_RIFLEMAN, WEAPON_CARBINE, &"warehouse")
	_add_spawn_marker(author, spawns, &"EnemyAssault_1", &"enemy", Vector3i(6, 0, 3), Color("f06a4d"), Vector2i.LEFT, &"warehouse_assault_patrol", ARCHETYPE_ASSAULT, WEAPON_SHOTGUN, &"warehouse")
	_add_spawn_marker(author, spawns, &"EnemyGuard", &"enemy", Vector3i(10, 0, 7), Color("d44b4b"), Vector2i.LEFT, &"guard_patrol", ARCHETYPE_RIFLEMAN, WEAPON_CARBINE, &"outpost")
	_add_spawn_marker(author, spawns, &"EnemyAssault_2", &"enemy", Vector3i(9, 0, 4), Color("eb604d"), Vector2i.LEFT, &"outpost_assault_patrol", ARCHETYPE_ASSAULT, WEAPON_SHOTGUN, &"outpost")
	_add_spawn_marker(author, spawns, &"EnemyAssault_3", &"enemy", Vector3i(10, 0, 4), Color("f0784f"), Vector2i.LEFT, &"outpost_flank_patrol", ARCHETYPE_ASSAULT, WEAPON_SHOTGUN, &"outpost")

	var routes := Node3D.new()
	routes.name = "PatrolRoutes"
	_add_owned(author, routes)
	_add_route_marker(author, routes, &"scout_patrol", [Vector3i(7, 0, 2), Vector3i(7, 0, 1), Vector3i(6, 0, 1)], false)
	_add_route_marker(author, routes, &"rifleman_patrol", [Vector3i(7, 0, 1), Vector3i(7, 0, 0), Vector3i(6, 0, 0)], true)
	_add_route_marker(author, routes, &"warehouse_assault_patrol", [Vector3i(6, 0, 3), Vector3i(6, 0, 4), Vector3i(5, 0, 4)], true)
	_add_route_marker(author, routes, &"guard_patrol", [Vector3i(10, 0, 7), Vector3i(10, 0, 8), Vector3i(9, 0, 8)], true)
	_add_route_marker(author, routes, &"outpost_assault_patrol", [Vector3i(9, 0, 4), Vector3i(9, 0, 5), Vector3i(10, 0, 5)], true)
	_add_route_marker(author, routes, &"outpost_flank_patrol", [Vector3i(10, 0, 4), Vector3i(11, 0, 4), Vector3i(10, 0, 5)], true)

	var links := Node3D.new()
	links.name = "TraversalLinks"
	_add_owned(author, links)
	var stairs := TraversalLink3D.new()
	stairs.name = "StairsToUpperPlatform"
	stairs.from_cell = Vector3i(7, 0, 1)
	stairs.to_cell = Vector3i(8, 1, 1)
	stairs.move_cost = 2
	stairs.bidirectional = true
	_add_owned(links, stairs, author)
	_add_ramp_visual(author)
	_add_lighting(author)
	return author


func _add_spawn_marker(author: TacticalMapAuthor, parent: Node3D, unit_name: StringName, faction: StringName, cell: Vector3i, color: Color, facing: Vector2i, route_id: StringName = &"", archetype: UnitArchetype = null, weapon: WeaponDefinition = null, encounter_id: StringName = &"") -> void:
	var marker := UnitSpawnMarker3D.new()
	marker.name = String(unit_name)
	marker.unit_name = unit_name
	marker.faction = String(faction)
	marker.cell = cell
	marker.position = author.cell_to_local(cell)
	marker.visual_color = color
	marker.facing = facing
	marker.patrol_route_id = route_id
	marker.archetype = archetype
	marker.weapon = weapon
	marker.encounter_id = encounter_id
	_add_owned(parent, marker, author)


func _add_route_marker(author: TacticalMapAuthor, parent: Node3D, route_id: StringName, points: Array[Vector3i], loop: bool) -> void:
	var route := PatrolRoute3D.new()
	route.name = String(route_id)
	route.route_id = route_id
	route.points = points
	route.loop = loop
	_add_owned(parent, route, author)


func _add_object_marker(author: TacticalMapAuthor, parent: Node3D, id: StringName, kind: MapObjectPlacement.Kind, cell: Vector3i, scene_path: String, blocks_movement: bool, blocks_los: bool, loot_table: LootTableDefinition = null, loot_seed: int = -1) -> void:
	var marker := MapObjectMarker3D.new()
	marker.name = String(id)
	marker.object_id = id
	marker.kind = kind
	marker.cell = cell
	marker.position = author.cell_to_local(cell)
	marker.scene = load(scene_path)
	marker.blocks_movement = blocks_movement
	marker.blocks_los = blocks_los
	marker.loot_table = loot_table
	marker.loot_seed = loot_seed
	_add_owned(parent, marker, author)
func _add_ramp_visual(author: TacticalMapAuthor) -> void:
	var visuals := Node3D.new()
	visuals.name = "TraversalVisuals"
	_add_owned(author, visuals)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "StairsToUpperPlatform"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.82, 0.18, 1.7)
	mesh.material = load("res://assets/prototype/materials/low_cover.tres")
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(15.0, 1.0, 2.0)
	mesh_instance.rotation.z = deg_to_rad(45.0)
	_add_owned(visuals, mesh_instance, author)
	var body := StaticBody3D.new()
	body.name = "RampBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = mesh_instance.position
	body.rotation = mesh_instance.rotation
	_add_owned(visuals, body, author)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	shape_node.shape = shape
	_add_owned(body, shape_node, author)


func _add_lighting(author: TacticalMapAuthor) -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.028, 0.045, 1)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.4, 0.52, 1)
	environment.ambient_light_energy = 0.7
	world_environment.environment = environment
	_add_owned(author, world_environment)
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	key.light_color = Color(0.86, 0.92, 1.0, 1.0)
	key.light_energy = 1.2
	key.shadow_enabled = true
	_add_owned(author, key)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-30.0, 145.0, 0.0)
	fill.light_color = Color(0.42, 0.52, 0.72, 1.0)
	fill.light_energy = 0.25
	fill.shadow_enabled = false
	_add_owned(author, fill)


func _add_owned(parent: Node, child: Node, scene_owner: Node = null) -> void:
	parent.add_child(child)
	child.owner = scene_owner if scene_owner != null else parent
