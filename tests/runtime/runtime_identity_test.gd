extends SceneTree

const RuntimeOperationResultScript = preload("res://scripts/core/runtime/runtime_operation_result.gd")
const RuntimeInstanceScript = preload("res://scripts/core/runtime/runtime_instance.gd")
const RuntimeInstanceRegistryScript = preload("res://scripts/core/runtime/runtime_instance_registry.gd")
const InstanceIdGeneratorScript = preload("res://scripts/core/runtime/instance_id_generator.gd")

var _failures := 0


func _init() -> void:
	_test_operation_result()
	_test_runtime_instance_registry()
	_test_deterministic_id_generation()
	if _failures == 0:
		print("RUNTIME_IDENTITY_TEST: PASS")
	else:
		printerr("RUNTIME_IDENTITY_TEST: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_operation_result() -> void:
	var success := RuntimeOperationResultScript.succeeded("payload", "done", &"instance_a")
	_expect(success.success and success.reason_code == &"ok", "result: success result should be explicit")
	_expect(success.value == "payload" and success.related_id == &"instance_a", "result: value and related ID should be preserved")
	var failure := RuntimeOperationResultScript.failed(&"duplicate_instance_id", "already registered", null, &"instance_a")
	_expect(not failure.success and failure.reason_code == &"duplicate_instance_id", "result: failure reason should be stable")
	_expect(failure.as_dictionary()[&"message"] == "already registered", "result: dictionary form should preserve message")


func _test_runtime_instance_registry() -> void:
	var registry := RuntimeInstanceRegistryScript.new()
	var empty := RuntimeInstanceScript.new()
	var empty_result = registry.register(empty)
	_expect(not empty_result.success and empty_result.reason_code == &"invalid_instance_identity", "registry: empty identity must be rejected")
	var first: Variant = RuntimeInstanceScript.new(&"session:item:0000", &"item", &"medkit")
	var second: Variant = RuntimeInstanceScript.new(&"session:item:0001", &"item", &"medkit")
	var first_result = registry.register(first)
	_expect(first_result.success and registry.size() == 1, "registry: valid instance should register")
	_expect(first.call("get_stable_instance_id") == first.get("instance_id"), "instance: stable identity accessor should expose the StringName identity")
	_expect(first.call("get_definition_key").call("key_string") == "item/medkit", "instance: get_definition_key should expose both definition fields")
	_expect(bool(first.call("is_valid")), "instance: identity-only validation should accept a valid instance")
	_expect(first.call("to_snapshot")[&"instance_id"] == first.get("instance_id"), "instance: base snapshot should include stable identity")
	var duplicate_result = registry.register(RuntimeInstanceScript.new(&"session:item:0000", &"item", &"other"))
	_expect(not duplicate_result.success and duplicate_result.reason_code == &"duplicate_instance_id", "registry: duplicate ID must be rejected")
	_expect(registry.get_instance(&"session:item:0000") == first, "registry: query should return the registered object")
	_expect(registry.register(second).success and registry.get_all().size() == 2, "registry: independent IDs should coexist")
	var first_id: StringName = first.get("instance_id")
	var removed = registry.unregister(first_id)
	_expect(removed.success and not registry.contains(first_id) and registry.size() == 1, "registry: unregister should remove exactly one instance")
	var missing = registry.unregister(first_id)
	_expect(not missing.success and missing.reason_code == &"instance_not_found", "registry: missing unregister should be explicit")
	registry.clear()
	_expect(registry.size() == 0, "registry: clear should empty the identity index")


func _test_deterministic_id_generation() -> void:
	var first_generator := InstanceIdGeneratorScript.new(&"raid_alpha")
	var first_dynamic := first_generator.next_id(&"item")
	var first_fixed := first_generator.id_for_placement(&"unit", &"map_a", &"spawn_01")
	_expect(first_dynamic == &"raid_alpha:item:0000", "generator: dynamic ID should include session/type/counter")
	_expect(first_fixed == &"raid_alpha:unit:map_a:spawn_01", "generator: fixed point ID should include explicit placement identity")
	_expect(first_generator.fixed_point(&"unit", &"map_a", &"spawn_01") == first_fixed, "generator: fixed point ID should be stable")
	var captured: Dictionary = first_generator.capture_state()
	var second_dynamic := first_generator.next_dynamic(&"item")

	var same_inputs := InstanceIdGeneratorScript.new(&"raid_alpha")
	_expect(same_inputs.next_dynamic(&"item") == first_dynamic, "generator: same session and order should be deterministic")
	_expect(same_inputs.fixed_point(&"unit", &"map_a", &"spawn_01") == first_fixed, "generator: same fixed inputs should be deterministic")
	_expect(same_inputs.restore_state(captured), "generator: captured state should restore")
	_expect(same_inputs.next_dynamic(&"item") == second_dynamic, "generator: restored counter should continue without collision")

	var reserved := InstanceIdGeneratorScript.new(&"raid_beta")
	_expect(reserved.reserve(&"raid_beta:item:0005"), "generator: explicit old ID should be reservable")
	_expect(reserved.next_dynamic(&"item") == &"raid_beta:item:0006", "generator: reserving a dynamic ID should advance the counter")
	_expect(not reserved.reserve(&"raid_beta:item:0005"), "generator: duplicate reservation should be rejected")
	_expect(reserved.restore_state({&"session_id": &"other", &"counters": {}, &"reserved_ids": []}) == false, "generator: foreign session state should be rejected")
	_expect(not reserved.restore_state(42), "generator: non-dictionary restore state must be rejected")
	_expect(not reserved.restore_state({&"session_id": 42, &"counters": {}, &"reserved_ids": []}), "generator: numeric session state must be rejected")
	_expect(not reserved.restore_state({&"session_id": &"raid_beta", &"counters": {42: 1}, &"reserved_ids": []}), "generator: numeric counter key must be rejected")
	_expect(not reserved.restore_state({&"session_id": &"raid_beta", &"counters": {}, &"reserved_ids": [42]}), "generator: numeric reserved ID must be rejected")
	_expect(not reserved.restore_state({&"session_id": &"raid_beta", &"counters": {}, &"reserved_ids": [RefCounted.new()]}), "generator: object reserved ID must be rejected")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
