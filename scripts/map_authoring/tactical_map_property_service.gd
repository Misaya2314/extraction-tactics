@tool
class_name TacticalMapPropertyService
extends RefCounted

## Data-only property inspection and editing for the map authoring layer.
## EditorPlugin code can wrap these mutations in EditorUndoRedoManager
## actions; this service deliberately does not create editor undo actions.

signal authoring_data_changed(author: TacticalMapAuthor, coordinates: Array[Vector3i])
signal overrides_changed(author: TacticalMapAuthor, coordinates: Array[Vector3i])
signal default_source_changed(source: Resource, field: int)


func inspect_cells(author: TacticalMapAuthor, coordinates: Array[Vector3i]) -> Dictionary:
	var ordered_coordinates := _normalize_coordinates(coordinates)
	if author == null:
		return _missing_author_inspection(ordered_coordinates)
	return _inspect_compiled_cells(author, ordered_coordinates, TacticalMapBaker.compile_cells(author, true))


func inspect_all_cells(author: TacticalMapAuthor) -> Dictionary:
	if author == null:
		return _missing_author_inspection([])
	var compiled := TacticalMapBaker.compile_cells(author, true)
	var cells: Dictionary = compiled[&"cells"]
	var coordinates: Array[Vector3i] = []
	for coordinate in cells.keys():
		coordinates.append(coordinate)
	return _inspect_compiled_cells(author, _normalize_coordinates(coordinates), compiled)


func validate_author(author: TacticalMapAuthor) -> Dictionary:
	if author == null:
		var missing_message := "Missing TacticalMapAuthor."
		return {
			&"valid": false,
			&"errors": [missing_message],
			&"warnings": [],
			&"diagnostics": [TacticalMapDiagnostics.error(&"TMB-000", missing_message)],
		}
	var result := TacticalMapBaker.build(author)
	return {
		&"valid": (result[&"errors"] as Array[String]).is_empty(),
		&"errors": result[&"errors"],
		&"warnings": result[&"warnings"],
		&"diagnostics": result[&"diagnostics"],
		&"definition": result[&"definition"],
	}


func validation_diagnostics(author: TacticalMapAuthor) -> Array[Dictionary]:
	return validate_author(author)[&"diagnostics"]


func _inspect_compiled_cells(author: TacticalMapAuthor, ordered_coordinates: Array[Vector3i], compiled: Dictionary) -> Dictionary:
	var inspected: Array[Dictionary] = []
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var diagnostics: Array[Dictionary] = []
	errors.append_array(compiled[&"errors"])
	warnings.append_array(compiled[&"warnings"])
	diagnostics.append_array(compiled.get(&"diagnostics", []))
	var cells: Dictionary = compiled[&"cells"]
	var base_rules: Dictionary = compiled[&"base_rules"]
	var effective_rules: Dictionary = compiled[&"effective_rules"]
	var floor_content: Dictionary = compiled[&"floor_content"]
	var structure_content: Dictionary = compiled[&"structure_content"]
	var override_map: Dictionary = {}
	if author.authoring_data != null:
		override_map = author.authoring_data.get_cell_override_map()

	for coordinate in ordered_coordinates:
		var in_bounds := _inside_volume(author, coordinate)
		var exists := cells.has(coordinate)
		var cell_errors: Array[String] = []
		var cell_diagnostics: Array[Dictionary] = []
		if not in_bounds:
			var outside_message := "TP-002: Cell %s is outside the declared map volume." % coordinate
			cell_errors.append(outside_message)
			cell_diagnostics.append(TacticalMapDiagnostics.error(&"TP-002", outside_message, coordinate))
		elif not floor_content.has(coordinate):
			var no_floor_message := "TP-003: Cell %s has no Floor content." % coordinate
			cell_errors.append(no_floor_message)
			cell_diagnostics.append(TacticalMapDiagnostics.error(&"TP-003", no_floor_message, coordinate))
		var cell_override: TacticalCellOverride = override_map.get(coordinate) as TacticalCellOverride
		var base: TacticalCellRules = base_rules.get(coordinate) as TacticalCellRules
		var effective: TacticalCellRules = effective_rules.get(coordinate) as TacticalCellRules
		inspected.append({
			&"coordinate": coordinate,
			&"exists": exists,
			&"in_bounds": in_bounds,
			&"has_floor": floor_content.has(coordinate),
			&"has_structure": structure_content.has(coordinate),
			&"floor": _copy_content(floor_content.get(coordinate, {})),
			&"structure": _copy_content(structure_content.get(coordinate, {})),
			&"base_rules": base.duplicate_rules() if base != null else null,
			&"override_mask": cell_override.override_mask if cell_override != null else 0,
			&"override_values": cell_override.values.duplicate_rules() if cell_override != null and cell_override.values != null else null,
			&"effective_rules": effective.duplicate_rules() if effective != null else null,
			&"errors": cell_errors,
			&"warnings": [],
			&"diagnostics": cell_diagnostics,
		})
		diagnostics.append_array(cell_diagnostics)

	return {
		&"cells": inspected,
		&"summary": _summarize(inspected),
		&"errors": errors,
		&"warnings": warnings,
		&"diagnostics": TacticalMapDiagnostics.sort_diagnostics(diagnostics),
	}


func _missing_author_inspection(ordered_coordinates: Array[Vector3i]) -> Dictionary:
	var message := "TP-001: Missing TacticalMapAuthor."
	var diagnostic := TacticalMapDiagnostics.error(&"TP-001", message)
	var inspected: Array[Dictionary] = []
	for coordinate in ordered_coordinates:
		var cell := _empty_cell_inspection(coordinate, [message])
		cell[&"diagnostics"] = [diagnostic.duplicate(true)]
		inspected.append(cell)
	return {
		&"cells": inspected,
		&"summary": _summarize(inspected),
		&"errors": [message],
		&"warnings": [],
		&"diagnostics": [diagnostic],
	}


func field_descriptors() -> Array[Dictionary]:
	return [
		{
			&"field": TacticalCellOverride.Field.WALKABLE,
			&"bit": TacticalCellOverride.Field.WALKABLE,
			&"id": &"walkable",
			&"label": "可通行",
			&"type": &"bool",
			&"min": null,
			&"max": null,
			&"step": null,
		},
		{
			&"field": TacticalCellOverride.Field.MOVE_COST,
			&"bit": TacticalCellOverride.Field.MOVE_COST,
			&"id": &"move_cost",
			&"label": "移动消耗",
			&"type": &"int",
			&"min": 1,
			&"max": 99,
			&"step": 1,
		},
		{
			&"field": TacticalCellOverride.Field.SIGHT_BLOCK,
			&"bit": TacticalCellOverride.Field.SIGHT_BLOCK,
			&"id": &"sight_block",
			&"label": "视线阻挡",
			&"type": &"float",
			&"min": 0.0,
			&"max": 1.0,
			&"step": 0.01,
		},
		{
			&"field": TacticalCellOverride.Field.PROJECTILE_BLOCK,
			&"bit": TacticalCellOverride.Field.PROJECTILE_BLOCK,
			&"id": &"projectile_block",
			&"label": "弹道阻挡",
			&"type": &"float",
			&"min": 0.0,
			&"max": 1.0,
			&"step": 0.01,
		},
		{
			&"field": TacticalCellOverride.Field.OCCLUDER_HEIGHT,
			&"bit": TacticalCellOverride.Field.OCCLUDER_HEIGHT,
			&"id": &"occluder_height",
			&"label": "遮挡高度",
			&"type": &"float",
			&"min": 0.0,
			&"max": 20.0,
			&"step": 0.05,
		},
		{
			&"field": TacticalCellOverride.Field.SOUND_COST,
			&"bit": TacticalCellOverride.Field.SOUND_COST,
			&"id": &"sound_cost",
			&"label": "声音消耗",
			&"type": &"float",
			&"min": 0.0,
			&"max": 99.0,
			&"step": 0.05,
		},
		{
			&"field": TacticalCellOverride.Field.TERRAIN_TAGS,
			&"bit": TacticalCellOverride.Field.TERRAIN_TAGS,
			&"id": &"terrain_tags",
			&"label": "地形标签",
			&"type": &"string_array",
			&"min": null,
			&"max": null,
			&"step": null,
		},
		{
			&"field": TacticalCellOverride.Field.HAZARD_ID,
			&"bit": TacticalCellOverride.Field.HAZARD_ID,
			&"id": &"hazard_id",
			&"label": "危险标识",
			&"type": &"string_name",
			&"min": null,
			&"max": null,
			&"step": null,
		},
	]


func inspect_default_source(source: Resource) -> Dictionary:
	if source == null:
		return _invalid_default_source_result("TMS-001: Missing default property source.")
	var source_kind := _default_source_kind(source)
	if source_kind == &"":
		return _invalid_default_source_result("TMS-002: Unsupported default property source type.")
	var fields: Array[Dictionary] = []
	var rules: TacticalCellRules = null
	var rule_contribution_present := false
	if source is TacticalCellTileDefinition:
		var definition := source as TacticalCellTileDefinition
		rule_contribution_present = definition.rule_contribution != null
		rules = definition.rule_contribution.duplicate_rules() if rule_contribution_present else TacticalCellRules.new()
		for descriptor in field_descriptors():
			var field_descriptor := descriptor.duplicate(true)
			field_descriptor[&"field_supported"] = true
			field_descriptor[&"supported"] = true
			field_descriptor[&"reason"] = "TacticalCellRules.rule_contribution supports this field."
			field_descriptor[&"value"] = _read_field(rules, int(descriptor[&"field"]))
			fields.append(field_descriptor)
	elif source is MapTileRule:
		var legacy := source as MapTileRule
		var legacy_rules := TacticalRuleMerger.from_legacy(legacy)
		for descriptor in field_descriptors():
			var field_descriptor := descriptor.duplicate(true)
			if int(descriptor[&"field"]) == TacticalCellOverride.Field.SIGHT_BLOCK:
				field_descriptor[&"step"] = 1.0
				field_descriptor[&"allowed_values"] = [0.0, 1.0]
				field_descriptor[&"constraint"] = &"binary"
			var legacy_info := _legacy_field_info(legacy, int(descriptor[&"field"]), legacy_rules)
			field_descriptor[&"field_supported"] = legacy_info[&"supported"]
			field_descriptor[&"supported"] = legacy_info[&"supported"]
			field_descriptor[&"reason"] = legacy_info[&"reason"]
			field_descriptor[&"value"] = legacy_info[&"value"]
			fields.append(field_descriptor)
		rules = legacy_rules

	return {
		&"valid": true,
		&"source": source,
		&"source_kind": source_kind,
		&"source_id": _default_source_id(source),
		&"rule_contribution_present": rule_contribution_present,
		&"rules": rules,
		&"fields": fields,
		&"errors": [],
		&"warnings": [],
		&"diagnostics": [],
	}


func capture_default_state(source: Resource) -> Dictionary:
	if source == null:
		return {&"valid": false, &"source_kind": &"", &"errors": ["TMS-001: Missing default property source."]}
	if source is TacticalCellTileDefinition:
		var definition := source as TacticalCellTileDefinition
		return {
			&"valid": true,
			&"source_kind": &"definition",
			&"rule_contribution_present": definition.rule_contribution != null,
			&"rules": definition.rule_contribution.duplicate_rules() if definition.rule_contribution != null else null,
		}
	if source is MapTileRule:
		var legacy := source as MapTileRule
		return {
			&"valid": true,
			&"source_kind": &"legacy",
			&"layer": legacy.layer,
			&"item_id": legacy.item_id,
			&"tile_id": legacy.tile_id,
			&"walkable": legacy.walkable,
			&"move_cost": legacy.move_cost,
			&"blocks_los": legacy.blocks_los,
			&"occluder_height": legacy.occluder_height,
			&"cover_mask": legacy.cover_mask,
		}
	return {&"valid": false, &"source_kind": &"", &"errors": ["TMS-002: Unsupported default property source type."]}


func apply_default_field(source: Resource, field: int, value: Variant) -> bool:
	if source == null:
		return false
	if source is TacticalCellTileDefinition:
		var definition := source as TacticalCellTileDefinition
		var coerced := _coerce_field_value(field, value)
		if not bool(coerced.get(&"valid", false)):
			return false
		var old_rules := definition.rule_contribution
		var old_value: Variant = _read_field(old_rules, field) if old_rules != null else null
		var normalized_value: Variant = coerced[&"value"]
		if old_rules != null and _values_equal(old_value, normalized_value):
			return false
		if old_rules == null:
			old_rules = TacticalCellRules.new()
			definition.rule_contribution = old_rules
		_write_field(old_rules, field, normalized_value)
		old_rules.emit_changed()
		definition.emit_changed()
		_emit_default_source_change(definition, field)
		return true
	if source is MapTileRule:
		var legacy := source as MapTileRule
		var legacy_info := _legacy_field_info(legacy, field, TacticalRuleMerger.from_legacy(legacy))
		if not bool(legacy_info[&"supported"]):
			return false
		var normalized_legacy := _coerce_legacy_field(field, value)
		if not bool(normalized_legacy.get(&"valid", false)):
			return false
		if _values_equal(legacy_info[&"value"], normalized_legacy[&"value"]):
			return false
		_write_legacy_field(legacy, field, normalized_legacy[&"value"])
		legacy.emit_changed()
		_emit_default_source_change(legacy, field)
		return true
	return false


func restore_default_state(source: Resource, snapshot: Dictionary) -> bool:
	if source == null or not bool(snapshot.get(&"valid", false)):
		return false
	if source is TacticalCellTileDefinition and snapshot.get(&"source_kind", &"") == &"definition":
		var definition := source as TacticalCellTileDefinition
		var wants_rules := bool(snapshot.get(&"rule_contribution_present", false))
		var snapshot_rules: TacticalCellRules = snapshot.get(&"rules") as TacticalCellRules
		if wants_rules and snapshot_rules == null:
			return false
		var current_rules := definition.rule_contribution
		var same := (current_rules != null) == wants_rules
		if same and wants_rules:
			same = _rules_equal(current_rules, snapshot_rules)
		if same:
			return false
		definition.rule_contribution = snapshot_rules.duplicate_rules() if wants_rules else null
		if definition.rule_contribution != null:
			definition.rule_contribution.emit_changed()
		definition.emit_changed()
		_emit_default_source_change(definition, -1)
		return true
	if source is MapTileRule and snapshot.get(&"source_kind", &"") == &"legacy":
		var legacy := source as MapTileRule
		var same := legacy.layer == int(snapshot.get(&"layer", legacy.layer)) \
			and legacy.item_id == int(snapshot.get(&"item_id", legacy.item_id)) \
			and legacy.tile_id == StringName(snapshot.get(&"tile_id", legacy.tile_id)) \
			and legacy.walkable == bool(snapshot.get(&"walkable", legacy.walkable)) \
			and legacy.move_cost == int(snapshot.get(&"move_cost", legacy.move_cost)) \
			and legacy.blocks_los == bool(snapshot.get(&"blocks_los", legacy.blocks_los)) \
			and is_equal_approx(legacy.occluder_height, float(snapshot.get(&"occluder_height", legacy.occluder_height))) \
			and legacy.cover_mask == int(snapshot.get(&"cover_mask", legacy.cover_mask))
		if same:
			return false
		legacy.layer = int(snapshot.get(&"layer", legacy.layer))
		legacy.item_id = int(snapshot.get(&"item_id", legacy.item_id))
		legacy.tile_id = StringName(snapshot.get(&"tile_id", legacy.tile_id))
		legacy.walkable = bool(snapshot.get(&"walkable", legacy.walkable))
		legacy.move_cost = int(snapshot.get(&"move_cost", legacy.move_cost))
		legacy.blocks_los = bool(snapshot.get(&"blocks_los", legacy.blocks_los))
		legacy.occluder_height = float(snapshot.get(&"occluder_height", legacy.occluder_height))
		legacy.cover_mask = int(snapshot.get(&"cover_mask", legacy.cover_mask))
		legacy.emit_changed()
		_emit_default_source_change(legacy, -1)
		return true
	return false


func capture_override_state(author: TacticalMapAuthor, coordinates: Array[Vector3i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ordered_coordinates := _normalize_coordinates(coordinates)
	var authoring_data_present := author != null and author.authoring_data != null
	var override_map: Dictionary = {}
	if author != null and author.authoring_data != null:
		override_map = author.authoring_data.get_cell_override_map()
	for coordinate in ordered_coordinates:
		var cell_override: TacticalCellOverride = override_map.get(coordinate) as TacticalCellOverride
		if cell_override == null or cell_override.override_mask == 0:
			result.append({
				&"coordinate": coordinate,
				&"present": false,
				&"override_mask": 0,
				&"values": null,
				&"authoring_data_present": authoring_data_present,
			})
		else:
			result.append({
				&"coordinate": coordinate,
				&"present": true,
				&"override_mask": cell_override.override_mask,
				&"values": cell_override.values.duplicate_rules() if cell_override.values != null else null,
				&"authoring_data_present": authoring_data_present,
			})
	return result


func restore_override_state(author: TacticalMapAuthor, snapshots: Array[Dictionary]) -> bool:
	if author == null or snapshots.is_empty():
		return false
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	var snapshot_authoring_data_present := true
	var has_authoring_data_presence := false
	for snapshot in snapshots:
		if not snapshot.has(&"coordinate"):
			return false
		var coordinate: Vector3i = snapshot[&"coordinate"]
		if seen.has(coordinate):
			continue
		seen[coordinate] = true
		var present := bool(snapshot.get(&"present", false))
		var mask := int(snapshot.get(&"override_mask", 0))
		var values := snapshot.get(&"values") as TacticalCellRules
		if snapshot.has(&"authoring_data_present"):
			var entry_authoring_data_present := bool(snapshot[&"authoring_data_present"])
			if has_authoring_data_presence and entry_authoring_data_present != snapshot_authoring_data_present:
				return false
			snapshot_authoring_data_present = entry_authoring_data_present
			has_authoring_data_presence = true
		if present and (mask <= 0 or (mask & ~TacticalCellOverride.ALL_FIELDS) != 0 or values == null or not values.is_valid()):
			return false
		entries.append({
			&"coordinate": coordinate,
			&"present": present,
			&"override_mask": mask,
			&"values": values,
			&"authoring_data_present": snapshot_authoring_data_present,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _coordinate_less(a[&"coordinate"], b[&"coordinate"])
	)

	var compiled := TacticalMapBaker.compile_cells(author, false)
	for entry in entries:
		if bool(entry[&"present"]):
			var coordinate: Vector3i = entry[&"coordinate"]
			if not _inside_volume(author, coordinate) or not (compiled[&"cells"] as Dictionary).has(coordinate):
				return false

	var data := author.authoring_data
	var changed_coordinates: Array[Vector3i] = []
	for entry in entries:
		var coordinate: Vector3i = entry[&"coordinate"]
		var current: TacticalCellOverride = data.find_cell_override(coordinate) if data != null else null
		if _override_matches_snapshot(current, entry):
			continue
		changed_coordinates.append(coordinate)
	var desired_authoring_data_present := snapshot_authoring_data_present
	var data_presence_change := (desired_authoring_data_present and data == null) \
		or (not desired_authoring_data_present and data != null and data.is_empty())
	if changed_coordinates.is_empty() and not data_presence_change:
		return false
	if changed_coordinates.is_empty() and data_presence_change:
		for entry in entries:
			changed_coordinates.append(entry[&"coordinate"])

	if data == null:
		data = TacticalMapAuthoringData.new()
		author.authoring_data = data
	for entry in entries:
		var coordinate: Vector3i = entry[&"coordinate"]
		if not changed_coordinates.has(coordinate):
			continue
		var current: TacticalCellOverride = data.find_cell_override(coordinate)
		if bool(entry[&"present"]):
			if current == null:
				current = TacticalCellOverride.new()
				current.coordinate = coordinate
				data.cell_overrides.append(current)
			current.override_mask = int(entry[&"override_mask"])
			var snapshot_values: TacticalCellRules = entry[&"values"]
			current.values = snapshot_values.duplicate_rules()
			current.values.emit_changed()
			current.emit_changed()
		else:
			for index in range(data.cell_overrides.size() - 1, -1, -1):
				var candidate: TacticalCellOverride = data.cell_overrides[index]
				if candidate != null and candidate.coordinate == coordinate:
					data.cell_overrides.remove_at(index)
		_sort_overrides(data)
	var remove_empty_authoring_data := not snapshot_authoring_data_present and data.is_empty()
	if remove_empty_authoring_data:
		author.authoring_data = null
		_emit_change(author, changed_coordinates, data)
	else:
		_emit_change(author, changed_coordinates)
	return true


func apply_override_field(author: TacticalMapAuthor, coordinates: Array[Vector3i], field: int, value: Variant) -> bool:
	var descriptor := _descriptor_for(field)
	if author == null or descriptor.is_empty():
		return false
	var ordered_coordinates := _normalize_coordinates(coordinates)
	if ordered_coordinates.is_empty() or not _can_edit_cells(author, ordered_coordinates):
		return false
	var coerced := _coerce_field_value(field, value)
	if not bool(coerced[&"valid"]):
		return false
	var normalized_value: Variant = coerced[&"value"]
	var data := author.authoring_data
	var changed_coordinates: Array[Vector3i] = []
	for coordinate in ordered_coordinates:
		var current: TacticalCellOverride = data.find_cell_override(coordinate) if data != null else null
		if current == null or not current.has_override(field) or current.values == null or not _values_equal(_read_field(current.values, field), normalized_value):
			changed_coordinates.append(coordinate)
	if changed_coordinates.is_empty():
		return false

	if data == null:
		data = TacticalMapAuthoringData.new()
		author.authoring_data = data
	for coordinate in changed_coordinates:
		var current: TacticalCellOverride = data.find_cell_override(coordinate)
		if current == null:
			current = TacticalCellOverride.new()
			current.coordinate = coordinate
			current.values = TacticalCellRules.new()
			data.cell_overrides.append(current)
		elif current.values == null:
			current.values = TacticalCellRules.new()
		_write_field(current.values, field, normalized_value)
		current.override_mask |= field
		current.values.emit_changed()
		current.emit_changed()
	_sort_overrides(data)
	_emit_change(author, changed_coordinates)
	return true


func clear_override_field(author: TacticalMapAuthor, coordinates: Array[Vector3i], field: int) -> bool:
	if author == null or _descriptor_for(field).is_empty():
		return false
	var ordered_coordinates := _normalize_coordinates(coordinates)
	if ordered_coordinates.is_empty() or not _can_edit_cells(author, ordered_coordinates) or author.authoring_data == null:
		return false
	var data := author.authoring_data
	var changed_coordinates: Array[Vector3i] = []
	for coordinate in ordered_coordinates:
		var current := data.find_cell_override(coordinate)
		if current != null and current.has_override(field):
			changed_coordinates.append(coordinate)
	if changed_coordinates.is_empty():
		return false

	for coordinate in changed_coordinates:
		for index in range(data.cell_overrides.size() - 1, -1, -1):
			var current: TacticalCellOverride = data.cell_overrides[index]
			if current == null or current.coordinate != coordinate:
				continue
			current.override_mask &= ~field
			current.emit_changed()
			if current.override_mask == 0:
				data.cell_overrides.remove_at(index)
			break
	_sort_overrides(data)
	_emit_change(author, changed_coordinates)
	return true


func _can_edit_cells(author: TacticalMapAuthor, coordinates: Array[Vector3i]) -> bool:
	var compiled := TacticalMapBaker.compile_cells(author, false)
	var cells: Dictionary = compiled[&"cells"]
	for coordinate in coordinates:
		if not _inside_volume(author, coordinate) or not cells.has(coordinate):
			return false
	return true


func _emit_change(author: TacticalMapAuthor, coordinates: Array[Vector3i], data_override: TacticalMapAuthoringData = null) -> void:
	var data_to_emit := author.authoring_data if data_override == null else data_override
	if data_to_emit != null:
		data_to_emit.emit_changed()
	authoring_data_changed.emit(author, coordinates)
	overrides_changed.emit(author, coordinates)


func _descriptor_for(field: int) -> Dictionary:
	for descriptor in field_descriptors():
		if int(descriptor[&"field"]) == field:
			return descriptor
	return {}


func _coerce_field_value(field: int, value: Variant) -> Dictionary:
	match field:
		TacticalCellOverride.Field.WALKABLE:
			if typeof(value) != TYPE_BOOL:
				return {&"valid": false}
			return {&"valid": true, &"value": bool(value)}
		TacticalCellOverride.Field.MOVE_COST:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return {&"valid": false}
			var move_value := int(value)
			if not is_equal_approx(float(value), float(move_value)) or move_value < 1 or move_value > 99:
				return {&"valid": false}
			return {&"valid": true, &"value": move_value}
		TacticalCellOverride.Field.SIGHT_BLOCK, TacticalCellOverride.Field.PROJECTILE_BLOCK:
			return _coerce_float(value, 0.0, 1.0)
		TacticalCellOverride.Field.OCCLUDER_HEIGHT:
			return _coerce_float(value, 0.0, 20.0)
		TacticalCellOverride.Field.SOUND_COST:
			return _coerce_float(value, 0.0, 99.0)
		TacticalCellOverride.Field.TERRAIN_TAGS:
			var tags: Array[String] = []
			if value is PackedStringArray:
				for tag in value:
					if not tags.has(String(tag)):
						tags.append(String(tag))
			elif value is Array:
				for tag in value:
					if not tags.has(String(tag)):
						tags.append(String(tag))
			else:
				return {&"valid": false}
			tags.sort()
			return {&"valid": true, &"value": PackedStringArray(tags)}
		TacticalCellOverride.Field.HAZARD_ID:
			if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
				return {&"valid": false}
			return {&"valid": true, &"value": StringName(value)}
	return {&"valid": false}


func _coerce_float(value: Variant, minimum: float, maximum: float) -> Dictionary:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return {&"valid": false}
	var result := float(value)
	if result < minimum or result > maximum:
		return {&"valid": false}
	return {&"valid": true, &"value": result}


func _default_source_kind(source: Resource) -> StringName:
	if source is TacticalCellTileDefinition:
		return &"definition"
	if source is MapTileRule:
		return &"legacy"
	return &""


func _default_source_id(source: Resource) -> StringName:
	if source is TacticalCellTileDefinition:
		return (source as TacticalCellTileDefinition).placeable_id
	if source is MapTileRule:
		var legacy := source as MapTileRule
		return StringName("%d:%d:%s" % [legacy.layer, legacy.item_id, legacy.tile_id])
	return &""


func _invalid_default_source_result(message: String) -> Dictionary:
	var code := &"TMS-001" if message.begins_with("TMS-001") else &"TMS-002"
	return {
		&"valid": false,
		&"source_kind": &"",
		&"source_id": &"",
		&"fields": [],
		&"errors": [message],
		&"warnings": [],
		&"diagnostics": [TacticalMapDiagnostics.error(code, message)],
	}


func _legacy_field_info(legacy: MapTileRule, field: int, legacy_rules: TacticalCellRules) -> Dictionary:
	match field:
		TacticalCellOverride.Field.WALKABLE:
			return {&"supported": true, &"value": legacy.walkable, &"reason": "MapTileRule.walkable is directly editable."}
		TacticalCellOverride.Field.MOVE_COST:
			return {&"supported": true, &"value": legacy.move_cost, &"reason": "MapTileRule.move_cost is directly editable."}
		TacticalCellOverride.Field.SIGHT_BLOCK:
			return {
				&"supported": true,
				&"value": 1.0 if legacy.blocks_los else 0.0,
				&"reason": "Legacy blocks_los maps only to complete (1.0) or absent (0.0) sight blocking; only values 0 or 1 are accepted, partial values are unsupported.",
			}
		TacticalCellOverride.Field.OCCLUDER_HEIGHT:
			return {&"supported": true, &"value": legacy.occluder_height, &"reason": "MapTileRule.occluder_height is directly editable."}
		TacticalCellOverride.Field.PROJECTILE_BLOCK:
			return {&"supported": false, &"value": null, &"reason": "Legacy MapTileRule has no independent projectile_block field; no other semantic is mutated."}
		TacticalCellOverride.Field.SOUND_COST:
			return {&"supported": false, &"value": null, &"reason": "Legacy MapTileRule has no sound_cost field."}
		TacticalCellOverride.Field.TERRAIN_TAGS:
			return {&"supported": false, &"value": null, &"reason": "Legacy MapTileRule has no terrain_tags field."}
		TacticalCellOverride.Field.HAZARD_ID:
			return {&"supported": false, &"value": null, &"reason": "Legacy MapTileRule has no hazard_id field."}
	return {&"supported": false, &"value": null, &"reason": "Unknown default field."}


func _coerce_legacy_field(field: int, value: Variant) -> Dictionary:
	match field:
		TacticalCellOverride.Field.WALKABLE, TacticalCellOverride.Field.MOVE_COST, TacticalCellOverride.Field.OCCLUDER_HEIGHT:
			return _coerce_field_value(field, value)
		TacticalCellOverride.Field.SIGHT_BLOCK:
			if typeof(value) == TYPE_BOOL:
				return {&"valid": true, &"value": 1.0 if bool(value) else 0.0}
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return {&"valid": false}
			var binary_value := float(value)
			if is_equal_approx(binary_value, 0.0) or is_equal_approx(binary_value, 1.0):
				return {&"valid": true, &"value": binary_value}
	return {&"valid": false}


func _write_legacy_field(legacy: MapTileRule, field: int, value: Variant) -> void:
	match field:
		TacticalCellOverride.Field.WALKABLE:
			legacy.walkable = bool(value)
		TacticalCellOverride.Field.MOVE_COST:
			legacy.move_cost = int(value)
		TacticalCellOverride.Field.SIGHT_BLOCK:
			legacy.blocks_los = float(value) > 0.5
		TacticalCellOverride.Field.OCCLUDER_HEIGHT:
			legacy.occluder_height = float(value)


func _emit_default_source_change(source: Resource, field: int) -> void:
	default_source_changed.emit(source, field)


func _write_field(values: TacticalCellRules, field: int, value: Variant) -> void:
	match field:
		TacticalCellOverride.Field.WALKABLE:
			values.walkable = bool(value)
		TacticalCellOverride.Field.MOVE_COST:
			values.move_cost = int(value)
		TacticalCellOverride.Field.SIGHT_BLOCK:
			values.sight_block = float(value)
		TacticalCellOverride.Field.PROJECTILE_BLOCK:
			values.projectile_block = float(value)
		TacticalCellOverride.Field.OCCLUDER_HEIGHT:
			values.occluder_height = float(value)
		TacticalCellOverride.Field.SOUND_COST:
			values.sound_cost = float(value)
		TacticalCellOverride.Field.TERRAIN_TAGS:
			values.terrain_tags = value
		TacticalCellOverride.Field.HAZARD_ID:
			values.hazard_id = value


func _read_field(values: TacticalCellRules, field: int) -> Variant:
	if values == null:
		return null
	match field:
		TacticalCellOverride.Field.WALKABLE:
			return values.walkable
		TacticalCellOverride.Field.MOVE_COST:
			return values.move_cost
		TacticalCellOverride.Field.SIGHT_BLOCK:
			return values.sight_block
		TacticalCellOverride.Field.PROJECTILE_BLOCK:
			return values.projectile_block
		TacticalCellOverride.Field.OCCLUDER_HEIGHT:
			return values.occluder_height
		TacticalCellOverride.Field.SOUND_COST:
			return values.sound_cost
		TacticalCellOverride.Field.TERRAIN_TAGS:
			return values.terrain_tags
		TacticalCellOverride.Field.HAZARD_ID:
			return values.hazard_id
	return null


func _override_matches_snapshot(current: TacticalCellOverride, snapshot: Dictionary) -> bool:
	var present := bool(snapshot[&"present"])
	if not present:
		return current == null or current.override_mask == 0
	if current == null or current.override_mask != int(snapshot[&"override_mask"]):
		return false
	var values: TacticalCellRules = snapshot[&"values"]
	return current.values != null and _rules_equal(current.values, values)


func _rules_equal(first: TacticalCellRules, second: TacticalCellRules) -> bool:
	if first == null or second == null:
		return first == second
	for descriptor in field_descriptors():
		if not _values_equal(_read_field(first, int(descriptor[&"field"])), _read_field(second, int(descriptor[&"field"]))):
			return false
	return true


func _values_equal(first: Variant, second: Variant) -> bool:
	return first == second


func _sort_overrides(data: TacticalMapAuthoringData) -> void:
	if data == null:
		return
	data.cell_overrides.sort_custom(func(a: TacticalCellOverride, b: TacticalCellOverride) -> bool:
		if a == null:
			return false
		if b == null:
			return true
		return _coordinate_less(a.coordinate, b.coordinate)
	)


func _normalize_coordinates(coordinates: Array[Vector3i]) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var seen: Dictionary = {}
	for coordinate in coordinates:
		if seen.has(coordinate):
			continue
		seen[coordinate] = true
		result.append(coordinate)
	result.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _coordinate_less(a, b)
	)
	return result


func _inside_volume(author: TacticalMapAuthor, coordinate: Vector3i) -> bool:
	# Horizontal bounds are derived from authored content by TacticalMapBaker.
	# The service only guards the shared non-negative, bounded level contract.
	return author != null and coordinate.y >= 0 and coordinate.y < TacticalMapDefinition.MAX_LEVEL_COUNT


func _coordinate_less(first: Vector3i, second: Vector3i) -> bool:
	if first.y != second.y:
		return first.y < second.y
	if first.z != second.z:
		return first.z < second.z
	return first.x < second.x


func _copy_content(content: Variant) -> Dictionary:
	if content is Dictionary:
		return (content as Dictionary).duplicate(true)
	return {}


func _empty_cell_inspection(coordinate: Vector3i, cell_errors: Array[String]) -> Dictionary:
	return {
		&"coordinate": coordinate,
		&"exists": false,
		&"in_bounds": false,
		&"has_floor": false,
		&"has_structure": false,
		&"floor": {},
		&"structure": {},
		&"base_rules": null,
		&"override_mask": 0,
		&"override_values": null,
		&"effective_rules": null,
		&"errors": cell_errors,
		&"warnings": [],
		&"diagnostics": [],
	}


func _summarize(inspected: Array[Dictionary]) -> Dictionary:
	var existing_count := 0
	var mixed_fields: PackedStringArray = []
	var common_values: Dictionary = {}
	for item in inspected:
		var rules := item.get(&"effective_rules") as TacticalCellRules
		if rules == null:
			continue
		existing_count += 1
		for descriptor in field_descriptors():
			var field_id: StringName = descriptor[&"id"]
			if mixed_fields.has(String(field_id)):
				continue
			var value: Variant = _read_field(rules, int(descriptor[&"field"]))
			if not common_values.has(field_id):
				common_values[field_id] = value
			elif not _values_equal(common_values[field_id], value):
				mixed_fields.append(String(field_id))
				common_values.erase(field_id)
	return {
		&"count": inspected.size(),
		&"existing_count": existing_count,
		&"mixed_fields": mixed_fields,
		&"common_values": common_values,
	}
