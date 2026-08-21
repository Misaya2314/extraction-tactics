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
signal add_placeable_requested
signal new_map_requested
signal special_edit_finish_requested
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
	_edit_toggle.tooltip_text = "M 只在 3D 视口中快速切换地图编辑模式；关闭时保留 Godot 原生选择和相机操作。"
	_edit_toggle.toggled.connect(func(value: bool) -> void: edit_mode_changed.emit(value))
	content.add_child(_edit_toggle)
	var navigation_hint := Label.new()
	navigation_hint.name = "NavigationHint"
	navigation_hint.text = "视口导航：普通 RMB 为 Godot 原生自由观察；按住 RMB + WASD 飞行；MMB 原生环绕/平移（按 Godot 设置）。擦除：擦除工具 + 左键，或 Ctrl + 左键临时擦除。"
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
	_tool_option.add_item("Rotate", TacticalMapEditSession.Tool.ROTATE)
	_tool_option.add_item("Select", TacticalMapEditSession.Tool.SELECT)
	_tool_option.add_item("Box Paint", TacticalMapEditSession.Tool.BOX_PAINT)
	_tool_option.set_item_tooltip(_tool_option.item_count - 1, "按住左键拖出矩形，松开后批量绘制 Cell 地格。")
	_tool_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_option.item_selected.connect(func(index: int) -> void:
		tool_changed.emit(int(_tool_option.get_item_id(index)))
	)
	tool_row.add_child(_tool_option)
	_rotate_button = Button.new()
	_rotate_button.text = "R 旋转"
	_rotate_button.tooltip_text = "旋转选中的素材 90°；Rotate 工具可旋转目标格已有内容。"
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
	_add_placeable_button.tooltip_text = "打开素材向导，创建一个引用现有 MeshLibrary item 的 Cell 定义。"
	_add_placeable_button.pressed.connect(func() -> void: add_placeable_requested.emit())
	palette_heading.add_child(_add_placeable_button)
	_palette = ItemList.new()
	_palette.name = "Palette"
	_palette.select_mode = ItemList.SELECT_SINGLE
	_palette.custom_minimum_size = Vector2(0, 190)
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.item_selected.connect(_on_palette_item_selected)
	content.add_child(_palette)
	_build_special_panel(content)
	_build_spawn_panel(content)

	_build_property_panel(content)
	_build_debug_panel(content)
	_build_default_property_panel(content)
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
	_refresh()


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
	var grid := VBoxContainer.new()
	grid.name = "DefaultPropertyGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_default_panel.add_child(grid)
	for field in PROPERTY_FIELDS:
		_add_default_property_row(grid, field)


func _add_default_property_row(grid: Container, field: StringName) -> void:
	var descriptor := _property_descriptor(field)
	var row := VBoxContainer.new()
	row.name = "DefaultRow_%s" % field
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(row)
	var field_label := Label.new()
	field_label.name = "DefaultField_%s" % field
	field_label.text = String(descriptor.get(&"label", field))
	field_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(field_label)
	var values := GridContainer.new()
	values.name = "DefaultValues_%s" % field
	values.columns = 2
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(values)
	var value_label := Label.new()
	value_label.name = "DefaultValue_%s" % field
	value_label.text = "—"
	_default_value_labels[field] = value_label
	values.add_child(_captioned_value("默认值", value_label))
	var support_label := Label.new()
	support_label.name = "DefaultSupport_%s" % field
	support_label.text = "未选择"
	_default_support_labels[field] = support_label
	values.add_child(_captioned_value("支持状态", support_label))
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
	values.add_child(_captioned_control("编辑值", editor))
	var action_box := HBoxContainer.new()
	action_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(action_box)
	var write_button := Button.new()
	write_button.name = "DefaultWrite_%s" % field
	write_button.text = "写入"
	write_button.pressed.connect(_on_default_write_pressed.bind(field))
	_default_write_buttons[field] = write_button
	action_box.add_child(write_button)
	var restore_button := Button.new()
	restore_button.name = "DefaultRestore_%s" % field
	restore_button.text = "恢复"
	restore_button.pressed.connect(_on_default_restore_pressed.bind(field))
	_default_restore_buttons[field] = restore_button
	action_box.add_child(restore_button)


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

	var grid := VBoxContainer.new()
	grid.name = "PropertyGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_property_panel.add_child(grid)
	for field in PROPERTY_FIELDS:
		_add_property_row(grid, field)


func _add_property_row(grid: Container, field: StringName) -> void:
	var descriptor := _property_descriptor(field)
	var row := VBoxContainer.new()
	row.name = "PropertyRow_%s" % field
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(row)
	var field_label := Label.new()
	field_label.name = "PropertyField_%s" % field
	field_label.text = String(descriptor.get(&"label", field))
	field_label.tooltip_text = String(descriptor.get(&"id", String(field).to_lower()))
	field_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(field_label)
	var values := GridContainer.new()
	values.name = "PropertyValues_%s" % field
	values.columns = 2
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(values)

	var base_label := Label.new()
	base_label.name = "PropertyBase_%s" % field
	base_label.text = "—"
	_property_base_value_labels[field] = base_label
	values.add_child(_captioned_value("默认值", base_label))

	var override_label := Label.new()
	override_label.name = "PropertyOverride_%s" % field
	override_label.text = "—"
	_property_override_value_labels[field] = override_label
	values.add_child(_captioned_value("覆盖值", override_label))

	var value_label := Label.new()
	value_label.name = "PropertyValue_%s" % field
	value_label.text = "—"
	_property_value_labels[field] = value_label
	values.add_child(_captioned_value("最终值", value_label))

	var state_label := Label.new()
	state_label.name = "PropertyState_%s" % field
	state_label.text = "继承"
	_property_state_labels[field] = state_label
	values.add_child(_captioned_value("状态", state_label))

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
	values.add_child(_captioned_control("编辑值", editor))

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
	row.add_child(action_box)


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
		_refresh_property_panel()
		_refresh_debug_panel()
		_refresh_default_property_panel()
		_refresh_special_edit_panel()
		_refresh_spawn_configuration_panel()
	_refresh_validation_panel()
	if session == null:
		_refreshing = false
		return
	var has_author := session.has_author()
	if has_author and _map_locked and session.edit_mode:
		_selection_label.text = "地图已锁定，已隐藏根节点选择框：%s" % session.author.name
	else:
		_selection_label.text = "作者：%s" % session.author.name if has_author else "请在场景树中选择地图根节点后开启编辑。"
	_edit_toggle.disabled = not has_author
	_edit_toggle.button_pressed = session.edit_mode and has_author
	_edit_toggle.tooltip_text = "地图已锁定，已隐藏根节点选择框；可选择地图内子节点查看，但不会改变编辑层。" if _map_locked and has_author and session.edit_mode else "M 只在 3D 视口中快速切换地图编辑模式；关闭时保留 Godot 原生选择和相机操作。"
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
	_refresh_property_panel()
	_refresh_debug_panel()
	_refresh_default_property_panel()
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
	if not _ensure_scroll_container():
		return false
	_ensure_new_map_button()
	if not _ensure_tool_option():
		return false
	_ensure_select_tool_item()
	_ensure_box_paint_tool_item()
	_ensure_add_placeable_button()
	var property_ready := _ensure_property_panel()
	var debug_ready := _ensure_debug_panel()
	var default_ready := _ensure_default_property_panel()
	var validation_ready := _ensure_validation_panel()
	var special_ready := _ensure_special_panel()
	var spawn_ready := _ensure_spawn_panel()
	return property_ready and debug_ready and default_ready and validation_ready and special_ready and spawn_ready


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


func _ensure_box_paint_tool_item() -> void:
	if not _is_valid_control(_tool_option):
		return
	for index in range(_tool_option.item_count):
		if _tool_option.get_item_id(index) == TacticalMapEditSession.Tool.BOX_PAINT:
			return
	_tool_option.add_item("Box Paint", TacticalMapEditSession.Tool.BOX_PAINT)
	_tool_option.set_item_tooltip(_tool_option.item_count - 1, "按住左键拖出矩形，松开后批量绘制 Cell 地格。")


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

	var grid := _property_panel.find_child("PropertyGrid", true, false) as Container
	if grid == null:
		grid = VBoxContainer.new()
		grid.name = "PropertyGrid"
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_property_panel.add_child(grid)

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
	_add_placeable_button.tooltip_text = "打开素材向导，创建一个引用现有 MeshLibrary item 的 Cell 定义。"
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
