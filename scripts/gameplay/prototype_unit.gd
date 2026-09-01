class_name PrototypeUnit
extends Node3D

signal action_points_changed(current: int, maximum: int)
signal health_changed(current: int, maximum: int)
signal died(unit: PrototypeUnit)
signal attack_feedback_started(unit: PrototypeUnit, profile_id: StringName)
signal attack_feedback_finished(unit: PrototypeUnit, profile_id: StringName)

## The Node is a View/Adapter.  When runtime_state is bound, all mutable
## gameplay values below are read from that state; the private values are only
## a compatibility path for presentation/editor tests that still configure an
## unbound prototype unit.
var runtime_state: UnitRuntimeState
var _legacy_grid_cell := Vector3i.ZERO
var _legacy_faction: StringName = &"player"
var _legacy_max_hp := 10
var _legacy_max_action_points := 2
var _legacy_move_range := 4
var _legacy_attack_range := 5
var _legacy_attack_damage := 4
var _legacy_attack_ap_cost := 1
var _legacy_inner_vision_range := 4
var _legacy_vision_range := 7
var _legacy_archetype: UnitArchetype
var _legacy_weapon: WeaponDefinition
var _legacy_current_hp := 10
var _legacy_current_action_points := 2
var _legacy_unit_id: StringName = &""
var _legacy_facing := Vector2i(0, 1)

@export var grid_cell: Vector3i = Vector3i.ZERO:
	get:
		return runtime_state.cell if runtime_state != null else _legacy_grid_cell
	set(value):
		if runtime_state != null:
			runtime_state.set_cell(value)
		else:
			_legacy_grid_cell = value

@export var faction: StringName = &"player":
	get:
		return runtime_state.faction if runtime_state != null else _legacy_faction
	set(value):
		if runtime_state == null:
			_legacy_faction = value

@export var max_hp: int = 10:
	get:
		return runtime_state.max_hp if runtime_state != null else _legacy_max_hp
	set(value):
		if runtime_state == null:
			_legacy_max_hp = value

@export var max_action_points: int = 2:
	get:
		return runtime_state.max_action_points if runtime_state != null else _legacy_max_action_points
	set(value):
		if runtime_state == null:
			_legacy_max_action_points = value

@export var move_range: int = 4:
	get:
		return runtime_state.move_range if runtime_state != null else _legacy_move_range
	set(value):
		if runtime_state == null:
			_legacy_move_range = value

@export var attack_range: int = 5:
	get:
		if runtime_state != null:
			return weapon.range if weapon != null else 0
		return _legacy_attack_range
	set(value):
		if runtime_state == null:
			_legacy_attack_range = value

@export var attack_damage: int = 4:
	get:
		if runtime_state != null:
			return weapon.damage if weapon != null else 0
		return _legacy_attack_damage
	set(value):
		if runtime_state == null:
			_legacy_attack_damage = value

@export var attack_ap_cost: int = 1:
	get:
		if runtime_state != null:
			return weapon.ap_cost if weapon != null else 1
		return _legacy_attack_ap_cost
	set(value):
		if runtime_state == null:
			_legacy_attack_ap_cost = value

@export var inner_vision_range: int = 4:
	get:
		return runtime_state.inner_vision_range if runtime_state != null else _legacy_inner_vision_range
	set(value):
		if runtime_state == null:
			_legacy_inner_vision_range = value

@export var vision_range: int = 7:
	get:
		return runtime_state.vision_range if runtime_state != null else _legacy_vision_range
	set(value):
		if runtime_state == null:
			_legacy_vision_range = value

var outer_vision_range: int:
	get:
		return vision_range
	set(value):
		vision_range = value

@export var visual_color := Color("4f9dff")

var archetype: UnitArchetype:
	get:
		return runtime_state.archetype if runtime_state != null else _legacy_archetype
	set(value):
		if runtime_state == null:
			_legacy_archetype = value

var weapon: WeaponDefinition:
	get:
		if runtime_state != null:
			return runtime_state.weapon_instance.definition if runtime_state.weapon_instance != null else null
		return _legacy_weapon
	set(value):
		if runtime_state == null:
			_legacy_weapon = value

var current_hp: int:
	get:
		return runtime_state.current_hp if runtime_state != null else _legacy_current_hp
	set(value):
		if runtime_state == null:
			_legacy_current_hp = value

var current_action_points: int:
	get:
		return runtime_state.current_action_points if runtime_state != null else _legacy_current_action_points
	set(value):
		if runtime_state == null:
			_legacy_current_action_points = value

var unit_id: StringName:
	get:
		return runtime_state.instance_id if runtime_state != null else _legacy_unit_id
	set(value):
		if runtime_state == null:
			_legacy_unit_id = value

@onready var visual_root: Node3D = get_node_or_null("VisualRoot") as Node3D
@onready var body_mesh: MeshInstance3D = get_node_or_null("VisualRoot/Body") as MeshInstance3D
@onready var selection_marker: MeshInstance3D = $SelectionMarker
@onready var facing_marker: MeshInstance3D = $FacingMarker
@onready var status_label: Label3D = $StatusLabel
@onready var alert_badge: Label3D = get_node_or_null("AlertBadge") as Label3D
@onready var weapon_pivot: Node3D = get_node_or_null("VisualRoot/WeaponPivot") as Node3D
@onready var weapon_model_root: Node3D = get_node_or_null("VisualRoot/WeaponPivot/WeaponModelRoot") as Node3D
@onready var muzzle_flash: MeshInstance3D = get_node_or_null("VisualRoot/WeaponPivot/MuzzleFlash") as MeshInstance3D

var alert_level: int = 0:
	set(value):
		alert_level = value
		_update_alert_badge()

var facing: Vector2i:
	get:
		return runtime_state.facing if runtime_state != null else _legacy_facing
	set(value):
		if runtime_state == null:
			_legacy_facing = value
var last_attack_feedback_profile_id: StringName = &""
var attack_feedback_play_count: int = 0
var is_attack_feedback_playing: bool = false
var last_attack_feedback_duration: float = 0.0

var _attack_feedback_generation: int = 0
var _attack_feedback_tweens: Array[Tween] = []
var _visual_root_rest_position := Vector3.ZERO
var _visual_root_rest_rotation := Vector3.ZERO
var _visual_root_rest_scale := Vector3.ONE
var _weapon_pivot_rest_position := Vector3.ZERO
var _weapon_pivot_rest_rotation := Vector3.ZERO
var _weapon_pivot_rest_scale := Vector3.ONE
var _muzzle_flash_rest_position := Vector3(0.0, 0.0, 0.78)
var _muzzle_flash_rest_scale := Vector3.ONE


func _ready() -> void:
	_connect_runtime_state_signals()
	_apply_weapon_stats()
	_refresh_weapon_model()
	_capture_feedback_rest_pose()
	_apply_visual_color()
	set_selected(false)
	_apply_facing_visual()
	_update_status_label()
	_update_alert_badge()


func bind_runtime_state(new_state: UnitRuntimeState, new_color: Color = Color.WHITE) -> bool:
	if new_state == null or not new_state.is_valid():
		return false
	_disconnect_runtime_state_signals()
	runtime_state = new_state
	if new_color != Color.WHITE:
		visual_color = new_color
	_connect_runtime_state_signals()
	if is_node_ready():
		if is_attack_feedback_playing:
			_interrupt_attack_feedback()
		else:
			_reset_attack_feedback_visuals()
		_apply_weapon_stats()
		_refresh_weapon_model()
		_capture_feedback_rest_pose()
		_apply_weapon_facing()
		_apply_visual_color()
		_update_status_label()
		_update_alert_badge()
	return true


func rebind_runtime_state(new_state: UnitRuntimeState, new_color: Color = Color.WHITE) -> bool:
	return bind_runtime_state(new_state, new_color)


func unbind_runtime_state() -> UnitRuntimeState:
	var previous_state := runtime_state
	_disconnect_runtime_state_signals()
	runtime_state = null
	return previous_state


func configure(
		new_cell: Vector3i,
		new_faction: StringName,
		new_color: Color,
		new_archetype: UnitArchetype = null,
		new_weapon: WeaponDefinition = null
) -> void:
	# Compatibility-only path for old presentation callers.  The normal game
	# path binds a Factory-created UnitRuntimeState and never calls configure.
	if runtime_state != null:
		return
	grid_cell = new_cell
	faction = new_faction
	visual_color = new_color
	if new_archetype != null:
		archetype = new_archetype
		max_hp = archetype.max_hp
		max_action_points = archetype.max_action_points
		move_range = archetype.move_range
		inner_vision_range = archetype.inner_vision_range
		vision_range = archetype.vision_range
		weapon = new_weapon if new_weapon != null else archetype.default_weapon
	elif new_weapon != null:
		weapon = new_weapon
	_apply_weapon_stats()
	if is_node_ready():
		if is_attack_feedback_playing:
			_interrupt_attack_feedback()
		else:
			_reset_attack_feedback_visuals()
		_refresh_weapon_model()
		_capture_feedback_rest_pose()
		_apply_weapon_facing()
		_apply_visual_color()
		_update_status_label()


func set_weapon(new_weapon: WeaponDefinition) -> void:
	if runtime_state != null:
		# A View cannot turn a shared Definition into a runtime instance. Weapon
		# changes must be performed by a domain factory/state owner.
		return
	if is_attack_feedback_playing:
		_interrupt_attack_feedback()
	else:
		_reset_attack_feedback_visuals()
	weapon = new_weapon
	_apply_weapon_stats(new_weapon == null)
	_refresh_weapon_model()
	_capture_feedback_rest_pose()
	_apply_weapon_facing()
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
	var normalized := _normalize_facing(direction)
	if normalized == Vector2i.ZERO:
		return
	if runtime_state != null:
		runtime_state.set_facing(normalized)
	else:
		facing = normalized
	_apply_facing_visual()


func _apply_facing_visual() -> void:
	if is_instance_valid(facing_marker):
		facing_marker.position = Vector3(float(facing.x) * 0.55, 0.66, float(facing.y) * 0.55)
	_apply_weapon_facing()


static func _normalize_facing(direction: Variant) -> Vector2i:
	if direction is Vector3i:
		direction = Vector2i(direction.x, direction.z)
	if not direction is Vector2i:
		return Vector2i.ZERO
	var typed_direction: Vector2i = direction
	if typed_direction == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(typed_direction.x) >= absi(typed_direction.y):
		return Vector2i(1 if typed_direction.x > 0 else -1, 0)
	return Vector2i(0, 1 if typed_direction.y > 0 else -1)


## Plays only local presentation feedback. Gameplay rules and root/grid state
## are intentionally untouched by this coroutine.
func play_attack_feedback() -> void:
	if is_attack_feedback_playing:
		_interrupt_attack_feedback()
	else:
		_reset_attack_feedback_visuals()

	var profile: WeaponAttackFeedbackProfile = null
	if weapon != null:
		profile = weapon.attack_feedback_profile
	if profile == null or not _feedback_nodes_are_ready():
		last_attack_feedback_profile_id = profile.profile_id if profile != null else &""
		last_attack_feedback_duration = profile.total_duration() if profile != null else 0.0
		return

	_attack_feedback_generation += 1
	var generation := _attack_feedback_generation
	last_attack_feedback_profile_id = profile.profile_id
	last_attack_feedback_duration = profile.total_duration()
	attack_feedback_play_count += 1
	is_attack_feedback_playing = true
	attack_feedback_started.emit(self, profile.profile_id)
	_start_attack_feedback_tweens(profile)

	if not is_inside_tree():
		_complete_attack_feedback(generation, profile.profile_id)
		return
	await get_tree().create_timer(last_attack_feedback_duration).timeout
	if generation != _attack_feedback_generation:
		return
	_complete_attack_feedback(generation, profile.profile_id)


func _capture_feedback_rest_pose() -> void:
	if is_instance_valid(visual_root):
		_visual_root_rest_position = visual_root.position
		_visual_root_rest_rotation = visual_root.rotation
		_visual_root_rest_scale = visual_root.scale
	if is_instance_valid(weapon_pivot):
		_weapon_pivot_rest_position = weapon_pivot.position
		_weapon_pivot_rest_rotation = weapon_pivot.rotation
		_weapon_pivot_rest_scale = weapon_pivot.scale
	if is_instance_valid(muzzle_flash):
		_muzzle_flash_rest_position = muzzle_flash.position
		_muzzle_flash_rest_scale = muzzle_flash.scale


func _feedback_nodes_are_ready() -> bool:
	return is_instance_valid(visual_root) \
		and is_instance_valid(weapon_pivot) \
		and is_instance_valid(muzzle_flash)


func _apply_weapon_facing() -> void:
	if not is_instance_valid(weapon_pivot):
		return
	var pivot_rotation := _weapon_pivot_rest_rotation
	pivot_rotation.y = atan2(float(facing.x), float(facing.y))
	weapon_pivot.rotation = pivot_rotation


func _facing_forward() -> Vector3:
	var forward := Vector3(float(facing.x), 0.0, float(facing.y))
	return forward.normalized() if forward.length_squared() > 0.0 else Vector3.FORWARD


func _queue_feedback_tween(
		target: Object,
		property: NodePath,
		recoil_value: Variant,
		rest_value: Variant,
		profile: WeaponAttackFeedbackProfile
) -> void:
	var tween := create_tween()
	_attack_feedback_tweens.append(tween)
	var recoil_tweener := tween.tween_property(
		target,
		property,
		recoil_value,
		maxf(profile.recoil_duration, 0.001)
	)
	recoil_tweener.set_trans(Tween.TRANS_QUAD)
	recoil_tweener.set_ease(Tween.EASE_OUT)
	tween.tween_interval(maxf(profile.hold_duration, 0.0))
	var recover_tweener := tween.tween_property(
		target,
		property,
		rest_value,
		maxf(profile.recover_duration, 0.001)
	)
	recover_tweener.set_trans(Tween.TRANS_QUAD)
	recover_tweener.set_ease(Tween.EASE_IN_OUT)


func _start_attack_feedback_tweens(profile: WeaponAttackFeedbackProfile) -> void:
	var recoil_offset := -_facing_forward() * profile.recoil_distance
	var visual_recoil_position := _visual_root_rest_position + recoil_offset
	var visual_recoil_rotation := _visual_root_rest_rotation + Vector3(
		deg_to_rad(profile.weapon_kick_degrees * 0.25),
		0.0,
		0.0
	)
	var squash_factor := clampf(1.0 - profile.body_squash, 0.5, 1.0)
	var visual_recoil_scale := Vector3(
		_visual_root_rest_scale.x,
		_visual_root_rest_scale.y * squash_factor,
		_visual_root_rest_scale.z
	)
	_queue_feedback_tween(
		visual_root,
		NodePath("position"),
		visual_recoil_position,
		_visual_root_rest_position,
		profile
	)
	_queue_feedback_tween(
		visual_root,
		NodePath("rotation"),
		visual_recoil_rotation,
		_visual_root_rest_rotation,
		profile
	)
	_queue_feedback_tween(
		visual_root,
		NodePath("scale"),
		visual_recoil_scale,
		_visual_root_rest_scale,
		profile
	)

	var pivot_recoil_position := _weapon_pivot_rest_position + recoil_offset * 1.35
	var pivot_rest_rotation := _weapon_pivot_rest_rotation
	pivot_rest_rotation.y = atan2(float(facing.x), float(facing.y))
	var pivot_recoil_rotation := pivot_rest_rotation
	pivot_recoil_rotation.x += deg_to_rad(profile.weapon_kick_degrees)
	_queue_feedback_tween(
		weapon_pivot,
		NodePath("position"),
		pivot_recoil_position,
		_weapon_pivot_rest_position,
		profile
	)
	_queue_feedback_tween(
		weapon_pivot,
		NodePath("rotation"),
		pivot_recoil_rotation,
		pivot_rest_rotation,
		profile
	)

	muzzle_flash.visible = true
	muzzle_flash.scale = Vector3.ZERO
	var flash_duration := maxf(profile.muzzle_flash_duration, 0.001)
	var flash_rise_duration := minf(flash_duration * 0.35, 0.025)
	var flash_fall_duration := maxf(flash_duration - flash_rise_duration, 0.001)
	var flash_tween := create_tween()
	_attack_feedback_tweens.append(flash_tween)
	var flash_rise := flash_tween.tween_property(
		muzzle_flash,
		NodePath("scale"),
		_muzzle_flash_rest_scale * profile.muzzle_flash_scale,
		flash_rise_duration
	)
	flash_rise.set_trans(Tween.TRANS_BACK)
	flash_rise.set_ease(Tween.EASE_OUT)
	var flash_fall := flash_tween.tween_property(
		muzzle_flash,
		NodePath("scale"),
		Vector3.ZERO,
		flash_fall_duration
	)
	flash_fall.set_trans(Tween.TRANS_QUAD)
	flash_fall.set_ease(Tween.EASE_IN)


func _kill_attack_feedback_tweens() -> void:
	for tween in _attack_feedback_tweens:
		if is_instance_valid(tween):
			tween.kill()
	_attack_feedback_tweens.clear()


func _reset_attack_feedback_visuals() -> void:
	_kill_attack_feedback_tweens()
	if is_instance_valid(visual_root):
		visual_root.position = _visual_root_rest_position
		visual_root.rotation = _visual_root_rest_rotation
		visual_root.scale = _visual_root_rest_scale
	if is_instance_valid(weapon_pivot):
		weapon_pivot.position = _weapon_pivot_rest_position
		weapon_pivot.scale = _weapon_pivot_rest_scale
		_apply_weapon_facing()
		weapon_pivot.rotation.x = _weapon_pivot_rest_rotation.x
		weapon_pivot.rotation.z = _weapon_pivot_rest_rotation.z
	if is_instance_valid(muzzle_flash):
		muzzle_flash.position = _muzzle_flash_rest_position
		muzzle_flash.scale = _muzzle_flash_rest_scale
		muzzle_flash.visible = false


func _interrupt_attack_feedback() -> void:
	var interrupted_profile_id := last_attack_feedback_profile_id
	_attack_feedback_generation += 1
	_kill_attack_feedback_tweens()
	_reset_attack_feedback_visuals()
	var was_playing := is_attack_feedback_playing
	is_attack_feedback_playing = false
	if was_playing and interrupted_profile_id != &"":
		attack_feedback_finished.emit(self, interrupted_profile_id)


func _complete_attack_feedback(generation: int, profile_id: StringName) -> void:
	if generation != _attack_feedback_generation:
		return
	_attack_feedback_generation += 1
	_kill_attack_feedback_tweens()
	_reset_attack_feedback_visuals()
	is_attack_feedback_playing = false
	attack_feedback_finished.emit(self, profile_id)


func _connect_runtime_state_signals() -> void:
	if runtime_state == null:
		return
	var health_callback := Callable(self, "_on_runtime_health_changed")
	var ap_callback := Callable(self, "_on_runtime_action_points_changed")
	var cell_callback := Callable(self, "_on_runtime_cell_changed")
	var facing_callback := Callable(self, "_on_runtime_facing_changed")
	var weapon_callback := Callable(self, "_on_runtime_weapon_changed")
	var alive_callback := Callable(self, "_on_runtime_alive_changed")
	var died_callback := Callable(self, "_on_runtime_died")
	if not runtime_state.health_changed.is_connected(health_callback):
		runtime_state.health_changed.connect(health_callback)
	if not runtime_state.action_points_changed.is_connected(ap_callback):
		runtime_state.action_points_changed.connect(ap_callback)
	if not runtime_state.cell_changed.is_connected(cell_callback):
		runtime_state.cell_changed.connect(cell_callback)
	if not runtime_state.facing_changed.is_connected(facing_callback):
		runtime_state.facing_changed.connect(facing_callback)
	if not runtime_state.weapon_changed.is_connected(weapon_callback):
		runtime_state.weapon_changed.connect(weapon_callback)
	if not runtime_state.alive_changed.is_connected(alive_callback):
		runtime_state.alive_changed.connect(alive_callback)
	if not runtime_state.died.is_connected(died_callback):
		runtime_state.died.connect(died_callback)


func _disconnect_runtime_state_signals() -> void:
	if runtime_state == null:
		return
	var callbacks := [
		Callable(self, "_on_runtime_health_changed"),
		Callable(self, "_on_runtime_action_points_changed"),
		Callable(self, "_on_runtime_cell_changed"),
		Callable(self, "_on_runtime_facing_changed"),
		Callable(self, "_on_runtime_weapon_changed"),
		Callable(self, "_on_runtime_alive_changed"),
		Callable(self, "_on_runtime_died"),
	]
	var signals := [
		runtime_state.health_changed,
		runtime_state.action_points_changed,
		runtime_state.cell_changed,
		runtime_state.facing_changed,
		runtime_state.weapon_changed,
		runtime_state.alive_changed,
		runtime_state.died,
	]
	for index in range(callbacks.size()):
		var state_signal: Signal = signals[index]
		var callback: Callable = callbacks[index]
		if state_signal.is_connected(callback):
			state_signal.disconnect(callback)


func _on_runtime_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)
	_update_status_label()


func _on_runtime_action_points_changed(current: int, maximum: int) -> void:
	action_points_changed.emit(current, maximum)
	_update_status_label()


func _on_runtime_cell_changed(_previous: Vector3i, _current: Vector3i) -> void:
	_update_status_label()


func _on_runtime_facing_changed(_previous: Vector2i, _current: Vector2i) -> void:
	_apply_facing_visual()


func _on_runtime_weapon_changed(_previous: WeaponInstance, _current: WeaponInstance) -> void:
	_apply_weapon_stats(true)
	if is_node_ready():
		if is_attack_feedback_playing:
			_interrupt_attack_feedback()
		else:
			_reset_attack_feedback_visuals()
		_refresh_weapon_model()
		_capture_feedback_rest_pose()
		_apply_weapon_facing()
		_update_status_label()


func _on_runtime_alive_changed(_is_alive: bool) -> void:
	_update_status_label()


func _on_runtime_died() -> void:
	died.emit(self)


func is_alive() -> bool:
	return runtime_state.alive if runtime_state != null else current_hp > 0


func take_damage(amount: int) -> int:
	if amount <= 0 or not is_alive():
		return 0
	if runtime_state != null:
		var previous_hp := runtime_state.current_hp
		if not runtime_state.apply_damage(amount):
			return 0
		return previous_hp - runtime_state.current_hp
	var applied_damage := mini(amount, current_hp)
	current_hp -= applied_damage
	health_changed.emit(current_hp, max_hp)
	_update_status_label()
	if current_hp == 0:
		died.emit(self)
	return applied_damage


func reset_action_points() -> bool:
	if runtime_state != null:
		return runtime_state.reset_ap()
	current_action_points = max_action_points
	action_points_changed.emit(current_action_points, max_action_points)
	_update_status_label()
	return true


func can_spend_action_points(cost: int) -> bool:
	return cost >= 0 and is_alive() and current_action_points >= cost


func spend_action_points(cost: int) -> bool:
	if not can_spend_action_points(cost):
		return false
	if runtime_state != null:
		if cost == 0:
			return true
		return runtime_state.spend_ap(cost)
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
	var material := _cached_visual_material(visual_color)
	body_mesh.material_override = material


## Reuses one material per color across all units, so setting the visual color
## repeatedly (e.g. after every archetype swap) does not allocate a fresh
## StandardMaterial3D each time.
static var _visual_material_cache: Dictionary = {}

static func _cached_visual_material(color: Color) -> StandardMaterial3D:
	if _visual_material_cache.has(color):
		return _visual_material_cache[color]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	_visual_material_cache[color] = material
	return material


func _apply_weapon_stats(reset_if_unarmed: bool = false) -> void:
	if weapon == null:
		if reset_if_unarmed:
			attack_damage = 0
			attack_range = 0
			attack_ap_cost = 1
		return
	attack_range = weapon.range
	attack_damage = weapon.damage
	attack_ap_cost = weapon.ap_cost


func _refresh_weapon_model() -> void:
	_apply_muzzle_position()
	if not is_instance_valid(weapon_model_root):
		return
	for child in weapon_model_root.get_children():
		child.free()
	if weapon == null or weapon.world_model_scene == null:
		return
	var model := weapon.world_model_scene.instantiate()
	if model == null:
		push_warning("Weapon model could not be instantiated for %s" % weapon.weapon_id)
		return
	if not (model is Node3D):
		push_warning("Weapon model root is not Node3D for %s" % weapon.weapon_id)
		model.free()
		return
	model.name = "WeaponModel"
	weapon_model_root.add_child(model)
	var model_root := model as Node3D
	model_root.position = weapon.world_model_position
	model_root.rotation_degrees = weapon.world_model_rotation_degrees
	model_root.scale = weapon.world_model_scale


func _apply_muzzle_position() -> void:
	if not is_instance_valid(muzzle_flash):
		return
	_muzzle_flash_rest_position = weapon.muzzle_position if weapon != null else Vector3(0.0, 0.0, 0.78)
	muzzle_flash.position = _muzzle_flash_rest_position


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


func set_alert_level(level: int) -> void:
	alert_level = level


func _update_alert_badge() -> void:
	if not is_instance_valid(alert_badge):
		return
	if faction != &"enemy" or alert_level == AlertState.Level.UNAWARE:
		alert_badge.visible = false
		return
	alert_badge.visible = true
	match alert_level:
		AlertState.Level.SUSPICIOUS:
			alert_badge.text = "❓ 警戒"
			alert_badge.modulate = Color(1.0, 0.85, 0.15, 1.0)
			alert_badge.outline_modulate = Color(0.2, 0.12, 0.0, 0.95)
		AlertState.Level.ALERTED:
			alert_badge.text = "❗ 发现!"
			alert_badge.modulate = Color(1.0, 0.35, 0.05, 1.0)
			alert_badge.outline_modulate = Color(0.3, 0.05, 0.0, 0.95)
		AlertState.Level.ENGAGED:
			alert_badge.text = "⚔️ 交战"
			alert_badge.modulate = Color(1.0, 0.15, 0.15, 1.0)
			alert_badge.outline_modulate = Color(0.3, 0.0, 0.0, 0.95)
		_:
			alert_badge.visible = false


func _exit_tree() -> void:
	# Invalidate any coroutine timer before resetting local presentation state.
	# Do not emit attack_feedback_finished here: leaving the tree can be part of
	# Controller/scene teardown, where a gameplay callback would be unsafe.
	_attack_feedback_generation += 1
	_reset_attack_feedback_visuals()
	is_attack_feedback_playing = false
	_disconnect_runtime_state_signals()
