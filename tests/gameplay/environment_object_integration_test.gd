extends SceneTree

## Scene-free environment gameplay coverage.  Everything below is built from
## in-memory Definitions, placements, runtime states and View nodes; no formal
## map or main scene is loaded.

const ControllerScript = preload("res://scripts/gameplay/prototype_controller.gd")
const UnitScript = preload("res://scripts/gameplay/prototype_unit.gd")
const UnitRuntimeStateScript = preload("res://scripts/core/units/unit_runtime_state.gd")
const UnitArchetypeScript = preload("res://scripts/core/units/unit_archetype.gd")
const WeaponDefinitionScript = preload("res://scripts/core/combat/weapon_definition.gd")
const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")
const ObjectDefinitionScript = preload("res://scripts/core/map/tactical_object_definition.gd")
const PlacementScript = preload("res://scripts/core/map/map_object_placement.gd")
const MapDefinitionScript = preload("res://scripts/core/map/tactical_map_definition.gd")
const MapCellDataScript = preload("res://scripts/core/map/map_cell_data.gd")
const ManifestScript = preload("res://scripts/core/content/game_content_manifest.gd")
const RegistryScript = preload("res://scripts/core/content/game_definition_registry.gd")
const RuntimeRegistryScript = preload("res://scripts/core/runtime/runtime_instance_registry.gd")
const IdGeneratorScript = preload("res://scripts/core/runtime/instance_id_generator.gd")
const EnvironmentFactoryScript = preload("res://scripts/core/environment/environment_object_factory.gd")
const EnvironmentStateScript = preload("res://scripts/core/environment/environment_object_runtime_state.gd")
const ExplosionEffectScript = preload("res://scripts/core/environment/explosion_effect_definition.gd")
const CoverSettingsScript = preload("res://scripts/core/cover/cover_combat_settings.gd")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")
const TurnManagerScript = preload("res://scripts/core/turn/turn_manager.gd")
const EnvironmentViewScript = preload("res://scripts/gameplay/environment/environment_object_view.gd")

const PLAYER_ID: StringName = &"environment_test_player"
const ENEMY_ID: StringName = &"environment_test_enemy"

var _failures: Array[String] = []
var _root: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_view_scene_and_collision_toggle()
	await _test_controller_attack_chain_and_dynamic_rules()
	await _test_controller_environment_undo()
	await _test_stale_environment_view_reference_cleanup()
	_finish()


func _test_view_scene_and_collision_toggle() -> void:
	var packed := load("res://scenes/prototype/environment/prototype_explosive_barrel.tscn") as PackedScene
	_expect(packed != null, "view: barrel PackedScene should load")
	if packed == null:
		return
	var view := packed.instantiate() as EnvironmentObjectView
	_expect(view != null, "view: barrel root should use EnvironmentObjectView")
	if view == null:
		return
	_root = Node3D.new()
	_root.name = "EnvironmentIntegrationRoot"
	get_root().add_child(_root)
	_root.add_child(view)
	await process_frame
	var body := view.get_node_or_null("BarrelBody") as StaticBody3D
	var shape := view.get_node_or_null("BarrelBody/CollisionShape3D") as CollisionShape3D
	_expect(body != null and shape != null, "view: barrel should retain StaticBody3D and CollisionShape3D")
	if body == null or shape == null:
		view.queue_free()
		return
	_expect(body.collision_layer == 2 and body.collision_mask == 0, "view: initial collision contract should be preserved")
	_expect(not shape.disabled and view.visible, "view: active object should be visible and collidable")
	view.set_runtime_active(false)
	_expect(not view.visible and shape.disabled and body.collision_layer == 0 and body.collision_mask == 0, "view: destroyed object should hide and disable collision")
	view.set_runtime_active(true)
	_expect(view.visible and not shape.disabled and body.collision_layer == 2, "view: restoring active state should restore presentation collision")
	view.queue_free()
	await process_frame
	_root.queue_free()
	_root = null


func _test_controller_attack_chain_and_dynamic_rules() -> void:
	var fixture := _make_controller_fixture(true)
	var controller: PrototypeController = fixture[&"controller"]
	var player: PrototypeUnit = fixture[&"player"]
	var enemy: PrototypeUnit = fixture[&"enemy"]
	var primary := controller.environment_objects_by_placement_id[&"barrel_primary"] as EnvironmentObjectRuntimeState
	var secondary := controller.environment_objects_by_placement_id[&"barrel_secondary"] as EnvironmentObjectRuntimeState
	_expect(primary != null and secondary != null, "attack: Controller should index environment placements through EnvironmentObjectFactory")
	if primary == null or secondary == null:
		_cleanup_fixture(fixture)
		return
	secondary.current_hp = 4
	var before_ap := player.current_action_points
	var result: ActionResult = await controller.attack_environment_object(player, primary)
	_expect(result != null and result.success and result.action_type == &"attack", "attack: environment target should use successful ActionExecutor attack")
	_expect(result != null and result.damage == 10, "attack: deterministic weapon damage should apply once")
	_expect(player.current_action_points == before_ap - 1, "attack: AP should commit exactly once after handler success")
	_expect(primary.destroyed and not primary.active, "attack: primary barrel should be destroyed at zero HP")
	_expect(secondary.destroyed and not secondary.active, "attack: allow_chain should destroy adjacent barrel once")
	_expect(enemy.current_hp == enemy.max_hp - 4, "attack: explosion should affect an enemy candidate directly")
	_expect(controller.grid.is_walkable(primary.cell) and controller.grid.is_walkable(secondary.cell), "attack: destroyed blockers should restore walkability")
	_expect(not controller.grid.cell_blocks_los(primary.cell), "attack: destroyed object should remove its dynamic LOS blocker")
	_expect(result != null and bool(result.metadata.get(&"destroyed", false)), "attack: result metadata should observe destruction")
	_expect(int(result.metadata.get(&"chain_count", 0)) == 1, "attack: chain metadata should report one chained object")

	var blocked_placement := _make_placement(&"barrel_los_blocked", fixture[&"definition"].placeable_id, Vector3i(2, 0, 1))
	blocked_placement.kind = PlacementScript.Kind.EXPLOSIVE
	var blocked_state: EnvironmentObjectRuntimeState = EnvironmentStateScript.new(
		StringName("environment_test:environment:%s:barrel_los_blocked" % fixture[&"map_definition"].map_id),
		fixture[&"definition"],
		blocked_placement
	)
	controller.object_placements[blocked_placement.object_id] = blocked_placement
	controller.environment_objects_by_placement_id[blocked_placement.object_id] = blocked_state
	controller.environment_objects_by_instance_id[blocked_state.instance_id] = blocked_state
	controller._rebuild_dynamic_environment_rules()
	controller.opaque_cells[Vector3i(1, 0, 1)] = true
	var blocked_ap := player.current_action_points
	var blocked_feedback_count := player.attack_feedback_play_count
	var blocked_hp := blocked_state.current_hp
	var blocked_result: ActionResult = await controller.attack_environment_object(player, blocked_state)
	_expect(blocked_result != null and not blocked_result.success and blocked_result.reason == &"no_los", "reject: LOS-blocked environment attack should use executor rejection")
	_expect(player.current_action_points == blocked_ap and blocked_state.current_hp == blocked_hp, "reject: LOS block must preserve AP and target HP")
	_expect(player.attack_feedback_play_count == blocked_feedback_count, "reject: LOS block must not play attack feedback")
	controller.opaque_cells.erase(Vector3i(1, 0, 1))
	controller._rebuild_dynamic_environment_rules()

	var fresh_placement := _make_placement(&"barrel_no_ap", fixture[&"definition"].placeable_id, Vector3i(2, 0, 4))
	fresh_placement.kind = PlacementScript.Kind.EXPLOSIVE
	fresh_placement.blocks_movement = true
	controller.object_placements[fresh_placement.object_id] = fresh_placement
	var fresh_state: EnvironmentObjectRuntimeState = EnvironmentStateScript.new(
		StringName("environment_test:environment:%s:barrel_no_ap" % fixture[&"map_definition"].map_id),
		fixture[&"definition"],
		fresh_placement
	)
	controller.environment_objects_by_placement_id[fresh_placement.object_id] = fresh_state
	controller.environment_objects_by_instance_id[fresh_state.instance_id] = fresh_state
	controller._rebuild_dynamic_environment_rules()
	player.runtime_state.current_action_points = 0
	var rejected: ActionResult = await controller.attack_environment_object(player, fresh_state)
	_expect(rejected != null and not rejected.success and rejected.reason == &"no_ap", "reject: insufficient AP should reject environment attack")
	_expect(player.current_action_points == 0 and fresh_state.current_hp == fresh_state.get_max_hp(), "reject: no AP must not mutate target or AP")
	_cleanup_fixture(fixture)


func _test_controller_environment_undo() -> void:
	var fixture := _make_controller_fixture(false)
	var controller: PrototypeController = fixture[&"controller"]
	var state := controller.environment_objects_by_placement_id[&"barrel_primary"] as EnvironmentObjectRuntimeState
	var player: PrototypeUnit = fixture[&"player"]
	controller._configure_undo_manager()
	var started: bool = controller._begin_undo_player_action(player)
	_expect(started, "undo: player environment mutation should start a checkpoint transaction")
	var applied := state.apply_damage(state.current_hp)
	var destruction := controller._resolve_environment_destruction(state)
	controller._rebuild_dynamic_environment_rules()
	controller._finish_undo_player_action(started, applied.success and bool(destruction is Dictionary))
	_expect(state.destroyed and controller.grid.is_walkable(state.cell), "undo: destroyed state should remove its blocker before undo")
	controller._perform_undo(false)
	_expect(state.active and not state.destroyed and state.current_hp == state.get_max_hp(), "undo: runtime object HP/lifecycle should restore")
	_expect(not controller.grid.is_walkable(state.cell), "undo: restored active blocker should restore non-walkability")
	_cleanup_fixture(fixture)


func _test_stale_environment_view_reference_cleanup() -> void:
	var fixture := _make_controller_fixture(false)
	var controller: PrototypeController = fixture[&"controller"]
	var holder := Node3D.new()
	get_root().add_child(holder)
	var freed_view := EnvironmentViewScript.new() as EnvironmentObjectView
	holder.add_child(freed_view)
	await process_frame
	controller.environment_views_by_placement_id[&"barrel_primary"] = freed_view
	controller.environment_visuals_by_placement_id[&"barrel_primary"] = freed_view
	freed_view.free()
	controller._update_object_visibility()
	controller._refresh_highlights()
	_expect(not controller.environment_views_by_placement_id.has(&"barrel_primary"), "stale: freed typed view reference should be cleared before casting")
	_expect(not controller.environment_visuals_by_placement_id.has(&"barrel_primary"), "stale: freed visual reference should be cleared before casting")

	var queued_view := EnvironmentViewScript.new() as EnvironmentObjectView
	holder.add_child(queued_view)
	await process_frame
	controller.environment_views_by_placement_id[&"barrel_primary"] = queued_view
	controller.environment_visuals_by_placement_id[&"barrel_primary"] = queued_view
	queued_view.queue_free()
	controller._update_object_visibility()
	controller._refresh_highlights()
	_expect(not controller.environment_views_by_placement_id.has(&"barrel_primary"), "stale: queued typed view reference should be cleared")
	_expect(not controller.environment_visuals_by_placement_id.has(&"barrel_primary"), "stale: queued visual reference should be cleared")
	holder.queue_free()
	await process_frame
	_cleanup_fixture(fixture)


func _make_controller_fixture(include_chain: bool) -> Dictionary:
	var map_definition: TacticalMapDefinition = _make_map_definition()
	var weapon_definition: WeaponDefinition = _make_weapon()
	var archetype: UnitArchetype = _make_archetype(weapon_definition)
	var object_definition: TacticalObjectDefinition = _make_object_definition(include_chain)
	var primary := _make_placement(&"barrel_primary", object_definition.placeable_id, Vector3i(2, 0, 1))
	primary.kind = PlacementScript.Kind.EXPLOSIVE
	primary.blocks_movement = true
	var secondary := _make_placement(&"barrel_secondary", object_definition.placeable_id, Vector3i(3, 0, 1))
	secondary.kind = PlacementScript.Kind.EXPLOSIVE
	secondary.blocks_movement = true
	map_definition.objects.append(primary)
	if include_chain:
		map_definition.objects.append(secondary)

	var manifest: GameContentManifest = ManifestScript.new()
	manifest.placeable_definitions.append(object_definition)
	var registry: GameDefinitionRegistry = RegistryScript.new()
	var registry_result: Dictionary = registry.configure(manifest)
	_expect(bool(registry_result.get(&"valid", false)), "fixture: synthetic object manifest should validate")
	var runtime_registry: RuntimeInstanceRegistry = RuntimeRegistryScript.new()
	var generator: InstanceIdGenerator = IdGeneratorScript.new(&"environment_test")
	var factory: EnvironmentObjectFactory = EnvironmentFactoryScript.new(registry, runtime_registry, generator)
	var controller: PrototypeController = ControllerScript.new()
	controller.map_definition = map_definition
	controller.grid = GridModel.new()
	_expect(controller.grid.configure_from_definition(map_definition), "fixture: synthetic GridModel should configure")
	controller.definition_registry = registry
	controller.runtime_instance_registry = runtime_registry
	controller.instance_id_generator = generator
	controller.environment_object_factory = factory
	controller._runtime_content_ready = true
	controller.cover_combat_settings = CoverSettingsScript.make_default()
	controller.session_manager = GameStateManagerScript.new()
	controller.session_manager.start_exploration()
	controller.turn_manager = TurnManagerScript.new()
	controller.turn_manager.configure([PLAYER_ID], [ENEMY_ID])
	controller.loot_containers = {}
	controller.object_placements = {}
	controller.environment_objects_by_placement_id = {}
	controller.environment_objects_by_instance_id = {}
	controller.environment_views_by_placement_id = {}
	controller.environment_visuals_by_placement_id = {}
	controller.opaque_cells = {}
	controller._index_map_objects()
	controller._apply_map_rules()

	var player_weapon := WeaponInstanceScript.new(&"environment_weapon_player", weapon_definition)
	var enemy_weapon := WeaponInstanceScript.new(&"environment_weapon_enemy", weapon_definition)
	var player_state: UnitRuntimeState = UnitRuntimeStateScript.new(PLAYER_ID, archetype, &"player", Vector3i(0, 0, 1), player_weapon)
	var enemy_state: UnitRuntimeState = UnitRuntimeStateScript.new(ENEMY_ID, archetype, &"enemy", Vector3i(1, 0, 1), enemy_weapon)
	var player := _make_unit(player_state, "EnvironmentPlayer")
	var enemy := _make_unit(enemy_state, "EnvironmentEnemy")
	controller.units_by_id = {PLAYER_ID: player, ENEMY_ID: enemy}
	controller.all_player_ids = [PLAYER_ID]
	controller.all_enemy_ids = [ENEMY_ID]
	controller.selected_unit = player
	controller._configure_action_executor()
	_expect(controller.grid.occupy(player.grid_cell, PLAYER_ID), "fixture: player should occupy its cell")
	_expect(controller.grid.occupy(enemy.grid_cell, ENEMY_ID), "fixture: enemy should occupy its cell")
	return {
		&"controller": controller,
		&"player": player,
		&"enemy": enemy,
		&"definition": object_definition,
		&"map_definition": map_definition,
		&"generator": generator,
	}


func _make_map_definition() -> TacticalMapDefinition:
	var definition: TacticalMapDefinition = MapDefinitionScript.new()
	definition.schema_version = 3
	definition.map_id = &"environment_synthetic_map"
	definition.footprint_size = Vector2i(7, 7)
	definition.level_count = 1
	definition.cell_size = Vector3(2.0, 2.0, 2.0)
	for z in range(7):
		for x in range(7):
			var cell: MapCellData = MapCellDataScript.new()
			cell.coordinate = Vector3i(x, 0, z)
			cell.walkable = true
			cell.move_cost = 1
			definition.cells.append(cell)
	return definition


func _make_weapon() -> WeaponDefinition:
	var definition: WeaponDefinition = WeaponDefinitionScript.new()
	definition.weapon_id = &"environment_test_rifle"
	definition.display_name = "Environment Rifle"
	definition.damage = 10
	definition.range = 6
	definition.ap_cost = 1
	return definition


func _make_archetype(weapon: WeaponDefinition) -> UnitArchetype:
	var archetype: UnitArchetype = UnitArchetypeScript.new()
	archetype.archetype_id = &"environment_test_soldier"
	archetype.display_name = "Environment Soldier"
	archetype.max_hp = 10
	archetype.max_action_points = 3
	archetype.move_range = 4
	archetype.inner_vision_range = 2
	archetype.vision_range = 6
	archetype.default_weapon = weapon
	return archetype


func _make_object_definition(with_effect: bool) -> TacticalObjectDefinition:
	var definition: TacticalObjectDefinition = ObjectDefinitionScript.new()
	definition.placeable_id = &"environment_test_explosive"
	definition.display_name = "Synthetic Barrel"
	definition.object_kind = &"explosive"
	definition.targetable = true
	definition.damageable = true
	definition.max_hp = 10
	definition.blocks_movement = true
	if with_effect:
		var effect: ExplosionEffectDefinition = ExplosionEffectScript.new()
		effect.effect_id = &"environment_test_explosion"
		effect.radius = 1
		effect.damage = 4
		effect.affect_players = true
		effect.affect_enemies = true
		effect.affect_environment_objects = true
		effect.allow_chain = true
		definition.on_destroy_effects.append(effect)
	return definition


func _make_placement(object_id: StringName, definition_id: StringName, cell: Vector3i) -> MapObjectPlacement:
	var placement: MapObjectPlacement = PlacementScript.new()
	placement.object_id = object_id
	placement.definition_id = definition_id
	placement.cell = cell
	return placement


func _make_unit(state: UnitRuntimeState, unit_name: String) -> PrototypeUnit:
	var unit := UnitScript.new() as PrototypeUnit
	unit.name = unit_name
	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	var body := MeshInstance3D.new()
	body.name = "Body"
	visual_root.add_child(body)
	var weapon_pivot := Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	var weapon_model_root := Node3D.new()
	weapon_model_root.name = "WeaponModelRoot"
	weapon_pivot.add_child(weapon_model_root)
	var muzzle_flash := MeshInstance3D.new()
	muzzle_flash.name = "MuzzleFlash"
	weapon_pivot.add_child(muzzle_flash)
	visual_root.add_child(weapon_pivot)
	unit.add_child(visual_root)
	var selection_marker := MeshInstance3D.new()
	selection_marker.name = "SelectionMarker"
	unit.add_child(selection_marker)
	var status_label := Label3D.new()
	status_label.name = "StatusLabel"
	unit.add_child(status_label)
	_expect(unit.bind_runtime_state(state, Color.WHITE), "fixture: %s should bind runtime state" % unit_name)
	get_root().add_child(unit)
	return unit


func _cleanup_fixture(fixture: Dictionary) -> void:
	var controller := fixture.get(&"controller") as Node
	if is_instance_valid(controller):
		controller.free()
	var player := fixture.get(&"player") as Node
	if is_instance_valid(player):
		player.free()
	var enemy := fixture.get(&"enemy") as Node
	if is_instance_valid(enemy):
		enemy.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	if _failures.is_empty():
		print("ENVIRONMENT_OBJECT_INTEGRATION_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ENVIRONMENT_OBJECT_INTEGRATION_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
