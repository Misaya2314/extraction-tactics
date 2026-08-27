@tool
class_name MapEdgeData
extends Resource

## Baked/runtime representation of one canonical edge. Legacy cover_a/b stay
## serialized for migration, while profile fields are the preferred runtime
## cover contract. Provenance is plain data for diagnostics only.

@export var cell_a: Vector3i = Vector3i.ZERO
@export var cell_b: Vector3i = Vector3i(1, 0, 0)
@export var placeable_id: StringName = &""
@export var cover_a: TacticalEdgeRules.CoverLevel = TacticalEdgeRules.CoverLevel.NONE
@export var cover_b: TacticalEdgeRules.CoverLevel = TacticalEdgeRules.CoverLevel.NONE
@export var cover_profile_a: TacticalCoverProfile
@export var cover_profile_b: TacticalCoverProfile
@export var blocks_movement: bool = false
@export_range(0.0, 1.0, 0.01) var sight_block: float = 0.0
@export_range(0.0, 1.0, 0.01) var projectile_block: float = 0.0
@export_range(0.0, 20.0, 0.05) var height: float = 0.0
@export var destructible: bool = false
@export var runtime_state_id: StringName = &""
@export var source_type: StringName = &"explicit"
@export var source_layer: StringName = &""
@export var source_cell: Vector3i = Vector3i.ZERO
@export var source_placeable_id: StringName = &""
@export var source_mesh_item_id: int = -1


static func from_placement(placement: TacticalEdgePlacement, provenance: Dictionary = {}) -> MapEdgeData:
	var result := MapEdgeData.new()
	if placement == null or placement.edge_key == null:
		return result
	# TacticalEdgeRules.cover_a/cover_b are authored against the original
	# placement.edge_key.cell_a/cell_b endpoints. The baked edge uses the
	# canonical endpoint order, so preserve the physical side by swapping the
	# two cover values when authoring order is reversed.
	var source_a := placement.edge_key.cell_a
	var source_b := placement.edge_key.cell_b
	var key := placement.edge_key.canonicalized()
	result.cell_a = key.cell_a
	result.cell_b = key.cell_b
	result.placeable_id = placement.placeable_id
	result.source_type = StringName(provenance.get(&"source_type", &"explicit"))
	result.source_layer = StringName(provenance.get(&"source_layer", &"edge"))
	result.source_cell = provenance.get(&"source_cell", source_a)
	result.source_placeable_id = StringName(provenance.get(&"source_placeable_id", placement.placeable_id))
	result.source_mesh_item_id = int(provenance.get(&"source_mesh_item_id", -1))
	if placement.rules != null:
		var source_is_reversed := source_a == key.cell_b and source_b == key.cell_a
		if source_is_reversed:
			result.cover_a = placement.rules.cover_b
			result.cover_b = placement.rules.cover_a
		else:
			result.cover_a = placement.rules.cover_a
			result.cover_b = placement.rules.cover_b
		if source_is_reversed:
			result.cover_profile_a = placement.rules.cover_profile_b
			result.cover_profile_b = placement.rules.cover_profile_a
		else:
			result.cover_profile_a = placement.rules.cover_profile_a
			result.cover_profile_b = placement.rules.cover_profile_b
		result.blocks_movement = placement.rules.blocks_movement
		result.sight_block = placement.rules.sight_block
		result.projectile_block = placement.rules.projectile_block
		result.height = placement.rules.height
		result.destructible = placement.rules.destructible
		result.runtime_state_id = placement.rules.runtime_state_id
	return result


static func from_rules(source_cell: Vector3i, neighbor_cell: Vector3i, rules: TacticalEdgeRules, provenance: Dictionary = {}) -> MapEdgeData:
	var result := MapEdgeData.new()
	var key := TacticalEdgeKey.from_cells(source_cell, neighbor_cell)
	result.cell_a = key.cell_a
	result.cell_b = key.cell_b
	result.source_type = StringName(provenance.get(&"source_type", &"derived"))
	result.source_layer = StringName(provenance.get(&"source_layer", &""))
	result.source_cell = provenance.get(&"source_cell", source_cell)
	result.source_placeable_id = StringName(provenance.get(&"source_placeable_id", &""))
	result.source_mesh_item_id = int(provenance.get(&"source_mesh_item_id", -1))
	result.placeable_id = result.source_placeable_id
	if rules == null:
		return result
	var source_is_reversed := source_cell == key.cell_b and neighbor_cell == key.cell_a
	result.cover_a = rules.cover_b if source_is_reversed else rules.cover_a
	result.cover_b = rules.cover_a if source_is_reversed else rules.cover_b
	result.cover_profile_a = rules.cover_profile_b if source_is_reversed else rules.cover_profile_a
	result.cover_profile_b = rules.cover_profile_a if source_is_reversed else rules.cover_profile_b
	result.blocks_movement = rules.blocks_movement
	result.sight_block = rules.sight_block
	result.projectile_block = rules.projectile_block
	result.height = rules.height
	result.destructible = rules.destructible
	result.runtime_state_id = rules.runtime_state_id
	return result


func copy_from(other: MapEdgeData) -> void:
	if other == null:
		return
	cell_a = other.cell_a
	cell_b = other.cell_b
	placeable_id = other.placeable_id
	cover_a = other.cover_a
	cover_b = other.cover_b
	cover_profile_a = other.cover_profile_a
	cover_profile_b = other.cover_profile_b
	blocks_movement = other.blocks_movement
	sight_block = other.sight_block
	projectile_block = other.projectile_block
	height = other.height
	destructible = other.destructible
	runtime_state_id = other.runtime_state_id
	source_type = other.source_type
	source_layer = other.source_layer
	source_cell = other.source_cell
	source_placeable_id = other.source_placeable_id
	source_mesh_item_id = other.source_mesh_item_id


func duplicate_data() -> MapEdgeData:
	var result := MapEdgeData.new()
	result.copy_from(self)
	return result


func resolve_profile(side: int, settings = null) -> TacticalCoverProfile:
	var legacy_level := cover_a if side == 0 else cover_b
	var authored_profile := cover_profile_a if side == 0 else cover_profile_b
	if authored_profile != null and authored_profile.is_valid():
		return authored_profile
	if settings != null and settings.has_method("resolve_profile"):
		return settings.resolve_profile(authored_profile, legacy_level)
	return TacticalCoverProfile.default_for_level(int(legacy_level))


func semantic_key() -> String:
	return "%s|%d|%d|%s|%s|%s|%.6f|%.6f|%.6f|%s|%s" % [
		key_string(),
		int(cover_a),
		int(cover_b),
		_profile_key(cover_profile_a),
		_profile_key(cover_profile_b),
		blocks_movement,
		sight_block,
		projectile_block,
		height,
		destructible,
		runtime_state_id,
	]


func get_key() -> TacticalEdgeKey:
	return TacticalEdgeKey.from_cells(cell_a, cell_b)


func key_string() -> String:
	return get_key().key_string()


static func _profile_key(profile: TacticalCoverProfile) -> String:
	return "" if profile == null else profile.semantic_key()
