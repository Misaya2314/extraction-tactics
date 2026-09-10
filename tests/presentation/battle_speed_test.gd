extends SceneTree

const CONFIG_PATH := "user://battle_speed.cfg"

var _backup := PackedByteArray()
var _had_config := false

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous := Engine.time_scale
	_backup_config()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))
	var button := Button.new()
	button.set_script(preload("res://scripts/gameplay/ui/battle_speed_button.gd"))
	root.add_child(button)
	assert(Engine.time_scale == 1.0)
	var unit := preload("res://scenes/main/prototype_unit.tscn").instantiate() as PrototypeUnit
	root.add_child(unit)
	unit.configure(Vector3i.ZERO, &"player", Color.CYAN)
	var hp := unit.current_hp
	var ap := unit.current_action_points
	var start := Time.get_ticks_msec()
	await unit.move_along_world_path([Vector3(3, 0, 0)], Vector3i(1, 0, 0))
	var normal := Time.get_ticks_msec() - start
	button.pressed.emit()
	assert(Engine.time_scale == 2.0 and button.text.contains("2×"))
	assert(_saved_speed() == 2.0, "2x must be persisted to disk")
	button.pressed.emit()
	assert(Engine.time_scale == 4.0)
	start = Time.get_ticks_msec()
	await unit.move_along_world_path([Vector3.ZERO], Vector3i.ZERO)
	var fast := Time.get_ticks_msec() - start
	assert(fast < normal * 0.5, "4x movement must substantially reduce real waiting time")
	assert(unit.global_position == Vector3.ZERO and unit.current_hp == hp and unit.current_action_points == ap)
	button.pressed.emit()
	assert(Engine.time_scale == 1.0)
	button.pressed.emit()
	button.free()
	assert(Engine.time_scale == previous, "leaving battle must restore clock")
	var restored := Button.new()
	restored.set_script(preload("res://scripts/gameplay/ui/battle_speed_button.gd"))
	root.add_child(restored)
	assert(Engine.time_scale == 2.0 and restored.text.contains("2×"), "next battle must load the saved speed")
	restored.free()
	assert(Engine.time_scale == previous, "leaving battle must restore clock again")
	unit.free()
	_restore_config()
	await process_frame
	await process_frame
	print("BATTLE_SPEED_TEST: PASS (1x=%d ms, 4x=%d ms)" % [normal, fast])
	quit()

func _saved_speed() -> float:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return -1.0
	return float(config.get_value("speed", "value", -1.0))

func _backup_config() -> void:
	_had_config = FileAccess.file_exists(CONFIG_PATH)
	if not _had_config:
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file:
		_backup = file.get_buffer(file.get_length())

func _restore_config() -> void:
	if not _had_config:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_buffer(_backup)
