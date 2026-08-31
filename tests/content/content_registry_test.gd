extends SceneTree

const DefinitionKeyScript = preload("res://scripts/core/content/definition_key.gd")
const DefinitionAliasScript = preload("res://scripts/core/content/definition_alias.gd")
const ManifestScript = preload("res://scripts/core/content/game_content_manifest.gd")
const RegistryScript = preload("res://scripts/core/content/game_definition_registry.gd")
const ItemDefinitionScript = preload("res://scripts/core/items/item_definition.gd")
const WeaponDefinitionScript = preload("res://scripts/core/combat/weapon_definition.gd")
const UnitArchetypeScript = preload("res://scripts/core/units/unit_archetype.gd")
const MapDefinitionScript = preload("res://scripts/core/map/tactical_map_definition.gd")
const MapSpawnDataScript = preload("res://scripts/core/map/map_spawn_data.gd")
const MapEdgeDataScript = preload("res://scripts/core/map/map_edge_data.gd")
const PlaceableDefinitionScript = preload("res://scripts/core/map/tactical_placeable_definition.gd")
const EdgeDefinitionScript = preload("res://scripts/core/map/tactical_edge_definition.gd")
const EdgeRulesScript = preload("res://scripts/core/map/tactical_edge_rules.gd")
const CoverProfileScript = preload("res://scripts/core/cover/tactical_cover_profile.gd")

var _failures := 0


func _init() -> void:
	_test_definition_key()
	_test_registry_types_and_order()
	_test_registry_diagnostics()
	_test_cross_reference_diagnostics()
	_test_alias_resolution_and_cycles()
	_test_project_manifest()
	if _failures == 0:
		print("CONTENT_REGISTRY_TEST: PASS")
	else:
		printerr("CONTENT_REGISTRY_TEST: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_definition_key() -> void:
	var first := DefinitionKeyScript.new(&"item", &"shared")
	var second := DefinitionKeyScript.new(&"item", &"shared")
	var different_type := DefinitionKeyScript.new(&"weapon", &"shared")
	_expect(first.is_valid(), "key: normal type/id should be valid")
	_expect(first.equals(second) and first.is_equal(second), "key: equality should include type and ID")
	_expect(not first.equals(different_type), "key: same bare ID in another type must not collide")
	_expect(first.key_string() == "item/shared", "key: stable string form should include both fields")
	_expect(not DefinitionKeyScript.new(&"", &"shared").is_valid(), "key: empty type should be invalid")
	_expect(not DefinitionKeyScript.new(&"item", &"bad/id").is_valid(), "key: path-like IDs should be invalid")
	var roundtrip := DefinitionKeyScript.from_dictionary(first.to_dictionary())
	_expect(roundtrip.equals(first), "key: dictionary roundtrip should preserve identity")
	_expect(not DefinitionKeyScript.from_dictionary({&"definition_type": 7, &"definition_id": &"shared"}).is_valid(), "key: numeric dictionary type must be rejected")
	_expect(not DefinitionKeyScript.from_dictionary({&"definition_type": &"item", &"definition_id": RefCounted.new()}).is_valid(), "key: object dictionary ID must be rejected")


func _test_registry_types_and_order() -> void:
	var manifest = _make_manifest()
	var registry := RegistryScript.new()
	var report: Dictionary = registry.configure(manifest)
	_expect(bool(report[&"valid"]), "registry: valid synthetic manifest should configure")
	_expect(registry.contains(&"item", &"shared"), "registry: item should resolve by adapted item_id")
	_expect(registry.contains(&"weapon", &"shared"), "registry: weapon may reuse the same bare ID")
	_expect(registry.contains(&"unit_archetype", &"unit_shared"), "registry: unit archetype should resolve by archetype_id")
	_expect(registry.contains(&"map", &"map_shared"), "registry: map should resolve by map_id")
	_expect(registry.contains(&"placeable", &"placeable_shared"), "registry: placeable should resolve by placeable_id")
	_expect(registry.contains(&"cover", &"cover_shared"), "registry: cover should resolve by cover_id")
	var item_list: Array[Resource] = registry.get_all(&"item")
	_expect(item_list.size() == 1 and item_list[0].item_id == &"shared", "registry: get_all should preserve manifest order")
	_expect(registry.resolve(DefinitionKeyScript.new(&"item", &"shared")) != null, "registry: DefinitionKey input should resolve")
	_expect(not registry.contains(7, &"shared"), "registry: numeric type input must not be coerced into a key")
	_expect(not registry.contains(&"item", RefCounted.new()), "registry: object ID input must not be coerced into a key")
	_expect(not bool(registry.resolve_result({&"definition_type": 7, &"definition_id": &"shared"})[&"found"]), "registry: invalid dictionary key types must fail resolution")
	_expect(not bool(registry.resolve_result(RefCounted.new())[&"found"]), "registry: unrelated objects must not be treated as DefinitionKey")


func _test_registry_diagnostics() -> void:
	var duplicate_manifest = _make_manifest()
	duplicate_manifest.item_definitions.append(_make_item(&"shared"))
	var duplicate_registry := RegistryScript.new()
	duplicate_registry.configure(duplicate_manifest)
	_expect(_has_code(duplicate_registry.validate(), &"duplicate_definition_id"), "registry: duplicate same-type IDs need a diagnostic")

	var null_manifest = _make_manifest()
	null_manifest.item_definitions.append(null)
	var null_registry := RegistryScript.new()
	null_registry.configure(null_manifest)
	_expect(_has_code(null_registry.validate(), &"empty_definition_reference"), "registry: null manifest entries need a diagnostic")

	var empty_id_manifest = _make_manifest()
	empty_id_manifest.item_definitions.append(_make_item(&""))
	var empty_id_registry := RegistryScript.new()
	empty_id_registry.configure(empty_id_manifest)
	_expect(_has_code(empty_id_registry.validate(), &"empty_definition_id"), "registry: empty adapted IDs need a diagnostic")

	var invalid_manifest = _make_manifest()
	var invalid_weapon := _make_weapon(&"invalid_weapon")
	invalid_weapon.damage = 0
	invalid_manifest.weapon_definitions.append(invalid_weapon)
	var invalid_registry := RegistryScript.new()
	invalid_registry.configure(invalid_manifest)
	_expect(_has_code(invalid_registry.validate(), &"invalid_definition"), "registry: invalid Definition resources need a diagnostic")
	invalid_manifest.weapon_definitions.append(invalid_weapon)
	var invalid_duplicate_registry := RegistryScript.new()
	invalid_duplicate_registry.configure(invalid_manifest)
	_expect(_has_code(invalid_duplicate_registry.validate(), &"duplicate_definition_id"), "registry: duplicate IDs should be diagnosed even when the first Definition is invalid")

	var missing_result: Dictionary = invalid_registry.resolve_result(&"item", &"not_present")
	_expect(not bool(missing_result[&"found"]), "registry: missing resolve should not silently fall back")
	_expect(_has_code(missing_result[&"diagnostics"], &"missing_definition"), "registry: missing resolve should expose a stable diagnostic")


func _test_cross_reference_diagnostics() -> void:
	var manifest = _make_manifest()
	var missing_weapon: WeaponDefinition = _make_weapon(&"missing_weapon")
	var missing_archetype: UnitArchetype = UnitArchetypeScript.new()
	missing_archetype.archetype_id = &"missing_archetype"
	missing_archetype.display_name = "Missing Archetype"
	missing_archetype.default_weapon = missing_weapon
	manifest.unit_archetypes.append(missing_archetype)
	var map: TacticalMapDefinition = MapDefinitionScript.new()
	map.map_id = &"cross_reference_map"
	map.schema_version = TacticalMapDefinition.CURRENT_SCHEMA_VERSION
	var spawn: MapSpawnData = MapSpawnDataScript.new()
	spawn.archetype = missing_archetype
	spawn.weapon = missing_weapon
	map.spawns.append(spawn)
	var missing_profile: TacticalCoverProfile = CoverProfileScript.new()
	missing_profile.cover_id = &"missing_cover"
	missing_profile.display_name = "Missing Cover"
	missing_profile.cover_level = 1
	missing_profile.damage_reduction_ratio = 0.5
	var edge: MapEdgeData = MapEdgeDataScript.new()
	edge.cover_profile_a = missing_profile
	map.edges.append(edge)
	manifest.map_definitions.append(map)
	var placeable: TacticalEdgeDefinition = EdgeDefinitionScript.new()
	placeable.placeable_id = &"cross_reference_edge"
	var rules: TacticalEdgeRules = EdgeRulesScript.new()
	rules.cover_profile_b = missing_profile
	placeable.edge_rules = rules
	manifest.placeable_definitions.append(placeable)
	var registry := RegistryScript.new()
	var report: Dictionary = registry.configure(manifest)
	_expect(not bool(report[&"valid"]), "registry: missing cross references must invalidate the manifest")
	var diagnostics: Array = registry.validate()
	_expect(_has_code(diagnostics, GameDefinitionRegistry.DIAG_MISSING_DEFINITION_REFERENCE), "registry: cross references need a stable diagnostic code")
	var found_owner := false
	for diagnostic in diagnostics:
		if StringName(diagnostic.get(&"code", &"")) != GameDefinitionRegistry.DIAG_MISSING_DEFINITION_REFERENCE:
			continue
		if StringName(diagnostic.get(&"target_definition_id", &"")) == &"missing_weapon":
			found_owner = StringName(diagnostic.get(&"owner_definition_type", &"")) == &"unit_archetype"
			break
	_expect(found_owner, "registry: missing reference diagnostic should identify owner and target")


func _test_alias_resolution_and_cycles() -> void:
	var alias_manifest = _make_manifest()
	alias_manifest.aliases.append(_make_alias(&"item", &"old_shared", &"item", &"shared"))
	var alias_registry := RegistryScript.new()
	var alias_report: Dictionary = alias_registry.configure(alias_manifest)
	_expect(bool(alias_report[&"valid"]), "alias: valid migration should configure")
	var migrated: Dictionary = alias_registry.resolve_result(&"item", &"old_shared")
	_expect(bool(migrated[&"found"]) and migrated[&"definition"].item_id == &"shared", "alias: old key should resolve to target Definition")
	_expect(_has_code(migrated[&"diagnostics"], &"alias_applied"), "alias: resolution should report migration metadata")

	var missing_target_manifest = _make_manifest()
	missing_target_manifest.aliases.append(_make_alias(&"item", &"old_missing", &"item", &"missing"))
	var missing_target_registry := RegistryScript.new()
	missing_target_registry.configure(missing_target_manifest)
	_expect(_has_code(missing_target_registry.validate(), &"alias_target_missing"), "alias: missing target should be diagnosed")

	var cycle_manifest = _make_manifest()
	cycle_manifest.aliases.append(_make_alias(&"item", &"cycle_a", &"item", &"cycle_b"))
	cycle_manifest.aliases.append(_make_alias(&"item", &"cycle_b", &"item", &"cycle_a"))
	var cycle_registry := RegistryScript.new()
	cycle_registry.configure(cycle_manifest)
	_expect(_has_code(cycle_registry.validate(), &"alias_cycle"), "alias: cycle should be diagnosed")
	var cycle_result: Dictionary = cycle_registry.resolve_result(&"item", &"cycle_a")
	_expect(not bool(cycle_result[&"found"]) and _has_code(cycle_result[&"diagnostics"], &"alias_cycle"), "alias: cycle resolution should fail explicitly")


func _test_project_manifest() -> void:
	var manifest = ResourceLoader.load("res://resources/content/game_content_manifest.tres")
	_expect(manifest != null, "manifest: project manifest should load")
	if manifest == null:
		return
	_expect(manifest.item_definitions.size() >= 4, "manifest: current item content should be explicitly referenced")
	_expect(manifest.weapon_definitions.size() >= 3, "manifest: current weapon content should be explicitly referenced")
	_expect(manifest.unit_archetypes.size() >= 5, "manifest: current unit content should be explicitly referenced")
	_expect(manifest.map_definitions.size() >= 4, "manifest: current map content should be explicitly referenced")
	_expect(manifest.placeable_definitions.size() >= 7, "manifest: current placeable content should be explicitly referenced")
	_expect(manifest.cover_profiles.size() >= 3, "manifest: current cover content should be explicitly referenced")
	var registry := RegistryScript.new()
	var report: Dictionary = registry.configure(manifest)
	if not bool(report[&"valid"]):
		for error_message in report[&"errors"]:
			printerr("MANIFEST ERROR: " + String(error_message))
	_expect(bool(report[&"valid"]), "manifest: current explicit manifest should configure without errors")


func _make_manifest():
	var manifest = ManifestScript.new()
	manifest.item_definitions.append(_make_item(&"shared"))
	manifest.weapon_definitions.append(_make_weapon(&"shared"))
	var unit: UnitArchetype = UnitArchetypeScript.new()
	unit.archetype_id = &"unit_shared"
	unit.display_name = "Synthetic Unit"
	unit.default_weapon = manifest.weapon_definitions[0]
	manifest.unit_archetypes.append(unit)
	var map: TacticalMapDefinition = MapDefinitionScript.new()
	map.map_id = &"map_shared"
	map.schema_version = TacticalMapDefinition.CURRENT_SCHEMA_VERSION
	manifest.map_definitions.append(map)
	var placeable: TacticalPlaceableDefinition = PlaceableDefinitionScript.new()
	placeable.placeable_id = &"placeable_shared"
	placeable.display_name = "Synthetic Placeable"
	manifest.placeable_definitions.append(placeable)
	var cover: TacticalCoverProfile = CoverProfileScript.new()
	cover.cover_id = &"cover_shared"
	cover.display_name = "Synthetic Cover"
	manifest.cover_profiles.append(cover)
	return manifest


func _make_item(item_id: StringName) -> ItemDefinition:
	var item: ItemDefinition = ItemDefinitionScript.new()
	item.item_id = item_id
	item.display_name = "Synthetic Item"
	item.value = 1
	return item


func _make_weapon(weapon_id: StringName) -> WeaponDefinition:
	var weapon: WeaponDefinition = WeaponDefinitionScript.new()
	weapon.weapon_id = weapon_id
	weapon.display_name = "Synthetic Weapon"
	weapon.damage = 1
	weapon.range = 1
	weapon.ap_cost = 1
	return weapon


func _make_alias(from_type: StringName, from_id: StringName, to_type: StringName, to_id: StringName):
	var alias = DefinitionAliasScript.new()
	alias.from_type = from_type
	alias.from_id = from_id
	alias.to_type = to_type
	alias.to_id = to_id
	return alias


func _has_code(diagnostics: Array, code: StringName) -> bool:
	for diagnostic in diagnostics:
		if diagnostic is Dictionary and StringName(diagnostic.get(&"code", &"")) == code:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
