extends SceneTree

const UnitRuntimeStateScript = preload("res://scripts/core/units/unit_runtime_state.gd")
const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")
const UnitStateSnapshotScript = preload("res://scripts/core/runtime/snapshots/unit_state_snapshot.gd")
const PLAYER_ALPHA: UnitArchetype = preload("res://resources/units/player_alpha.tres")
const ASSAULT_RIFLE: WeaponDefinition = preload("res://resources/weapons/assault_rifle.tres")

class DefinitionRegistryStub extends RefCounted:
	var _allowed: Dictionary = {}

	func allow(definition_type: StringName, definition_id: StringName) -> void:
		_allowed["%s/%s" % [String(definition_type), String(definition_id)]] = true

	func contains(definition_type: Variant, definition_id: Variant = &"") -> bool:
		return _allowed.has("%s/%s" % [String(definition_type), String(definition_id)])


var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_hp := PLAYER_ALPHA.max_hp
	var original_ap := PLAYER_ALPHA.max_action_points
	var first_weapon: WeaponInstance = WeaponInstanceScript.new(&"weapon_alpha", ASSAULT_RIFLE)
	var second_weapon: WeaponInstance = WeaponInstanceScript.new(&"weapon_bravo", ASSAULT_RIFLE)
	var first: UnitRuntimeState = UnitRuntimeStateScript.new(&"unit_alpha", PLAYER_ALPHA, &"player", Vector3i(1, 0, 2), first_weapon)
	var second: UnitRuntimeState = UnitRuntimeStateScript.new(&"unit_bravo", PLAYER_ALPHA, &"player", Vector3i(2, 0, 2), second_weapon)
	_expect(first.is_valid() and second.is_valid(), "state: initialized states should be valid")
	_expect(first.current_hp == original_hp and first.current_action_points == original_ap, "state: defaults should come from archetype")
	_expect(first.weapon_instance == first_weapon and second.weapon_instance == second_weapon, "state: unit should retain externally-created weapon instances")
	_expect(first.weapon_instance_id != second.weapon_instance_id, "state: same definition instances should keep distinct IDs")
	_expect(PLAYER_ALPHA.max_hp == original_hp and PLAYER_ALPHA.max_action_points == original_ap, "state: initialization must not mutate archetype")
	var no_implicit_weapon: UnitRuntimeState = UnitRuntimeStateScript.new(&"unit_empty", PLAYER_ALPHA, &"player", Vector3i(0, 0, 0))
	_expect(no_implicit_weapon.weapon_instance == null, "state: unit must not create a weapon from the archetype default")

	var shared_weapon: WeaponInstance = WeaponInstanceScript.new(&"weapon_shared", ASSAULT_RIFLE)
	var ownership_holder: UnitRuntimeState = UnitRuntimeStateScript.new(&"unit_holder", PLAYER_ALPHA, &"player", Vector3i(4, 0, 4))
	var ownership_contender: UnitRuntimeState = UnitRuntimeStateScript.new(&"unit_contender", PLAYER_ALPHA, &"player", Vector3i(5, 0, 4))
	var contender_weapon: WeaponInstance = WeaponInstanceScript.new(&"weapon_contender", ASSAULT_RIFLE)
	_expect(ownership_holder.equip(shared_weapon), "ownership: first unit should claim a weapon instance")
	_expect(ownership_contender.equip(contender_weapon), "ownership: second unit should equip its own weapon instance")
	_expect(not ownership_contender.equip(shared_weapon) and ownership_contender.get_last_operation_reason() == &"weapon_already_owned", "ownership: shared weapon must be rejected without replacing the current weapon")
	_expect(ownership_contender.weapon_instance == contender_weapon, "ownership: rejected replacement must leave the old weapon equipped")
	_expect(ownership_holder.unequip(), "ownership: unequip should release the weapon claim")
	_expect(ownership_contender.equip(shared_weapon), "ownership: released weapon should be replaceable by another unit")
	_expect(ownership_holder.equip(contender_weapon), "ownership: replacing a weapon must release the previous unit claim")
	_expect(ownership_contender.unequip(), "ownership: replacement owner should be able to unequip")
	_expect(ownership_holder.equip(shared_weapon), "ownership: released replacement should be reusable")

	var constructor_weapon: WeaponInstance = WeaponInstanceScript.new(&"weapon_constructor_shared", ASSAULT_RIFLE)
	var constructor_owner: UnitRuntimeState = UnitRuntimeStateScript.new(&"unit_constructor_owner", PLAYER_ALPHA, &"player", Vector3i(6, 0, 4), constructor_weapon)
	var constructor_contender: UnitRuntimeState = UnitRuntimeStateScript.new(&"unit_constructor_contender", PLAYER_ALPHA, &"player", Vector3i(7, 0, 4), constructor_weapon)
	_expect(constructor_owner.weapon_instance == constructor_weapon, "ownership: constructor should claim an external weapon instance")
	_expect(constructor_contender.weapon_instance == null and constructor_contender.get_last_operation_reason() == &"weapon_already_owned", "ownership: constructor must reject an already-owned weapon instance")

	var disposable_weapon: WeaponInstance = WeaponInstanceScript.new(&"weapon_disposable", ASSAULT_RIFLE)
	var disposable_state: UnitRuntimeState = UnitRuntimeStateScript.new(&"unit_disposable", PLAYER_ALPHA, &"player", Vector3i(8, 0, 4), disposable_weapon)
	_expect(disposable_state.weapon_instance == disposable_weapon, "ownership: disposable state should claim its weapon")
	disposable_state = null
	var replacement_state: UnitRuntimeState = UnitRuntimeStateScript.new(&"unit_after_dispose", PLAYER_ALPHA, &"player", Vector3i(9, 0, 4))
	_expect(replacement_state.equip(disposable_weapon), "ownership: state destruction should release the weapon claim")

	_expect(first.apply_damage(5), "state: damage should mutate only the selected state")
	_expect(first.current_hp == original_hp - 5 and second.current_hp == original_hp, "state: damage should not leak between states")
	_expect(first.spend_ap(1), "state: AP spend should succeed within budget")
	_expect(first.current_action_points == original_ap - 1 and second.current_action_points == original_ap, "state: AP should remain independent")
	_expect(first.set_cell(Vector3i(-4, 1, -3)), "state: negative cell coordinates should be accepted")
	_expect(first.cell == Vector3i(-4, 1, -3), "state: movement should retain cell")
	_expect(not first.apply_damage(-1) and first.get_last_operation_reason() == &"invalid_damage", "state: negative damage should be rejected")
	_expect(not first.spend_ap(99) and first.get_last_operation_reason() == &"insufficient_ap", "state: excessive AP should be rejected")
	_expect(not first.set_cell(Vector2i(-1, 0)) and first.get_last_operation_reason() == &"invalid_cell", "state: non-Vector3i cell should be rejected")

	var replacement: WeaponInstance = WeaponInstanceScript.new(&"unit_alpha.sidearm", ASSAULT_RIFLE)
	_expect(first.equip(replacement), "state: valid weapon instance should equip")
	_expect(first.weapon_instance_id == replacement.instance_id and first.weapon_instance == replacement, "state: equipment identity should be authoritative")
	_expect(first.unequip(), "state: weapon should be removable")
	_expect(first.weapon_instance == null and first.weapon_instance_id == &"", "state: unequip should clear both references")
	_expect(first.equip(replacement), "state: weapon should be re-equipable")
	_expect(not first.equip(ASSAULT_RIFLE) and first.get_last_operation_reason() == &"invalid_weapon_instance", "state: definition alone cannot be equipped as an instance")
	_expect(first.state_version == UnitRuntimeState.CURRENT_STATE_VERSION and second.state_version == UnitRuntimeState.CURRENT_STATE_VERSION, "state: mutations must not increment schema version")

	var snapshot: UnitStateSnapshot = first.to_snapshot_resource()
	_expect(snapshot is UnitStateSnapshotScript and snapshot.is_valid(), "snapshot: state snapshot should be valid")
	var resolved_weapon: WeaponInstance = WeaponInstanceScript.new(replacement.instance_id, ASSAULT_RIFLE)
	var restored := UnitRuntimeStateScript.from_snapshot(snapshot, PLAYER_ALPHA, resolved_weapon)
	_expect(restored != null and restored.is_valid(), "snapshot: state should hydrate without a Node")
	if restored != null:
		_expect(restored.instance_id == first.instance_id, "snapshot: unit identity should round-trip")
		_expect(restored.current_hp == first.current_hp and restored.current_action_points == first.current_action_points, "snapshot: HP/AP should round-trip")
		_expect(restored.cell == first.cell, "snapshot: cell should round-trip")
		_expect(restored.weapon_instance_id == replacement.instance_id and restored.weapon_instance == resolved_weapon, "snapshot: weapon relation should resolve by ID")
		_expect(PLAYER_ALPHA.max_hp == original_hp and PLAYER_ALPHA.default_weapon == first.weapon_instance.definition, "snapshot: hydration must not mutate definitions")

	var dictionary := snapshot.to_dictionary()
	var decoded := UnitStateSnapshotScript.from_dictionary(dictionary)
	_expect(decoded != null and decoded.instance_id == snapshot.instance_id and decoded.cell == snapshot.cell, "snapshot: dictionary codec should retain primitive state")
	var missing_cell := dictionary.duplicate(true)
	missing_cell.erase(&"cell")
	_expect(UnitStateSnapshotScript.from_dictionary(missing_cell) == null, "snapshot: missing cell must be rejected")
	var wrong_cell_type := dictionary.duplicate(true)
	wrong_cell_type[&"cell"] = Vector2i(-4, -3)
	_expect(UnitStateSnapshotScript.from_dictionary(wrong_cell_type) == null, "snapshot: wrong cell type must be rejected")
	var wrong_alive_type := dictionary.duplicate(true)
	wrong_alive_type[&"alive"] = 1
	_expect(UnitStateSnapshotScript.from_dictionary(wrong_alive_type) == null, "snapshot: non-boolean alive must be rejected")
	var wrong_hp_type := dictionary.duplicate(true)
	wrong_hp_type[&"current_hp"] = float(first.current_hp)
	_expect(UnitStateSnapshotScript.from_dictionary(wrong_hp_type) == null, "snapshot: non-integer HP must be rejected")
	var future_version := dictionary.duplicate(true)
	future_version[&"state_version"] = 2
	_expect(UnitStateSnapshotScript.from_dictionary(future_version) == null, "snapshot: unsupported schema version must be rejected")
	var generic_dictionary: Dictionary = first.to_snapshot()
	var generic_resolved_weapon: WeaponInstance = WeaponInstanceScript.new(replacement.instance_id, ASSAULT_RIFLE)
	var generic_restored: UnitRuntimeState = UnitRuntimeStateScript.from_snapshot(generic_dictionary, PLAYER_ALPHA, generic_resolved_weapon)
	_expect(generic_restored != null and generic_restored.instance_id == first.instance_id, "snapshot: generic RuntimeInstance dictionary should hydrate")
	_expect(restored != null and restored.cell == Vector3i(-4, 1, -3), "snapshot: negative cell should round-trip")

	var dead := UnitRuntimeStateScript.new(&"unit_dead", PLAYER_ALPHA, &"player", Vector3i(3, 0, 3))
	_expect(dead.apply_damage(dead.current_hp), "state: lethal damage should be accepted")
	_expect(not dead.alive and dead.current_hp == 0, "state: lethal damage should mark only state as dead")
	_expect(not dead.reset_ap() and dead.get_last_operation_reason() == &"not_alive", "state: dead unit cannot reset AP")
	var dead_restored := UnitRuntimeStateScript.from_snapshot(dead.to_snapshot_resource(), PLAYER_ALPHA, dead.weapon_instance)
	_expect(dead_restored != null and not dead_restored.alive and dead_restored.current_hp == 0, "snapshot: dead state should hydrate silently")

	var registry := DefinitionRegistryStub.new()
	registry.allow(&"unit_archetype", PLAYER_ALPHA.archetype_id)
	registry.allow(&"weapon", ASSAULT_RIFLE.weapon_id)
	_expect(first.is_valid(registry), "state: valid definition registry should validate unit and weapon")
	var missing_weapon_registry := DefinitionRegistryStub.new()
	missing_weapon_registry.allow(&"unit_archetype", PLAYER_ALPHA.archetype_id)
	_expect(not first.is_valid(missing_weapon_registry), "state: registry must resolve equipped weapon definition")
	var missing_unit_registry := DefinitionRegistryStub.new()
	missing_unit_registry.allow(&"weapon", ASSAULT_RIFLE.weapon_id)
	_expect(not first.is_valid(missing_unit_registry), "state: registry must resolve unit archetype definition")

	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("UNIT_RUNTIME_STATE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("UNIT_RUNTIME_STATE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
