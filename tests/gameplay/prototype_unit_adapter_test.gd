extends SceneTree

const UNIT_SCENE: PackedScene = preload("res://scenes/main/prototype_unit.tscn")
const UnitRuntimeStateScript = preload("res://scripts/core/units/unit_runtime_state.gd")
const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")

var _failures: Array[String] = []
var _state_death_count := 0
var _view_death_count := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var rifle := _weapon(&"adapter.rifle", "Adapter Rifle", 4, 5, 1)
	var archetype := _archetype(&"adapter.scout", "Adapter Scout", rifle)
	var weapon_instance := WeaponInstanceScript.new(&"adapter:weapon:alpha", rifle)
	var state := UnitRuntimeStateScript.new(
			&"adapter:unit:alpha",
			archetype,
			&"player",
			Vector3i(-3, 1, 4),
			Vector2i(1, 0),
			weapon_instance
	)
	var original_hp := archetype.max_hp
	var original_ap := archetype.max_action_points
	var original_damage := rifle.damage
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	_expect(unit != null, "adapter: prototype scene should instantiate")
	if unit == null:
		_finish()
		return
	_expect(unit.bind_runtime_state(state, Color("4f9dff")), "adapter: a valid state should bind")
	get_root().add_child(unit)
	await process_frame
	_expect(unit.runtime_state == state, "adapter: bound state should be retained")
	_expect(unit.unit_id == state.instance_id and unit.faction == state.faction, "adapter: identity and faction should proxy state")
	_expect(unit.grid_cell == state.cell and unit.facing == state.facing, "adapter: cell and facing should proxy state")
	_expect(unit.current_hp == original_hp and unit.current_action_points == original_ap, "adapter: initial HP/AP should come from state")
	_expect(unit.archetype == archetype and unit.weapon == rifle, "adapter: definitions should proxy state/equipment")
	_expect(unit.attack_damage == rifle.damage and unit.attack_range == rifle.range and unit.attack_ap_cost == rifle.ap_cost, "adapter: weapon stats should proxy the equipped definition")
	_expect(state.unequip(), "adapter: runtime state should support unequipping the weapon")
	_expect(unit.weapon == null, "adapter: unarmed runtime state must not fall back to the legacy weapon")
	_expect(unit.attack_damage == 0 and unit.attack_range == 0 and unit.attack_ap_cost == 1, "adapter: unarmed runtime state must expose zero damage/range and one AP cost")
	_expect(state.equip(weapon_instance), "adapter: the same runtime state should be able to re-equip its weapon")
	_expect(unit.weapon == rifle and unit.attack_damage == rifle.damage and unit.attack_range == rifle.range and unit.attack_ap_cost == rifle.ap_cost, "adapter: re-equipped runtime weapon should restore its stats")

	_expect(state.apply_damage(3), "adapter: state damage should succeed")
	_expect(state.spend_ap(1), "adapter: state AP spend should succeed")
	_expect(state.set_cell(Vector3i(-8, 2, -1)), "adapter: state cell change should succeed")
	_expect(state.set_facing(Vector2i(-1, 0)), "adapter: state facing change should succeed")
	_expect(unit.current_hp == original_hp - 3 and unit.current_action_points == original_ap - 1, "adapter: view should follow state HP/AP")
	_expect(unit.grid_cell == Vector3i(-8, 2, -1) and unit.facing == Vector2i(-1, 0), "adapter: view should follow state cell/facing")
	_expect(archetype.max_hp == original_hp and archetype.max_action_points == original_ap and rifle.damage == original_damage, "adapter: state changes must not mutate definitions")
	var view_damage_hp := state.current_hp
	var view_damage_ap := state.current_action_points
	_expect(unit.take_damage(1) == 1 and state.current_hp == view_damage_hp - 1, "adapter: bound View damage must mutate only UnitRuntimeState")
	_expect(unit.spend_action_points(1) and state.current_action_points == view_damage_ap - 1, "adapter: bound View AP spend must mutate only UnitRuntimeState")

	var second_weapon := WeaponInstanceScript.new(&"adapter:weapon:bravo", rifle)
	var second_state := UnitRuntimeStateScript.new(
			&"adapter:unit:bravo",
			archetype,
			&"player",
			Vector3i(2, 0, 5),
			Vector2i(0, -1),
			second_weapon
	)
	_expect(second_state.spend_ap(2), "adapter: second state should have independent AP")
	_expect(second_state.apply_damage(5), "adapter: second state should have independent HP")
	var second_hp := second_state.current_hp
	var second_ap := second_state.current_action_points
	_expect(unit.bind_runtime_state(second_state), "adapter: view should rebind to another valid state")
	_expect(unit.unit_id == second_state.instance_id and unit.current_hp == second_hp and unit.current_action_points == second_ap, "adapter: rebind must not reset or copy state values")
	_expect(unit.grid_cell == second_state.cell and unit.weapon == rifle, "adapter: rebind should expose the new state equipment and cell")

	unit.queue_free()
	await process_frame
	_expect(not is_instance_valid(unit), "adapter: old View should be removable without destroying state")
	var rebuilt := UNIT_SCENE.instantiate() as PrototypeUnit
	_expect(rebuilt != null and rebuilt.bind_runtime_state(second_state), "adapter: a new View should bind the surviving state")
	if rebuilt != null:
		get_root().add_child(rebuilt)
		await process_frame
		_expect(rebuilt.unit_id == second_state.instance_id and rebuilt.current_hp == second_hp and rebuilt.current_action_points == second_ap, "adapter: recreated View should preserve state")
		_expect(rebuilt.grid_cell == second_state.cell and rebuilt.facing == second_state.facing, "adapter: recreated View should preserve cell/facing")
		second_state.died.connect(_on_state_died)
		rebuilt.died.connect(_on_view_died)
		_expect(second_state.apply_damage(second_state.current_hp), "adapter: lethal damage should succeed once")
		_expect(_state_death_count == 1 and _view_death_count == 1, "adapter: death event should be emitted exactly once")
		_expect(not second_state.apply_damage(1), "adapter: dead state should reject further damage")
		_expect(_state_death_count == 1 and _view_death_count == 1, "adapter: rejected post-death damage must not emit again")
		rebuilt.queue_free()

	var source := FileAccess.get_file_as_string("res://scripts/gameplay/prototype_unit.gd")
	_expect(not source.contains("get_instance_id()"), "adapter: PrototypeUnit must not derive identity from Object.get_instance_id")
	_finish()


func _weapon(id: StringName, label: String, damage: int, weapon_range: int, ap: int) -> WeaponDefinition:
	var result := WeaponDefinition.new()
	result.weapon_id = id
	result.display_name = label
	result.damage = damage
	result.range = weapon_range
	result.ap_cost = ap
	return result


func _archetype(id: StringName, label: String, weapon: WeaponDefinition) -> UnitArchetype:
	var result := UnitArchetype.new()
	result.archetype_id = id
	result.display_name = label
	result.max_hp = 14
	result.max_action_points = 4
	result.move_range = 6
	result.vision_range = 9
	result.default_weapon = weapon
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _on_state_died() -> void:
	_state_death_count += 1


func _on_view_died(_unit: PrototypeUnit) -> void:
	_view_death_count += 1


func _finish() -> void:
	if _failures.is_empty():
		print("PROTOTYPE_UNIT_ADAPTER_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("PROTOTYPE_UNIT_ADAPTER_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
