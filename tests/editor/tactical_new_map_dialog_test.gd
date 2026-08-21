extends SceneTree

## Pure headless coverage for the New Map dialog layout and presentation rules.
## It does not create a map and does not depend on a concrete map scene.

const DialogScript := preload("res://addons/tactical_map_editor/ui/tactical_new_map_dialog.gd")

var _failures: Array[String] = []


func _init() -> void:
	var dialog := DialogScript.new()
	# SceneTree._init runs before the newly added child receives _ready.
	# Build explicitly so the structural assertions remain synchronous/headless.
	dialog.call("_build_ui")
	root.add_child(dialog)

	var content := dialog.get_node("NewMapDialogMargin/NewMapDialogContent") as VBoxContainer
	var scroll := dialog.get_node("NewMapDialogMargin/NewMapDialogContent/NewMapBodyScroll") as ScrollContainer
	var actions := dialog.get_node("NewMapDialogMargin/NewMapDialogContent/NewMapActions") as HBoxContainer
	_expect(content != null, "layout: dialog content should exist")
	_expect(scroll != null, "layout: form should be inside a ScrollContainer")
	_expect(actions != null, "layout: fixed action bar should exist")
	if scroll != null and actions != null:
		_expect(scroll.is_ancestor_of(actions) == false, "layout: actions must stay outside the scroll area")
		_expect(actions.is_ancestor_of(scroll) == false, "layout: scroll area must stay above the action bar")
		_expect(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "layout: horizontal scrolling should stay disabled")
		_expect(scroll.get_node_or_null("NewMapFormContent") != null, "layout: scroll area should contain the form content")
	_expect(dialog.min_size.x <= 480 and dialog.min_size.y <= 440, "layout: minimum size should remain usable in a compact editor")
	_expect(dialog.size.x <= 600 and dialog.size.y <= 640, "layout: initial dialog size should be clamped")

	var unique := DialogScript.dedupe_messages(["first", "first", "second", "first"])
	_expect(unique == ["first", "second"], "validation: dedupe should preserve first-seen order")

	var error_label := dialog.get_node("NewMapDialogMargin/NewMapDialogContent/NewMapBodyScroll/NewMapFormContent/ValidationErrors") as Label
	var warning_label := dialog.get_node("NewMapDialogMargin/NewMapDialogContent/NewMapBodyScroll/NewMapFormContent/ValidationWarnings") as Label
	var create_button := dialog.get_node("NewMapDialogMargin/NewMapDialogContent/NewMapActions/CreateMap") as Button
	var cancel_button := dialog.get_node("NewMapDialogMargin/NewMapDialogContent/NewMapActions/CancelNewMap") as Button
	_expect(error_label != null and warning_label != null, "validation: error and warning labels should be in the scroll area")
	_expect(create_button != null and cancel_button != null, "validation: both action buttons should exist")
	if error_label != null and warning_label != null and create_button != null and cancel_button != null:
		var duplicate_errors: Array[String] = ["场景已存在，为避免覆盖请更换路径：res://maps/a.tscn", "场景已存在，为避免覆盖请更换路径：res://maps/a.tscn", "烘焙资源已存在，为避免覆盖请更换路径：res://maps/a.tres"]
		var duplicate_warnings: Array[String] = ["素材库有提示", "素材库有提示"]
		dialog.call("_show_validation", duplicate_errors, duplicate_warnings)
		_expect(_count_occurrences(error_label.text, "场景已存在，为避免覆盖请更换路径：res://maps/a.tscn") == 1, "validation: duplicate scene error should render once")
		_expect(_count_occurrences(error_label.text, "烘焙资源已存在，为避免覆盖请更换路径：res://maps/a.tres") == 1, "validation: duplicate output error should render once")
		_expect(_count_occurrences(warning_label.text, "素材库有提示") == 1, "validation: duplicate warning should render once")
		_expect(error_label.text.begins_with("错误：\n"), "validation: error heading should render once")
		_expect(create_button.disabled, "validation: create should be disabled when errors exist")
		_expect(cancel_button.visible and not cancel_button.disabled, "validation: cancel should remain visible and enabled")
		var no_errors: Array[String] = []
		var no_warnings: Array[String] = []
		dialog.call("_show_validation", no_errors, no_warnings)
		_expect(not create_button.disabled, "validation: create should re-enable after errors clear")

	dialog.free()
	_finish()


func _count_occurrences(text: String, needle: String) -> int:
	var count := 0
	var offset := 0
	while true:
		var index := text.find(needle, offset)
		if index < 0:
			return count
		count += 1
		offset = index + needle.length()
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_NEW_MAP_DIALOG_TEST: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TACTICAL_NEW_MAP_DIALOG_TEST: FAIL (%d)" % _failures.size())
	quit(1)
