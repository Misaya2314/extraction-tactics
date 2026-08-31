extends SceneTree

const FactoryScript = preload("res://scripts/core/units/unit_instance_factory.gd")
const MapSpawnDataScript = preload("res://scripts/core/map/map_spawn_data.gd")
const RuntimeInstanceScript = preload("res://scripts/core/runtime/runtime_instance.gd")
const RuntimeRegistryScript = preload("res://scripts/core/runtime/runtime_instance_registry.gd")
const IdGeneratorScript = preload("res://scripts/core/runtime/instance_id_generator.gd")
const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")
const WEAPON_TYPE: StringName = &"weapon"
const UNIT_TYPE: StringName = &"unit_archetype"

var _failures: Array[String] = []


class DefinitionRegistryStub extends RefCounted:
	var _definitions: Dictionary = {}

	func add(definition_type: StringName, definition_id: StringName, definition: Resource) -> void:
		_definitions["%s/%s" % [String(definition_type), String(definition_id)]] = definition

	func contains(definition_type: Variant, definition_id: Variant = &"") -> bool:
		return _definitions.has("%s/%s" % [String(definition_type), String(definition_id)])

	func resolve(definition_type: Variant, definition_id: Variant = &"") -> Resource:
		return _definitions.get("%s/%s" % [String(definition_type), String(definition_id)]) as Resource


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var weapon := _weapon(&"factory.rifle", "Factory Rifle", 4, 5, 1)
	var alternate_weapon := _weapon(&"factory.carbine", "Factory Carbine", 3, 6, 1)
	var archetype := _archetype(&"factory.scout", "Factory Scout", weapon)
	var registry := DefinitionRegistryStub.new()
	registry.add(WEAPON_TYPE, weapon.weapon_id, weapon)
	registry.add(WEAPON_TYPE, alternate_weapon.weapon_id, alternate_weapon)
	registry.add(UNIT_TYPE, archetype.archetype_id, archetype)
	var runtime_registry := RuntimeRegistryScript.new()
	var id_generator := IdGeneratorScript.new(&"factory_test")
	var factory := FactoryScript.new(registry, runtime_registry, id_generator)

	var spawn := _spawn(&"spawn_alpha", &"Alpha", archetype, Vector3i(-2, 1, 4))
	var created_result := factory.create_from_spawn_result(spawn, &"synthetic_map", 0)
	_expect(created_result.success, "factory: valid spawn should create a runtime pair")
	var state := created_result.value as UnitRuntimeState
	_expect(state != null and state.is_valid(registry), "factory: result should be a valid UnitRuntimeState")
	if state != null:
		_expect(state.instance_id == &"factory_test:unit:synthetic_map:spawn_alpha", "factory: unit ID should be deterministic")
		_expect(state.weapon_instance_id == &"factory_test:weapon:synthetic_map:spawn_alpha", "factory: weapon ID should be deterministic")
		_expect(state.weapon_instance.definition == weapon, "factory: default weapon should be resolved from archetype")
	_expect(runtime_registry.size() == 2, "factory: both unit and weapon should be registered")

	var override_spawn := _spawn(&"spawn_bravo", &"Bravo", archetype, Vector3i(0, 0, 0))
	override_spawn.weapon = alternate_weapon
	var override_state := factory.create_from_spawn(override_spawn, &"synthetic_map", 1)
	_expect(override_state != null and override_state.weapon_instance.definition == alternate_weapon, "factory: spawn weapon should override archetype default")
	_expect(runtime_registry.size() == 4, "factory: override spawn should register another pair")

	var duplicate_result := factory.create_from_spawn_result(spawn, &"synthetic_map", 0)
	_expect(not duplicate_result.success and duplicate_result.reason_code == &"weapon_register_failed", "factory: duplicate pair should fail at registration")
	_expect(runtime_registry.size() == 4, "factory: duplicate registration must not add a partial pair")

	var rollback_registry := RuntimeRegistryScript.new()
	var rollback_generator := IdGeneratorScript.new(&"rollback_test")
	var occupied_unit_id := &"rollback_test:unit:synthetic_map:spawn_charlie"
	var occupied_identity := RuntimeInstanceScript.new(occupied_unit_id, UNIT_TYPE, archetype.archetype_id)
	_expect(rollback_registry.register(occupied_identity).success, "factory: test precondition should register occupied unit identity")
	var rollback_factory := FactoryScript.new(registry, rollback_registry, rollback_generator)
	var rollback_spawn := _spawn(&"spawn_charlie", &"Charlie", archetype, Vector3i(1, 0, 1))
	var rollback_result := rollback_factory.create_from_spawn_result(rollback_spawn, &"synthetic_map", 0)
	_expect(not rollback_result.success and rollback_result.reason_code == &"unit_register_failed", "factory: second registration failure should be reported")
	_expect(rollback_registry.size() == 1, "factory: failed unit registration must roll back its weapon")
	_expect(not rollback_registry.contains(&"rollback_test:weapon:synthetic_map:spawn_charlie"), "factory: rollback must not leave an orphan weapon")
	_expect(not rollback_generator.is_reserved(&"rollback_test:weapon:synthetic_map:spawn_charlie"), "factory: rollback should restore generator reservations")

	var compatibility_spawn := _spawn(&"Legacy Unit", &"Legacy", archetype, Vector3i(2, 0, 2))
	compatibility_spawn.spawn_id = &""
	var compatibility_result := factory.create_from_spawn_result(compatibility_spawn, &"synthetic_map", 7)
	_expect(compatibility_result.success, "factory: legacy spawn without ID should use deterministic compatibility ID")
	var explicit_factory := FactoryScript.new(registry, RuntimeRegistryScript.new(), IdGeneratorScript.new(&"explicit_test"))
	explicit_factory.require_explicit_spawn_id = true
	var explicit_result := explicit_factory.create_from_spawn_result(compatibility_spawn, &"synthetic_map", 7)
	_expect(not explicit_result.success and explicit_result.reason_code == &"missing_spawn_id", "factory: new content mode should require explicit spawn_id")

	var stable_spawn := MapSpawnDataScript.new()
	stable_spawn.unit_name = &"Legacy Unit"
	_expect(stable_spawn.get_stable_spawn_id(7) == &"legacy_Legacy_Unit_0007", "spawn: compatibility ID should not use a native Node ID")
	_expect(stable_spawn.get_stable_spawn_id(8) != stable_spawn.get_stable_spawn_id(7), "spawn: legacy index should keep old duplicate names distinct")
	var controller_source := FileAccess.get_file_as_string("res://scripts/gameplay/prototype_controller.gd")
	_expect(controller_source.contains("UnitInstanceFactoryScript"), "controller: runtime spawning should own a UnitInstanceFactory")
	_expect(controller_source.contains("create_from_spawn_result"), "controller: normal spawning should use the factory result")
	_expect(not controller_source.contains("unit.configure("), "controller: normal spawning must not configure a duplicate legacy state")
	_expect(not controller_source.contains("get_instance_id()"), "controller: stable IDs must not use a native Object ID")
	_finish()


func _weapon(id: StringName, label: String, damage: int, weapon_range: int, ap: int) -> WeaponDefinition:
	var result := WeaponDefinition.new()
	result.weapon_id = id
	result.display_name = label
	result.damage = damage
	result.range = weapon_range
	result.ap_cost = ap
	return result


func _archetype(id: StringName, label: String, default_weapon: WeaponDefinition) -> UnitArchetype:
	var result := UnitArchetype.new()
	result.archetype_id = id
	result.display_name = label
	result.max_hp = 12
	result.max_action_points = 3
	result.move_range = 5
	result.vision_range = 8
	result.default_weapon = default_weapon
	return result


func _spawn(id: StringName, label: StringName, archetype: UnitArchetype, cell: Vector3i) -> MapSpawnData:
	var result := MapSpawnDataScript.new()
	result.spawn_id = id
	result.unit_name = label
	result.faction = &"player"
	result.cell = cell
	result.facing = Vector2i(0, 1)
	result.archetype = archetype
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("UNIT_INSTANCE_FACTORY_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("UNIT_INSTANCE_FACTORY_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
