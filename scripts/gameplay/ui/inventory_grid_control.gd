class_name InventoryGridControl
extends Control

## A real 2D inventory surface.  It deliberately draws every cell and puts
## item controls in an overlay, so irregular shapes never rely on a
## GridContainer pretending that one item occupies one slot.

signal command_requested(command: Dictionary)

const DEFAULT_COLUMNS := 6
const DEFAULT_ROWS := 8
const DEFAULT_CELL_SIZE := 30.0
const GRID_BACKGROUND := Color(0.035, 0.055, 0.08, 0.96)
const CELL_COLOR := Color(0.10, 0.15, 0.20, 0.92)
const CELL_BORDER := Color(0.30, 0.45, 0.58, 0.9)
const PREVIEW_VALID := Color(0.22, 0.90, 0.43, 0.58)
const PREVIEW_INVALID := Color(0.95, 0.25, 0.22, 0.62)

@export var columns := DEFAULT_COLUMNS
@export var rows := DEFAULT_ROWS
@export var cell_size := DEFAULT_CELL_SIZE

var inventory: SquadInventory
var preview_handler: Callable
var command_handler: Callable

var _item_controls: Dictionary = {}
var _active_drag: Dictionary = {}
var _preview_cells: Array[Vector2i] = []
var _preview_valid := false
var _preview_anchor := Vector2i(-1, -1)
var _preview_rotation := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(columns * cell_size, rows * cell_size)
	queue_redraw()


func configure(
		new_inventory: SquadInventory,
		new_preview_handler: Callable = Callable(),
		new_command_handler: Callable = Callable()
	) -> void:
	inventory = new_inventory
	preview_handler = new_preview_handler
	command_handler = new_command_handler
	refresh()


func set_inventory(new_inventory: SquadInventory) -> void:
	inventory = new_inventory
	refresh()


func refresh() -> void:
	_clear_item_controls()
	if inventory == null:
		queue_redraw()
		return
	columns = inventory.get_width()
	rows = inventory.get_height()
	custom_minimum_size = Vector2(columns * cell_size, rows * cell_size)
	for placement in inventory.get_placements():
		if placement == null or placement.instance == null:
			continue
		var item_control := InventoryItemControl.new()
		item_control.configure(
			placement.instance,
			placement.anchor,
			placement.rotation,
			&"inventory",
			placement.instance.instance_id,
			-1,
			cell_size
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
		item_control.position = Vector2(placement.anchor) * cell_size
		item_control.z_index = 2
		add_child(item_control)
		_item_controls[placement.instance.instance_id] = item_control
	queue_redraw()


func get_cell_count() -> int:
	return columns * rows


func get_dimensions() -> Vector2i:
	return Vector2i(columns, rows)


func get_item_control_count() -> int:
	return _item_controls.size()


func get_item_control(instance_id: StringName) -> InventoryItemControl:
	return _item_controls.get(instance_id) as InventoryItemControl


func get_preview_cells() -> Array[Vector2i]:
	return _preview_cells.duplicate()


func is_preview_valid() -> bool:
	return _preview_valid


func has_active_drag() -> bool:
	return not _active_drag.is_empty()


func get_active_drag_payload() -> Dictionary:
	return _active_drag.duplicate()


func clear_preview() -> void:
	_clear_drag_state()


func rotate_active_drag() -> void:
	if _active_drag.is_empty():
		return
	_active_drag["rotation"] = ItemDefinition.rotation_to_degrees(int(_active_drag.get("rotation", 0)) + 90)
	_preview_rotation = int(_active_drag["rotation"])
	_update_source_drag_preview(_active_drag, _preview_rotation)
	if _preview_anchor.x >= 0 and _preview_anchor.y >= 0:
		_refresh_drag_preview(_active_drag, _preview_anchor, _preview_rotation)
	else:
		queue_redraw()
	var target_grid: Control = _active_drag.get("target_grid") as Control
	var target_anchor: Vector2i = _active_drag.get("hover_anchor", Vector2i(-1, -1))
	if is_instance_valid(target_grid) and target_grid != self and target_grid.has_method("_refresh_drag_preview"):
		target_grid.call("_refresh_drag_preview", _active_drag, target_anchor, _preview_rotation)


func _draw() -> void:
	var grid_size := Vector2(columns * cell_size, rows * cell_size)
	draw_rect(Rect2(Vector2.ZERO, grid_size), GRID_BACKGROUND, true)
	for y in range(rows):
		for x in range(columns):
			var rect := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			draw_rect(rect, CELL_COLOR, true)
			draw_rect(rect, CELL_BORDER, false, 1.0)
	for cell in _preview_cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= columns or cell.y >= rows:
			continue
		var preview_rect := Rect2(Vector2(cell) * cell_size, Vector2.ONE * cell_size)
		draw_rect(preview_rect, PREVIEW_VALID if _preview_valid else PREVIEW_INVALID, true)
		draw_rect(preview_rect, Color.WHITE, false, 1.5)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var payload: Dictionary = data
	var source := StringName(payload.get("source_kind", payload.get("source", &"")))
	if source != &"inventory" and source != &"loot":
		return false
	var anchor := _cell_from_position(at_position)
	var rotation := int(payload.get("rotation", 0))
	payload["target_grid"] = self
	payload["hover_anchor"] = anchor
	payload["hover_rotation"] = rotation
	_active_drag = payload
	var preview := _preview_payload(payload, anchor, rotation)
	_apply_preview(anchor, rotation, preview)
	return _preview_valid


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		clear_preview()
		return
	var payload: Dictionary = data
	var anchor := _cell_from_position(at_position)
	var rotation := int(payload.get("rotation", 0))
	var source := StringName(payload.get("source_kind", payload.get("source", &"")))
	var command := {
		"type": &"move_inventory" if source == &"inventory" else &"place_loot",
		"instance_id": StringName(payload.get("instance_id", &"")),
		"container_id": StringName(payload.get("container_id", &"")),
		"index": int(payload.get("index", -1)),
		"anchor": anchor,
		"rotation": rotation,
	}
	_emit_command(command)
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
	_preview_rotation = int(payload.get("rotation", 0))


func _on_item_right_click(payload: Dictionary) -> void:
	var instance_id := StringName(payload.get("instance_id", &""))
	_emit_command({"type": &"rotate_inventory", "instance_id": instance_id})


func _on_drag_end() -> void:
	_clear_drag_state()


func _refresh_drag_preview(payload: Dictionary, anchor: Vector2i, rotation: int) -> void:
	payload["target_grid"] = self
	payload["hover_anchor"] = anchor
	payload["hover_rotation"] = rotation
	_active_drag = payload
	_preview_rotation = rotation
	_update_source_drag_preview(payload, rotation)
	_apply_preview(anchor, rotation, _preview_payload(payload, anchor, rotation))


func _apply_preview(anchor: Vector2i, rotation: int, preview: Dictionary) -> void:
	_preview_anchor = anchor
	_preview_rotation = rotation
	_preview_cells = _coerce_cells(preview.get("cells", []))
	_preview_valid = bool(preview.get("valid", false))
	queue_redraw()


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
	_preview_cells.clear()
	_preview_anchor = Vector2i(-1, -1)
	_preview_valid = false
	_preview_rotation = 0
	queue_redraw()


func _notification(what: int) -> void:
	if what == Control.NOTIFICATION_DRAG_END:
		_clear_drag_state()


func _preview_payload(payload: Dictionary, anchor: Vector2i, rotation: int) -> Dictionary:
	if preview_handler.is_valid():
		var result = preview_handler.call(
			StringName(payload.get("container_id", &"")),
			int(payload.get("index", -1)),
			StringName(payload.get("instance_id", &"")),
			anchor,
			rotation,
			StringName(payload.get("source_kind", payload.get("source", &"")))
		)
		if result is Dictionary:
			return result
	var item = payload.get("item")
	var valid := false
	if inventory != null and item != null:
		if StringName(payload.get("source_kind", payload.get("source", &""))) == &"inventory":
			valid = inventory.can_move(StringName(payload.get("instance_id", &"")), anchor, rotation)
		else:
			valid = inventory.can_place(item, anchor, rotation)
	return {"valid": valid, "cells": _shape_cells(item, anchor, rotation)}


func _shape_cells(item: Variant, anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var instance := item as InventoryItemInstance
	if instance == null or instance.definition == null:
		return result
	for relative_cell in instance.definition.get_rotated_cells(rotation):
		result.append(anchor + relative_cell)
	return result


func _cell_from_position(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))


func _emit_command(command: Dictionary) -> Variant:
	command_requested.emit(command)
	if command_handler.is_valid():
		return command_handler.call(command)
	return null


func _coerce_cells(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if value is Array:
		for cell in value:
			if cell is Vector2i:
				result.append(cell)
	return result


func _clear_item_controls() -> void:
	_item_controls.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
