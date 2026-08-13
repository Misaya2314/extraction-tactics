class_name InventoryItemControl
extends Control

## Visual item control shared by the inventory grid and the Loot tray.
##
## The control never mutates inventory state.  It only creates a native
## Godot drag payload or forwards a right-click rotation request to its
## owner.  The controller remains the single place where model mutations
## happen.

const INVENTORY_COLOR := Color("3f8edb")
const CONSUMABLE_COLOR := Color("4fa86a")
const VALUABLE_COLOR := Color("b883d6")
const CHIP_COLOR := Color("d69c43")
const BORDER_COLOR := Color(0.92, 0.96, 1.0, 0.9)

var item: InventoryItemInstance
var anchor := Vector2i.ZERO
var item_rotation_degrees := 0
var source_kind: StringName = &"inventory"
var source_id: StringName = &""
var source_index := -1
var cell_size := 30.0
var details_text := ""

var drag_start_handler: Callable
var drag_end_handler: Callable
var right_click_handler: Callable
var drop_owner: Control
var drop_can_handler: Callable
var drop_handler: Callable
var _details_label: Label
var _active_drag_preview: InventoryItemControl


func configure(
		new_item: InventoryItemInstance,
		new_anchor: Vector2i = Vector2i.ZERO,
		new_rotation: int = 0,
		new_source_kind: StringName = &"inventory",
		new_source_id: StringName = &"",
		new_source_index: int = -1,
		new_cell_size: float = 30.0,
		new_details_text: String = ""
	) -> void:
	item = new_item
	anchor = new_anchor
	item_rotation_degrees = ItemDefinition.rotation_to_degrees(new_rotation)
	source_kind = new_source_kind
	source_id = new_source_id
	source_index = new_source_index
	cell_size = maxf(new_cell_size, 8.0)
	details_text = new_details_text
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_update_size()
	_ensure_details_label()
	_update_details_label()
	queue_redraw()


func set_interaction_handlers(
		new_drag_start_handler: Callable,
		new_right_click_handler: Callable,
		new_drag_end_handler: Callable = Callable()
	) -> void:
	drag_start_handler = new_drag_start_handler
	right_click_handler = new_right_click_handler
	drag_end_handler = new_drag_end_handler


func set_drop_forwarder(new_owner: Control, new_can_handler: Callable, new_drop_handler: Callable) -> void:
	drop_owner = new_owner
	drop_can_handler = new_can_handler
	drop_handler = new_drop_handler


func set_rotation_preview(new_rotation: int) -> void:
	item_rotation_degrees = ItemDefinition.rotation_to_degrees(new_rotation)
	_update_size()
	_update_details_label()
	queue_redraw()


func update_active_drag_preview(new_rotation: int) -> void:
	if is_instance_valid(_active_drag_preview):
		_active_drag_preview.set_rotation_preview(new_rotation)


func get_active_drag_preview() -> InventoryItemControl:
	return _active_drag_preview


func clear_active_drag_preview() -> void:
	_active_drag_preview = null


func get_item_rotation() -> int:
	return item_rotation_degrees


func get_shape_cells() -> Array[Vector2i]:
	if item == null or item.definition == null:
		return []
	return item.definition.get_rotated_cells(item_rotation_degrees)


func get_occupied_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for relative_cell in get_shape_cells():
		result.append(anchor + relative_cell)
	return result


func get_drag_payload() -> Dictionary:
	return {
		"source": source_kind,
		"source_kind": source_kind,
		"instance_id": item.instance_id if item != null else &"",
		"container_id": source_id if source_kind == &"loot" else &"",
		"index": source_index,
		"anchor": anchor,
		"rotation": item_rotation_degrees,
		"item": item,
		"source_control": self,
	}


func _get_drag_data(_at_position: Vector2) -> Variant:
	var payload := get_drag_payload()
	var preview := InventoryItemControl.new()
	preview.configure(item, Vector2i.ZERO, item_rotation_degrees, source_kind, source_id, source_index, cell_size, details_text)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.modulate = Color(1.0, 1.0, 1.0, 0.78)
	_active_drag_preview = preview
	if drag_start_handler.is_valid():
		drag_start_handler.call(payload)
	# Unit tests may call this native hook directly without an active viewport
	# drag.  Godot only accepts a preview while gui_is_dragging() is true.
	var viewport := get_viewport()
	if viewport != null and viewport.gui_is_dragging():
		set_drag_preview(preview)
	return payload


func _notification(what: int) -> void:
	if what != Control.NOTIFICATION_DRAG_END:
		return
	clear_active_drag_preview()
	if drag_end_handler.is_valid():
		drag_end_handler.call()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if right_click_handler.is_valid():
			right_click_handler.call(get_drag_payload())
		accept_event()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not drop_can_handler.is_valid() or not is_instance_valid(drop_owner):
		return false
	return bool(drop_can_handler.call(_to_drop_owner_position(at_position), data))


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if drop_handler.is_valid() and is_instance_valid(drop_owner):
		drop_handler.call(_to_drop_owner_position(at_position), data)


func _to_drop_owner_position(at_position: Vector2) -> Vector2:
	var global_point := get_global_transform_with_canvas() * at_position
	return drop_owner.get_global_transform_with_canvas().affine_inverse() * global_point


func _has_point(point: Vector2) -> bool:
	if point.x < 0.0 or point.y < 0.0 or point.x >= size.x or point.y >= size.y:
		return false
	if cell_size <= 0.0:
		return false
	var cell := Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
	return get_shape_cells().has(cell)


func _draw() -> void:
	if item == null or item.definition == null:
		return
	var fill := _item_color()
	for relative_cell in get_shape_cells():
		var rect := Rect2(Vector2(relative_cell) * cell_size, Vector2.ONE * cell_size)
		draw_rect(rect, fill, true)
		draw_rect(rect, BORDER_COLOR, false, 1.0)


func _ensure_details_label() -> void:
	if is_instance_valid(_details_label):
		return
	_details_label = Label.new()
	_details_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_label.add_theme_font_size_override("font_size", 11)
	add_child(_details_label)


func _update_details_label() -> void:
	if not is_instance_valid(_details_label):
		return
	_details_label.text = details_text if not details_text.is_empty() else _short_name()
	_details_label.position = Vector2(2.0, 2.0)
	_details_label.size = Vector2(maxf(size.x - 4.0, 4.0), maxf(size.y - 4.0, 4.0))


func _update_size() -> void:
	var shape_size := Vector2i.ONE
	if item != null and item.definition != null:
		shape_size = item.definition.get_shape_size(item_rotation_degrees)
	size = Vector2(shape_size) * cell_size
	custom_minimum_size = size


func _short_name() -> String:
	if item == null:
		return "?"
	var trimmed := item.display_name.strip_edges()
	return trimmed.substr(0, mini(trimmed.length(), 2)) if not trimmed.is_empty() else "?"


func _item_color() -> Color:
	if item == null or item.definition == null:
		return INVENTORY_COLOR
	match item.definition.kind:
		ItemDefinition.Kind.CONSUMABLE:
			return CONSUMABLE_COLOR
		ItemDefinition.Kind.VALUABLE:
			return VALUABLE_COLOR
		ItemDefinition.Kind.CHIP:
			return CHIP_COLOR
		_:
			return INVENTORY_COLOR
