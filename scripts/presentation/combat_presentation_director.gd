class_name CombatPresentationDirector
extends Node

signal mode_changed(new_mode: Mode)

## Presentation only: snapshots never write HP, AP, occupancy or random combat state.
enum Mode { FULL, KILLS_ONLY, OFF }
@export var mode: Mode = Mode.FULL:
	set(value):
		if mode == value:
			return
		mode = value
		_sync_camera_rig()
		mode_changed.emit(mode)

var camera_rig: TacticalCameraRig:
	set(value):
		camera_rig = value
		_sync_camera_rig()
@export_range(0.0, 1.0) var slow_motion_chance: float = 0.25
@export var slow_motion_enabled: bool = true
var active: bool = false
var skipped: bool = false
var impacts: Array[Dictionary] = []
var _before: Array[Dictionary] = []
var _rig: TacticalCameraRig
var _camera_rest: Transform3D
var _camera_goal: Transform3D
var _rng := RandomNumberGenerator.new()
var _since_highlight: int = 3
var _hint: Label
var _settings: OptionButton
var _slow_toggle: CheckButton
var _environment: Array[EnvironmentObjectView] = []
var vfx: CombatVfx
var _environment_impacts: Array[Vector3] = []
var _hidden_labels: Dictionary = {}
var _explosive_views: Dictionary = {}
var remains: Array[Dictionary] = []
var _posed_attacker: PrototypeUnit


func _ready() -> void:
	_rng.randomize()
	vfx = CombatVfx.new()
	add_child(vfx)
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var row := HBoxContainer.new()
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(anchor)
	var panel := PanelContainer.new()
	anchor.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position += Vector2(-280, -138)
	# The presentation panel uses the project's active default theme.  Keep this
	# controller independent from optional UI theme assets so a reverted HUD can
	# still load the main scene.
	panel.add_child(row)
	_settings = OptionButton.new()
	for title in ["战斗演出：完整", "战斗演出：仅击杀", "战斗演出：关闭"]:
		_settings.add_item(title)
	var config := ConfigFile.new()
	if config.load("user://combat_presentation.cfg") == OK:
		mode = clampi(int(config.get_value("presentation", "mode", mode)), 0, 2) as Mode
		slow_motion_enabled = bool(config.get_value("presentation", "slow_motion", true))
	_settings.selected = mode
	_settings.item_selected.connect(func(index: int) -> void: mode = index as Mode; _save_settings())
	row.add_child(_settings)
	_slow_toggle = CheckButton.new()
	_slow_toggle.text = "击杀慢镜头"
	_slow_toggle.button_pressed = slow_motion_enabled
	_slow_toggle.toggled.connect(func(value: bool) -> void: slow_motion_enabled = value; _save_settings())
	row.add_child(_slow_toggle)
	_hint = Label.new()
	_hint.text = "空格 / Esc 跳过演出"
	_hint.visible = false
	row.add_child(_hint)
	_sync_camera_rig()


func _sync_camera_rig() -> void:
	var target_rig: TacticalCameraRig = camera_rig if is_instance_valid(camera_rig) else _rig
	if is_instance_valid(target_rig):
		target_rig.sprint_moments_enabled = (mode != Mode.OFF)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("presentation", "mode", mode)
	config.set_value("presentation", "slow_motion", slow_motion_enabled)
	config.save("user://combat_presentation.cfg")


func retain_environment(view: EnvironmentObjectView, explosive: bool = false) -> void:
	if is_instance_valid(view) and view.is_visible_in_tree():
		_environment.append(view)
		_explosive_views[view] = explosive
		view.hold_destruction_visual = true


func begin(units: Dictionary, rig: TacticalCameraRig) -> void:
	prune_remains()
	active = true
	skipped = false
	_before.clear()
	impacts.clear()
	_environment.clear()
	_explosive_views.clear()
	_environment_impacts.clear()
	_rig = rig
	if not is_instance_valid(camera_rig) and is_instance_valid(rig):
		camera_rig = rig
	_sync_camera_rig()
	if is_instance_valid(_rig):
		_camera_rest = _rig.begin_cinematic()
	for value in units.values():
		var unit := value as PrototypeUnit
		if is_instance_valid(unit) and unit.is_alive():
			_before.append({"unit": unit, "hp": unit.current_hp,
				"visible": unit.visible, "position": unit.global_position, "defer_audio": unit.defer_damage_feedback,
				"pose": unit.visual_root.transform if is_instance_valid(unit.visual_root) else Transform3D.IDENTITY})
			unit.defer_damage_feedback = true
	if is_instance_valid(_hint):
		_hint.visible = mode != Mode.OFF
		_settings.disabled = true
		_slow_toggle.disabled = true


func retains(unit: PrototypeUnit) -> bool:
	if not active:
		return false
	for entry in _before:
		if entry.unit == unit:
			return true
	return false


func skip() -> void:
	skipped = true


func _input(event: InputEvent) -> void:
	if active and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
			skip()
			get_viewport().set_input_as_handled()


func play(attacker: PrototypeUnit, focus: Vector3, area: bool = false, final_action: bool = false, fire_weapon: bool = true, peek_offset: Vector3 = Vector3.ZERO) -> void:
	if not is_inside_tree():
		finish()
		return
	var kills := 0
	for entry in _before:
		var unit: PrototypeUnit = entry.unit
		if is_instance_valid(unit) and unit.current_hp < int(entry.hp) and entry.visible:
			entry["damage"] = int(entry.hp) - unit.current_hp
			entry["killed"] = not unit.is_alive()
			entry["fall_sign"] = -1.0 if _rng.randf() < 0.5 else 1.0
			impacts.append(entry)
			if entry.killed:
				kills += 1
	var cinematic := mode == Mode.FULL or (mode == Mode.KILLS_ONLY and kills > 0)
	var highlight := cinematic and slow_motion_enabled and kills > 0 and (final_action or kills > 1 or (_since_highlight >= 2 and _rng.randf() < slow_motion_chance))
	_since_highlight = 0 if highlight else _since_highlight + 1
	if cinematic:
		for entry in _before:
			var unit: PrototypeUnit = entry.unit
			for label in [unit.status_label, unit.alert_badge, unit.facing_marker]:
				if is_instance_valid(label):
					_hidden_labels[label] = label.visible
					label.visible = false
	if cinematic and is_instance_valid(attacker) and attacker.visible:
		_choose_camera(attacker.global_position, focus, area)
		await _blend_camera(_camera_rest, _camera_goal, 0.16)
	var impact_time := 0.06
	var reaction_strength := 0.16
	var aim := focus + Vector3.UP * 1.05
	for entry in _before:
		var target: PrototypeUnit = entry.unit
		if is_instance_valid(target) and target.global_position.distance_to(focus) < 0.1 and is_instance_valid(target.robot_visual):
			var torso := target.robot_visual.find_child("Torso", true, false) as Node3D
			aim = torso.global_position
	if fire_weapon and is_instance_valid(attacker) and is_instance_valid(attacker.robot_visual):
		_posed_attacker = attacker
		await _pose_attack(attacker, peek_offset, aim, true)
	if is_instance_valid(attacker):
		if attacker.weapon != null and attacker.weapon.attack_feedback_profile != null:
			impact_time = attacker.weapon.attack_feedback_profile.impact_time
			reaction_strength = attacker.weapon.attack_feedback_profile.impact_strength
		if not skipped and fire_weapon:
			var profile := attacker.weapon.attack_feedback_profile if attacker.weapon != null else null
			var count := profile.burst_count if profile != null else 1
			for shot_index in range(count):
				if skipped or not is_instance_valid(attacker) or not is_inside_tree():
					break
				attacker.play_attack_feedback()
				if is_instance_valid(attacker.robot_visual):
					attacker.robot_visual.set_attack_pose(1.0, peek_offset, aim)
					attacker.robot_visual.sync_weapon(attacker.weapon_pivot)
				if attacker.is_visible_in_tree() and is_instance_valid(vfx):
					var source := attacker.muzzle_flash.global_position if is_instance_valid(attacker.muzzle_flash) else attacker.global_position + Vector3.UP
					vfx.shot(source, aim, impact_time, reaction_strength > 0.2)
				if shot_index < count - 1:
					await _wait(profile.burst_interval)
	await _wait(impact_time)
	# An actor killed by its own blast must not have recoil reset its death pose.
	if is_instance_valid(attacker) and not attacker.is_alive():
		attacker._interrupt_attack_feedback()
	for view in _environment:
		if is_instance_valid(view):
			if not view._runtime_active and _explosive_views.get(view, false):
				_environment_impacts.append(view.global_position)
			view.release_destruction_visual()
	if area and not skipped:
		if _environment_impacts.is_empty() and not fire_weapon:
			_environment_impacts.append(focus)
		for position in _environment_impacts:
			_show_blast(position)
	for entry in impacts:
		var unit: PrototypeUnit = entry.unit
		var origin := attacker.global_position + peek_offset if is_instance_valid(attacker) else focus
		entry["incoming"] = entry.position - (focus if area else origin)
		entry["impact_kind"] = &"fatal" if entry.killed else (&"armor" if is_instance_valid(unit.robot_visual) else &"normal")
		if not skipped and is_instance_valid(vfx):
			var hit_point: Vector3 = entry.position + Vector3.UP * 1.05
			if is_instance_valid(unit.robot_visual):
				hit_point = (unit.robot_visual.find_child("Torso", true, false) as Node3D).global_position
			vfx.impact(hit_point, entry.incoming, entry.position.y, entry.impact_kind)
		unit._play_sfx("AudioDeath" if entry.killed else "AudioHit", ImpactAudio.stream(entry.impact_kind))
		_show_damage(entry)
	var elapsed := 0.0
	var wall_time := 0.0
	var reaction_duration := 0.70 if area or kills > 0 else 0.38
	while elapsed < reaction_duration and not skipped and is_inside_tree():
		await get_tree().process_frame
		var delta := get_process_delta_time()
		wall_time += delta
		var local_delta := delta * (0.3 if highlight and wall_time < 0.3 else 1.0)
		elapsed += local_delta
		if is_instance_valid(vfx):
			vfx.advance(local_delta)
		for entry in impacts:
			var unit: PrototypeUnit = entry.unit
			if not is_instance_valid(unit) or not is_instance_valid(unit.visual_root):
				continue
			var progress := clampf(elapsed / (0.7 if entry.killed else 0.34), 0.0, 1.0)
			if is_instance_valid(unit.robot_visual):
				unit.robot_visual.set_reaction(progress, entry.killed, entry.incoming)
				unit.robot_visual.sync_weapon(unit.weapon_pivot)
				continue
			var pose: Transform3D = entry.pose
			var direction: Vector3 = (entry.position - focus).normalized() if area else (entry.position - attacker.global_position).normalized()
			direction.y = 0.0
			direction = unit.global_basis.inverse() * direction
			var amount := progress if entry.killed else sin(progress * PI)
			pose.origin += direction * amount * reaction_strength * (2.0 if entry.killed else 1.0)
			var axis := Vector3.UP.cross(direction).normalized()
			if axis.is_zero_approx():
				axis = Vector3.RIGHT
			pose.basis = pose.basis.rotated(axis, amount * (1.35 if entry.killed else 0.14))
			if entry.killed:
				pose.basis = pose.basis.rotated(Vector3.FORWARD, amount * 0.15 * float(entry.fall_sign))
			unit.visual_root.transform = pose
	if is_instance_valid(attacker) and attacker.is_alive() and fire_weapon:
		await _pose_attack(attacker, peek_offset, aim, false)
	await _wait(0.08 if kills > 0 else 0.0)
	if cinematic:
		await _blend_camera(_rig.camera.global_transform if is_instance_valid(_rig) else _camera_rest, _camera_rest, 0.16)
	if is_instance_valid(attacker) and attacker.is_attack_feedback_playing:
		attacker._interrupt_attack_feedback()
	finish()


func _wait(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration and not skipped and is_inside_tree():
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		if is_instance_valid(vfx):
			vfx.advance(delta)


func _choose_camera(source: Vector3, target: Vector3, area: bool) -> void:
	_camera_goal = _camera_rest
	if not is_instance_valid(_rig):
		return
	var direction := (target - source).normalized()
	var side := direction.cross(Vector3.UP).normalized()
	var aim := target + Vector3.UP * 0.8
	var candidates: Array[Vector3] = []
	if area:
		candidates.append(target + Vector3(0, 7, 6))
	else:
		candidates.append(source - direction * 1.8 + side * 0.9 + Vector3.UP * 1.6)
		candidates.append(source - direction * 1.8 - side * 0.9 + Vector3.UP * 1.6)
		var side_position := (source + target) * 0.5 + side * 3.5 + Vector3.UP * 2.0
		if source.distance_to(target) < 3.0:
			candidates.push_front(side_position)
		else:
			candidates.append(side_position)
	var space := _rig.get_world_3d().direct_space_state
	for candidate in candidates:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.2
		var shape := PhysicsShapeQueryParameters3D.new()
		shape.shape = sphere
		shape.transform.origin = candidate
		# Floors use layer 1, walls/cover use layer 2.
		shape.collision_mask = 3
		if not space.intersect_shape(shape, 1).is_empty():
			continue
		var ray := PhysicsRayQueryParameters3D.create(candidate, aim, 3)
		if not space.intersect_ray(ray).is_empty():
			continue
		_camera_goal = Transform3D(Basis.looking_at(aim - candidate), candidate)
		return


func _blend_camera(start: Transform3D, goal: Transform3D, duration: float) -> void:
	if is_instance_valid(_rig):
		var ray := PhysicsRayQueryParameters3D.create(start.origin, goal.origin, 3)
		if not _rig.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			_rig.camera.global_transform = goal
			return
	var elapsed := 0.0
	while elapsed < duration and not skipped and is_instance_valid(_rig):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if is_instance_valid(vfx):
			vfx.advance(get_process_delta_time())
		_rig.camera.global_transform = start.interpolate_with(goal, smoothstep(0.0, 1.0, clampf(elapsed / duration, 0.0, 1.0)))


func _show_damage(entry: Dictionary) -> void:
	if skipped:
		return
	var label := Label3D.new()
	label.text = "-%d%s" % [entry.damage, " 击杀" if entry.killed else ""]
	label.font_size = 44
	label.modulate = Color(1, 0.65, 0.2) if entry.killed else Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.global_position = entry.position + Vector3.UP * 1.8
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.5, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)


func _show_blast(position: Vector3) -> void:
	if is_instance_valid(vfx):
		vfx.explosion(position)


func finish() -> void:
	if not active:
		return
	for label in _hidden_labels:
		if is_instance_valid(label):
			label.visible = _hidden_labels[label]
	_hidden_labels.clear()
	for view in _environment:
		if is_instance_valid(view):
			view.release_destruction_visual()
	_environment.clear()
	if is_instance_valid(vfx):
		vfx.clear()
	for entry in impacts:
		if entry.killed and is_instance_valid(entry.unit) and is_instance_valid(entry.unit.robot_visual):
			entry.unit.robot_visual.set_reaction(1.0, true, entry.get("incoming", Vector3.BACK))
			entry.unit.robot_visual.sync_weapon(entry.unit.weapon_pivot)
			_store_remains(entry.unit)
	if is_instance_valid(_posed_attacker) and is_instance_valid(_posed_attacker.robot_visual):
		_posed_attacker.robot_visual.set_attack_pose(0.0, Vector3.ZERO, Vector3.ZERO)
	_posed_attacker = null
	for entry in _before:
		var unit: PrototypeUnit = entry.unit
		if not is_instance_valid(unit):
			continue
		unit.defer_damage_feedback = entry.defer_audio
		if is_instance_valid(unit.robot_visual):
			unit.robot_visual.set_attack_pose(0.0, Vector3.ZERO, Vector3.ZERO)
			unit.robot_visual.reset_pose()
			unit._apply_weapon_facing()
		if is_instance_valid(unit.visual_root):
			unit.visual_root.transform = entry.pose
		if not unit.is_alive():
			unit.visible = false
			unit.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_rig):
		_rig.end_cinematic(_camera_rest)
	active = false
	_before.clear()
	if is_instance_valid(_hint):
		_hint.visible = false
		_settings.disabled = false
		_slow_toggle.disabled = false


func _exit_tree() -> void:
	finish()


func _pose_attack(unit: PrototypeUnit, offset: Vector3, target: Vector3, opening: bool) -> void:
	if not is_instance_valid(unit.robot_visual):
		return
	var elapsed := 0.0
	while elapsed < 0.16 and not skipped and is_inside_tree():
		await get_tree().process_frame
		if not is_instance_valid(unit):
			return
		elapsed += get_process_delta_time()
		var t := smoothstep(0.0, 1.0, minf(elapsed / 0.16, 1.0))
		unit.robot_visual.set_attack_pose(t if opening else 1.0 - t, offset, target)
		unit.robot_visual.sync_weapon(unit.weapon_pivot)
		if is_instance_valid(vfx):
			vfx.advance(get_process_delta_time())


func _store_remains(unit: PrototypeUnit) -> void:
	for entry in remains:
		if entry.source == unit:
			return
	var body := Node3D.new()
	body.name = "RobotRemains"
	add_child(body)
	for branch in [unit.robot_visual, unit.weapon_model_root]:
		for source in branch.find_children("*", "MeshInstance3D", true, false):
			var mesh := MeshInstance3D.new()
			mesh.mesh = source.mesh
			mesh.material_override = source.material_override
			for i in range(source.mesh.get_surface_count()):
				mesh.set_surface_override_material(i, source.get_surface_override_material(i))
			body.add_child(mesh)
			mesh.global_transform = source.global_transform
	remains.append({"source": unit, "node": body})
	while remains.size() > 32:
		remains.pop_front().node.free()


func prune_remains() -> void:
	for i in range(remains.size() - 1, -1, -1):
		var entry := remains[i]
		if not is_instance_valid(entry.source) or entry.source.is_alive():
			entry.node.free()
			remains.remove_at(i)
