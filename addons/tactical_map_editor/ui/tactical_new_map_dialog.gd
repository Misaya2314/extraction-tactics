@tool
class_name TacticalNewMapDialog
extends Window

## Editor-only form for creating a TacticalMapAuthor scene and its baked
## resource.  The creation service owns validation, normalization, directory
## creation, and serialization; this dialog only collects a request and
## presents the result.

const CREATION_SERVICE_PATH := "res://addons/tactical_map_editor/content/tactical_map_creation_service.gd"

signal map_created(result: Dictionary)
signal canceled

var _service_script: Script
var _ui_built := false
var _updating_paths := false
var _scene_path_user_edited := false
var _output_path_user_edited := false
var _suggested_scene_path := ""
var _suggested_output_path := ""
var _last_validation: Dictionary = {}

var _display_name_edit: LineEdit
var _map_id_edit: LineEdit
var _scene_path_edit: LineEdit
var _output_path_edit: LineEdit
var _level_spin: SpinBox
var _dimension_spins: Array[SpinBox] = []
var _origin_spins: Array[SpinBox] = []
var _library_path_edit: LineEdit
var _library_dialog: FileDialog
var _library_summary_label: Label
var _error_label: Label
var _warning_label: Label
var _create_button: Button


func _ready() -> void:
	_build_ui()
	close_requested.connect(_on_close_requested)
	reset_form()


func open_for_default() -> void:
	_build_ui()
	reset_form()
	_validate_form()
	popup_centered(Vector2i(580, 760))


func reset_form() -> void:
	if not _ui_built:
		return
	var defaults := _default_request()
	_scene_path_user_edited = false
	_output_path_user_edited = false
	_suggested_scene_path = String(defaults.get(&"scene_path", "res://scenes/maps/new_map.tscn"))
	_suggested_output_path = String(defaults.get(&"output_resource_path", "res://resources/maps/new_map.tres"))
	_set_line_text(_display_name_edit, String(defaults.get(&"display_name", "新地图")))
	_set_line_text(_map_id_edit, String(defaults.get(&"map_id", "new_map")))
	_set_line_text(_scene_path_edit, _suggested_scene_path)
	_set_line_text(_output_path_edit, _suggested_output_path)
	_level_spin.value = clampi(int(defaults.get(&"level_count", 1)), 1, 32)
	_set_vector_spins(_dimension_spins, defaults.get(&"cell_dimensions", Vector3(2.0, 2.0, 2.0)), Vector3(2.0, 2.0, 2.0))
	_set_vector_spins(_origin_spins, defaults.get(&"grid_origin", Vector3.ZERO), Vector3.ZERO)
	var library = defaults.get(&"placeable_library", null)
	_set_line_text(_library_path_edit, _resource_path(library))
	_refresh_library_summary()
	_validate_form()


func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	title = "新建 Tactical 地图"
	min_size = Vector2i(520, 620)
	size = Vector2i(580, 760)
	transient = true
	exclusive = true

	var margin := MarginContainer.new()
	margin.name = "NewMapDialogMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.name = "NewMapDialogContent"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var heading := Label.new()
	heading.text = "创建新的 TacticalMapAuthor"
	heading.add_theme_font_size_override("font_size", 18)
	root.add_child(heading)
	var intro := Label.new()
	intro.text = "创建完成后会打开新作者场景；已有文件不会被默认覆盖。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color("aab4c5"))
	root.add_child(intro)

	_display_name_edit = _add_line_field(root, "显示名", "例如：训练场")
	_display_name_edit.name = "MapDisplayName"
	_display_name_edit.text_changed.connect(_on_form_changed)
	_map_id_edit = _add_line_field(root, "稳定 map_id", "只使用字母、数字、下划线、点或连字符")
	_map_id_edit.name = "MapId"
	_map_id_edit.text_changed.connect(_on_map_id_changed)
	_scene_path_edit = _add_line_field(root, "作者场景路径", "res://scenes/maps/<id>.tscn")
	_scene_path_edit.name = "MapScenePath"
	_scene_path_edit.text_changed.connect(_on_scene_path_changed)
	_output_path_edit = _add_line_field(root, "Bake 输出路径", "res://resources/maps/<id>.tres")
	_output_path_edit.name = "MapOutputPath"
	_output_path_edit.text_changed.connect(_on_output_path_changed)

	_level_spin = SpinBox.new()
	_level_spin.name = "LevelCount"
	_level_spin.min_value = 1
	_level_spin.max_value = 32
	_level_spin.step = 1
	_level_spin.value = 1
	_level_spin.tooltip_text = "地图层数，至少为 1。"
	_level_spin.value_changed.connect(_on_form_changed)
	root.add_child(_captioned("层数", _level_spin))

	_dimension_spins = _add_vector_fields(root, "格子尺寸", "CellDimensions", Vector3(2.0, 2.0, 2.0), false)
	_origin_spins = _add_vector_fields(root, "grid_origin", "GridOrigin", Vector3.ZERO, true)

	var library_box := HBoxContainer.new()
	library_box.name = "PlaceableLibraryRow"
	library_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_path_edit = LineEdit.new()
	_library_path_edit.name = "PlaceableLibraryPath"
	_library_path_edit.placeholder_text = "默认：res://resources/map_tiles/libraries/default_placeable_library.tres"
	_library_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_path_edit.text_changed.connect(_on_form_changed)
	library_box.add_child(_captioned("TacticalPlaceableLibrary（必选）", _library_path_edit))
	var browse := Button.new()
	browse.name = "BrowsePlaceableLibrary"
	browse.text = "选择…"
	browse.tooltip_text = "选择一个现有 TacticalPlaceableLibrary 资源。"
	browse.pressed.connect(_open_library_dialog)
	library_box.add_child(browse)
	root.add_child(library_box)

	_library_summary_label = Label.new()
	_library_summary_label.name = "PlaceableLibrarySummary"
	_library_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_library_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_library_summary_label.add_theme_color_override("font_color", Color("aab4c5"))
	root.add_child(_library_summary_label)

	var workflow := Label.new()
	workflow.name = "WorkflowHint"
	workflow.text = "工作流：创建 → 素材库 → 绘制结构层 → 添加玩法标记 → 局部属性 → Validate / Save / Bake 或 Bake & Play"
	workflow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	workflow.add_theme_color_override("font_color", Color("aab4c5"))
	root.add_child(workflow)

	_error_label = Label.new()
	_error_label.name = "ValidationErrors"
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override("font_color", Color("ff8c8c"))
	root.add_child(_error_label)
	_warning_label = Label.new()
	_warning_label.name = "ValidationWarnings"
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.add_theme_color_override("font_color", Color("ffd27d"))
	root.add_child(_warning_label)

	var actions := HBoxContainer.new()
	actions.name = "NewMapActions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	var cancel := Button.new()
	cancel.name = "CancelNewMap"
	cancel.text = "取消"
	cancel.pressed.connect(_on_cancel_pressed)
	actions.add_child(cancel)
	_create_button = Button.new()
	_create_button.name = "CreateMap"
	_create_button.text = "创建并打开"
	_create_button.tooltip_text = "仅当请求通过 Core 创建服务校验时可用。"
	_create_button.pressed.connect(_on_create_pressed)
	actions.add_child(_create_button)
	root.add_child(actions)


func _add_line_field(parent: VBoxContainer, label_text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_captioned(label_text, edit))
	return edit


func _captioned(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", Color("aab4c5"))
	box.add_child(label)
	box.add_child(control)
	return box


func _add_vector_fields(parent: VBoxContainer, label_text: String, node_name: String, value: Vector3, allow_negative: bool) -> Array[SpinBox]:
	var row := HBoxContainer.new()
	row.name = node_name
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var result: Array[SpinBox] = []
	for index in 3:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = ["X", "Y", "Z"][index]
		box.add_child(label)
		var spin := SpinBox.new()
		spin.name = "%s%s" % [node_name, ["X", "Y", "Z"][index]]
		spin.min_value = -100000.0 if allow_negative else 0.01
		spin.max_value = 100000.0
		spin.step = 0.01
		spin.value = value[index]
		spin.allow_greater = true
		spin.allow_lesser = allow_negative
		spin.value_changed.connect(_on_form_changed)
		box.add_child(spin)
		row.add_child(box)
		result.append(spin)
	parent.add_child(_captioned(label_text, row))
	return result


func _on_map_id_changed(value: String) -> void:
	if not _updating_paths:
		var token := _safe_id_token(value)
		var suggested_scene := "res://scenes/maps/%s.tscn" % token
		var suggested_output := "res://resources/maps/%s.tres" % token
		if not _scene_path_user_edited or _scene_path_edit.text == _suggested_scene_path:
			_set_line_text(_scene_path_edit, suggested_scene)
		if not _output_path_user_edited or _output_path_edit.text == _suggested_output_path:
			_set_line_text(_output_path_edit, suggested_output)
		_suggested_scene_path = suggested_scene
		_suggested_output_path = suggested_output
	_validate_form()


func _on_scene_path_changed(_value: String) -> void:
	if not _updating_paths:
		_scene_path_user_edited = _scene_path_edit.text != _suggested_scene_path
	_validate_form()


func _on_output_path_changed(_value: String) -> void:
	if not _updating_paths:
		_output_path_user_edited = _output_path_edit.text != _suggested_output_path
	_validate_form()


func _on_form_changed(_value: Variant = null) -> void:
	_refresh_library_summary()
	_validate_form()


func _set_line_text(edit: LineEdit, value: String) -> void:
	if edit == null:
		return
	_updating_paths = true
	edit.text = value
	_updating_paths = false


func _set_vector_spins(spins: Array[SpinBox], value: Variant, fallback: Vector3) -> void:
	var vector := value as Vector3 if value is Vector3 else fallback
	for index in mini(spins.size(), 3):
		spins[index].value = vector[index]


func _default_request() -> Dictionary:
	var defaults := {
		&"map_id": "new_map",
		&"display_name": "新地图",
		&"scene_path": "res://scenes/maps/new_map.tscn",
		&"output_resource_path": "res://resources/maps/new_map.tres",
		&"level_count": 1,
		&"cell_dimensions": Vector3(2.0, 2.0, 2.0),
		&"grid_origin": Vector3.ZERO,
		&"placeable_library": ResourceLoader.load("res://resources/map_tiles/libraries/default_placeable_library.tres"),
	}
	var service := _resolve_service()
	if service == null:
		return defaults
	var value = service.call("default_request")
	if value is Dictionary:
		for key in defaults.keys():
			if not value.has(key):
				value[key] = defaults[key]
		return value
	return defaults


func _build_request() -> Dictionary:
	return {
		&"map_id": String(_map_id_edit.text.strip_edges()),
		&"display_name": String(_display_name_edit.text.strip_edges()),
		&"scene_path": String(_scene_path_edit.text.strip_edges()),
		&"output_resource_path": String(_output_path_edit.text.strip_edges()),
		&"level_count": int(_level_spin.value),
		&"cell_dimensions": Vector3(_dimension_spins[0].value, _dimension_spins[1].value, _dimension_spins[2].value),
		&"grid_origin": Vector3(_origin_spins[0].value, _origin_spins[1].value, _origin_spins[2].value),
		&"placeable_library": _load_library_resource(),
	}


func _validate_form() -> Dictionary:
	if not _ui_built:
		return {&"valid": false, &"errors": ["新建地图对话框尚未初始化。"], &"warnings": []}
	var request := _build_request()
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var map_id := String(request.get(&"map_id", "")).strip_edges()
	if map_id.is_empty() or not _is_valid_id(map_id):
		errors.append("map_id 不能为空，且只能包含字母、数字、下划线、点或连字符。")
	if String(request.get(&"display_name", "")).strip_edges().is_empty():
		errors.append("显示名不能为空。")
	_check_path(String(request.get(&"scene_path", "")), ".tscn", "作者场景路径", errors)
	_check_path(String(request.get(&"output_resource_path", "")), ".tres", "Bake 输出路径", errors)
	if request.get(&"scene_path", "") == request.get(&"output_resource_path", ""):
		errors.append("作者场景路径与 Bake 输出路径不能相同。")
	if int(request.get(&"level_count", 0)) < 1:
		errors.append("层数必须至少为 1。")
	for index in 3:
		if float(_dimension_spins[index].value) <= 0.0:
			errors.append("格子尺寸必须为正数。")
			break
	var library_path := _library_path_edit.text.strip_edges()
	if library_path.is_empty():
		errors.append("必须提供有效的 TacticalPlaceableLibrary 素材库。")
	elif _load_library_resource() == null:
		errors.append("TacticalPlaceableLibrary 路径无效或资源无法加载。")
	var service := _resolve_service()
	if service == null:
		errors.append("地图创建服务尚未加载，请先完成 Core 创建服务接入。")
	else:
		var service_result = service.call("validate_request", request)
		if service_result is Dictionary:
			errors.append_array(_string_array(service_result.get(&"errors", [])))
			warnings.append_array(_string_array(service_result.get(&"warnings", [])))
			if not bool(service_result.get(&"valid", errors.is_empty())) and errors.is_empty():
				errors.append("创建请求未通过地图创建服务校验。")
		else:
			errors.append("地图创建服务没有返回有效校验结果。")
	_check_existing(String(request.get(&"scene_path", "")), "作者场景路径", errors)
	_check_existing(String(request.get(&"output_resource_path", "")), "Bake 输出路径", errors)
	_last_validation = {&"valid": errors.is_empty(), &"errors": errors, &"warnings": warnings, &"request": request}
	_show_validation(errors, warnings)
	return _last_validation


func _check_path(path: String, suffix: String, label: String, errors: Array[String]) -> void:
	if not path.begins_with("res://"):
		errors.append("%s 必须使用 res:// 路径。" % label)
	elif not path.to_lower().ends_with(suffix):
		errors.append("%s 必须以 %s 结尾。" % [label, suffix])


func _check_existing(path: String, label: String, errors: Array[String]) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		errors.append("%s 已存在，为避免覆盖请更换路径：%s" % [label, path])


func _show_validation(errors: Array[String], warnings: Array[String]) -> void:
	if _error_label != null:
		_error_label.text = "" if errors.is_empty() else "错误：\n" + "\n".join(errors)
	if _warning_label != null:
		_warning_label.text = "" if warnings.is_empty() else "提示：\n" + "\n".join(warnings)
	if _create_button != null:
		_create_button.disabled = not errors.is_empty()


func _on_create_pressed() -> void:
	var validation := _validate_form()
	if not bool(validation.get(&"valid", false)):
		return
	var service := _resolve_service()
	if service == null:
		return
	var result = service.call("create_map", validation.get(&"request", _build_request()))
	if not result is Dictionary:
		_show_validation(["地图创建服务没有返回有效结果。"], [])
		return
	var result_dictionary: Dictionary = result
	if not bool(result_dictionary.get(&"valid", false)):
		_show_validation(_string_array(result_dictionary.get(&"errors", ["地图创建失败。"])), _string_array(result_dictionary.get(&"warnings", [])))
		return
	map_created.emit(result_dictionary)


func _on_cancel_pressed() -> void:
	hide()
	canceled.emit()


func _on_close_requested() -> void:
	hide()
	canceled.emit()


func _open_library_dialog() -> void:
	if _library_dialog == null or not is_instance_valid(_library_dialog):
		_library_dialog = FileDialog.new()
		_library_dialog.name = "PlaceableLibraryFileDialog"
		_library_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_library_dialog.access = FileDialog.ACCESS_RESOURCES
		_library_dialog.filters = PackedStringArray(["*.tres ; Resource", "*.res ; Resource"])
		_library_dialog.file_selected.connect(_on_library_file_selected)
		add_child(_library_dialog)
	_library_dialog.popup_centered(Vector2i(700, 520))


func _on_library_file_selected(path: String) -> void:
	_set_line_text(_library_path_edit, path)
	_refresh_library_summary()
	_validate_form()


func _refresh_library_summary() -> void:
	if _library_summary_label == null:
		return
	var path := _library_path_edit.text.strip_edges() if _library_path_edit != null else ""
	if path.is_empty():
		_library_summary_label.text = "素材库摘要错误：尚未提供 TacticalPlaceableLibrary 路径。"
		return
	var library := _load_library_resource()
	if library == null:
		_library_summary_label.text = "素材库摘要错误：无法加载有效的 TacticalPlaceableLibrary。请检查路径或选择 .tres/.res 文件。"
		return
	var counts := _library_definition_counts(library)
	var validation_errors: Array[String] = library.get_validation_errors()
	var count_text := "Floor %d 个定义；Structure %d 个定义；Object %d 个定义。" % [counts[&"floor"], counts[&"structure"], counts[&"object"]]
	var source_text := "Decoration：由 Cell 视觉别名提供；Traversal / Spawner / AI：由内建标记工具提供。"
	if int(library.schema_version) != TacticalPlaceableLibrary.CURRENT_SCHEMA_VERSION or not validation_errors.is_empty():
		var detail := "schema_version 不受支持。" if int(library.schema_version) != TacticalPlaceableLibrary.CURRENT_SCHEMA_VERSION else validation_errors[0]
		_library_summary_label.text = "素材库摘要错误：该 TacticalPlaceableLibrary 未通过结构校验（%s）\n%s\n%s" % [detail, count_text, source_text]
		return
	_library_summary_label.text = "素材库摘要：可用于 %s\n%s" % [count_text, source_text]


func _library_definition_counts(library: TacticalPlaceableLibrary) -> Dictionary:
	var counts := {&"floor": 0, &"structure": 0, &"object": 0}
	for definition in library.definitions:
		if definition == null:
			continue
		if definition is TacticalObjectDefinition:
			counts[&"object"] += 1
			continue
		if definition is TacticalCellTileDefinition:
			var cell_definition := definition as TacticalCellTileDefinition
			match int(cell_definition.target_layer):
				MapTileRule.Layer.FLOOR:
					counts[&"floor"] += 1
				MapTileRule.Layer.STRUCTURE:
					counts[&"structure"] += 1
			continue
		if int(definition.placement_kind) == TacticalPlaceableDefinition.PlacementKind.OBJECT:
			counts[&"object"] += 1
	return counts


func _load_library_resource() -> Resource:
	var path := _library_path_edit.text.strip_edges() if _library_path_edit != null else ""
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var value = ResourceLoader.load(path)
	return value as TacticalPlaceableLibrary


func _resolve_service() -> Script:
	if _service_script != null and is_instance_valid(_service_script):
		return _service_script
	if not ResourceLoader.exists(CREATION_SERVICE_PATH):
		return null
	var loaded = load(CREATION_SERVICE_PATH)
	if loaded is Script:
		_service_script = loaded as Script
	return _service_script


func _resource_path(value: Variant) -> String:
	if value is Resource:
		return String((value as Resource).resource_path)
	return String(value) if value != null else ""


func _safe_id_token(value: String) -> String:
	var token := value.strip_edges()
	var result := ""
	for character in token:
		if (character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9") or character in ["_", ".", "-"]:
			result += character
	if result.is_empty():
		result = "new_map"
	return result


func _is_valid_id(value: String) -> bool:
	if value.is_empty() or value.begins_with(".") or value.begins_with("-"):
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9") or character in ["_", ".", "-"]):
			return false
	return true


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(String(item))
	return result
