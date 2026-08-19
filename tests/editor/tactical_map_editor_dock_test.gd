extends SceneTree

## Pure Dock wiring coverage. It exercises the code-built control only and
## never loads a map scene or invokes authoring/bake data.

const DockScript = preload("res://addons/tactical_map_editor/ui/tactical_map_dock.gd")
const SessionScript = preload("res://addons/tactical_map_editor/editing/map_edit_session.gd")

var _failures: Array[String] = []
var _play_signal_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dock = DockScript.new()
	var session = SessionScript.new()
	# Match the EditorPlugin lifecycle: set_session can happen before the Dock
	# enters the tree and before _ready() builds the controls.
	dock.set_status_message("before-ready", false)
	dock.set_session(session)
	get_root().add_child(dock)
	await process_frame
	var play_button := dock.find_child("BakeAndPlayButton", true, false) as Button
	_expect(play_button != null, "dock: Bake & Play button should be created")
	if play_button != null:
		_expect(play_button.text == "Bake & Play", "dock: button label should be stable")
		dock.play_requested.connect(_on_play_requested)
		play_button.pressed.emit()
		_expect(_play_signal_count == 1, "dock: button should emit play_requested once")

	_expect(play_button == null or play_button.disabled, "dock: no Author should disable Bake & Play")
	# Simulate a hot-reloaded script whose new field was not restored on the
	# existing Dock instance. _refresh must recover the existing button safely.
	dock.set("_play_button", null)
	dock.call("_refresh")
	var recovered_button := dock.find_child("BakeAndPlayButton", true, false) as Button
	_expect(recovered_button != null and recovered_button.disabled, "dock: refresh should recover a stale play-button field")
	var status_label := dock.find_child("StatusLabel", true, false) as Label
	_expect(status_label != null, "dock: status label should be available after ready")
	if status_label != null:
		dock.set_status_message("ready-error", false)
		_expect(status_label.text == "ready-error", "dock: public status API should update text")
		_expect(status_label.modulate == Color("ff8c8c"), "dock: invalid status should use error color")
		dock.set_status_message("ready-ok", true)
		_expect(status_label.text == "ready-ok", "dock: public status API should update valid text")
		_expect(status_label.modulate == Color("8fe388"), "dock: valid status should use success color")
	dock.free()
	_finish()


func _on_play_requested() -> void:
	_play_signal_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_MAP_EDITOR_DOCK_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_MAP_EDITOR_DOCK_TEST: FAIL (%d failure(s))" % _failures.size())
	quit(1)
