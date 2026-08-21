extends SceneTree

## Pure selection/lock contract coverage. It does not instantiate EditorPlugin
## or load a concrete map scene.

const EditorPluginScript := preload("res://addons/tactical_map_editor/tactical_map_editor_plugin.gd")

var _failures: Array[String] = []


func _init() -> void:
	var author := TacticalMapAuthor.new()
	author.name = "RootAuthor"
	# Godot may place the edited scene root below an internal editor parent.
	# Root eligibility is therefore checked by scene-root identity, not parent.
	var internal_parent := Node.new()
	internal_parent.name = "GodotInternalParent"
	internal_parent.add_child(author)
	var child := Node3D.new()
	child.name = "FloorGrid"
	author.add_child(child)
	var wrapper := Node3D.new()
	var nested_author := TacticalMapAuthor.new()
	nested_author.name = "NestedAuthor"
	wrapper.add_child(nested_author)
	var other_root := TacticalMapAuthor.new()
	other_root.name = "OtherRoot"
	var unrelated := Node3D.new()

	_expect(EditorPluginScript.is_map_author_root_node(author), "selection: root author should qualify")
	_expect(not EditorPluginScript.is_map_author_root_node(child), "selection: child node must not qualify")
	_expect(EditorPluginScript.is_map_author_root_node(nested_author), "selection: author type qualifies independent of parent")
	_expect(EditorPluginScript.selected_scene_root_author([author], author) == author, "selection: only the selected edited-scene root may bind")
	_expect(EditorPluginScript.selected_scene_root_author([child], author) == null, "selection: child cannot bind by parent lookup")
	_expect(EditorPluginScript.selected_scene_root_author([nested_author], author) == null, "selection: nested author cannot bind relative to outer root")
	_expect(EditorPluginScript.selected_scene_root_author([nested_author], wrapper) == null, "selection: nested author cannot bind")
	_expect(EditorPluginScript.selected_scene_root_author([other_root], author) == null, "selection: another scene root cannot bind")
	_expect(EditorPluginScript.selected_scene_root_author([author, child], author) == null, "selection: multi-selection cannot bind")
	_expect(EditorPluginScript.selection_belongs_to_author([], author), "lock: empty selection must preserve active editing")
	_expect(EditorPluginScript.selection_belongs_to_author([child], author), "lock: current map descendants must preserve active editing")
	_expect(EditorPluginScript.selection_belongs_to_author([author], author), "lock: current author selection must remain in active map")
	_expect(not EditorPluginScript.selection_belongs_to_author([other_root], author), "lock: another root must exit active editing")
	_expect(not EditorPluginScript.selection_belongs_to_author([unrelated], author), "lock: external node must exit active editing")
	_expect(not EditorPluginScript.selection_belongs_to_author([nested_author], author), "lock: nested author outside active root must exit active editing")

	internal_parent.free()
	wrapper.free()
	other_root.free()
	unrelated.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_EDITOR_SELECTION_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_EDITOR_SELECTION_TEST: FAIL (%d)" % _failures.size())
	quit(1)
