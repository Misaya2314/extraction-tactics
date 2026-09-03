extends SceneTree

const EffectDefinitionScript = preload("res://scripts/core/environment/environment_effect_definition.gd")
const ExplosionEffectScript = preload("res://scripts/core/environment/explosion_effect_definition.gd")
const EffectResolverScript = preload("res://scripts/core/environment/environment_effect_resolver.gd")
const EnvironmentStateScript = preload("res://scripts/core/environment/environment_object_runtime_state.gd")
const EnvironmentFactoryScript = preload("res://scripts/core/environment/environment_object_factory.gd")
const ObjectDefinitionScript = preload("res://scripts/core/map/tactical_object_definition.gd")
const PlacementScript = preload("res://scripts/core/map/map_object_placement.gd")
const MarkerScript = preload("res://scripts/map_authoring/map_object_marker_3d.gd")
const ManifestScript = preload("res://scripts/core/content/game_content_manifest.gd")
const RegistryScript = preload("res://scripts/core/content/game_definition_registry.gd")
const RuntimeRegistryScript = preload("res://scripts/core/runtime/runtime_instance_registry.gd")
const GeneratorScript = preload("res://scripts/core/runtime/instance_id_generator.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_effect_definition_validation()
	_test_runtime_state_and_snapshot()
	_test_factory_resolution_and_identity()
	_test_effect_resolution()
	_test_authoring_definition_link()
	_test_formal_barrel_resource()
	if _failures.is_empty():
		print("ENVIRONMENT_CORE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ENVIRONMENT_CORE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)


func _test_effect_definition_validation() -> void:
	var base := EffectDefinitionScript.new()
	_expect(not base.is_valid(), "effect: empty effect_id must be invalid")
	base.effect_id = &"synthetic_effect"
	_expect(base.is_valid(), "effect: stable effect_id should make the base definition valid")
	var explosion := ExplosionEffectScript.new()
	explosion.effect_id = &"synthetic_explosion"
	explosion.radius = 2
	explosion.damage = 7
	_expect(explosion.is_valid(), "effect: valid explosion configuration should pass")
	explosion.damage = -1
	_expect(not explosion.is_valid(), "effect: negative damage must be invalid")
	explosion.damage = 7
	explosion.affect_players = false
	explosion.affect_enemies = false
	explosion.affect_environment_objects = false
	_expect(not explosion.is_valid(), "effect: an explosion with no target category must be invalid")


func _test_runtime_state_and_snapshot() -> void:
	var definition := _make_object(&"environment.synthetic", &"synthetic", 10)
	var placement := _make_placement(&"placement_state", &"environment.synthetic", Vector3i(2, 1, -3))
	var state: EnvironmentObjectRuntimeState = EnvironmentStateScript.new(&"raid_state:environment:map:placement_state", definition, placement)
	_expect(state.is_valid(), "state: a configured environment state should be valid")
	var second_placement := _make_placement(&"placement_state_2", &"environment.synthetic", Vector3i(3, 1, -3))
	var second: EnvironmentObjectRuntimeState = EnvironmentStateScript.new(&"raid_state:environment:map:placement_state_2", definition, second_placement)
	_expect(second.is_valid(), "state: a second instance of one Definition should be valid")
	var damage_result := state.apply_damage(3)
	_expect(damage_result.success and damage_result.value[&"damage"] == 3, "state: damage result should report the applied amount")
	_expect(state.current_hp == 7 and second.current_hp == 10 and definition.max_hp == 10, "state: damage must not leak to another instance or Definition")
	var lethal_result := state.apply_damage(99)
	_expect(lethal_result.success and lethal_result.value[&"damage"] == 7 and lethal_result.value[&"destroyed_now"], "state: lethal damage should clamp and destroy exactly once")
	_expect(state.destroyed and not state.active and state.current_hp == 0, "state: destroyed object should be inactive at zero HP")
	_expect(state.trigger_destroy_effects(), "state: destroy effect trigger should be accepted once")
	_expect(not state.trigger_destroy_effects(), "state: destroy effect trigger must not fire twice")
	var repeated := state.apply_damage(1)
	_expect(not repeated.success and repeated.reason_code == &"already_destroyed", "state: damage after destruction must be rejected")
	var snapshot := state.to_snapshot()
	_expect(snapshot[&"schema_version"] == EnvironmentStateScript.SNAPSHOT_SCHEMA_VERSION, "snapshot: schema version should be explicit")
	_expect(snapshot[&"instance_id"] == state.instance_id and snapshot[&"placement_id"] == placement.object_id, "snapshot: identity and placement must round-trip")
	_expect(snapshot[&"current_hp"] == 0 and snapshot[&"destroyed"] and snapshot[&"effect_triggered"], "snapshot: mutable lifecycle state must be preserved")
	_expect(not snapshot.has(&"definition") and not snapshot.has(&"scene"), "snapshot: runtime snapshot must contain no Resource or Node reference")
	var restored: EnvironmentObjectRuntimeState = EnvironmentStateScript.from_snapshot(snapshot, definition)
	_expect(restored != null and restored.instance_id == state.instance_id and restored.current_hp == 0 and restored.destroy_effect_triggered, "snapshot: strict in-memory hydrate should preserve state")
	var wrong_schema := snapshot.duplicate(true)
	wrong_schema[&"schema_version"] = "1"
	_expect(EnvironmentStateScript.from_snapshot(wrong_schema, definition) == null, "snapshot: string schema version must be rejected")
	var wrong_hp := snapshot.duplicate(true)
	wrong_hp[&"current_hp"] = 0.0
	_expect(EnvironmentStateScript.from_snapshot(wrong_hp, definition) == null, "snapshot: float HP must be rejected")
	var missing_field := snapshot.duplicate(true)
	missing_field.erase(&"effect_triggered")
	_expect(EnvironmentStateScript.from_snapshot(missing_field, definition) == null, "snapshot: missing lifecycle field must be rejected")


func _test_factory_resolution_and_identity() -> void:
	var definition := _make_object(&"environment.factory", &"explosive", 12)
	var context := _make_context([definition], &"factory_test")
	var factory: EnvironmentObjectFactory = context[&"factory"]
	var runtime_registry: RuntimeInstanceRegistry = context[&"runtime_registry"]
	var generator: InstanceIdGenerator = context[&"generator"]
	var placement := _make_placement(&"barrel_a", definition.placeable_id, Vector3i(-2, 0, 4))
	placement.kind = PlacementScript.Kind.EXPLOSIVE
	var created_result := factory.create_from_placement_result(placement, &"synthetic_map")
	_expect(created_result.success, "factory: explicit Definition ID should create a state")
	var state := created_result.value as EnvironmentObjectRuntimeState
	_expect(state != null and state.definition == definition and state.instance_id == &"factory_test:environment:synthetic_map:barrel_a", "factory: state should use the resolved Definition and fixed ID")
	var second_placement := _make_placement(&"barrel_b", definition.placeable_id, Vector3i(-1, 0, 4))
	second_placement.kind = PlacementScript.Kind.EXPLOSIVE
	var second_result := factory.create_from_placement_result(second_placement, &"synthetic_map")
	_expect(second_result.success and runtime_registry.size() == 2, "factory: two placements should create two registered instances")
	var generator_before_duplicate := generator.capture_state()
	var duplicate_result := factory.create_from_placement_result(placement, &"synthetic_map")
	_expect(not duplicate_result.success and duplicate_result.reason_code == &"duplicate_instance_id", "factory: a second object with the same fixed ID must be rejected")
	_expect(generator.capture_state() == generator_before_duplicate, "factory: duplicate registration must roll back generator reservations")
	var missing_placement := _make_placement(&"missing", &"environment.missing", Vector3i.ZERO)
	var missing_before := generator.capture_state()
	var missing_result := factory.create_from_placement_result(missing_placement, &"synthetic_map")
	_expect(not missing_result.success and missing_result.reason_code == &"missing_definition", "factory: missing Definition must fail explicitly")
	_expect(generator.capture_state() == missing_before, "factory: unresolved Definition must not consume an ID")

	var legacy_placement := _make_placement(&"legacy_barrel", &"", Vector3i(5, 0, 5))
	legacy_placement.kind = PlacementScript.Kind.EXPLOSIVE
	legacy_placement.scene = definition.scene
	var legacy_result := factory.create_from_placement_result(legacy_placement, &"synthetic_map")
	_expect(legacy_result.success and (legacy_result.value as EnvironmentObjectRuntimeState).definition == definition, "factory: legacy unique scene/object-kind fallback should resolve without an ID hardcode")

	var ambiguous_definition := _make_object(&"environment.factory.2", &"explosive", 12)
	ambiguous_definition.scene = definition.scene
	var ambiguous_context := _make_context([definition, ambiguous_definition], &"ambiguous_test")
	var ambiguous_factory: EnvironmentObjectFactory = ambiguous_context[&"factory"]
	var ambiguous_placement := _make_placement(&"legacy_ambiguous", &"", Vector3i.ZERO)
	ambiguous_placement.kind = PlacementScript.Kind.EXPLOSIVE
	ambiguous_placement.scene = definition.scene
	var ambiguous_result := ambiguous_factory.create_from_placement_result(ambiguous_placement, &"synthetic_map")
	_expect(not ambiguous_result.success and ambiguous_result.reason_code == &"ambiguous_definition", "factory: ambiguous legacy matching must fail explicitly")

	var snapshot := (state as EnvironmentObjectRuntimeState).to_snapshot()
	var hydrate_registry: RuntimeInstanceRegistry = RuntimeRegistryScript.new()
	var hydrate_generator: InstanceIdGenerator = GeneratorScript.new(&"hydrate_test")
	var hydrate_factory: EnvironmentObjectFactory = EnvironmentFactoryScript.new(context[&"registry"], hydrate_registry, hydrate_generator)
	var hydrate_result := hydrate_factory.hydrate_from_snapshot_result(snapshot)
	_expect(hydrate_result.success and (hydrate_result.value as EnvironmentObjectRuntimeState).instance_id == state.instance_id, "factory: hydrate should resolve by DefinitionKey and preserve identity")
	var hydrate_before_duplicate := hydrate_generator.capture_state()
	var duplicate_hydrate := hydrate_factory.hydrate_from_snapshot_result(snapshot)
	_expect(not duplicate_hydrate.success and duplicate_hydrate.reason_code == &"duplicate_instance_id", "factory: repeated hydrate must reject the duplicate global identity")
	_expect(hydrate_generator.capture_state() == hydrate_before_duplicate, "factory: duplicate hydrate must not leave generator state behind")
	var missing_snapshot := snapshot.duplicate(true)
	missing_snapshot[&"definition_id"] = &"environment.missing"
	var missing_hydrate_before := hydrate_generator.capture_state()
	var missing_hydrate := hydrate_factory.hydrate_from_snapshot_result(missing_snapshot)
	_expect(not missing_hydrate.success and missing_hydrate.reason_code == &"missing_definition", "factory: snapshot recovery must not fall back to another Definition")
	_expect(hydrate_generator.capture_state() == missing_hydrate_before, "factory: failed hydrate must preserve generator state")


func _test_effect_resolution() -> void:
	var effect := ExplosionEffectScript.new()
	effect.effect_id = &"area_test"
	effect.radius = 1
	effect.damage = 4
	effect.affect_players = true
	effect.affect_enemies = false
	effect.affect_environment_objects = true
	var candidates: Array = [
		{&"target_id": &"enemy_near", &"cell": Vector3i(0, 0, 1), &"faction": &"enemy"},
		{&"target_id": &"player_far", &"cell": Vector3i(0, 0, 2), &"faction": &"player"},
		{&"target_id": &"player_near", &"cell": Vector3i(1, 0, 0), &"faction": &"player"},
		{&"target_id": &"barrel_near", &"cell": Vector3i(-1, 0, 0), &"target_type": &"environment"},
		{&"target_id": &"other_floor", &"cell": Vector3i(0, 1, 0), &"faction": &"player"},
	]
	var resolved: Array[Dictionary] = EffectResolverScript.resolve_area_damage(effect, Vector3i.ZERO, candidates)
	_expect(resolved.size() == 2, "resolver: radius and faction filters should select exactly two candidates")
	_expect(resolved[0].get(&"target_id") == &"barrel_near" and resolved[1].get(&"target_id") == &"player_near", "resolver: results should be deterministically sorted by stable target ID")
	_expect(resolved[0].get(&"damage") == 4 and resolved[1].get(&"distance") == 1, "resolver: output should carry deterministic damage and distance")
	var affected := EffectResolverScript.affected_cells(Vector3i.ZERO, 1)
	_expect(affected.size() == 5 and EffectResolverScript.is_in_area(Vector3i.ZERO, Vector3i(1, 0, 0), 1), "resolver: Manhattan radius should include the four neighbors")
	_expect(not EffectResolverScript.is_in_area(Vector3i.ZERO, Vector3i(0, 1, 0), 1), "resolver: another floor must not be included")


func _test_authoring_definition_link() -> void:
	var marker: MapObjectMarker3D = MarkerScript.new()
	marker.object_id = &"synthetic_marker"
	marker.definition_id = &"environment.synthetic"
	marker.kind = PlacementScript.Kind.EXPLOSIVE
	var placement: MapObjectPlacement = marker.to_data()
	_expect(placement.definition_id == marker.definition_id and placement.object_id == marker.object_id, "authoring: Marker to_data must preserve definition_id")


func _test_formal_barrel_resource() -> void:
	var barrel := load("res://resources/map_tiles/definitions/objects/prototype_explosive_barrel.tres") as TacticalObjectDefinition
	_expect(barrel != null and barrel.is_valid(), "resource: formal explosive barrel Definition should remain valid")
	if barrel == null:
		return
	_expect(barrel.targetable and barrel.damageable and barrel.max_hp > 0, "resource: barrel should be targetable and damageable with deterministic HP")
	_expect(barrel.on_destroy_effects.size() == 1 and barrel.on_destroy_effects[0] is ExplosionEffectDefinition, "resource: barrel should own one configured explosion effect")


func _make_context(definitions: Array, session: StringName) -> Dictionary:
	var manifest: GameContentManifest = ManifestScript.new()
	for definition in definitions:
		manifest.placeable_definitions.append(definition)
	var registry: GameDefinitionRegistry = RegistryScript.new()
	var report := registry.configure(manifest)
	_expect(bool(report.get(&"valid", false)), "fixture: synthetic placeable manifest should be valid")
	var runtime_registry: RuntimeInstanceRegistry = RuntimeRegistryScript.new()
	var generator: InstanceIdGenerator = GeneratorScript.new(session)
	var factory: EnvironmentObjectFactory = EnvironmentFactoryScript.new(registry, runtime_registry, generator)
	return {
		&"manifest": manifest,
		&"registry": registry,
		&"runtime_registry": runtime_registry,
		&"generator": generator,
		&"factory": factory,
	}


func _make_object(id: StringName, object_kind: StringName, hp: int) -> TacticalObjectDefinition:
	var definition: TacticalObjectDefinition = ObjectDefinitionScript.new()
	definition.placeable_id = id
	definition.display_name = String(id)
	definition.object_kind = object_kind
	definition.scene = PackedScene.new()
	definition.targetable = true
	definition.damageable = true
	definition.max_hp = hp
	var effect: ExplosionEffectDefinition = ExplosionEffectScript.new()
	effect.effect_id = StringName("%s.effect" % id)
	effect.radius = 1
	effect.damage = 4
	definition.on_destroy_effects.append(effect)
	return definition


func _make_placement(id: StringName, definition_id: StringName, position: Vector3i) -> MapObjectPlacement:
	var placement: MapObjectPlacement = PlacementScript.new()
	placement.object_id = id
	placement.definition_id = definition_id
	placement.cell = position
	return placement


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
