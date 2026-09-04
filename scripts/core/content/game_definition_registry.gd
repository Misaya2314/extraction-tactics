@tool
class_name GameDefinitionRegistry
extends RefCounted

## Read-only lookup index configured from one explicit GameContentManifest.
## Existing Definition resources remain untouched; this class adapts their
## established ID fields to DefinitionKey.

const TYPE_ITEM: StringName = &"item"
const TYPE_WEAPON: StringName = &"weapon"
const TYPE_UNIT_ARCHETYPE: StringName = &"unit_archetype"
const TYPE_MAP: StringName = &"map"
const TYPE_PLACEABLE: StringName = &"placeable"
const TYPE_COVER: StringName = &"cover"
const TYPE_SKILL: StringName = &"skill"
const DIAG_MISSING_DEFINITION_REFERENCE: StringName = &"missing_definition_reference"
const DefinitionKeyScript = preload("res://scripts/core/content/definition_key.gd")

var _manifest
var _definitions: Dictionary = {}
var _ordered_definitions: Dictionary = {}
var _aliases: Dictionary = {}
var _seen_definition_keys: Dictionary = {}
var _diagnostics: Array[Dictionary] = []
var _last_resolution_diagnostics: Array[Dictionary] = []


func configure(manifest) -> Dictionary:
	_clear_index()
	_manifest = manifest
	if manifest == null:
		_append_diagnostic(&"error", &"manifest_missing", "GameContentManifest is required.")
		return _validation_result()
	if typeof(manifest) != TYPE_OBJECT or not manifest.has_method("get_definition_groups"):
		_append_diagnostic(&"error", &"invalid_manifest", "The configured manifest is not a GameContentManifest.")
		return _validation_result()
	if not manifest.is_schema_compatible():
		_append_diagnostic(&"error", &"manifest_schema_unsupported", "Unsupported GameContentManifest schema version %d." % manifest.schema_version)
	for group in manifest.get_definition_groups():
		var definition_type := StringName(group.get(&"definition_type", &""))
		_definitions[definition_type] = {}
		_ordered_definitions[definition_type] = []
		var definitions: Array = group.get(&"definitions", [])
		for definition in definitions:
			_register_definition(definition_type, definition)
	_validate_cross_references()
	for alias in manifest.aliases:
		_register_alias(alias)
	_validate_aliases()
	return _validation_result()


func resolve(definition_type: Variant, definition_id: Variant = &"") -> Resource:
	return resolve_result(definition_type, definition_id).get(&"definition") as Resource


func resolve_key(key) -> Resource:
	return resolve(key, &"")


func resolve_result(definition_type: Variant, definition_id: Variant = &"") -> Dictionary:
	_last_resolution_diagnostics = []
	var requested = _coerce_key(definition_type, definition_id)
	if requested == null or not requested.is_valid():
		var invalid := _make_diagnostic(&"error", &"invalid_definition_key", "DefinitionKey is empty or invalid.", requested)
		_last_resolution_diagnostics.append(invalid)
		return {&"found": false, &"definition": null, &"key": requested, &"diagnostics": _copy_diagnostics(_last_resolution_diagnostics)}

	var current = requested.duplicate_key()
	var visited: Dictionary = {}
	while true:
		var current_string = current.key_string()
		if visited.has(current_string):
			var cycle := _make_diagnostic(&"error", &"alias_cycle", "Definition alias cycle while resolving %s." % requested.key_string(), requested)
			_last_resolution_diagnostics.append(cycle)
			return {&"found": false, &"definition": null, &"key": current, &"diagnostics": _copy_diagnostics(_last_resolution_diagnostics)}
		visited[current_string] = true
		var direct := _lookup_direct(current)
		if direct != null:
			if not current.equals(requested):
				_last_resolution_diagnostics.append(_make_diagnostic(
					&"warning",
					&"alias_applied",
					"Definition %s migrated to %s." % [requested.key_string(), current.key_string()],
					current
				))
			return {
				&"found": true,
				&"definition": direct,
				&"key": current,
				&"requested_key": requested,
				&"diagnostics": _copy_diagnostics(_last_resolution_diagnostics),
			}
		if not _aliases.has(current_string):
			var missing := _make_diagnostic(
				&"error",
				&"missing_definition",
				"Definition %s could not be resolved." % requested.key_string(),
				current
			)
			_last_resolution_diagnostics.append(missing)
			return {&"found": false, &"definition": null, &"key": current, &"diagnostics": _copy_diagnostics(_last_resolution_diagnostics)}
		current = (_aliases[current_string] as Object).call("duplicate_key")
	return {&"found": false, &"definition": null, &"key": current, &"diagnostics": _copy_diagnostics(_last_resolution_diagnostics)}


func contains(definition_type: Variant, definition_id: Variant = &"") -> bool:
	return bool(resolve_result(definition_type, definition_id).get(&"found", false))


func get_all(definition_type: StringName) -> Array[Resource]:
	var result: Array[Resource] = []
	for definition in _ordered_definitions.get(definition_type, []):
		result.append(definition as Resource)
	return result


func validate() -> Array[Dictionary]:
	return _copy_diagnostics(_diagnostics)


func get_last_resolution_diagnostics() -> Array[Dictionary]:
	return _copy_diagnostics(_last_resolution_diagnostics)


func get_manifest():
	return _manifest


func is_configured() -> bool:
	return _manifest != null and _diagnostics.filter(func(item: Dictionary) -> bool: return StringName(item.get(&"severity", &"error")) == &"error").is_empty()


func _clear_index() -> void:
	_definitions.clear()
	_ordered_definitions.clear()
	_aliases.clear()
	_seen_definition_keys.clear()
	_diagnostics = []
	_last_resolution_diagnostics = []


func _register_definition(definition_type: StringName, definition: Resource) -> void:
	if definition == null:
		_append_diagnostic(&"error", &"empty_definition_reference", "Manifest contains an empty %s Definition reference." % definition_type)
		return
	var definition_id := _extract_definition_id(definition_type, definition)
	if definition_id == &"":
		_append_diagnostic(&"error", &"empty_definition_id", "Manifest contains a %s Definition with an empty ID." % definition_type, DefinitionKeyScript.new(definition_type, definition_id))
		return
	var key := DefinitionKeyScript.new(definition_type, definition_id)
	var key_string: String = key.key_string()
	if _seen_definition_keys.has(key_string):
		_append_diagnostic(&"error", &"duplicate_definition_id", "Duplicate %s Definition ID '%s'." % [definition_type, definition_id], DefinitionKeyScript.new(definition_type, definition_id))
		return
	_seen_definition_keys[key_string] = true
	var bucket: Dictionary = _definitions.get(definition_type, {})
	if not _definition_is_valid(definition_type, definition):
		_append_diagnostic(&"error", &"invalid_definition", "Invalid %s Definition '%s'." % [definition_type, definition_id], DefinitionKeyScript.new(definition_type, definition_id))
		return
	bucket[definition_id] = definition
	_definitions[definition_type] = bucket
	var ordered: Array = _ordered_definitions.get(definition_type, [])
	ordered.append(definition)
	_ordered_definitions[definition_type] = ordered


func _register_alias(alias) -> void:
	if alias == null:
		_append_diagnostic(&"error", &"empty_alias_reference", "Manifest contains an empty Definition alias reference.")
		return
	if typeof(alias) != TYPE_OBJECT or not alias.has_method("is_valid") or not alias.has_method("source_key") or not alias.has_method("target_key"):
		_append_diagnostic(&"error", &"invalid_alias", "Manifest contains an invalid Definition alias.")
		return
	if not alias.is_valid():
		_append_diagnostic(&"error", &"invalid_alias", "Manifest contains an invalid Definition alias.")
		return
	var source = alias.source_key()
	var target = alias.target_key()
	var source_string = source.key_string()
	if _aliases.has(source_string):
		_append_diagnostic(&"error", &"duplicate_alias", "Duplicate Definition alias '%s'." % source_string, source)
		return
	_aliases[source_string] = target


func _validate_aliases() -> void:
	for source_string in _aliases.keys():
		var visited: Dictionary = {}
		var current = DefinitionKeyScript.from_values(
			StringName(String(source_string).split("/", false, 1)[0]),
			StringName(String(source_string).split("/", false, 1)[1])
		)
		while _aliases.has(current.key_string()):
			var current_string = current.key_string()
			if visited.has(current_string):
				_append_diagnostic(&"error", &"alias_cycle", "Definition alias cycle starts at %s." % source_string, current)
				break
			visited[current_string] = true
			current = (_aliases[current_string] as Object).call("duplicate_key")
		if not visited.has(current.key_string()) and _lookup_direct(current) == null:
			_append_diagnostic(&"error", &"alias_target_missing", "Definition alias target '%s' is missing." % current.key_string(), current)


func _lookup_direct(key) -> Resource:
	if key == null:
		return null
	var bucket: Dictionary = _definitions.get(key.definition_type, {})
	return bucket.get(key.definition_id) as Resource


func _extract_definition_id(definition_type: StringName, definition: Resource) -> StringName:
	var property_name := ""
	match definition_type:
		TYPE_ITEM:
			property_name = "item_id"
		TYPE_WEAPON:
			property_name = "weapon_id"
		TYPE_UNIT_ARCHETYPE:
			property_name = "archetype_id"
		TYPE_MAP:
			property_name = "map_id"
		TYPE_PLACEABLE:
			property_name = "placeable_id"
		TYPE_COVER:
			property_name = "cover_id"
		TYPE_SKILL:
			property_name = "skill_id"
		_:
			return &""
	var raw_value = definition.get(property_name)
	return &"" if raw_value == null else StringName(raw_value)


func _definition_is_valid(definition_type: StringName, definition: Resource) -> bool:
	if definition_type == TYPE_MAP:
		var map_id = definition.get("map_id")
		var schema = definition.get("schema_version")
		return map_id != null \
			and not String(map_id).strip_edges().is_empty() \
			and schema != null \
			and TacticalMapDefinition.is_schema_version_supported(int(schema))
	if not definition.has_method("is_valid"):
		return false
	return bool(definition.call("is_valid"))


func _coerce_key(definition_type: Variant, definition_id: Variant):
	if typeof(definition_type) == TYPE_OBJECT:
		var object_value: Object = definition_type
		if object_value.get_script() != DefinitionKeyScript:
			return null
		if object_value.has_method("key_string") and object_value.has_method("duplicate_key"):
			var duplicate = object_value.call("duplicate_key")
			if typeof(duplicate) == TYPE_OBJECT and duplicate.get_script() == DefinitionKeyScript:
				return duplicate
			return null
	if definition_type is Dictionary:
		return DefinitionKeyScript.from_dictionary(definition_type as Dictionary)
	if not _is_string_like(definition_type) or not _is_string_like(definition_id):
		return null
	return DefinitionKeyScript.new(StringName(definition_type), StringName(definition_id))


func _validate_cross_references() -> void:
	for archetype in _ordered_definitions.get(TYPE_UNIT_ARCHETYPE, []):
		var owner_id := _extract_definition_id(TYPE_UNIT_ARCHETYPE, archetype as Resource)
		_validate_reference(
			TYPE_UNIT_ARCHETYPE,
			owner_id,
			"default_weapon",
			archetype.get("default_weapon"),
			TYPE_WEAPON,
			"weapon_id",
			true
		)
	for map_definition in _ordered_definitions.get(TYPE_MAP, []):
		_validate_map_references(map_definition as Resource)
	for placeable in _ordered_definitions.get(TYPE_PLACEABLE, []):
		_validate_placeable_references(placeable as Resource)


func _validate_map_references(map_definition: Resource) -> void:
	var owner_id := _extract_definition_id(TYPE_MAP, map_definition)
	var spawns = map_definition.get("spawns")
	if spawns is Array:
		for index in spawns.size():
			var spawn = spawns[index]
			if spawn == null:
				continue
			_validate_reference(
				TYPE_MAP,
				owner_id,
				"spawns[%d].archetype" % index,
				spawn.get("archetype"),
				TYPE_UNIT_ARCHETYPE,
				"archetype_id"
			)
			_validate_reference(
				TYPE_MAP,
				owner_id,
				"spawns[%d].weapon" % index,
				spawn.get("weapon"),
				TYPE_WEAPON,
				"weapon_id"
			)
	var edges = map_definition.get("edges")
	if edges is Array:
		for index in edges.size():
			var edge = edges[index]
			if edge == null:
				continue
			_validate_reference(
				TYPE_MAP,
				owner_id,
				"edges[%d].cover_profile_a" % index,
				edge.get("cover_profile_a"),
				TYPE_COVER,
				"cover_id"
			)
			_validate_reference(
				TYPE_MAP,
				owner_id,
				"edges[%d].cover_profile_b" % index,
				edge.get("cover_profile_b"),
				TYPE_COVER,
				"cover_id"
			)


func _validate_placeable_references(placeable: Resource) -> void:
	var owner_id := _extract_definition_id(TYPE_PLACEABLE, placeable)
	var edge_rules = placeable.get("edge_rules")
	if edge_rules != null:
		_validate_edge_rule_references(TYPE_PLACEABLE, owner_id, "edge_rules", edge_rules)
	var contributions = placeable.get("edge_contributions")
	if contributions is Array:
		for index in contributions.size():
			var contribution = contributions[index]
			if contribution == null:
				continue
			var contribution_rules = contribution.get("edge_rules")
			if contribution_rules != null:
				_validate_edge_rule_references(
					TYPE_PLACEABLE,
					owner_id,
					"edge_contributions[%d].edge_rules" % index,
					contribution_rules
				)


func _validate_edge_rule_references(owner_type: StringName, owner_id: StringName, field_prefix: String, rules) -> void:
	_validate_reference(owner_type, owner_id, field_prefix + ".cover_profile_a", rules.get("cover_profile_a"), TYPE_COVER, "cover_id")
	_validate_reference(owner_type, owner_id, field_prefix + ".cover_profile_b", rules.get("cover_profile_b"), TYPE_COVER, "cover_id")


func _validate_reference(
	owner_type: StringName,
	owner_id: StringName,
	field_name: String,
	reference,
	target_type: StringName,
	target_id_property: String,
	required: bool = false
) -> void:
	if reference == null:
		if required:
			_append_missing_reference(owner_type, owner_id, field_name, target_type, &"")
		return
	var raw_target_id = reference.get(target_id_property)
	if not _is_string_like(raw_target_id):
		_append_missing_reference(owner_type, owner_id, field_name, target_type, &"")
		return
	var target_id := StringName(raw_target_id)
	if target_id == &"" or not _definitions.get(target_type, {}).has(target_id):
		_append_missing_reference(owner_type, owner_id, field_name, target_type, target_id)


func _append_missing_reference(
	owner_type: StringName,
	owner_id: StringName,
	field_name: String,
	target_type: StringName,
	target_id: StringName
) -> void:
	var owner_key = DefinitionKeyScript.new(owner_type, owner_id)
	var target_key = DefinitionKeyScript.new(target_type, target_id)
	var target_label := "%s/<empty>" % target_type if target_id == &"" else target_key.key_string()
	var diagnostic := _make_diagnostic(
		&"error",
		DIAG_MISSING_DEFINITION_REFERENCE,
		"Definition %s field %s references missing %s." % [owner_key.key_string(), field_name, target_label],
		owner_key
	)
	diagnostic[&"owner_definition_type"] = owner_type
	diagnostic[&"owner_definition_id"] = owner_id
	diagnostic[&"reference_field"] = field_name
	diagnostic[&"target_definition_type"] = target_type
	diagnostic[&"target_definition_id"] = target_id
	_diagnostics.append(diagnostic)


func _validation_result() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	for diagnostic in _diagnostics:
		var message := String(diagnostic.get(&"message", ""))
		if StringName(diagnostic.get(&"severity", &"error")) == &"warning":
			warnings.append(message)
		else:
			errors.append(message)
	return {
		&"valid": errors.is_empty(),
		&"errors": errors,
		&"warnings": warnings,
		&"diagnostics": _copy_diagnostics(_diagnostics),
	}


func _append_diagnostic(severity: StringName, code: StringName, message: String, key = null) -> void:
	_diagnostics.append(_make_diagnostic(severity, code, message, key))


func _make_diagnostic(severity: StringName, code: StringName, message: String, key = null) -> Dictionary:
	return {
		&"severity": severity,
		&"code": code,
		&"message": message,
		&"definition_type": key.definition_type if key != null else &"",
		&"definition_id": key.definition_id if key != null else &"",
	}


func _copy_diagnostics(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for diagnostic in source:
		result.append(diagnostic.duplicate(true))
	return result


static func _is_string_like(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING_NAME or typeof(value) == TYPE_STRING
