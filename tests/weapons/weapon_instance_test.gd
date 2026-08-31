extends SceneTree

const WeaponInstanceScript = preload("res://scripts/core/combat/weapon_instance.gd")
const WeaponInstanceSnapshotScript = preload("res://scripts/core/runtime/snapshots/weapon_instance_snapshot.gd")
const ASSAULT_RIFLE: WeaponDefinition = preload("res://resources/weapons/assault_rifle.tres")
const SHOTGUN: WeaponDefinition = preload("res://resources/weapons/shotgun.tres")

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
	var first: WeaponInstance = WeaponInstanceScript.new(&"weapon_alpha", ASSAULT_RIFLE)
	var second: WeaponInstance = WeaponInstanceScript.new(&"weapon_bravo", ASSAULT_RIFLE)
	_expect(first.is_valid() and second.is_valid(), "instance: same definition should create valid instances")
	_expect(first.instance_id != second.instance_id, "instance: same definition instances need distinct IDs")
	_expect(first.definition == second.definition and first.definition_id == ASSAULT_RIFLE.weapon_id, "instance: definition reference and ID should resolve consistently")
	_expect(first.definition_type == &"weapon", "instance: definition type should be fixed to weapon")
	_expect(first.definition.damage == 4 and first.definition.range == 5 and first.definition.ap_cost == 1, "instance: definition values should remain unchanged")
	var copied: WeaponInstance = first.copy()
	_expect(copied == null and first.last_operation_reason == &"copy_not_supported", "instance: copy must fail instead of creating a duplicate stable ID")

	var snapshot: WeaponInstanceSnapshot = first.to_snapshot_resource()
	_expect(snapshot is WeaponInstanceSnapshotScript and snapshot.is_valid(), "snapshot: weapon snapshot should contain valid identity")
	_expect(snapshot.state_version == WeaponInstanceSnapshot.CURRENT_STATE_VERSION, "snapshot: schema version should start at one")
	var roundtrip: WeaponInstance = WeaponInstanceScript.from_snapshot(snapshot, ASSAULT_RIFLE)
	_expect(roundtrip != null and roundtrip.is_valid(), "snapshot: weapon instance should hydrate with resolved definition")
	if roundtrip != null:
		_expect(roundtrip.instance_id == first.instance_id and roundtrip.definition_id == first.definition_id, "snapshot: identity should round-trip")
		_expect(roundtrip.definition == ASSAULT_RIFLE and roundtrip.definition_type == &"weapon", "snapshot: resolved definition should be retained")

	var dictionary: Dictionary = snapshot.to_dictionary()
	var decoded := WeaponInstanceSnapshotScript.from_dictionary(dictionary)
	_expect(decoded != null and decoded.instance_id == snapshot.instance_id and decoded.definition_id == snapshot.definition_id, "snapshot: dictionary codec should preserve identity")
	var missing_definition_id := dictionary.duplicate(true)
	missing_definition_id.erase(&"definition_id")
	_expect(WeaponInstanceSnapshotScript.from_dictionary(missing_definition_id) == null, "snapshot: missing definition ID must be rejected")
	var wrong_version_type := dictionary.duplicate(true)
	wrong_version_type[&"state_version"] = 1.0
	_expect(WeaponInstanceSnapshotScript.from_dictionary(wrong_version_type) == null, "snapshot: non-integer schema version must be rejected")
	var future_version := dictionary.duplicate(true)
	future_version[&"state_version"] = 2
	_expect(WeaponInstanceSnapshotScript.from_dictionary(future_version) == null, "snapshot: unsupported schema version must be rejected")
	var wrong_instance_type := dictionary.duplicate(true)
	wrong_instance_type[&"instance_id"] = 17
	_expect(WeaponInstanceSnapshotScript.from_dictionary(wrong_instance_type) == null, "snapshot: non-string instance ID must be rejected")
	_expect(WeaponInstanceScript.from_snapshot(snapshot, SHOTGUN) == null, "snapshot: mismatched definition must be rejected")
	_expect(WeaponInstanceScript.from_snapshot(snapshot) == null, "snapshot: missing definition must be rejected")
	var unresolved := WeaponInstanceScript.new()
	_expect(not unresolved.hydrate_from_snapshot(snapshot) and unresolved.last_operation_reason == &"missing_definition", "snapshot: missing definition should expose a stable reason")
	var generic_dictionary: Dictionary = first.to_snapshot()
	var generic_roundtrip: WeaponInstance = WeaponInstanceScript.from_snapshot(generic_dictionary, ASSAULT_RIFLE)
	_expect(generic_roundtrip != null and generic_roundtrip.instance_id == first.instance_id, "snapshot: generic RuntimeInstance dictionary should hydrate")

	var invalid: WeaponInstance = WeaponInstanceScript.new(&"weapon_invalid", null)
	_expect(not invalid.is_valid(), "instance: unresolved definition must not be valid")
	_expect(first.state_version == WeaponInstance.DEFAULT_STATE_VERSION, "instance: state schema version must not be an operation counter")
	var registry := DefinitionRegistryStub.new()
	registry.allow(&"weapon", ASSAULT_RIFLE.weapon_id)
	_expect(first.is_valid(registry), "instance: registry must resolve the weapon definition")
	var missing_registry := DefinitionRegistryStub.new()
	_expect(not first.is_valid(missing_registry), "instance: missing registry definition must invalidate the instance")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("WEAPON_INSTANCE_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WEAPON_INSTANCE_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
