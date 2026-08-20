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
signal debug_view_changed(view: int)
signal validation_location_requested(diagnostic: Dictionary)
signal property_override_requested(field: StringName, value: Variant)
signal property_inherit_requested(field: StringName)
signal default_property_override_requested(field: StringName, value: Variant)
signal default_property_restore_requested(field: StringName)

const PROPERTY_FIELDS: Array[StringName] = [
	&"WALKABLE",
	&"MOVE_COST",
	&"SIGHT_BLOCK",
	&"PROJECTILE_BLOCK",
	&"OCCLUDER_HEIGHT",
]
const PROPERTY_SERVICE_SCRIPT := preload("res://scripts/map_authoring/tactical_map_property_service.gd")

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
var _scroll: ScrollContainer
var _content: VBoxContainer
var _debug_panel: VBoxContainer
var _debug_option: OptionButton
var _debug_legend: Label
var _validation_panel: VBoxContainer
var _validation_summary: Label
var _validation_list: ItemList
var _validation_diagnostics: Array[Dictionary] = []
var _property_panel: VBoxContainer
var _property_selection_label: Label
var _property_state_labels: Dictionary = {}
var _property_base_value_labels: Dictionary = {}
var _property_override_value_labels: Dictionary = {}
var _property_value_labels: Dictionary = {}
var _property_editors: Dictionary = {}
var _property_write_buttons: Dictionary = {}
var _property_inherit_buttons: Dictionary = {}
var _default_panel: VBoxContainer
var _default_context_label: Label
var _default_scope_label: Label
var _default_value_labels: Dictionary = {}
var _default_support_labels: Dictionary = {}
var _default_editors: Dictionary = {}
var _default_write_buttons: Dictionary = {}
var _default_restore_buttons: Dictionary = {}
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
	margin.name = "TacticalMapDockMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	_scroll = ScrollContainer.new()
	_scroll.name = "TacticalMapDockScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll)
	var content := VBoxContainer.new()
	content.name = "TacticalMapDockContent"
	_content = content
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_scroll.add_child(content)

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
	_tool_option.name = "ToolOption"
	_tool_option.add_item("Paint", TacticalMapEditSession.Tool.PAINT)
	_tool_option.add_item("Erase", TacticalMapEditSession.Tool.ERASE)
	_tool_option.add_item("Pick", TacticalMapEditSession.Tool.PICK)
	_tool_option.add_item("Rotate", TacticalMapEditSession.Tool.ROTATE)
	_tool_option.add_item("Select", TacticalMapEditSession.Tool.SELECT)
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

	_build_property_panel(content)
	_build_debug_panel(content)
	_build_default_property_panel(content)
	_build_validation_panel(content)

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


func _build_debug_panel(content: VBoxContainer) -> void:
	_debug_panel = VBoxContainer.new()
	_debug_panel.name = "DebugViewPanel"
	content.add_child(_debug_panel)
	var heading := Label.new()
	heading.text = "规则调试视图"
	heading.add_theme_font_size_override("font_size", 14)
	_debug_panel.add_child(heading)
	var row := HBoxContainer.new()
	_debug_panel.add_child(row)
	var label := Label.new()
	label.text = "视图"
	label.custom_minimum_size.x = 52
	row.add_child(label)
	_debug_option = OptionButton.new()
	_debug_option.name = "DebugViewOption"
	_add_debug_view_items(_debug_option)
	_debug_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_option.item_selected.connect(_on_debug_view_selected)
	row.add_child(_debug_option)
	_debug_legend = Label.new()
	_debug_legend.name = "DebugLegend"
	_debug_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_legend.text = "正常模型；调试覆盖已关闭。"
	_debug_panel.add_child(_debug_legend)


func _add_debug_view_items(option: OptionButton) -> void:
	if option == null:
		return
	var items := [
		["Normal", TacticalMapEditSession.DebugView.NORMAL],
		["Walkability", TacticalMapEditSession.DebugView.WALKABILITY],
		["Move Cost", TacticalMapEditSession.DebugView.MOVE_COST],
		["Sight Block", TacticalMapEditSession.DebugView.SIGHT_BLOCK],
		["Projectile Block", TacticalMapEditSession.DebugView.PROJECTILE_BLOCK],
		["Occluder Height", TacticalMapEditSession.DebugView.OCCLUDER_HEIGHT],
		["Validation", TacticalMapEditSession.DebugView.VALIDATION],
	]
	for item in items:
		var found := false
		for index in range(option.item_count):
			if option.get_item_id(index) == int(item[1]):
				found = true
				break
		if not found:
			option.add_item(String(item[0]), int(item[1]))


func _build_default_property_panel(content: VBoxContainer) -> void:
	_default_panel = VBoxContainer.new()
	_default_panel.name = "DefaultPropertyPanel"
	_default_panel.custom_minimum_size = Vector2(0, 190)
	content.add_child(_default_panel)
	var heading := Label.new()
	heading.text = "素材默认属性"
	heading.add_theme_font_size_override("font_size", 14)
	_default_panel.add_child(heading)
	_default_context_label = Label.new()
	_default_context_label.name = "DefaultPropertyContext"
	_default_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_default_panel.add_child(_default_context_label)
	_default_scope_label = Label.new()
	_default_scope_label.name = "DefaultPropertyScope"
	_default_scope_label.text = "影响所有未覆盖实例。稳定 ID 不可在此修改。"
	_default_scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_default_scope_label.add_theme_color_override("font_color", Color("e6c86e"))
	_default_panel.add_child(_default_scope_label)
	var grid := GridContainer.new()
	grid.name = "DefaultPropertyGrid"
	grid.columns = 6
	_default_panel.add_child(grid)
	for heading_text in ["字段", "默认值", "支持状态", "编辑值", "写入", "恢复"]:
		var column_heading := Label.new()
		column_heading.text = heading_text
		column_heading.add_theme_color_override("font_color", Color("aab4c5"))
		grid.add_child(column_heading)
	for field in PROPERTY_FIELDS:
		_add_default_property_row(grid, field)


func _add_default_property_row(grid: GridContainer, field: StringName) -> void:
	var descriptor := _property_descriptor(field)
	var field_label := Label.new()
	field_label.name = "DefaultField_%s" % field
	field_label.text = String(descriptor.get(&"label", field))
	grid.add_child(field_label)
	var value_label := Label.new()
	value_label.name = "DefaultValue_%s" % field
	value_label.text = "—"
	_default_value_labels[field] = value_label
	grid.add_child(value_label)
	var support_label := Label.new()
	support_label.name = "DefaultSupport_%s" % field
	support_label.text = "未选择"
	_default_support_labels[field] = support_label
	grid.add_child(support_label)
	var editor: Control
	if String(descriptor.get(&"type", &"float")) == "bool":
		var check := CheckButton.new()
		check.name = "DefaultEditor_%s" % field
		editor = check
	else:
		var spin := SpinBox.new()
		spin.name = "DefaultEditor_%s" % field
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var minimum = descriptor.get(&"min")
		var maximum = descriptor.get(&"max")
		var step = descriptor.get(&"step")
		if minimum != null:
			spin.min_value = float(minimum)
		if maximum != null:
			spin.max_value = float(maximum)
		if step != null:
			spin.step = float(step)
		editor = spin
	_default_editors[field] = editor
	grid.add_child(editor)
	var write_button := Button.new()
	write_button.name = "DefaultWrite_%s" % field
	write_button.text = "写入"
	write_button.pressed.connect(_on_default_write_pressed.bind(field))
	_default_write_buttons[field] = write_button
	grid.add_child(write_button)
	var restore_button := Button.new()
	restore_button.name = "DefaultRestore_%s" % field
	restore_button.text = "恢复"
	restore_button.pressed.connect(_on_default_restore_pressed.bind(field))
	_default_restore_buttons[field] = restore_button
	grid.add_child(restore_button)


func _build_validation_panel(content: VBoxContainer) -> void:
	_validation_panel = VBoxContainer.new()
	_validation_panel.name = "ValidationPanel"
	_validation_panel.custom_minimum_size = Vector2(0, 120)
	content.add_child(_validation_panel)
	var heading := Label.new()
	heading.text = "Validation 诊断"
	heading.add_theme_font_size_override("font_size", 14)
	_validation_panel.add_child(heading)
	_validation_summary = Label.new()
	_validation_summary.name = "ValidationSummary"
	_validation_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_panel.add_child(_validation_summary)
	_validation_list = ItemList.new()
	_validation_list.name = "ValidationList"
	_validation_list.custom_minimum_size = Vector2(0, 110)
	_validation_list.allow_reselect = true
	_validation_list.item_selected.connect(_on_validation_item_selected)
	_validation_panel.add_child(_validation_list)


func _build_property_panel(content: VBoxContainer) -> void:
	_property_panel = VBoxContainer.new()
	_property_panel.name = "CellPropertyPanel"
	_property_panel.custom_minimum_size = Vector2(0, 190)
	content.add_child(_property_panel)
	var heading := Label.new()
	heading.text = "地格属性"
	heading.add_theme_font_size_override("font_size", 14)
	_property_panel.add_child(heading)
	_property_selection_label = Label.new()
	_property_selection_label.name = "PropertySelectionLabel"
	_property_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_property_panel.add_child(_property_selection_label)

	var grid := GridContainer.new()
	grid.name = "PropertyGrid"
	grid.columns = 7
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_property_panel.add_child(grid)
	for heading_text in ["字段", "默认值", "覆盖值", "最终值", "状态", "编辑值", "操作"]:
		var column_heading := Label.new()
		column_heading.text = heading_text
		column_heading.add_theme_color_override("font_color", Color("aab4c5"))
		grid.add_child(column_heading)

	for field in PROPERTY_FIELDS:
		_add_property_row(grid, field)


func _add_property_row(grid: GridContainer, field: StringName) -> void:
	var descriptor := _property_descriptor(field)
	var field_label := Label.new()
	field_label.name = "PropertyField_%s" % field
	field_label.text = String(descriptor.get(&"label", field))
	field_label.tooltip_text = String(descriptor.get(&"id", String(field).to_lower()))
	grid.add_child(field_label)

	var base_label := Label.new()
	base_label.name = "PropertyBase_%s" % field
	base_label.text = "—"
	_property_base_value_labels[field] = base_label
	grid.add_child(base_label)

	var override_label := Label.new()
	override_label.name = "PropertyOverride_%s" % field
	override_label.text = "—"
	_property_override_value_labels[field] = override_label
	grid.add_child(override_label)

	var value_label := Label.new()
	value_label.name = "PropertyValue_%s" % field
	value_label.text = "—"
	_property_value_labels[field] = value_label
	grid.add_child(value_label)

	var state_label := Label.new()
	state_label.name = "PropertyState_%s" % field
	state_label.text = "继承"
	_property_state_labels[field] = state_label
	grid.add_child(state_label)

	var editor: Control
	var descriptor_type := String(descriptor.get(&"type", &"float"))
	if descriptor_type == "bool":
		var check := CheckButton.new()
		check.name = "PropertyEditor_%s" % field
		check.tooltip_text = "写入覆盖时使用当前勾选状态。"
		editor = check
	else:
		var spin := SpinBox.new()
		spin.name = "PropertyEditor_%s" % field
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var minimum = descriptor.get(&"min")
		var maximum = descriptor.get(&"max")
		var step = descriptor.get(&"step")
		if minimum != null:
			spin.min_value = float(minimum)
		if maximum != null:
			spin.max_value = float(maximum)
		if step != null:
			spin.step = float(step)
		editor = spin
	_property_editors[field] = editor
	grid.add_child(editor)

	var action_box := HBoxContainer.new()
	var write_button := Button.new()
	write_button.name = "PropertyWrite_%s" % field
	write_button.text = "写入覆盖"
	write_button.tooltip_text = "对当前选择的全部地格写入一个字段覆盖。"
	write_button.pressed.connect(_on_property_write_pressed.bind(field))
	action_box.add_child(write_button)
	_property_write_buttons[field] = write_button
	var inherit_button := Button.new()
	inherit_button.name = "PropertyInherit_%s" % field
	inherit_button.text = "恢复继承"
	inherit_button.tooltip_text = "只清除当前字段的覆盖。"
	inherit_button.pressed.connect(_on_property_inherit_pressed.bind(field))
	action_box.add_child(inherit_button)
	_property_inherit_buttons[field] = inherit_button
	grid.add_child(action_box)


func _refresh() -> void:
	_ensure_phase_c_ui()
	_ensure_play_button()
	if not _has_ui_ready():
		return
	_refreshing = true
	if session == null:
		_refresh_property_panel()
		_refresh_debug_panel()
		_refresh_default_property_panel()
	_refresh_validation_panel()
	if session == null:
		_refreshing = false
		return
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
	_refresh_property_panel()
	_refresh_debug_panel()
	_refresh_default_property_panel()
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


func _refresh_property_panel() -> void:
	if not _is_valid_control(_property_panel) or not _is_valid_control(_property_selection_label):
		return
	var cells := session.get_selected_cells() if session != null else []
	if cells.is_empty():
		_property_selection_label.text = "未选择地格"
		_set_property_controls_enabled(false)
		return
	if cells.size() == 1:
		_property_selection_label.text = "选中 1 格 · 坐标 %s" % cells[0]
	else:
		_property_selection_label.text = "选中 %d 格 · 多格编辑" % cells.size()
	_set_property_controls_enabled(true)
	var summary := session.get_selected_property_summary()
	for field in PROPERTY_FIELDS:
		var field_summary: Dictionary = summary.get(field, {})
		var state_label: Label = _property_state_labels.get(field) as Label
		var base_label: Label = _property_base_value_labels.get(field) as Label
		var override_label: Label = _property_override_value_labels.get(field) as Label
		var value_label: Label = _property_value_labels.get(field) as Label
		if state_label != null:
			state_label.text = String(field_summary.get("state", "继承"))
		if base_label != null:
			base_label.text = String(field_summary.get("base_display", "—"))
		if override_label != null:
			override_label.text = String(field_summary.get("override_display", "—"))
		if value_label != null:
			value_label.text = String(field_summary.get("display", "—"))
		var inherit_button: Button = _property_inherit_buttons.get(field) as Button
		if inherit_button != null:
			inherit_button.disabled = String(field_summary.get("state", "继承")) == "继承"
		var editor: Control = _property_editors.get(field) as Control
		if editor != null and not bool(field_summary.get("mixed", false)) and field_summary.has("value"):
			var value = field_summary.get("value")
			if editor is CheckButton:
				(editor as CheckButton).button_pressed = bool(value)
			elif editor is SpinBox and value != null:
				(editor as SpinBox).value = float(value)


func _refresh_debug_panel() -> void:
	if not _is_valid_control(_debug_option) or not _is_valid_control(_debug_legend):
		return
	var has_session := session != null
	_debug_option.disabled = not has_session
	var current_view := TacticalMapEditSession.DebugView.NORMAL
	if has_session:
		current_view = session.get_debug_view()
	for index in range(_debug_option.item_count):
		if _debug_option.get_item_id(index) == current_view:
			_debug_option.select(index)
			break
	_debug_legend.text = session.debug_view_legend(current_view) if has_session else "选择地图作者后可查看规则调试覆盖。"


func _refresh_default_property_panel() -> void:
	if not _is_valid_control(_default_panel) or not _is_valid_control(_default_context_label):
		return
	var context: Dictionary = {}
	if session != null and session.has_method("get_default_property_context"):
		context = session.get_default_property_context()
	var available := bool(context.get(&"available", false))
	if available:
		_default_context_label.text = "当前素材：%s（%s）" % [context.get(&"label", "素材"), context.get(&"source_id", "")]
	else:
		_default_context_label.text = "未选择可编辑的素材默认属性。"
	var values: Dictionary = context.get(&"values", {})
	var supported: Dictionary = context.get(&"supported", {})
	var reasons: Dictionary = context.get(&"reasons", {})
	var descriptors: Dictionary = context.get(&"descriptors", {})
	var editable := bool(context.get(&"editable", false))
	for field in PROPERTY_FIELDS:
		var value_label: Label = _default_value_labels.get(field) as Label
		var support_label: Label = _default_support_labels.get(field) as Label
		var editor: Control = _default_editors.get(field) as Control
		var write_button: Button = _default_write_buttons.get(field) as Button
		var restore_button: Button = _default_restore_buttons.get(field) as Button
		var field_supported := bool(supported.get(field, false))
		var descriptor: Dictionary = descriptors.get(field, _property_descriptor(field))
		_apply_default_editor_descriptor(editor, descriptor)
		if value_label != null:
			value_label.text = _format_value(values.get(field, null)) if field_supported else "—"
		if support_label != null:
			if not available:
				support_label.text = "未选择"
			elif field_supported:
				var allowed := _descriptor_allowed_values(descriptor)
				if allowed.is_empty():
					support_label.text = "可编辑"
					support_label.tooltip_text = ""
				else:
					var allowed_text: Array[String] = []
					for allowed_value in allowed:
						allowed_text.append(_format_value(allowed_value))
					support_label.text = "可编辑（仅 %s）" % "、".join(allowed_text)
					support_label.tooltip_text = "该素材来源限制为：%s" % "、".join(allowed_text)
			else:
				support_label.text = "不支持：%s" % String(reasons.get(field, "素材未提供该字段"))
				support_label.tooltip_text = support_label.text
		if editor != null:
			if editor is SpinBox:
				(editor as SpinBox).editable = editable and field_supported
				if field_supported and values.get(field, null) != null:
					(editor as SpinBox).value = float(values[field])
			elif editor is BaseButton:
				(editor as BaseButton).disabled = not (editable and field_supported)
		if write_button != null:
			write_button.disabled = not (editable and field_supported)
		if restore_button != null:
			restore_button.disabled = not (editable and field_supported)


func _apply_default_editor_descriptor(editor: Control, descriptor: Dictionary) -> void:
	if editor == null or descriptor.is_empty():
		return
	if editor is SpinBox:
		var spin := editor as SpinBox
		var minimum = descriptor.get(&"min", null)
		var maximum = descriptor.get(&"max", null)
		var step = descriptor.get(&"step", null)
		if minimum != null:
			spin.min_value = float(minimum)
		if maximum != null:
			spin.max_value = float(maximum)
		if step != null:
			spin.step = maxf(float(step), 0.0001)
		var allowed := _descriptor_allowed_values(descriptor)
		if not allowed.is_empty():
			var allowed_text: Array[String] = []
			for value in allowed:
				allowed_text.append(_format_value(value))
			spin.tooltip_text = "允许值：%s" % ", ".join(allowed_text)
		else:
			# A reused editor can come from a legacy binary source.  Clear its
			# source-specific hint when a formal descriptor is applied next.
			spin.tooltip_text = ""


func _descriptor_allowed_values(descriptor: Dictionary) -> Array:
	for key in [&"allowed_values", &"choices"]:
		var values = descriptor.get(key, null)
		if values is Array:
			return values
	for key in [&"constraint", &"constraints"]:
		var constraint = descriptor.get(key, null)
		if constraint is Dictionary:
			for value_key in [&"allowed_values", &"values", &"choices"]:
				var values = (constraint as Dictionary).get(value_key, null)
				if values is Array:
					return values
	return []


func _refresh_validation_panel() -> void:
	if not _is_valid_control(_validation_list) or not _is_valid_control(_validation_summary):
		return
	_validation_list.clear()
	if _validation_diagnostics.is_empty():
		_validation_summary.text = "暂无结构化诊断。"
		return
	var error_count := 0
	var warning_count := 0
	for diagnostic in _validation_diagnostics:
		var severity := String(diagnostic.get(&"severity", diagnostic.get(&"level", "warning"))).to_lower()
		var is_error := severity == "error" or severity == "错误"
		if is_error:
			error_count += 1
		else:
			warning_count += 1
		var message := String(diagnostic.get(&"message", diagnostic.get(&"text", "未提供消息")))
		var coordinate = diagnostic.get(&"coordinate", null)
		var suffix := ""
		if coordinate is Vector3i:
			suffix = " · %s" % coordinate
		else:
			suffix = " · 不可定位"
		var index := _validation_list.add_item("[%s] %s%s" % ["错误" if is_error else "警告", message, suffix])
		_validation_list.set_item_metadata(index, diagnostic.duplicate(true))
		_validation_list.set_item_disabled(index, not (coordinate is Vector3i))
	_validation_summary.text = "错误 %d · 警告 %d；点击带坐标条目可定位。" % [error_count, warning_count]


func set_validation_diagnostics(diagnostics: Array) -> void:
	_validation_diagnostics.clear()
	for diagnostic in diagnostics:
		if diagnostic is Dictionary:
			_validation_diagnostics.append((diagnostic as Dictionary).duplicate(true))
	_refresh_validation_panel()


func get_validation_diagnostics() -> Array[Dictionary]:
	return _validation_diagnostics.duplicate(true)


func _set_property_controls_enabled(enabled: bool) -> void:
	for field in PROPERTY_FIELDS:
		var editor: Control = _property_editors.get(field) as Control
		if editor != null:
			if editor is SpinBox:
				(editor as SpinBox).editable = enabled
			elif editor is BaseButton:
				(editor as BaseButton).disabled = not enabled
		var write_button: Button = _property_write_buttons.get(field) as Button
		if write_button != null:
			write_button.disabled = not enabled
		var inherit_button: Button = _property_inherit_buttons.get(field) as Button
		if inherit_button != null:
			inherit_button.disabled = not enabled


func _format_value(value: Variant) -> String:
	if value == null:
		return "—"
	if value is bool:
		return "是" if bool(value) else "否"
	if value is float:
		return "%.2f" % float(value)
	return str(value)


func _property_descriptor(field: StringName) -> Dictionary:
	var descriptors: Array[Dictionary] = []
	if session != null:
		descriptors = session.get_property_descriptors()
	else:
		descriptors = PROPERTY_SERVICE_SCRIPT.new().field_descriptors()
	for descriptor in descriptors:
		var descriptor_id := StringName(String(descriptor.get(&"id", "")).to_upper())
		if descriptor_id == field:
			return descriptor
	return {}


func _on_property_write_pressed(field: StringName) -> void:
	if session == null:
		return
	var editor: Control = _property_editors.get(field) as Control
	if editor == null:
		return
	var value: Variant
	if editor is CheckButton:
		value = (editor as CheckButton).button_pressed
	elif editor is SpinBox:
		value = (editor as SpinBox).value
	else:
		return
	property_override_requested.emit(field, value)


func _on_property_inherit_pressed(field: StringName) -> void:
	if session != null:
		property_inherit_requested.emit(field)


func _on_debug_view_selected(index: int) -> void:
	if _refreshing or not _is_valid_control(_debug_option):
		return
	debug_view_changed.emit(_debug_option.get_item_id(index))


func _on_validation_item_selected(index: int) -> void:
	if not _is_valid_control(_validation_list) or index < 0 or index >= _validation_list.item_count:
		return
	if _validation_list.is_item_disabled(index):
		_set_status("该诊断没有结构化坐标，无法定位。", false)
		return
	var diagnostic = _validation_list.get_item_metadata(index)
	if diagnostic is Dictionary and (diagnostic as Dictionary).get(&"coordinate", null) is Vector3i:
		validation_location_requested.emit((diagnostic as Dictionary).duplicate(true))
		return
	_set_status("该诊断没有结构化坐标，无法定位。", false)


func _on_default_write_pressed(field: StringName) -> void:
	if session == null:
		return
	var editor: Control = _default_editors.get(field) as Control
	if editor == null:
		return
	var value: Variant
	if editor is CheckButton:
		value = (editor as CheckButton).button_pressed
	elif editor is SpinBox:
		value = (editor as SpinBox).value
	else:
		return
	var context := session.get_default_property_context() if session.has_method("get_default_property_context") else {}
	var descriptor: Dictionary = context.get(&"descriptors", {}).get(field, _property_descriptor(field))
	var allowed := _descriptor_allowed_values(descriptor)
	if editor is SpinBox and not allowed.is_empty():
		var selected_value := float(value)
		var best_value := float(allowed[0])
		var best_distance := absf(selected_value - best_value)
		for allowed_value in allowed:
			var candidate := float(allowed_value)
			var distance := absf(selected_value - candidate)
			if distance < best_distance:
				best_distance = distance
				best_value = candidate
		(editor as SpinBox).value = best_value
		value = best_value
	default_property_override_requested.emit(field, value)


func _on_default_restore_pressed(field: StringName) -> void:
	if session != null:
		default_property_restore_requested.emit(field)


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
	return _has_base_ui_ready() \
		and _is_valid_control(_scroll) \
		and _is_valid_control(_play_button) \
		and _is_valid_control(_debug_option) \
		and _is_valid_control(_debug_legend) \
		and _is_valid_control(_default_panel) \
		and _is_valid_control(_default_context_label) \
		and _is_valid_control(_validation_list) \
		and _is_valid_control(_validation_summary)


func _ensure_phase_c_ui() -> bool:
	if not _ensure_scroll_container():
		return false
	if not _ensure_tool_option():
		return false
	_ensure_select_tool_item()
	var property_ready := _ensure_property_panel()
	var debug_ready := _ensure_debug_panel()
	var default_ready := _ensure_default_property_panel()
	var validation_ready := _ensure_validation_panel()
	return property_ready and debug_ready and default_ready and validation_ready


func _ensure_scroll_container() -> bool:
	if not _is_valid_control(_content):
		var existing_content := find_child("TacticalMapDockContent", true, false)
		if existing_content is VBoxContainer:
			_content = existing_content as VBoxContainer
	if not _is_valid_control(_scroll):
		var existing_scroll := find_child("TacticalMapDockScroll", true, false)
		if existing_scroll is ScrollContainer:
			_scroll = existing_scroll as ScrollContainer
	if _is_valid_control(_scroll) and _is_valid_control(_content):
		if _content.get_parent() != _scroll:
			var old_parent := _content.get_parent()
			if old_parent != null:
				old_parent.remove_child(_content)
			_scroll.add_child(_content)
		return true
	if not _is_valid_control(_content):
		return false
	var content_parent := _content.get_parent()
	if content_parent == null:
		return false
	_scroll = ScrollContainer.new()
	_scroll.name = "TacticalMapDockScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_parent.remove_child(_content)
	content_parent.add_child(_scroll)
	_scroll.add_child(_content)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return true


func _ensure_debug_panel() -> bool:
	if not _is_valid_control(_debug_panel):
		var existing := find_child("DebugViewPanel", true, false)
		if existing is VBoxContainer:
			_debug_panel = existing as VBoxContainer
	if not _is_valid_control(_debug_panel):
		var parent := _content if _is_valid_control(_content) else self
		if parent is VBoxContainer:
			_build_debug_panel(parent as VBoxContainer)
	if not _is_valid_control(_debug_panel):
		return false
	if not _is_valid_control(_debug_option):
		var option := _debug_panel.find_child("DebugViewOption", true, false)
		if option is OptionButton:
			_debug_option = option as OptionButton
	if not _is_valid_control(_debug_legend):
		var legend := _debug_panel.find_child("DebugLegend", true, false)
		if legend is Label:
			_debug_legend = legend as Label
	if not _is_valid_control(_debug_option) or not _is_valid_control(_debug_legend):
		return false
	_add_debug_view_items(_debug_option)
	if not _debug_option.item_selected.is_connected(_on_debug_view_selected):
		_debug_option.item_selected.connect(_on_debug_view_selected)
	return true


func _ensure_default_property_panel() -> bool:
	if not _is_valid_control(_default_panel):
		var existing := find_child("DefaultPropertyPanel", true, false)
		if existing is VBoxContainer:
			_default_panel = existing as VBoxContainer
	if not _is_valid_control(_default_panel):
		var parent := _content if _is_valid_control(_content) else self
		if parent is VBoxContainer:
			_build_default_property_panel(parent as VBoxContainer)
	if not _is_valid_control(_default_panel):
		return false
	if not _is_valid_control(_default_context_label):
		var context_label := _default_panel.find_child("DefaultPropertyContext", true, false)
		if context_label is Label:
			_default_context_label = context_label as Label
	var complete := _is_valid_control(_default_context_label)
	for field in PROPERTY_FIELDS:
		if _default_panel.find_child("DefaultEditor_%s" % field, true, false) == null \
			or _default_panel.find_child("DefaultWrite_%s" % field, true, false) == null \
			or _default_panel.find_child("DefaultRestore_%s" % field, true, false) == null:
			complete = false
			break
	if not complete:
		var parent := _default_panel.get_parent()
		if parent != null:
			parent.remove_child(_default_panel)
		_default_panel.free()
		_default_panel = null
		_default_context_label = null
		_default_scope_label = null
		_default_value_labels.clear()
		_default_support_labels.clear()
		_default_editors.clear()
		_default_write_buttons.clear()
		_default_restore_buttons.clear()
		if parent is VBoxContainer:
			_build_default_property_panel(parent as VBoxContainer)
			return _is_valid_control(_default_panel)
	_default_value_labels.clear()
	_default_support_labels.clear()
	_default_editors.clear()
	_default_write_buttons.clear()
	_default_restore_buttons.clear()
	for field in PROPERTY_FIELDS:
		_default_value_labels[field] = _default_panel.find_child("DefaultValue_%s" % field, true, false)
		_default_support_labels[field] = _default_panel.find_child("DefaultSupport_%s" % field, true, false)
		_default_editors[field] = _default_panel.find_child("DefaultEditor_%s" % field, true, false)
		_default_write_buttons[field] = _default_panel.find_child("DefaultWrite_%s" % field, true, false)
		_default_restore_buttons[field] = _default_panel.find_child("DefaultRestore_%s" % field, true, false)
	return true


func _ensure_validation_panel() -> bool:
	if not _is_valid_control(_validation_panel):
		var existing := find_child("ValidationPanel", true, false)
		if existing is VBoxContainer:
			_validation_panel = existing as VBoxContainer
	if not _is_valid_control(_validation_panel):
		var parent := _content if _is_valid_control(_content) else self
		if parent is VBoxContainer:
			_build_validation_panel(parent as VBoxContainer)
	if not _is_valid_control(_validation_panel):
		return false
	if not _is_valid_control(_validation_summary):
		var summary := _validation_panel.find_child("ValidationSummary", true, false)
		if summary is Label:
			_validation_summary = summary as Label
	if not _is_valid_control(_validation_list):
		var list := _validation_panel.find_child("ValidationList", true, false)
		if list is ItemList:
			_validation_list = list as ItemList
	if not _is_valid_control(_validation_summary) or not _is_valid_control(_validation_list):
		return false
	if not _validation_list.item_selected.is_connected(_on_validation_item_selected):
		_validation_list.item_selected.connect(_on_validation_item_selected)
	return true


func _ensure_tool_option() -> bool:
	if not _is_valid_control(_tool_option):
		var named := find_child("ToolOption", true, false)
		if named is OptionButton:
			_tool_option = named as OptionButton
	if not _is_valid_control(_tool_option):
		_tool_option = _find_tool_option(self)
	return _is_valid_control(_tool_option)


func _find_tool_option(root: Node) -> OptionButton:
	for child in root.get_children():
		if child is OptionButton and _looks_like_tool_option(child as OptionButton):
			return child as OptionButton
		var nested := _find_tool_option(child)
		if nested != null:
			return nested
	return null


func _looks_like_tool_option(option: OptionButton) -> bool:
	var has_paint := false
	var has_erase := false
	var has_rotate := false
	for index in range(option.item_count):
		var text := option.get_item_text(index).to_lower()
		has_paint = has_paint or text == "paint"
		has_erase = has_erase or text == "erase"
		has_rotate = has_rotate or text == "rotate"
	return has_paint and has_erase and has_rotate


func _ensure_select_tool_item() -> void:
	if not _is_valid_control(_tool_option):
		return
	for index in range(_tool_option.item_count):
		if _tool_option.get_item_id(index) == TacticalMapEditSession.Tool.SELECT:
			return
	_tool_option.add_item("Select", TacticalMapEditSession.Tool.SELECT)


func _ensure_property_panel() -> bool:
	if not _is_valid_control(_property_panel):
		var existing := find_child("CellPropertyPanel", true, false)
		if existing is VBoxContainer:
			_property_panel = existing as VBoxContainer
		else:
			var parent := _content if _is_valid_control(_content) else self
			_build_property_panel(parent as VBoxContainer)
	if not _is_valid_control(_property_panel):
		return false
	if not _is_valid_control(_property_selection_label):
		var selection_label := _property_panel.find_child("PropertySelectionLabel", true, false)
		if selection_label is Label:
			_property_selection_label = selection_label as Label
	if not _is_valid_control(_property_selection_label):
		_property_selection_label = Label.new()
		_property_selection_label.name = "PropertySelectionLabel"
		_property_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_property_panel.add_child(_property_selection_label)

	var grid := _property_panel.find_child("PropertyGrid", true, false) as GridContainer
	if grid == null:
		grid = GridContainer.new()
		grid.name = "PropertyGrid"
		grid.columns = 7
		_property_panel.add_child(grid)
		for heading_text in ["字段", "默认值", "覆盖值", "最终值", "状态", "编辑值", "操作"]:
			var column_heading := Label.new()
			column_heading.text = heading_text
			column_heading.add_theme_color_override("font_color", Color("aab4c5"))
			grid.add_child(column_heading)

	_property_state_labels.clear()
	_property_base_value_labels.clear()
	_property_override_value_labels.clear()
	_property_value_labels.clear()
	_property_editors.clear()
	_property_write_buttons.clear()
	_property_inherit_buttons.clear()
	for field in PROPERTY_FIELDS:
		var control_names := [
			"PropertyField_%s" % field,
			"PropertyBase_%s" % field,
			"PropertyOverride_%s" % field,
			"PropertyValue_%s" % field,
			"PropertyState_%s" % field,
			"PropertyEditor_%s" % field,
			"PropertyWrite_%s" % field,
			"PropertyInherit_%s" % field,
		]
		var complete := true
		for control_name in control_names:
			if _property_panel.find_child(control_name, true, false) == null:
				complete = false
				break
		if not complete:
			for control_name in control_names:
				_remove_property_control(control_name)
			_add_property_row(grid, field)
			continue
		_property_state_labels[field] = _property_panel.find_child(control_names[4], true, false)
		_property_base_value_labels[field] = _property_panel.find_child(control_names[1], true, false)
		_property_override_value_labels[field] = _property_panel.find_child(control_names[2], true, false)
		_property_value_labels[field] = _property_panel.find_child(control_names[3], true, false)
		_property_editors[field] = _property_panel.find_child(control_names[5], true, false)
		_property_write_buttons[field] = _property_panel.find_child(control_names[6], true, false)
		_property_inherit_buttons[field] = _property_panel.find_child(control_names[7], true, false)
	return true


func _remove_property_control(control_name: String) -> void:
	if not _is_valid_control(_property_panel):
		return
	var control := _property_panel.find_child(control_name, true, false)
	if control == null:
		return
	var parent := control.get_parent()
	if parent != null:
		parent.remove_child(control)
		control.free()
		if parent is HBoxContainer and parent.get_child_count() == 0:
			var row_parent := parent.get_parent()
			if row_parent != null:
				row_parent.remove_child(parent)
			parent.free()


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
	var parent := _content if _is_valid_control(_content) else self
	parent.add_child(run_row)
	return true
