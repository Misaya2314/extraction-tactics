@tool
class_name TacticalMapDock
extends VBoxContainer

## Small, code-built Dock for the stage-B workflow.  Keeping the controls in
## code avoids adding a second authored scene and lets the Dock survive when
## the selected map scene changes.

signal edit_mode_changed(enabled: bool)
signal floor_changed(level: int)
signal target_layer_changed(layer: int)
signal tool_changed(tool: int)
signal rotate_requested
signal placeable_selected(index: int)
signal validate_requested
signal bake_requested
signal save_requested
signal play_requested

var session: TacticalMapEditSession
var _title: Label
var _selection_label: Label
var _edit_toggle: CheckButton
var _floor_spin: SpinBox
var _target_option: OptionButton
var _tool_option: OptionButton
var _rotate_button: Button
var _search: LineEdit
var _palette: ItemList
var _status: Label
var _validate_button: Button
var _bake_button: Button
var _save_button: Button
var _play_button: Button
var _refreshing := false


func _ready() -> void:
	_build_ui()


func set_session(next_session: TacticalMapEditSession) -> void:
	if session != null:
		if session.changed.is_connected(_on_session_changed):
			session.changed.disconnect(_on_session_changed)
		if session.status_changed.is_connected(_on_session_status_changed):
			session.status_changed.disconnect(_on_session_status_changed)
	session = next_session
	if session != null:
		session.changed.connect(_on_session_changed)
		session.status_changed.connect(_on_session_status_changed)
	_refresh()


func show_result(action_name: String, result: Dictionary) -> void:
	var errors: Array = result.get(&"errors", [])
	var warnings: Array = result.get(&"warnings", [])
	if errors.is_empty():
		var suffix := ""
		if not warnings.is_empty():
			suffix = " 警告 %d 条。" % warnings.size()
		_set_status("%s 成功。%s" % [action_name, suffix], true)
	else:
		_set_status("%s 失败：%s" % [action_name, String(errors[0])], false)
		if errors.size() > 1:
			_set_status("%s 失败：%s（另有 %d 条错误）" % [action_name, String(errors[0]), errors.size() - 1], false)


func _build_ui() -> void:
	custom_minimum_size = Vector2(280, 360)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(content)

	_title = Label.new()
	_title.text = "Tactical Map Builder · MVP"
	_title.add_theme_font_size_override("font_size", 16)
	content.add_child(_title)

	_selection_label = Label.new()
	_selection_label.text = "未选择 TacticalMapAuthor"
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_selection_label)

	_edit_toggle = CheckButton.new()
	_edit_toggle.text = "地图编辑模式"
	_edit_toggle.tooltip_text = "关闭时插件不消费 3D 视口输入，保留 Godot 原生选择和相机操作。"
	_edit_toggle.toggled.connect(func(value: bool) -> void: edit_mode_changed.emit(value))
	content.add_child(_edit_toggle)

	var level_row := HBoxContainer.new()
	content.add_child(level_row)
	var level_label := Label.new()
	level_label.text = "楼层"
	level_label.custom_minimum_size.x = 52
	level_row.add_child(level_label)
	_floor_spin = SpinBox.new()
	_floor_spin.min_value = 0
	_floor_spin.max_value = 0
	_floor_spin.step = 1
	_floor_spin.tooltip_text = "当前鼠标编辑平面。坐标按 Vector3i(x, level, z) 处理。"
	_floor_spin.value_changed.connect(func(value: float) -> void: floor_changed.emit(int(value)))
	level_row.add_child(_floor_spin)
	var target_label := Label.new()
	target_label.text = "目标层"
	target_label.custom_minimum_size.x = 52
	level_row.add_child(target_label)
	_target_option = OptionButton.new()
	_target_option.add_item("Floor", TacticalMapEditSession.TargetLayer.FLOOR)
	_target_option.add_item("Structure", TacticalMapEditSession.TargetLayer.STRUCTURE)
	_target_option.add_item("Decoration", TacticalMapEditSession.TargetLayer.DECORATION)
	_target_option.add_item("Object", TacticalMapEditSession.TargetLayer.OBJECT)
	_target_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_option.item_selected.connect(func(index: int) -> void:
		target_layer_changed.emit(int(_target_option.get_item_id(index)))
	)
	level_row.add_child(_target_option)

	var tool_row := HBoxContainer.new()
	content.add_child(tool_row)
	var tool_label := Label.new()
	tool_label.text = "工具"
	tool_label.custom_minimum_size.x = 52
	tool_row.add_child(tool_label)
	_tool_option = OptionButton.new()
	_tool_option.add_item("Paint", TacticalMapEditSession.Tool.PAINT)
	_tool_option.add_item("Erase", TacticalMapEditSession.Tool.ERASE)
	_tool_option.add_item("Pick", TacticalMapEditSession.Tool.PICK)
	_tool_option.add_item("Rotate", TacticalMapEditSession.Tool.ROTATE)
	_tool_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_option.item_selected.connect(func(index: int) -> void:
		tool_changed.emit(int(_tool_option.get_item_id(index)))
	)
	tool_row.add_child(_tool_option)
	_rotate_button = Button.new()
	_rotate_button.text = "R 旋转"
	_rotate_button.tooltip_text = "旋转选中的素材 90°；Rotate 工具可旋转目标格已有内容。"
	_rotate_button.pressed.connect(func() -> void: rotate_requested.emit())
	tool_row.add_child(_rotate_button)

	_search = LineEdit.new()
	_search.placeholder_text = "搜索素材 / 分类 / 稳定 ID"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _refresh_palette())
	content.add_child(_search)

	_palette = ItemList.new()
	_palette.select_mode = ItemList.SELECT_SINGLE
	_palette.custom_minimum_size = Vector2(0, 190)
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.item_selected.connect(_on_palette_item_selected)
	content.add_child(_palette)

	var action_row := HBoxContainer.new()
	content.add_child(action_row)
	_validate_button = Button.new()
	_validate_button.text = "Validate"
	_validate_button.pressed.connect(func() -> void: validate_requested.emit())
	action_row.add_child(_validate_button)
	_bake_button = Button.new()
	_bake_button.text = "Bake"
	_bake_button.pressed.connect(func() -> void: bake_requested.emit())
	action_row.add_child(_bake_button)
	_save_button = Button.new()
	_save_button.text = "Save Scene"
	_save_button.pressed.connect(func() -> void: save_requested.emit())
	action_row.add_child(_save_button)

	var run_row := HBoxContainer.new()
	content.add_child(run_row)
	_play_button = Button.new()
	_play_button.name = "BakeAndPlayButton"
	_play_button.text = "Bake & Play"
	_play_button.tooltip_text = "保存当前作者场景，Bake 成功后运行主场景。"
	_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_button.pressed.connect(_emit_play_requested)
	run_row.add_child(_play_button)

	_status = Label.new()
	_status.name = "StatusLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "选择一个 TacticalMapAuthor 开始编辑。"
	content.add_child(_status)
	_refresh()


func _refresh() -> void:
	if session == null or not _ensure_play_button() or not _has_ui_ready():
		return
	_refreshing = true
	var has_author := session.has_author()
	_selection_label.text = "作者：%s" % session.author.name if has_author else "未选择 TacticalMapAuthor"
	_edit_toggle.disabled = not has_author
	_edit_toggle.button_pressed = session.edit_mode and has_author
	_floor_spin.mouse_filter = Control.MOUSE_FILTER_STOP if has_author else Control.MOUSE_FILTER_IGNORE
	var floor_line_edit := _floor_spin.get_line_edit()
	if floor_line_edit != null:
		floor_line_edit.editable = has_author
	_floor_spin.max_value = maxi(session.level_count() - 1, 0)
	_floor_spin.value = session.floor_level
	_target_option.disabled = not has_author
	_tool_option.disabled = not has_author
	_rotate_button.disabled = not has_author
	_validate_button.disabled = not has_author
	_bake_button.disabled = not has_author
	_save_button.disabled = not has_author
	_play_button.disabled = not has_author
	for target_index in range(_target_option.item_count):
		if _target_option.get_item_id(target_index) == session.target_layer:
			_target_option.select(target_index)
			break
	for tool_index in range(_tool_option.item_count):
		if _tool_option.get_item_id(tool_index) == session.tool:
			_tool_option.select(tool_index)
			break
	_refresh_palette()
	var status := session.get_last_status()
	_set_status(String(status.get("message", "")), bool(status.get("valid", true)))
	_refreshing = false


func _refresh_palette() -> void:
	if not _is_valid_control(_palette):
		return
	_palette.clear()
	if session == null:
		return
	var entries := session.get_placeables(_search.text if _search != null else "")
	var selected_id := String(session.get_selected_placeable().get("id", ""))
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var label := String(entry.get("label", entry.get("id", "素材")))
		_palette.add_item(label)
		_palette.set_item_tooltip(_palette.item_count - 1, "%s · %s" % [entry.get("category", ""), entry.get("id", "")])
		_palette.set_item_metadata(_palette.item_count - 1, entry.get("id", ""))
		if String(entry.get("id", "")) == selected_id:
			_palette.select(_palette.item_count - 1)


func _on_palette_item_selected(index: int) -> void:
	if _refreshing or session == null:
		return
	var entries := session.get_placeables(_search.text)
	if index < 0 or index >= entries.size():
		return
	var selected_id := String(entries[index].get("id", ""))
	for full_index in range(session.placeables.size()):
		if String(session.placeables[full_index].get("id", "")) == selected_id:
			emit_signal("placeable_selected", full_index)
			return


func _on_session_changed() -> void:
	if not _refreshing:
		_refresh()


func _on_session_status_changed(message: String, valid: bool) -> void:
	_set_status(message, valid)


func _set_status(message: String, valid: bool) -> void:
	if not _is_valid_control(_status):
		return
	_status.text = message
	_status.modulate = Color("8fe388") if valid else Color("ff8c8c")


func set_status_message(message: String, valid: bool = true) -> void:
	_set_status(message, valid)


func _emit_play_requested() -> void:
	play_requested.emit()


func _is_valid_control(control: Object) -> bool:
	return control != null and is_instance_valid(control)


func _has_base_ui_ready() -> bool:
	return _is_valid_control(_title) \
		and _is_valid_control(_selection_label) \
		and _is_valid_control(_edit_toggle) \
		and _is_valid_control(_floor_spin) \
		and _is_valid_control(_target_option) \
		and _is_valid_control(_tool_option) \
		and _is_valid_control(_rotate_button) \
		and _is_valid_control(_search) \
		and _is_valid_control(_palette) \
		and _is_valid_control(_status) \
		and _is_valid_control(_validate_button) \
		and _is_valid_control(_bake_button) \
		and _is_valid_control(_save_button)


func _has_ui_ready() -> bool:
	return _has_base_ui_ready() and _is_valid_control(_play_button)


func _ensure_play_button() -> bool:
	if _is_valid_control(_play_button):
		return true
	var existing := find_child("BakeAndPlayButton", true, false)
	if existing is Button:
		_play_button = existing as Button
		if not _play_button.pressed.is_connected(_emit_play_requested):
			_play_button.pressed.connect(_emit_play_requested)
		return true
	if not _has_base_ui_ready():
		return false
	# A hot-reloaded Dock can retain the old controls without the newly added
	# button. Add only this missing control; never rebuild the whole UI.
	var run_row := HBoxContainer.new()
	run_row.name = "BakeAndPlayRow"
	_play_button = Button.new()
	_play_button.name = "BakeAndPlayButton"
	_play_button.text = "Bake & Play"
	_play_button.tooltip_text = "保存当前作者场景，Bake 成功后运行主场景。"
	_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_button.pressed.connect(_emit_play_requested)
	run_row.add_child(_play_button)
	add_child(run_row)
	return true
