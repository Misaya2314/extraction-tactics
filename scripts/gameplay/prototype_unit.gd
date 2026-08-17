class_name PrototypeUnit
extends Node3D

signal action_points_changed(current: int, maximum: int)
signal health_changed(current: int, maximum: int)
signal died(unit: PrototypeUnit)

@export var grid_cell := Vector3i.ZERO
@export var faction: StringName = &"player"
@export var max_hp := 10
@export var max_action_points := 2
@export var move_range := 4
@export var attack_range := 5
@export var attack_damage := 4
@export var attack_ap_cost := 1
@export var vision_range := 7
@export var visual_color := Color("4f9dff")

var archetype: UnitArchetype
var weapon: WeaponDefinition
var current_hp := 10
var current_action_points := 2
var unit_id: StringName

@onready var body_mesh: MeshInstance3D = $Body
@onready var selection_marker: MeshInstance3D = $SelectionMarker
@onready var facing_marker: MeshInstance3D = $FacingMarker
@onready var status_label: Label3D = $StatusLabel

var facing := Vector2i(0, 1)


func _ready() -> void:
	current_hp = max_hp
	current_action_points = max_action_points
	_apply_weapon_stats()
	if unit_id.is_empty():
		unit_id = StringName("%s_%s" % [faction, get_instance_id()])
	_apply_visual_color()
	set_selected(false)
	set_facing(facing)
	_update_status_label()


func configure(
		new_cell: Vector3i,
		new_faction: StringName,
		new_color: Color,
		new_archetype: UnitArchetype = null,
		new_weapon: WeaponDefinition = null
) -> void:
	grid_cell = new_cell
	faction = new_faction
	visual_color = new_color
	if new_archetype != null:
		archetype = new_archetype
		max_hp = archetype.max_hp
		max_action_points = archetype.max_action_points
		move_range = archetype.move_range
		vision_range = archetype.vision_range
		weapon = new_weapon if new_weapon != null else archetype.default_weapon
	elif new_weapon != null:
		weapon = new_weapon
	_apply_weapon_stats()
	unit_id = StringName("%s_%s" % [faction, get_instance_id()])
	if is_node_ready():
		current_hp = max_hp
		current_action_points = max_action_points
		_apply_visual_color()
		_update_status_label()


func set_weapon(new_weapon: WeaponDefinition) -> void:
	weapon = new_weapon
	_apply_weapon_stats()
	_update_status_label()


func get_weapon_display_name() -> String:
	return weapon.display_name if weapon != null else "未配置武器"


func get_weapon_summary() -> String:
	if weapon == null:
		return "未配置武器"
	return weapon.get_summary()


func set_selected(is_selected: bool) -> void:
	if is_instance_valid(selection_marker):
		selection_marker.visible = is_selected


func set_facing(direction: Variant) -> void:
	if direction is Vector3i:
		direction = Vector2i(direction.x, direction.z)
	if direction == Vector2i.ZERO:
		return
	if absi(direction.x) >= absi(direction.y):
		facing = Vector2i(1 if direction.x > 0 else -1, 0)
	else:
		facing = Vector2i(0, 1 if direction.y > 0 else -1)
	if is_instance_valid(facing_marker):
		facing_marker.position = Vector3(float(facing.x) * 0.55, 0.66, float(facing.y) * 0.55)


func is_alive() -> bool:
	return current_hp > 0


func take_damage(amount: int) -> int:
	if amount <= 0 or not is_alive():
		return 0
	var applied_damage := mini(amount, current_hp)
	current_hp -= applied_damage
	health_changed.emit(current_hp, max_hp)
	_update_status_label()
	if current_hp == 0:
		died.emit(self)
	return applied_damage


func reset_action_points() -> void:
	current_action_points = max_action_points
	action_points_changed.emit(current_action_points, max_action_points)
	_update_status_label()


func can_spend_action_points(cost: int) -> bool:
	return cost >= 0 and current_action_points >= cost


func spend_action_points(cost: int) -> bool:
	if not can_spend_action_points(cost):
		return false
	current_action_points -= cost
	action_points_changed.emit(current_action_points, max_action_points)
	_update_status_label()
	return true


func move_along_world_path(
		world_points: Array[Vector3],
		destination_cell: Vector3i
) -> void:
	for target_position in world_points:
		var movement_delta := target_position - global_position
		set_facing(Vector2i(roundi(movement_delta.x), roundi(movement_delta.z)))
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


func _apply_weapon_stats() -> void:
	if weapon == null:
		return
	attack_range = weapon.range
	attack_damage = weapon.damage
	attack_ap_cost = weapon.ap_cost


func _update_status_label() -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = "%s\nHP %d/%d · AP %d/%d" % [
		name,
		current_hp,
		max_hp,
		current_action_points,
		max_action_points,
	]
