@tool
class_name TacticalPlaceableWizard
extends Window

## Small, self-contained Add Placeable dialog.  It deliberately keeps the
## first implementation to Cell definitions backed by an existing
## GridMap/MeshLibrary item; arbitrary model import is not silently guessed.

signal saved(result: Dictionary)

const SERVICE_SCRIPT := preload("res://addons/tactical_map_editor/content/tactical_placeable_wizard_service.gd")

var author: Node
var _mesh_options: Array[Dictionary] = []
var _definition_path_default := ""
var _library_path_default := ""
var _built := false

var _type_option: OptionButton
var _id_edit: LineEdit
var _name_edit: LineEdit
var _category_edit: LineEdit
var _tags_edit: LineEdit
var _layer_option: OptionButton
var _mesh_option: OptionButton
var _definition_path_edit: LineEdit
var _library_path_edit: LineEdit
var _walkable: CheckButton
var _move_cost: SpinBox
var _sight_block: SpinBox
var _projectile_block: SpinBox
var _occluder_height: SpinBox
var _sound_cost: SpinBox
var _terrain_tags_edit: LineEdit
var _hazard_id_edit: LineEdit
var _status: Label


func _ready() -> void:
	if not _built:
		_build_ui()
	if _definition_path_edit != null:
		_definition_path_edit.text = _definition_path_default
	if _library_path_edit != null:
		_library_path_edit.text = _library_path_default
	_refresh_mesh_options()


func configure(next_author: Node, definition_path: String, library_path: String) -> void:
	author = next_author
	_definition_path_default = definition_path
	_library_path_default = library_path
	_mesh_options = SERVICE_SCRIPT.collect_mesh_options(author)
	if _built:
		_id_edit.text = String(SERVICE_SCRIPT.default_request().get(&"placeable_id", ""))
		_name_edit.text = "新地格"
		_category_edit.text = "地面"
		_tags_edit.text = ""
		_definition_path_edit.text = definition_path
		_library_path_edit.text = library_path
		_refresh_mesh_options()


func _build_ui() -> void:
	_built = true
	title = "添加素材"
	min_size = Vector2i(460, 620)
	size = Vector2i(500, 720)
	transient = true
	exclusive = true
	var margin := MarginContainer.new()
	margin.name = "WizardMargin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "WizardScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "WizardContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(content)

	var heading := Label.new()
	heading.text = "添加素材 / Cell 地格"
	heading.add_theme_font_size_override("font_size", 18)
	content.add_child(heading)
	var hint := Label.new()
	hint.text = "当前向导只引用已有 GridMap MeshLibrary item，不会自动猜测模型、碰撞或修改地图布局。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("aab4c5"))
	content.add_child(hint)

	_type_option = OptionButton.new()
	_type_option.name = "PlaceableTypeOption"
	_type_option.add_item("Cell 地格", 0)
	_type_option.disabled = true
	_add_labeled_control(content, "类型", _type_option)
	_id_edit = LineEdit.new()
	_id_edit.name = "PlaceableIdEdit"
	_id_edit.placeholder_text = "例如 terrain.factory.floor_new"
	_add_labeled_control(content, "稳定 ID", _id_edit)
	_name_edit = LineEdit.new()
	_name_edit.name = "DisplayNameEdit"
	_name_edit.placeholder_text = "素材显示名"
	_add_labeled_control(content, "显示名", _name_edit)
	_category_edit = LineEdit.new()
	_category_edit.name = "CategoryEdit"
	_category_edit.placeholder_text = "地面 / 结构 / 装饰"
	_add_labeled_control(content, "分类", _category_edit)
	_tags_edit = LineEdit.new()
	_tags_edit.name = "TagsEdit"
	_tags_edit.placeholder_text = "逗号分隔，例如 factory,metal"
	_add_labeled_control(content, "标签", _tags_edit)

	_layer_option = OptionButton.new()
	_layer_option.name = "TargetLayerOption"
	_layer_option.add_item("Floor", MapTileRule.Layer.FLOOR)
	_layer_option.add_item("Structure", MapTileRule.Layer.STRUCTURE)
	_layer_option.item_selected.connect(func(_index: int) -> void: _refresh_mesh_options())
	_add_labeled_control(content, "目标层", _layer_option)
	_mesh_option = OptionButton.new()
	_mesh_option.name = "MeshLibraryItemOption"
	_add_labeled_control(content, "视觉来源", _mesh_option)
	var source_hint := Label.new()
	source_hint.text = "只列出当前作者 FloorGrid / StructureGrid 已有的 MeshLibrary item。"
	source_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source_hint.add_theme_color_override("font_color", Color("aab4c5"))
	content.add_child(source_hint)

	var path_heading := Label.new()
	path_heading.text = "资源保存路径"
	path_heading.add_theme_font_size_override("font_size", 14)
	content.add_child(path_heading)
	_definition_path_edit = LineEdit.new()
	_definition_path_edit.name = "DefinitionPathEdit"
	_definition_path_edit.placeholder_text = "res://resources/map_tiles/definitions/generated/example.tres"
	_add_labeled_control(content, "Definition", _definition_path_edit)
	_library_path_edit = LineEdit.new()
	_library_path_edit.name = "LibraryPathEdit"
	_library_path_edit.placeholder_text = "res://resources/map_tiles/libraries/<map>_placeable_library.tres"
	_add_labeled_control(content, "Library", _library_path_edit)

	var rules_heading := Label.new()
	rules_heading.text = "默认玩法属性"
	rules_heading.add_theme_font_size_override("font_size", 14)
	content.add_child(rules_heading)
	_walkable = CheckButton.new()
	_walkable.name = "WalkableCheck"
	_walkable.text = "默认可通行"
	_walkable.button_pressed = true
	content.add_child(_walkable)
	_move_cost = _new_spin("MoveCostSpin", 1.0, 99.0, 1.0, 1.0)
	_add_labeled_control(content, "move_cost", _move_cost)
	_sight_block = _new_spin("SightBlockSpin", 0.0, 1.0, 0.01, 0.0)
	_add_labeled_control(content, "sight_block", _sight_block)
	_projectile_block = _new_spin("ProjectileBlockSpin", 0.0, 1.0, 0.01, 0.0)
	_add_labeled_control(content, "projectile_block", _projectile_block)
	_occluder_height = _new_spin("OccluderHeightSpin", 0.0, 20.0, 0.05, 0.0)
	_add_labeled_control(content, "occluder_height", _occluder_height)
	_sound_cost = _new_spin("SoundCostSpin", 0.0, 99.0, 0.05, 0.0)
	_add_labeled_control(content, "sound_cost", _sound_cost)
	_terrain_tags_edit = LineEdit.new()
	_terrain_tags_edit.name = "TerrainTagsEdit"
	_terrain_tags_edit.placeholder_text = "逗号分隔，例如 indoor,metal"
	_add_labeled_control(content, "terrain_tags", _terrain_tags_edit)
	_hazard_id_edit = LineEdit.new()
	_hazard_id_edit.name = "HazardIdEdit"
	_hazard_id_edit.placeholder_text = "可选稳定 ID"
	_add_labeled_control(content, "hazard_id", _hazard_id_edit)

	_status = Label.new()
	_status.name = "WizardStatusLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("ffcc66"))
	content.add_child(_status)
	var button_row := VBoxContainer.new()
	content.add_child(button_row)
	var save_button := Button.new()
	save_button.name = "SavePlaceableButton"
	save_button.text = "保存 Definition 并加入素材库"
	save_button.pressed.connect(_on_save_pressed)
	button_row.add_child(save_button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelPlaceableButton"
	cancel_button.text = "取消"
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_row.add_child(cancel_button)


func _add_labeled_control(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _new_spin(control_name: String, minimum: float, maximum: float, step: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = control_name
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _refresh_mesh_options() -> void:
	if _mesh_option == null:
		return
	_mesh_option.clear()
	var layer := int(_layer_option.get_selected_id()) if _layer_option != null else MapTileRule.Layer.FLOOR
	var first := true
	for option in _mesh_options:
		if int(option.get(&"layer", -1)) != layer:
			continue
		_mesh_option.add_item(String(option.get(&"label", "MeshLibrary item")))
		_mesh_option.set_item_metadata(_mesh_option.item_count - 1, option)
		if first:
			_mesh_option.select(_mesh_option.item_count - 1)
			first = false
	if first:
		_mesh_option.add_item("当前层没有可用 MeshLibrary item")
		_mesh_option.set_item_disabled(0, true)


func _request() -> Dictionary:
	var selected_option: Dictionary = {}
	if _mesh_option != null and _mesh_option.selected >= 0 and _mesh_option.item_count > 0 and not _mesh_option.is_item_disabled(_mesh_option.selected):
		var metadata := _mesh_option.get_item_metadata(_mesh_option.selected)
		if metadata is Dictionary:
			selected_option = metadata
	var request := SERVICE_SCRIPT.default_request()
	request[&"placeable_id"] = _id_edit.text
	request[&"display_name"] = _name_edit.text
	request[&"category"] = StringName(_category_edit.text.strip_edges())
	request[&"tags"] = SERVICE_SCRIPT.normalize_tags(_tags_edit.text)
	request[&"target_layer"] = int(_layer_option.get_selected_id())
	request[&"mesh_library"] = selected_option.get(&"mesh_library", null)
	request[&"mesh_item_id"] = int(selected_option.get(&"mesh_item_id", -1))
	request[&"walkable"] = _walkable.button_pressed
	request[&"move_cost"] = int(_move_cost.value)
	request[&"sight_block"] = _sight_block.value
	request[&"projectile_block"] = _projectile_block.value
	request[&"occluder_height"] = _occluder_height.value
	request[&"sound_cost"] = _sound_cost.value
	request[&"terrain_tags"] = SERVICE_SCRIPT.normalize_tags(_terrain_tags_edit.text)
	request[&"hazard_id"] = StringName(_hazard_id_edit.text.strip_edges())
	return request


func _on_save_pressed() -> void:
	var result := SERVICE_SCRIPT.save_new_cell(author, _request(), _definition_path_edit.text, _library_path_edit.text)
	if not bool(result.get(&"valid", false)):
		var errors: Array = result.get(&"errors", [])
		_status.text = "保存失败：%s" % (String(errors[0]) if not errors.is_empty() else "未知错误")
		_status.add_theme_color_override("font_color", Color("ff8c8c"))
		return
	_status.text = "已保存并加入素材库：%s。返回 Dock 后请保存作者场景。" % result.get(&"placeable_id", "")
	_status.add_theme_color_override("font_color", Color("8fe388"))
	saved.emit(result)
	hide()


func _on_cancel_pressed() -> void:
	hide()
