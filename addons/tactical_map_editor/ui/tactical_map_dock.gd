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
signal selection_replace_requested
signal selection_rotate_requested
signal selection_delete_requested
signal selection_copy_requested
signal selection_paste_requested
signal placeable_selected(index: int)
signal validate_requested
signal bake_requested
signal save_requested
signal play_requested
signal add_placeable_requested
signal new_map_requested
signal special_edit_finish_requested
signal debug_view_changed(view: int)
signal validation_location_requested(diagnostic: Dictionary)

## TargetLayer is an ordered public contract shared with the Session.  Keep
## the numeric IDs local here as well so this Dock can load safely while an
## older hot-reloaded Session still exposes only the original four layers.
const TARGET_LAYER_OPTIONS: Array[Dictionary] = [
	{&"id": 0, &"label": "Floor"},
	{&"id": 1, &"label": "Structure"},
	{&"id": 2, &"label": "Decoration"},
	{&"id": 3, &"label": "Traversal"},
	{&"id": 4, &"label": "Spawner"},
	{&"id": 5, &"label": "Object"},
	{&"id": 6, &"label": "AI"},
]

var session: TacticalMapEditSession
var _title: Label
var _selection_label: Label
var _new_map_button: Button
var _edit_toggle: CheckButton
var _floor_spin: SpinBox
var _target_option: OptionButton
var _tool_option: OptionButton
var _rotate_button: Button
var _selection_actions_panel: VBoxContainer
var _selection_count_label: Label
var _selection_replace_button: Button
var _selection_rotate_button: Button
var _selection_delete_button: Button
var _selection_copy_button: Button
var _selection_paste_button: Button
var _search: LineEdit
var _palette: ItemList
var _add_placeable_button: Button
var _special_panel: VBoxContainer
var _special_state_label: Label
var _special_finish_button: Button
var _spawn_panel: VBoxContainer
var _spawn_context_label: Label
var _spawn_archetype_picker: Control
var _spawn_weapon_picker: Control
var _spawn_encounter_edit: LineEdit
var _spawn_patrol_edit: LineEdit
var _spawn_apply_button: Button
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
var _refreshing := false
var _map_locked := false

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

func set_map_locked(locked: bool) -> void:
	_map_locked = locked
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
	# Let the editor decide the Dock width.  The content stacks vertically and
	# the ScrollContainer below is deliberately horizontal-scroll free.
	custom_minimum_size = Vector2(0, 360)
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
	# The editor Dock is often only a few hundred pixels wide.  Horizontal
	# scrolling would hide the primary controls, so all rows below are allowed
	# to wrap/stack vertically instead.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	_selection_label.name = "SelectionLabel"
	_selection_label.text = "请在场景树中选择地图根节点后开启编辑。"
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_selection_label)

	_new_map_button = Button.new()
	_new_map_button.name = "NewMapButton"
	_new_map_button.text = "新建地图"
	_new_map_button.tooltip_text = "创建一个新的 TacticalMapAuthor 场景与地图资源；不会默认覆盖已有文件。"
	_new_map_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_map_button.pressed.connect(_emit_new_map_requested)
	content.add_child(_new_map_button)

	_edit_toggle = CheckButton.new()
	_edit_toggle.name = "EditModeToggle"
	_edit_toggle.text = "地图编辑模式（M）"
	_edit_toggle.tooltip_text = "M 只在 3D 视口中快速切换地图编辑模式；关闭编辑模式后仍可执行 Validate / Bake / Save Scene / Bake & Play，并保留 Godot 原生选择和相机操作。"
	_edit_toggle.toggled.connect(func(value: bool) -> void: edit_mode_changed.emit(value))
	content.add_child(_edit_toggle)
	var navigation_hint := Label.new()
	navigation_hint.name = "NavigationHint"
	navigation_hint.text = "视口导航：普通 RMB 为 Godot 原生自由观察；按住 RMB + WASD 飞行；MMB 原生环绕/平移（按 Godot 设置）。擦除：擦除工具 + 左键，或 Ctrl + 左键临时擦除；Box Paint 按住 Ctrl 拖选为擦除。"
	navigation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	navigation_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navigation_hint.add_theme_color_override("font_color", Color("aab4c5"))
	content.add_child(navigation_hint)

	var level_row := VBoxContainer.new()
	level_row.name = "LevelControls"
	content.add_child(level_row)
	var level_label := Label.new()
	level_label.text = "楼层"
	level_row.add_child(level_label)
	_floor_spin = SpinBox.new()
	_floor_spin.min_value = 0
	_floor_spin.max_value = 0
	_floor_spin.step = 1
	_floor_spin.tooltip_text = "当前鼠标编辑平面。坐标按 Vector3i(x, level, z) 处理。"
	_floor_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_floor_spin.value_changed.connect(func(value: float) -> void: floor_changed.emit(int(value)))
	level_row.add_child(_floor_spin)
	var target_row := VBoxContainer.new()
	target_row.name = "TargetLayerControls"
	content.add_child(target_row)
	var target_label := Label.new()
	target_label.text = "目标层"
	target_row.add_child(target_label)
	_target_option = OptionButton.new()
	_target_option.name = "TargetLayerOption"
	for layer_option in TARGET_LAYER_OPTIONS:
		_target_option.add_item(String(layer_option[&"label"]), int(layer_option[&"id"]))
	_target_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_option.item_selected.connect(_on_target_layer_selected)
	target_row.add_child(_target_option)

	var tool_row := VBoxContainer.new()
	tool_row.name = "ToolControls"
	content.add_child(tool_row)
	var tool_label := Label.new()
	tool_label.text = "工具"
	tool_row.add_child(tool_label)
	_tool_option = OptionButton.new()
	_tool_option.name = "ToolOption"
	_tool_option.add_item("Paint", TacticalMapEditSession.Tool.PAINT)
	_tool_option.add_item("Erase", TacticalMapEditSession.Tool.ERASE)
	_tool_option.add_item("Pick", TacticalMapEditSession.Tool.PICK)
	_tool_option.add_item("Select", TacticalMapEditSession.Tool.SELECT)
	_tool_option.add_item("Box Paint", TacticalMapEditSession.Tool.BOX_PAINT)
	_tool_option.set_item_tooltip(_tool_option.item_count - 1, "按住左键拖出矩形，松开后批量绘制 Cell 地格；按住 Ctrl 拖选时改为批量擦除。")
	_tool_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_option.item_selected.connect(func(index: int) -> void:
		tool_changed.emit(int(_tool_option.get_item_id(index)))
	)
	tool_row.add_child(_tool_option)
	_rotate_button = Button.new()
	_rotate_button.text = "R 旋转"
	_rotate_button.tooltip_text = "非 Select 模式旋转当前素材 90°；Select 模式请使用“选择操作”中的批量旋转。"
	_rotate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rotate_button.pressed.connect(func() -> void: rotate_requested.emit())
	tool_row.add_child(_rotate_button)

	_search = LineEdit.new()
	_search.name = "PlaceableSearch"
	_search.placeholder_text = "搜索素材 / 分类 / 稳定 ID"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _refresh_palette())
	content.add_child(_search)

	var palette_heading := HBoxContainer.new()
	palette_heading.name = "PaletteHeading"
	content.add_child(palette_heading)
	var palette_label := Label.new()
	palette_label.text = "素材栏"
	palette_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_heading.add_child(palette_label)
	_add_placeable_button = Button.new()
	_add_placeable_button.name = "AddPlaceableButton"
	_add_placeable_button.text = "添加素材"
	_add_placeable_button.tooltip_text = "从资源文件导入一个已有的 Cell 或 Object Definition。"
	_add_placeable_button.pressed.connect(func() -> void: add_placeable_requested.emit())
	palette_heading.add_child(_add_placeable_button)
	_palette = ItemList.new()
	_palette.name = "Palette"
	_palette.select_mode = ItemList.SELECT_SINGLE
	_palette.custom_minimum_size = Vector2(0, 190)
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.item_selected.connect(_on_palette_item_selected)
	content.add_child(_palette)
	_build_selection_actions_panel(content)
	_build_special_panel(content)
	_build_spawn_panel(content)

	_build_debug_panel(content)
	_build_validation_panel(content)

	var action_row := VBoxContainer.new()
	action_row.name = "MapActions"
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

	var run_row := VBoxContainer.new()
	run_row.name = "RunActions"
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
	_remove_legacy_property_panels()
	_refresh()

func _remove_legacy_property_panels() -> void:
	for panel_name in ["CellPropertyPanel", "DefaultPropertyPanel"]:
		var legacy := find_child(panel_name, true, false)
		if legacy != null:
			var parent := legacy.get_parent()
			if parent != null:
				parent.remove_child(legacy)
			legacy.queue_free()
	if _is_valid_control(_content):
		for child in _content.get_children():
			if child.name in ["CellPropertyPanel", "DefaultPropertyPanel"]:
				_content.remove_child(child)
				child.queue_free()

func _build_special_panel(content: VBoxContainer) -> void:
	_special_panel = VBoxContainer.new()
	_special_panel.name = "SpecialEditPanel"
	_special_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_special_panel)
	var heading := Label.new()
	heading.text = "特殊编辑状态"
	heading.add_theme_font_size_override("font_size", 14)
	_special_panel.add_child(heading)
	_special_state_label = Label.new()
	_special_state_label.name = "SpecialEditStateLabel"
	_special_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_special_panel.add_child(_special_state_label)
	_special_finish_button = Button.new()
	_special_finish_button.name = "FinishSpecialEditButton"
	_special_finish_button.text = "结束特殊编辑"
	_special_finish_button.tooltip_text = "结束等待终点的连接或当前巡逻路线，并交给 Session 生成一次 Undo。"
	_special_finish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_special_finish_button.pressed.connect(func() -> void: special_edit_finish_requested.emit())
	_special_panel.add_child(_special_finish_button)

func _build_spawn_panel(content: VBoxContainer) -> void:
	_spawn_panel = VBoxContainer.new()
	_spawn_panel.name = "SpawnConfigurationPanel"
	_spawn_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spawn_panel.visible = false
	content.add_child(_spawn_panel)
	var heading := Label.new()
	heading.text = "出生点模板配置"
	heading.add_theme_font_size_override("font_size", 14)
	_spawn_panel.add_child(heading)
	_spawn_context_label = Label.new()
	_spawn_context_label.name = "SpawnConfigurationContext"
	_spawn_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spawn_panel.add_child(_spawn_context_label)
	_spawn_archetype_picker = _make_spawn_resource_control("SpawnArchetypePicker", "UnitArchetype")
	_add_spawn_labeled_control("UnitArchetype", _spawn_archetype_picker)
	_spawn_weapon_picker = _make_spawn_resource_control("SpawnWeaponPicker", "WeaponDefinition")
	_add_spawn_labeled_control("WeaponDefinition", _spawn_weapon_picker)
	_spawn_encounter_edit = LineEdit.new()
	_spawn_encounter_edit.name = "SpawnEncounterIdEdit"
	_spawn_encounter_edit.placeholder_text = "可选 encounter_id"
	_add_spawn_labeled_control("encounter_id", _spawn_encounter_edit)
	_spawn_patrol_edit = LineEdit.new()
	_spawn_patrol_edit.name = "SpawnPatrolRouteIdEdit"
	_spawn_patrol_edit.placeholder_text = "可选 patrol_route_id"
	_add_spawn_labeled_control("patrol_route_id", _spawn_patrol_edit)
	var hint := Label.new()
	hint.name = "SpawnConfigurationHint"
	hint.text = "只配置出生模板；玩法规则仍由 UnitArchetype / WeaponDefinition 与 Session 负责。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("aab4c5"))
	_spawn_panel.add_child(hint)
	_spawn_apply_button = Button.new()
	_spawn_apply_button.name = "ApplySpawnConfigurationButton"
	_spawn_apply_button.text = "应用出生点模板"
	_spawn_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spawn_apply_button.pressed.connect(_on_spawn_configuration_apply)
	_spawn_panel.add_child(_spawn_apply_button)

func _make_spawn_resource_control(control_name: String, resource_type: String) -> Control:
	var control: Control
	if Engine.is_editor_hint():
		var picker := EditorResourcePicker.new()
		picker.name = control_name
		picker.set("base_type", resource_type)
		picker.tooltip_text = "选择 %s 资源。" % resource_type
		if picker.has_signal("resource_changed"):
			picker.connect("resource_changed", _on_spawn_resource_changed.bind(control_name))
		control = picker
	else:
		var fallback := LineEdit.new()
		fallback.name = control_name
		fallback.editable = false
		fallback.placeholder_text = "编辑器资源选择器仅在 Godot 编辑器中可用"
		control = fallback
	return control

func _add_spawn_labeled_control(label_text: String, control: Control) -> void:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	_spawn_panel.add_child(row)

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
		["Cover / 掩体", TacticalMapEditSession.DebugView.COVER],
	]
	for item in items:
		var found := false
		for index in range(option.item_count):
			if option.get_item_id(index) == int(item[1]):
				found = true
				break
		if not found:
			option.add_item(String(item[0]), int(item[1]))

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

func _captioned_value(caption: String, value: Control) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = caption
	label.add_theme_color_override("font_color", Color("aab4c5"))
	box.add_child(label)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(value)
	return box

func _captioned_control(caption: String, control: Control) -> Control:
	return _captioned_value(caption, control)

func _refresh() -> void:
	_ensure_phase_c_ui()
	_ensure_play_button()
	if not _has_ui_ready():
		return
	_refreshing = true
	if session == null:
		_refresh_debug_panel()
		_refresh_special_edit_panel()
		_refresh_spawn_configuration_panel()
	_refresh_validation_panel()
	_refresh_selection_actions()
	if session == null:
		_rotate_button.visible = false
		_refreshing = false
		return
	var has_author := session.has_author()
	if has_author and _map_locked and session.edit_mode:
		_selection_label.text = "地图已锁定，已隐藏根节点选择框：%s" % session.author.name
	else:
		_selection_label.text = "作者：%s" % session.author.name if has_author else "请在场景树中选择地图根节点后开启编辑。"
	_edit_toggle.disabled = not has_author
	_edit_toggle.button_pressed = session.edit_mode and has_author
	_edit_toggle.tooltip_text = "地图已锁定，已隐藏根节点选择框；可选择地图内子节点查看，但不会改变编辑层。" if _map_locked and has_author and session.edit_mode else "M 只在 3D 视口中快速切换地图编辑模式；关闭编辑模式后仍可执行 Validate / Bake / Save Scene / Bake & Play，并保留 Godot 原生选择和相机操作。"
	_floor_spin.mouse_filter = Control.MOUSE_FILTER_STOP if has_author else Control.MOUSE_FILTER_IGNORE
	var floor_line_edit := _floor_spin.get_line_edit()
	if floor_line_edit != null:
		floor_line_edit.editable = has_author
	_floor_spin.max_value = maxi(session.level_count() - 1, 0)
	_floor_spin.value = session.floor_level
	_target_option.disabled = not has_author
	_tool_option.disabled = not has_author
	_rotate_button.disabled = not has_author
	_rotate_button.visible = has_author and session.tool != TacticalMapEditSession.Tool.SELECT
	_validate_button.disabled = not has_author
	_bake_button.disabled = not has_author
	_save_button.disabled = not has_author
	_play_button.disabled = not has_author
	if _is_valid_control(_add_placeable_button):
		_add_placeable_button.disabled = not has_author
	var target_layer_id := _target_layer_ui_id(int(session.target_layer))
	for target_index in range(_target_option.item_count):
		if _target_option.get_item_id(target_index) == target_layer_id:
			_target_option.select(target_index)
			break
	for tool_index in range(_tool_option.item_count):
		if _tool_option.get_item_id(tool_index) == session.tool:
			_tool_option.select(tool_index)
			break
	_refresh_palette()
	_refresh_selection_actions()
	_refresh_debug_panel()
	_refresh_special_edit_panel()
	_refresh_spawn_configuration_panel()
	var status := session.get_last_status()
	_set_status(String(status.get("message", "")), bool(status.get("valid", true)))
	_refreshing = false

func _refresh_palette() -> void:
	if not _is_valid_control(_palette):
		return
	_palette.clear()
	if session == null:
		return
	var entries := _get_palette_entries(_search.text if _search != null else "")
	var selected_id := String(session.get_selected_placeable().get("id", ""))
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var label := String(entry.get("label", entry.get("id", "素材")))
		_palette.add_item(label)
		_palette.set_item_tooltip(_palette.item_count - 1, "%s · %s" % [entry.get("category", ""), entry.get("id", "")])
		_palette.set_item_metadata(_palette.item_count - 1, entry.get("id", ""))
		if String(entry.get("id", "")) == selected_id:
			_palette.select(_palette.item_count - 1)


func _build_selection_actions_panel(content: VBoxContainer) -> void:
	_selection_actions_panel = VBoxContainer.new()
	_selection_actions_panel.name = "SelectionActionsPanel"
	_selection_actions_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_selection_actions_panel)
	var heading := Label.new()
	heading.text = "选择操作"
	heading.add_theme_font_size_override("font_size", 14)
	_selection_actions_panel.add_child(heading)
	_selection_count_label = Label.new()
	_selection_count_label.name = "SelectionCountLabel"
	_selection_count_label.text = "已选地格：0"
	_selection_actions_panel.add_child(_selection_count_label)
	var hint := Label.new()
	hint.name = "SelectionActionsHint"
	hint.text = "拖拽框选；拖拽已选地格移动；Shift 追加/切换。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("aab4c5"))
	_selection_actions_panel.add_child(hint)
	var edit_grid := GridContainer.new()
	edit_grid.name = "SelectionEditButtons"
	edit_grid.columns = 3
	edit_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_actions_panel.add_child(edit_grid)
	_selection_replace_button = Button.new()
	_selection_replace_button.name = "SelectionReplaceButton"
	_selection_replace_button.text = "替换"
	_selection_replace_button.tooltip_text = "使用素材栏当前素材替换所有选中地格。"
	_selection_replace_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_replace_button.pressed.connect(_emit_selection_replace_requested)
	edit_grid.add_child(_selection_replace_button)
	_selection_rotate_button = Button.new()
	_selection_rotate_button.name = "SelectionRotateButton"
	_selection_rotate_button.text = "旋转"
	_selection_rotate_button.tooltip_text = "将当前目标层中所有选中内容旋转 90°。"
	_selection_rotate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_rotate_button.pressed.connect(_emit_selection_rotate_requested)
	edit_grid.add_child(_selection_rotate_button)
	_selection_delete_button = Button.new()
	_selection_delete_button.name = "SelectionDeleteButton"
	_selection_delete_button.text = "删除"
	_selection_delete_button.tooltip_text = "删除当前目标层中所有选中内容。"
	_selection_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_delete_button.pressed.connect(_emit_selection_delete_requested)
	edit_grid.add_child(_selection_delete_button)
	var clipboard_row := HBoxContainer.new()
	clipboard_row.name = "SelectionClipboardButtons"
	clipboard_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_actions_panel.add_child(clipboard_row)
	_selection_copy_button = Button.new()
	_selection_copy_button.name = "SelectionCopyButton"
	_selection_copy_button.text = "复制"
	_selection_copy_button.tooltip_text = "复制当前目标层的选中内容。"
	_selection_copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_copy_button.pressed.connect(_emit_selection_copy_requested)
	clipboard_row.add_child(_selection_copy_button)
	_selection_paste_button = Button.new()
	_selection_paste_button.name = "SelectionPasteButton"
	_selection_paste_button.text = "粘贴"
	_selection_paste_button.tooltip_text = "以第一个选中地格为起点粘贴剪贴板内容。"
	_selection_paste_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_paste_button.pressed.connect(_emit_selection_paste_requested)
	clipboard_row.add_child(_selection_paste_button)

func _refresh_selection_actions() -> void:
	if not _is_valid_control(_selection_actions_panel):
		return
	var has_author := session != null and session.has_author()
	var selected_count := session.selected_cell_count() if has_author else 0
	var selection_tool_active := has_author and session.edit_mode and session.tool == TacticalMapEditSession.Tool.SELECT
	_selection_actions_panel.visible = selection_tool_active
	var has_selection := selection_tool_active and selected_count > 0
	_selection_count_label.text = "已选地格：%d" % selected_count
	var action_enabled := has_selection
	_selection_replace_button.disabled = not action_enabled
	_selection_rotate_button.disabled = not action_enabled
	_selection_delete_button.disabled = not action_enabled
	_selection_copy_button.disabled = not action_enabled
	_selection_paste_button.disabled = not action_enabled or not session.has_selection_clipboard()

func _get_palette_entries(query: String = "") -> Array:
	if session == null:
		return []
	var layer := int(session.target_layer)
	if _get_placeables_accepts_layer_filter():
		var filtered_value = session.call("get_placeables", query, layer)
		if filtered_value is Array:
			return filtered_value
		return []
	var all_value = session.call("get_placeables", query)
	if not all_value is Array:
		return []
	var filtered: Array = []
	for entry in all_value:
		if entry is Dictionary and _entry_layer(entry as Dictionary) == layer:
			filtered.append(entry)
	return filtered

func _get_all_placeable_entries() -> Array:
	if session == null:
		return []
	if _get_placeables_accepts_layer_filter():
		var all_value = session.call("get_placeables", "", -1)
		return all_value if all_value is Array else []
	var legacy_value = session.call("get_placeables", "")
	return legacy_value if legacy_value is Array else []

func _get_placeables_accepts_layer_filter() -> bool:
	if session == null:
		return false
	for method_info in session.get_method_list():
		if String(method_info.get("name", "")) != "get_placeables":
			continue
		var arguments = method_info.get("args", [])
		return arguments is Array and arguments.size() >= 2
	return false

func _entry_layer(entry: Dictionary) -> int:
	return int(entry.get(&"layer", entry.get(&"target_layer", -1)))

func _target_layer_ui_id(session_layer: int) -> int:
	if session != null and session.has_method("target_layer_name"):
		var semantic_name := String(session.call("target_layer_name", session_layer)).strip_edges().to_lower()
		for layer_option in TARGET_LAYER_OPTIONS:
			if String(layer_option[&"label"]).to_lower() == semantic_name:
				return int(layer_option[&"id"])
	return session_layer

func _refresh_special_edit_panel() -> void:
	if not _is_valid_control(_special_panel) or not _is_valid_control(_special_state_label) or not _is_valid_control(_special_finish_button):
		return
	if session == null or not session.has_method("get_special_edit_state"):
		_special_state_label.text = "当前 Session 未提供特殊编辑状态接口。"
		_special_finish_button.disabled = true
		return
	var state_value = session.call("get_special_edit_state")
	var state: Dictionary = state_value if state_value is Dictionary else {}
	# The current Session contract is kind/pending/active/active_route_id/
	# pending_from/can_finish/label. Keep the older names as a fallback for
	# hot-reloaded Sessions, but do not let stale legacy values override an
	# explicitly supplied formal key (including an explicit false/empty value).
	var has_formal_kind := state.has(&"kind")
	var kind := String(state.get(&"kind", "") if has_formal_kind else state.get(&"mode", state.get(&"active_mode", ""))).to_lower()
	var has_formal_pending := state.has(&"pending")
	var has_formal_active := state.has(&"active")
	var has_traversal := bool(state.get(&"pending", false) if has_formal_pending else state.get(&"traversal_pending", state.get(&"pending_traversal", false)))
	var traversal_from = state.get(&"pending_from", state.get(&"traversal_from", state.get(&"pending_traversal_from", null))) if state.has(&"pending_from") else state.get(&"traversal_from", state.get(&"pending_traversal_from", null))
	if traversal_from is Vector3i and traversal_from != Vector3i(-1, -1, -1):
		# A legacy state has no formal pending key, so a valid pending_from is
		# enough to infer the old pending state. Formal pending remains the
		# authority when present.
		if not has_formal_pending:
			has_traversal = true
	var route_id := String(state.get(&"active_route_id", state.get(&"patrol_route_id", state.get(&"active_patrol_route_id", ""))) if state.has(&"active_route_id") else state.get(&"patrol_route_id", state.get(&"active_patrol_route_id", "")))
	var has_patrol := bool(state.get(&"active", false) if has_formal_active else state.get(&"patrol_active", state.get(&"active_patrol", false)))
	if not has_formal_kind:
		if kind == "traversal" or kind == "connection":
			has_traversal = true
		if kind == "patrol":
			has_patrol = true
	if not has_formal_active:
		has_patrol = has_patrol or not route_id.is_empty()
	var can_finish := bool(state.get(&"can_finish", has_traversal or has_patrol))
	var formal_label := String(state.get(&"label", "") if state.has(&"label") else "").strip_edges()
	if kind == "traversal" or (not has_formal_kind and kind == "connection"):
		if has_traversal:
			_special_state_label.text = formal_label if not formal_label.is_empty() else "连接等待终点" + ("：起点 %s" % traversal_from if traversal_from is Vector3i else "")
		else:
			_special_state_label.text = "无等待终点或进行中的巡逻路线。"
		_special_finish_button.text = "取消连接等待"
		_special_finish_button.disabled = not can_finish if has_traversal else true
	elif kind == "patrol" and has_patrol:
		_special_state_label.text = formal_label if not formal_label.is_empty() else "当前巡逻路线" + ("：%s" % route_id if not route_id.is_empty() else "")
		_special_finish_button.text = "结束当前巡逻路线"
		_special_finish_button.disabled = not can_finish
	elif has_traversal:
		_special_state_label.text = formal_label if not formal_label.is_empty() else "连接等待终点" + ("：起点 %s" % traversal_from if traversal_from is Vector3i else "")
		_special_finish_button.text = "取消连接等待"
		_special_finish_button.disabled = not can_finish
	elif has_patrol:
		_special_state_label.text = formal_label if not formal_label.is_empty() else "当前巡逻路线" + ("：%s" % route_id if not route_id.is_empty() else "")
		_special_finish_button.text = "结束当前巡逻路线"
		_special_finish_button.disabled = not can_finish
	else:
		_special_state_label.text = "无等待终点或进行中的巡逻路线。"
		_special_finish_button.text = "结束特殊编辑"
		_special_finish_button.disabled = true

func _selected_spawn_configuration() -> Dictionary:
	if session == null:
		return {}
	if session.has_method("get_selected_spawn_configuration"):
		var value = session.call("get_selected_spawn_configuration")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	var selected := session.get_selected_placeable()
	return selected if String(selected.get("kind", "")) == "spawn" else {}

func _refresh_spawn_configuration_panel() -> void:
	if not _is_valid_control(_spawn_panel):
		return
	var configuration := _selected_spawn_configuration()
	_spawn_panel.visible = not configuration.is_empty()
	if configuration.is_empty():
		return
	_spawn_context_label.text = "当前出生素材：%s" % configuration.get("label", configuration.get("id", "出生点"))
	if _spawn_archetype_picker != null:
		if _spawn_archetype_picker.has_method("set") and _spawn_archetype_picker.get_class() == "EditorResourcePicker":
			_spawn_archetype_picker.set("edited_resource", configuration.get("archetype", null))
		elif _spawn_archetype_picker is LineEdit:
			(_spawn_archetype_picker as LineEdit).text = _resource_display(configuration.get("archetype", null))
	if _spawn_weapon_picker != null:
		if _spawn_weapon_picker.get_class() == "EditorResourcePicker":
			_spawn_weapon_picker.set("edited_resource", configuration.get("weapon", null))
		elif _spawn_weapon_picker is LineEdit:
			(_spawn_weapon_picker as LineEdit).text = _resource_display(configuration.get("weapon", null))
	_spawn_encounter_edit.text = String(configuration.get("encounter_id", ""))
	_spawn_patrol_edit.text = String(configuration.get("patrol_route_id", ""))

func _resource_display(value: Variant) -> String:
	if value == null:
		return "未设置（编辑器中使用资源选择器）"
	if value is Resource and not String((value as Resource).resource_path).is_empty():
		return String((value as Resource).resource_path)
	return String(value)

func _on_spawn_resource_changed(_resource: Resource, _control_name: String) -> void:
	# The actual mutation remains behind the explicit Apply button.
	if _spawn_context_label != null:
		_spawn_context_label.text = "出生点模板已修改，点击“应用出生点模板”提交。"

func _on_spawn_configuration_apply() -> void:
	if session == null or not session.has_method("set_selected_spawn_configuration"):
		_set_status("当前 Session 未提供出生点配置接口。", false)
		return
	var configuration := {
		&"archetype": _spawn_resource_value(_spawn_archetype_picker),
		&"weapon": _spawn_resource_value(_spawn_weapon_picker),
		&"encounter_id": StringName(_spawn_encounter_edit.text.strip_edges()),
		&"patrol_route_id": StringName(_spawn_patrol_edit.text.strip_edges()),
	}
	if not bool(session.call("set_selected_spawn_configuration", configuration)):
		_set_status("出生点模板配置未被 Session 接受。", false)
		return
	_refresh_spawn_configuration_panel()

func _spawn_resource_value(control: Control) -> Resource:
	if control == null or control.get_class() != "EditorResourcePicker":
		return null
	var value = control.get("edited_resource")
	return value as Resource

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

func _on_palette_item_selected(index: int) -> void:
	if _refreshing or session == null:
		return
	var entries := _get_palette_entries(_search.text)
	if index < 0 or index >= entries.size():
		return
	var selected_id := String(entries[index].get("id", ""))
	var all_entries := _get_all_placeable_entries()
	for full_index in range(all_entries.size()):
		if String(all_entries[full_index].get("id", "")) == selected_id:
			emit_signal("placeable_selected", full_index)
			return

func _on_target_layer_selected(index: int) -> void:
	if not _is_valid_control(_target_option) or index < 0 or index >= _target_option.item_count:
		return
	var layer := int(_target_option.get_item_id(index))
	if not _refreshing:
		target_layer_changed.emit(layer)
	# Refresh immediately as well as through Session.changed. This keeps the
	# palette responsive for lightweight/mock Sessions that do not emit changed.
	_refresh_palette()

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

func _emit_add_placeable_requested() -> void:
	add_placeable_requested.emit()

func _emit_new_map_requested() -> void:
	new_map_requested.emit()


func _emit_selection_replace_requested() -> void:
	selection_replace_requested.emit()


func _emit_selection_rotate_requested() -> void:
	selection_rotate_requested.emit()


func _emit_selection_delete_requested() -> void:
	selection_delete_requested.emit()


func _emit_selection_copy_requested() -> void:
	selection_copy_requested.emit()


func _emit_selection_paste_requested() -> void:
	selection_paste_requested.emit()

func _is_valid_control(control: Object) -> bool:
	return control != null and is_instance_valid(control)

func _has_base_ui_ready() -> bool:
	return _is_valid_control(_title) \
		and _is_valid_control(_selection_label) \
		and _is_valid_control(_new_map_button) \
		and _is_valid_control(_edit_toggle) \
		and _is_valid_control(_floor_spin) \
		and _is_valid_control(_target_option) \
		and _is_valid_control(_tool_option) \
		and _is_valid_control(_rotate_button) \
		and _is_valid_control(_selection_actions_panel) \
		and _is_valid_control(_selection_count_label) \
		and _is_valid_control(_selection_replace_button) \
		and _is_valid_control(_selection_rotate_button) \
		and _is_valid_control(_selection_delete_button) \
		and _is_valid_control(_selection_copy_button) \
		and _is_valid_control(_selection_paste_button) \
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
		and _is_valid_control(_validation_list) \
		and _is_valid_control(_validation_summary) \
		and _is_valid_control(_special_state_label) \
		and _is_valid_control(_special_finish_button) \
		and _is_valid_control(_spawn_context_label) \
		and _is_valid_control(_spawn_archetype_picker) \
		and _is_valid_control(_spawn_weapon_picker) \
		and _is_valid_control(_spawn_encounter_edit) \
		and _is_valid_control(_spawn_patrol_edit) \
		and _is_valid_control(_spawn_apply_button)

func _ensure_phase_c_ui() -> bool:
	_remove_legacy_property_panels()
	if not _ensure_scroll_container():
		return false
	_ensure_new_map_button()
	if not _ensure_tool_option():
		return false
	_remove_legacy_rotate_tool_item()
	_ensure_select_tool_item()
	_ensure_box_paint_tool_item()
	_ensure_add_placeable_button()
	var selection_actions_ready := _ensure_selection_actions_panel()
	var debug_ready := _ensure_debug_panel()
	var validation_ready := _ensure_validation_panel()
	var special_ready := _ensure_special_panel()
	var spawn_ready := _ensure_spawn_panel()
	return selection_actions_ready and debug_ready and validation_ready and special_ready and spawn_ready

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
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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

func _ensure_special_panel() -> bool:
	if not _is_valid_control(_special_panel):
		var existing := find_child("SpecialEditPanel", true, false)
		if existing is VBoxContainer:
			_special_panel = existing as VBoxContainer
	if not _is_valid_control(_special_panel):
		var parent := _content if _is_valid_control(_content) else self
		if parent is VBoxContainer:
			_build_special_panel(parent as VBoxContainer)
	if not _is_valid_control(_special_panel):
		return false
	if not _is_valid_control(_special_state_label):
		var state_label := _special_panel.find_child("SpecialEditStateLabel", true, false)
		if state_label is Label:
			_special_state_label = state_label as Label
	if not _is_valid_control(_special_finish_button):
		var finish_button := _special_panel.find_child("FinishSpecialEditButton", true, false)
		if finish_button is Button:
			_special_finish_button = finish_button as Button
	if not _is_valid_control(_special_state_label) or not _is_valid_control(_special_finish_button):
		return false
	return true

func _ensure_spawn_panel() -> bool:
	if not _is_valid_control(_spawn_panel):
		var existing := find_child("SpawnConfigurationPanel", true, false)
		if existing is VBoxContainer:
			_spawn_panel = existing as VBoxContainer
	if not _is_valid_control(_spawn_panel):
		var parent := _content if _is_valid_control(_content) else self
		if parent is VBoxContainer:
			_build_spawn_panel(parent as VBoxContainer)
	if not _is_valid_control(_spawn_panel):
		return false
	if not _is_valid_control(_spawn_context_label):
		var context := _spawn_panel.find_child("SpawnConfigurationContext", true, false)
		if context is Label:
			_spawn_context_label = context as Label
	if not _is_valid_control(_spawn_archetype_picker):
		_spawn_archetype_picker = _spawn_panel.find_child("SpawnArchetypePicker", true, false) as Control
	if not _is_valid_control(_spawn_weapon_picker):
		_spawn_weapon_picker = _spawn_panel.find_child("SpawnWeaponPicker", true, false) as Control
	if not _is_valid_control(_spawn_encounter_edit):
		_spawn_encounter_edit = _spawn_panel.find_child("SpawnEncounterIdEdit", true, false) as LineEdit
	if not _is_valid_control(_spawn_patrol_edit):
		_spawn_patrol_edit = _spawn_panel.find_child("SpawnPatrolRouteIdEdit", true, false) as LineEdit
	if not _is_valid_control(_spawn_apply_button):
		_spawn_apply_button = _spawn_panel.find_child("ApplySpawnConfigurationButton", true, false) as Button
	return _is_valid_control(_spawn_context_label) and _is_valid_control(_spawn_archetype_picker) and _is_valid_control(_spawn_weapon_picker) and _is_valid_control(_spawn_encounter_edit) and _is_valid_control(_spawn_patrol_edit) and _is_valid_control(_spawn_apply_button)


func _ensure_selection_actions_panel() -> bool:
	if not _is_valid_control(_selection_actions_panel):
		var existing := find_child("SelectionActionsPanel", true, false)
		if existing is VBoxContainer:
			_selection_actions_panel = existing as VBoxContainer
	if not _is_valid_control(_selection_actions_panel):
		var parent := _content if _is_valid_control(_content) else self
		if parent is VBoxContainer:
			_build_selection_actions_panel(parent as VBoxContainer)
	if not _is_valid_control(_selection_actions_panel):
		return false
	if not _is_valid_control(_selection_count_label):
		_selection_count_label = _selection_actions_panel.find_child("SelectionCountLabel", true, false) as Label
	if not _is_valid_control(_selection_replace_button):
		_selection_replace_button = _selection_actions_panel.find_child("SelectionReplaceButton", true, false) as Button
	if not _is_valid_control(_selection_rotate_button):
		_selection_rotate_button = _selection_actions_panel.find_child("SelectionRotateButton", true, false) as Button
	if not _is_valid_control(_selection_delete_button):
		_selection_delete_button = _selection_actions_panel.find_child("SelectionDeleteButton", true, false) as Button
	if not _is_valid_control(_selection_copy_button):
		_selection_copy_button = _selection_actions_panel.find_child("SelectionCopyButton", true, false) as Button
	if not _is_valid_control(_selection_paste_button):
		_selection_paste_button = _selection_actions_panel.find_child("SelectionPasteButton", true, false) as Button
	_ensure_selection_action_layout()
	_remove_legacy_selection_move_controls()
	if not _is_valid_control(_selection_count_label) or not _is_valid_control(_selection_replace_button) or not _is_valid_control(_selection_rotate_button) or not _is_valid_control(_selection_delete_button) or not _is_valid_control(_selection_copy_button) or not _is_valid_control(_selection_paste_button):
		return false
	if not _selection_replace_button.pressed.is_connected(_emit_selection_replace_requested):
		_selection_replace_button.pressed.connect(_emit_selection_replace_requested)
	if not _selection_rotate_button.pressed.is_connected(_emit_selection_rotate_requested):
		_selection_rotate_button.pressed.connect(_emit_selection_rotate_requested)
	if not _selection_delete_button.pressed.is_connected(_emit_selection_delete_requested):
		_selection_delete_button.pressed.connect(_emit_selection_delete_requested)
	if not _selection_copy_button.pressed.is_connected(_emit_selection_copy_requested):
		_selection_copy_button.pressed.connect(_emit_selection_copy_requested)
	if not _selection_paste_button.pressed.is_connected(_emit_selection_paste_requested):
		_selection_paste_button.pressed.connect(_emit_selection_paste_requested)
	return true


func _ensure_selection_action_layout() -> void:
	if not _is_valid_control(_selection_actions_panel):
		return
	if _selection_actions_panel.find_child("SelectionEditButtons", true, false) != null:
		return
	var legacy_grid := _selection_actions_panel.find_child("SelectionActionButtons", true, false)
	if legacy_grid == null or legacy_grid.get_parent() == null:
		return
	var parent := legacy_grid.get_parent()
	var insert_index := legacy_grid.get_index()
	var edit_grid := GridContainer.new()
	edit_grid.name = "SelectionEditButtons"
	edit_grid.columns = 3
	edit_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for button in [_selection_replace_button, _selection_rotate_button, _selection_delete_button]:
		if button == null or button.get_parent() == null:
			continue
		button.get_parent().remove_child(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit_grid.add_child(button)
	var clipboard_row := HBoxContainer.new()
	clipboard_row.name = "SelectionClipboardButtons"
	clipboard_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for button in [_selection_copy_button, _selection_paste_button]:
		if button == null or button.get_parent() == null:
			continue
		button.get_parent().remove_child(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clipboard_row.add_child(button)
	parent.add_child(edit_grid)
	parent.move_child(edit_grid, insert_index)
	parent.add_child(clipboard_row)
	parent.move_child(clipboard_row, insert_index + 1)
	legacy_grid.queue_free()
	_selection_replace_button.text = "替换"
	_selection_rotate_button.text = "旋转"
	_selection_delete_button.text = "删除"


func _remove_legacy_selection_move_controls() -> void:
	if not _is_valid_control(_selection_actions_panel):
		return
	var legacy_grid := _selection_actions_panel.find_child("SelectionMoveButtons", true, false)
	if legacy_grid != null:
		legacy_grid.visible = false
	for child in _selection_actions_panel.get_children():
		if child is Label and String((child as Label).text).strip_edges() == "移动":
			(child as Label).visible = false

func _ensure_tool_option() -> bool:
	if not _is_valid_control(_tool_option):
		var named := find_child("ToolOption", true, false)
		if named is OptionButton:
			_tool_option = named as OptionButton
	if not _is_valid_control(_tool_option):
		_tool_option = _find_tool_option(self)
	return _is_valid_control(_tool_option)


func _remove_legacy_rotate_tool_item() -> void:
	if not _is_valid_control(_tool_option):
		return
	for index in range(_tool_option.item_count - 1, -1, -1):
		if _tool_option.get_item_id(index) == TacticalMapEditSession.Tool.ROTATE:
			_tool_option.remove_item(index)


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
	var has_select := false
	for index in range(option.item_count):
		var text := option.get_item_text(index).to_lower()
		has_paint = has_paint or text == "paint"
		has_erase = has_erase or text == "erase"
		has_rotate = has_rotate or text == "rotate"
		has_select = has_select or option.get_item_id(index) == TacticalMapEditSession.Tool.SELECT
	return has_paint and has_erase and (has_rotate or has_select)

func _ensure_select_tool_item() -> void:
	if not _is_valid_control(_tool_option):
		return
	for index in range(_tool_option.item_count):
		if _tool_option.get_item_id(index) == TacticalMapEditSession.Tool.SELECT:
			return
	_tool_option.add_item("Select", TacticalMapEditSession.Tool.SELECT)

func _ensure_box_paint_tool_item() -> void:
	if not _is_valid_control(_tool_option):
		return
	for index in range(_tool_option.item_count):
		if _tool_option.get_item_id(index) == TacticalMapEditSession.Tool.BOX_PAINT:
			# Keep tooltip in sync with the Box Paint Ctrl-erase feature.
			_tool_option.set_item_tooltip(index, "按住左键拖出矩形，松开后批量绘制 Cell 地格；按住 Ctrl 拖选时改为批量擦除。")
			return
	_tool_option.add_item("Box Paint", TacticalMapEditSession.Tool.BOX_PAINT)
	_tool_option.set_item_tooltip(_tool_option.item_count - 1, "按住左键拖出矩形，松开后批量绘制 Cell 地格；按住 Ctrl 拖选时改为批量擦除。")

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
	var run_row := VBoxContainer.new()
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

func _ensure_add_placeable_button() -> bool:
	if _is_valid_control(_add_placeable_button):
		return true
	var existing := find_child("AddPlaceableButton", true, false)
	if existing is Button:
		_add_placeable_button = existing as Button
		if not _add_placeable_button.pressed.is_connected(_emit_add_placeable_requested):
			_add_placeable_button.pressed.connect(_emit_add_placeable_requested)
		return true
	var parent: Node = find_child("PaletteHeading", true, false)
	if parent == null:
		parent = _content if _is_valid_control(_content) else self
	if parent == null:
		return false
	_add_placeable_button = Button.new()
	_add_placeable_button.name = "AddPlaceableButton"
	_add_placeable_button.text = "添加素材"
	_add_placeable_button.tooltip_text = "从资源文件导入一个已有的 Cell 或 Object Definition。"
	_add_placeable_button.pressed.connect(_emit_add_placeable_requested)
	parent.add_child(_add_placeable_button)
	return true

func _ensure_new_map_button() -> bool:
	if _is_valid_control(_new_map_button):
		_new_map_button.disabled = false
		return true
	var existing := find_child("NewMapButton", true, false)
	if existing is Button:
		_new_map_button = existing as Button
		_new_map_button.disabled = false
		if not _new_map_button.pressed.is_connected(_emit_new_map_requested):
			_new_map_button.pressed.connect(_emit_new_map_requested)
		return true
	var parent: Node = _content if _is_valid_control(_content) else self
	if parent == null:
		return false
	_new_map_button = Button.new()
	_new_map_button.name = "NewMapButton"
	_new_map_button.text = "新建地图"
	_new_map_button.tooltip_text = "创建一个新的 TacticalMapAuthor 场景与地图资源；不会默认覆盖已有文件。"
	_new_map_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_map_button.pressed.connect(_emit_new_map_requested)
	parent.add_child(_new_map_button)
	if _edit_toggle != null and _edit_toggle.get_parent() == parent:
		parent.move_child(_new_map_button, _edit_toggle.get_index())
	return true
