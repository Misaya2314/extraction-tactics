class_name LootGridControl
extends Control

## Instance-aware Loot tray.  Items are draggable sources; the inventory grid
## is the target.  Returning an inventory item to this control is also routed
## through the controller command handler.

const ITEM_CELL_SIZE := 26.0

var container: LootContainerModel
var place_handler: Callable
var first_fit_handler: Callable
var return_handler: Callable
var preview_return_handler: Callable

var _rows_root: VBoxContainer
var _status_label: Label
var _item_controls: Dictionary = {}
var _pending_rotations: Dictionary = {}
var _active_drag: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rows_root = VBoxContainer.new()
	_rows_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rows_root.add_theme_constant_override("separation", 5)
	add_child(_rows_root)
	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows_root.add_child(_status_label)
	_status_label.text = "打开 Loot 箱后显示物品。"


func configure(
		new_place_handler: Callable,
		new_first_fit_handler: Callable,
		new_return_handler: Callable,
		new_preview_return_handler: Callable = Callable()
	) -> void:
	place_handler = new_place_handler
	first_fit_handler = new_first_fit_handler
	return_handler = new_return_handler
	preview_return_handler = new_preview_return_handler
	refresh()


func set_container(new_container: LootContainerModel) -> void:
	container = new_container
	refresh()


func clear_container() -> void:
	container = null
	refresh()


func refresh() -> void:
	_item_controls.clear()
	if not is_instance_valid(_rows_root):
		return
	var current_ids: Dictionary = {}
	if container != null:
		for current_item in container.get_contents_instances():
			if current_item != null:
				current_ids[current_item.instance_id] = true
	for pending_id in _pending_rotations.keys():
		if not current_ids.has(pending_id):
			_pending_rotations.erase(pending_id)
	for child in _rows_root.get_children():
		if child == _status_label:
			continue
		_rows_root.remove_child(child)
		child.queue_free()
	if container == null:
		_status_label.text = "打开 Loot 箱后显示物品。"
		return
	if container.is_depleted():
		_status_label.text = "Loot 已耗尽。"
		return
	_status_label.text = "拖动物品到左侧背包；R 或右键旋转。"
	for index in range(container.get_item_count()):
		var item := container.get_item(index)
		if item == null:
			continue
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 72)
		row.add_theme_constant_override("separation", 7)
		var item_rotation := int(_pending_rotations.get(item.instance_id, item.rotation))
		var item_control := InventoryItemControl.new()
		item_control.configure(
			item,
			Vector2i.ZERO,
			item_rotation,
			&"loot",
			container.container_id,
			index,
			ITEM_CELL_SIZE
		)
		item_control.set_interaction_handlers(
			Callable(self, "_on_item_drag_start"),
			Callable(self, "_on_item_right_click"),
			Callable(self, "_on_drag_end")
		)
		item_control.set_drop_forwarder(
			self,
			Callable(self, "_can_drop_data"),
			Callable(self, "_drop_data")
		)
		item_control.custom_minimum_size = Vector2(66, 66)
		item_control.size = Vector2(66, 66)
		row.add_child(item_control)
		_item_controls[index] = item_control

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := Label.new()
		name_label.text = item.display_name
		name_label.add_theme_font_size_override("font_size", 14)
		info.add_child(name_label)
		var detail_label := Label.new()
		detail_label.name = "Details"
		detail_label.text = _detail_text(item, item_rotation)
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(detail_label)
		var place_button := Button.new()
		place_button.text = "放入首个空位"
		place_button.tooltip_text = "使用当前旋转尝试放入背包"
		place_button.pressed.connect(_place_first_fit.bind(index, item_rotation))
		info.add_child(place_button)
		row.add_child(info)
		_rows_root.add_child(row)


func get_item_control(index: int) -> InventoryItemControl:
	return _item_controls.get(index) as InventoryItemControl


func get_item_control_count() -> int:
	return _item_controls.size()


func has_active_drag() -> bool:
	return not _active_drag.is_empty()


func get_active_drag_payload() -> Dictionary:
	return _active_drag.duplicate()


func clear_pending_rotation(instance_id: StringName) -> void:
	_pending_rotations.erase(instance_id)


func rotate_active_drag() -> void:
	if _active_drag.is_empty():
		return
	_active_drag["rotation"] = ItemDefinition.rotation_to_degrees(int(_active_drag.get("rotation", 0)) + 90)
	var rotation := int(_active_drag["rotation"])
	var index := int(_active_drag.get("index", -1))
	var control := get_item_control(index)
	if is_instance_valid(control):
		control.set_rotation_preview(rotation)
	_update_source_drag_preview(_active_drag, rotation)
	var target_grid: Control = _active_drag.get("target_grid") as Control
	var target_anchor: Vector2i = _active_drag.get("hover_anchor", Vector2i(-1, -1))
	if is_instance_valid(target_grid) and target_grid.has_method("_refresh_drag_preview"):
		target_grid.call("_refresh_drag_preview", _active_drag, target_anchor, rotation)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or container == null:
		return false
	var payload: Dictionary = data
	var source := StringName(payload.get("source_kind", payload.get("source", &"")))
	if source != &"inventory":
		return false
	payload["target_grid"] = self
	_active_drag = payload
	if preview_return_handler.is_valid():
		return bool(preview_return_handler.call(StringName(payload.get("instance_id", &"")), container.container_id))
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary or container == null:
		return
	var payload: Dictionary = data
	var source := StringName(payload.get("source_kind", payload.get("source", &"")))
	if source == &"inventory" and return_handler.is_valid():
		return_handler.call(StringName(payload.get("instance_id", &"")), container.container_id)
	_clear_drag_state_for_payload(payload)


func _input(event: InputEvent) -> void:
	if _active_drag.is_empty() or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_R:
		rotate_active_drag()
		get_viewport().set_input_as_handled()


func _on_item_drag_start(payload: Dictionary) -> void:
	payload["source_grid"] = self
	_active_drag = payload


func _on_item_right_click(payload: Dictionary) -> void:
	var index := int(payload.get("index", -1))
	if index < 0:
		return
	var item := container.get_item(index) if container != null else null
	if item == null:
		return
	_pending_rotations[item.instance_id] = ItemDefinition.rotation_to_degrees(int(payload.get("rotation", item.rotation)) + 90)
	refresh()


func _on_drag_end() -> void:
	_clear_drag_state()


func _update_source_drag_preview(payload: Dictionary, rotation: int) -> void:
	var source_control: InventoryItemControl = payload.get("source_control") as InventoryItemControl
	if is_instance_valid(source_control):
		source_control.update_active_drag_preview(rotation)


func _clear_drag_state_for_payload(payload: Dictionary) -> void:
	var source_control: InventoryItemControl = payload.get("source_control") as InventoryItemControl
	if is_instance_valid(source_control):
		source_control.clear_active_drag_preview()
	var source_grid: Control = payload.get("source_grid") as Control
	var target_grid: Control = payload.get("target_grid") as Control
	if is_instance_valid(source_grid) and source_grid.has_method("_clear_drag_state"):
		source_grid.call("_clear_drag_state")
	if is_instance_valid(target_grid) and target_grid != source_grid and target_grid.has_method("_clear_drag_state"):
		target_grid.call("_clear_drag_state")
	_clear_drag_state()


func _clear_drag_state() -> void:
	var source_control: InventoryItemControl = _active_drag.get("source_control") as InventoryItemControl
	if is_instance_valid(source_control):
		source_control.clear_active_drag_preview()
	_active_drag.clear()


func _notification(what: int) -> void:
	if what == Control.NOTIFICATION_DRAG_END:
		_clear_drag_state()


func _place_first_fit(index: int, rotation: int) -> void:
	if first_fit_handler.is_valid() and container != null:
		first_fit_handler.call(container.container_id, index, rotation)


func _detail_text(item: InventoryItemInstance, rotation: int) -> String:
	var shape_size := item.get_shape_size() if item != null else Vector2i.ZERO
	if item != null and item.definition != null:
		shape_size = item.definition.get_shape_size(rotation)
	return "价值 %d · 形状 %s · %d°" % [item.value, shape_size, ItemDefinition.rotation_to_degrees(rotation)]
