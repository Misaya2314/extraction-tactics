class_name PrototypeUnit
extends Node3D

signal action_points_changed(current: int, maximum: int)

@export var grid_cell := Vector2i.ZERO
@export var faction: StringName = &"player"
@export var max_hp := 10
@export var max_action_points := 2
@export var move_range := 4
@export var visual_color := Color("4f9dff")

var current_hp := 10
var current_action_points := 2
var unit_id: StringName

@onready var body_mesh: MeshInstance3D = $Body
@onready var selection_marker: MeshInstance3D = $SelectionMarker


func _ready() -> void:
	current_hp = max_hp
	current_action_points = max_action_points
	if unit_id.is_empty():
		unit_id = StringName("%s_%s" % [faction, get_instance_id()])
	_apply_visual_color()
	set_selected(false)


func configure(
		new_cell: Vector2i,
		new_faction: StringName,
		new_color: Color
) -> void:
	grid_cell = new_cell
	faction = new_faction
	visual_color = new_color
	unit_id = StringName("%s_%s" % [faction, get_instance_id()])
	if is_node_ready():
		_apply_visual_color()


func set_selected(is_selected: bool) -> void:
	if is_instance_valid(selection_marker):
		selection_marker.visible = is_selected


func reset_action_points() -> void:
	current_action_points = max_action_points
	action_points_changed.emit(current_action_points, max_action_points)


func can_spend_action_points(cost: int) -> bool:
	return cost >= 0 and current_action_points >= cost


func spend_action_points(cost: int) -> bool:
	if not can_spend_action_points(cost):
		return false
	current_action_points -= cost
	action_points_changed.emit(current_action_points, max_action_points)
	return true


func move_along_world_path(
		world_points: Array[Vector3],
		destination_cell: Vector2i
) -> void:
	for target_position in world_points:
		var movement_tween := create_tween()
		movement_tween.set_trans(Tween.TRANS_SINE)
		movement_tween.set_ease(Tween.EASE_IN_OUT)
		movement_tween.tween_property(self, "global_position", target_position, 0.09)
		await movement_tween.finished
	grid_cell = destination_cell


func _apply_visual_color() -> void:
	if not is_instance_valid(body_mesh):
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = visual_color
	material.roughness = 0.78
	body_mesh.material_override = material
