@tool
class_name MapObjectMarker3D
extends MapMarker3D

@export var object_id: StringName = &"object"
@export var kind: MapObjectPlacement.Kind = MapObjectPlacement.Kind.GENERIC
@export var facing: Vector2i = Vector2i.DOWN
@export var scene: PackedScene:
	set(value):
		scene = value
		_refresh_preview.call_deferred()
@export var blocks_movement: bool = false
@export var blocks_los: bool = false
@export var loot_table: LootTableDefinition
@export var loot_seed: int = -1


func _ready() -> void:
	super()
	_refresh_preview()


func to_data() -> MapObjectPlacement:
	var data := MapObjectPlacement.new()
	data.object_id = object_id
	data.kind = kind
	data.cell = cell
	data.facing = facing
	data.scene = scene
	data.blocks_movement = blocks_movement
	data.blocks_los = blocks_los
	data.loot_table = loot_table
	data.loot_seed = loot_seed
	return data


func _refresh_preview() -> void:
	if not is_inside_tree():
		return
	var old_preview := get_node_or_null("_Preview")
	if old_preview != null:
		old_preview.free()
	if scene == null:
		return
	var preview := scene.instantiate()
	preview.name = "_Preview"
	preview.set_meta(&"map_marker_preview", true)
	add_child(preview)
	if Engine.is_editor_hint() and owner != null:
		preview.owner = owner
