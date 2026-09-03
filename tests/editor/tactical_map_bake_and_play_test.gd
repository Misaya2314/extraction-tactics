extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main/prototype_main.tscn"
const TARGET_MAP_PATH := "res://resources/maps/gym.tres"
const RUNNER_SCENE_PATH := "user://bake_and_play_runner_test.tscn"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# 1. Verify default main scene retains its configured map
	var default_packed := load(MAIN_SCENE_PATH) as PackedScene
	_expect(default_packed != null, "main scene should load")
	if default_packed != null:
		var default_inst := default_packed.instantiate() as PrototypeController
		_expect(default_inst != null, "main scene should instantiate as PrototypeController")
		if default_inst != null:
			_expect(default_inst.map_definition != null, "default main scene should have map_definition")
			_expect(default_inst.map_definition.map_id == &"medium_warzone", "default main scene map_id should be medium_warzone")
			default_inst.free()

	# 2. Generate runner scene overriding map_definition with gym.tres
	var runner_tscn := """[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/main/prototype_main.tscn" id="1_main"]
[ext_resource type="Resource" path="%s" id="2_map"]

[node name="PrototypeMain" instance=ExtResource("1_main")]
map_definition = ExtResource("2_map")
""" % TARGET_MAP_PATH

	var file := FileAccess.open(RUNNER_SCENE_PATH, FileAccess.WRITE)
	_expect(file != null, "runner scene file should open for write")
	if file != null:
		file.store_string(runner_tscn)
		file.close()

	_expect(FileAccess.file_exists(RUNNER_SCENE_PATH), "runner scene file should exist on disk")

	# 3. Load and instantiate runner scene
	var runner_packed := load(RUNNER_SCENE_PATH) as PackedScene
	_expect(runner_packed != null, "runner scene should load as PackedScene")
	if runner_packed != null:
		var runner_inst := runner_packed.instantiate() as PrototypeController
		_expect(runner_inst != null, "runner scene should instantiate as PrototypeController")
		if runner_inst != null:
			_expect(runner_inst.map_definition != null, "runner scene should have map_definition")
			_expect(runner_inst.map_definition.map_id == &"gym", "runner scene map_id should be gym (overridden)")
			runner_inst.free()

	# 4. Clean up test file
	if FileAccess.file_exists(RUNNER_SCENE_PATH):
		DirAccess.remove_absolute(RUNNER_SCENE_PATH)

	if not _failures.is_empty():
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)
	else:
		print("TACTICAL_MAP_BAKE_AND_PLAY_TEST: PASS")
		quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
