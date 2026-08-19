@tool
class_name TacticalMapMigrator
extends RefCounted

## Explicit, non-destructive migration helpers. They return new resources or
## reports; they never rewrite a map scene/resource implicitly.


static func can_migrate_schema(version: int) -> bool:
	return version >= TacticalMapDefinition.MIN_SUPPORTED_SCHEMA_VERSION \
		and version <= TacticalMapDefinition.CURRENT_SCHEMA_VERSION


static func migration_report(definition: TacticalMapDefinition) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if definition == null:
		errors.append("TMM-001: Missing TacticalMapDefinition.")
		return _result(errors, warnings, -1, TacticalMapDefinition.CURRENT_SCHEMA_VERSION)
	var from_version := definition.schema_version
	if not can_migrate_schema(from_version):
		errors.append("TMM-002: Cannot migrate unsupported schema %d." % from_version)
	elif from_version < TacticalMapDefinition.CURRENT_SCHEMA_VERSION:
		warnings.append("TMM-003: Adds optional edges array; legacy cover_mask remains intact.")
	return _result(errors, warnings, from_version, TacticalMapDefinition.CURRENT_SCHEMA_VERSION)


static func migrate_definition(definition: TacticalMapDefinition) -> TacticalMapDefinition:
	if definition == null or not can_migrate_schema(definition.schema_version):
		return null
	var result := definition.duplicate(true) as TacticalMapDefinition
	if result == null:
		return null
	if result.edges == null:
		result.edges = []
	result.schema_version = TacticalMapDefinition.CURRENT_SCHEMA_VERSION
	return result


static func migrate_catalog(catalog: MapTileCatalog) -> TacticalPlaceableLibrary:
	var library := TacticalPlaceableLibrary.new()
	if catalog == null:
		return library
	var seen: Dictionary = {}
	for rule in catalog.rules:
		if rule == null:
			continue
		var layer_name := "floor" if rule.layer == MapTileRule.Layer.FLOOR else "structure"
		var id_text := "legacy.%s.%d" % [layer_name, rule.item_id]
		if rule.tile_id != &"":
			id_text = "legacy.%s.%s" % [layer_name, String(rule.tile_id)]
		if seen.has(id_text):
			id_text = "%s.%d" % [id_text, rule.item_id]
		seen[id_text] = true
		var definition := TacticalCellTileDefinition.new()
		definition.placeable_id = StringName(id_text)
		definition.display_name = String(rule.tile_id)
		definition.tile_id = rule.tile_id
		definition.target_layer = rule.layer
		definition.mesh_item_id = rule.item_id
		definition.rule_contribution = TacticalRuleMerger.from_legacy(rule)
		library.definitions.append(definition)
		var binding := MeshItemBinding.new()
		binding.placeable_id = definition.placeable_id
		binding.target_layer = rule.layer
		binding.mesh_item_id = rule.item_id
		library.item_bindings.append(binding)
	return library


static func _result(errors: Array[String], warnings: Array[String], from_version: int, to_version: int) -> Dictionary:
	return {
		&"valid": errors.is_empty(),
		&"errors": errors,
		&"warnings": warnings,
		&"from_schema": from_version,
		&"to_schema": to_version,
		&"changed": from_version != to_version,
	}

