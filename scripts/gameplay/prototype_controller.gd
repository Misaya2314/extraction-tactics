class_name PrototypeController
extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/main/prototype_unit.tscn")
const ActionResultScript = preload("res://scripts/core/action/action_result.gd")
const ActionRequestScript = preload("res://scripts/core/action/action_request.gd")
const ActionExecutionContextScript = preload("res://scripts/core/action/action_execution_context.gd")
const ActionExecutorScript = preload("res://scripts/core/action/action_executor.gd")
const GameStateManagerScript = preload("res://scripts/core/session/game_state_manager.gd")
const TacticalUndoManagerScript = preload("res://scripts/core/undo/tactical_undo_manager.gd")
const GameDefinitionRegistryScript = preload("res://scripts/core/content/game_definition_registry.gd")
const RuntimeInstanceRegistryScript = preload("res://scripts/core/runtime/runtime_instance_registry.gd")
const InstanceIdGeneratorScript = preload("res://scripts/core/runtime/instance_id_generator.gd")
const ItemInstanceFactoryScript = preload("res://scripts/core/items/item_instance_factory.gd")
const UnitInstanceFactoryScript = preload("res://scripts/core/units/unit_instance_factory.gd")
const EnvironmentObjectFactoryScript = preload("res://scripts/core/environment/environment_object_factory.gd")
const EnvironmentEffectResolverScript = preload("res://scripts/core/environment/environment_effect_resolver.gd")
const SquadInventoryScript = preload("res://scripts/core/inventory/squad_inventory.gd")
const LootContainerScript = preload("res://scripts/core/loot/loot_container_model.gd")
const LootSettlementScript = preload("res://scripts/core/loot/loot_settlement.gd")
const CoverQueryScript = preload("res://scripts/core/cover/cover_query.gd")
const CoverResolverScript = preload("res://scripts/core/cover/cover_resolver.gd")
const CoverCombatSettingsScript = preload("res://scripts/core/cover/cover_combat_settings.gd")
const TacticalStepOutScript = preload("res://scripts/core/cover/tactical_step_out.gd")
const InventoryGridScript = preload("res://scripts/gameplay/ui/inventory_grid_control.gd")
const LootGridScript = preload("res://scripts/gameplay/ui/loot_grid_control.gd")
const MOVE_ACTION_COST := 1
## Opening a Loot container is a one-AP Interact; confirming an extraction is
## also one AP, while taking items from an opened container is free.
const INTERACT_ACTION_COST := 1
const LOOT_OPEN_ACTION_COST := 1
const LOOT_ACTION_COST := 0
const INTERACTION_RANGE := 1
const ACTION_MOVE: StringName = &"move"
const ACTION_INTERACT: StringName = &"interact"
const ACTION_LOOT: StringName = &"loot"
const ACTION_ATTACK: StringName = &"attack"
const ACTION_MODE_MOVE: int = 0
const ACTION_MODE_ATTACK: int = 1
const PLAYER_COLOR := Color("4f9dff")
const ENEMY_COLOR := Color("ef5b5b")
const MOVE_HIGHLIGHT_COLOR := Color(0.2, 0.72, 1.0, 0.34)
const ATTACK_HIGHLIGHT_COLOR := Color(1.0, 0.23, 0.16, 0.48)
const LOOT_HIGHLIGHT_COLOR := Color(1.0, 0.82, 0.16, 0.56)
const EXTRACTION_HIGHLIGHT_COLOR := Color(0.2, 0.95, 0.42, 0.56)
const MOVE_HIGHLIGHT_SURFACE_OFFSET := 0.025
const CURSOR_HIGHLIGHT_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const CURSOR_SURFACE_OFFSET := 0.035
const HALF_COVER_TEXTURE: Texture2D = preload("res://assets/textures/half_cover.png")
const FULL_COVER_TEXTURE: Texture2D = preload("res://assets/textures/full_cover.png")
const CURSOR_HIGHLIGHT_DISTANCE: int = 0
const COVER_PREVIEW_DISTANCE: int = 1
const CURSOR_DISTANCE_ALPHA_FACTORS: Array[float] = [1.0]
const COVER_DISTANCE_ALPHA_FACTORS: Array[float] = [1.0, 0.65]
const COVER_ICON_SURFACE_OFFSET: float = 0.55
const COVER_ICON_EDGE_OFFSET_RATIO: float = 0.40
const COVER_ICON_PIXEL_SIZE: float = 0.003

@export var map_definition: TacticalMapDefinition
@export var cover_combat_settings: CoverCombatSettings

@export_group("Enemy Action Pacing")
@export var enemy_aim_duration: float = 0.35
@export var enemy_post_attack_delay: float = 0.35
@export var enemy_attack_interval: float = 0.8
@export var enemy_move_interval: float = 0.3
@export var enemy_switch_interval: float = 0.4

@export_group("Audio SFX")
@export var discover_sfx: AudioStream = preload("res://assets/audio/sfx/discover.wav")

var grid: GridModel
var _environment_root: Node3D
var turn_manager: TurnManager
var action_executor: ActionExecutor
var definition_registry: GameDefinitionRegistry
var runtime_instance_registry: RuntimeInstanceRegistry
var instance_id_generator: InstanceIdGenerator
var item_instance_factory: ItemInstanceFactory
var unit_instance_factory: UnitInstanceFactory
var environment_object_factory: EnvironmentObjectFactory
var tactical_undo_manager: TacticalUndoManager
var last_action_result: ActionResult
var last_cover_query: CoverQueryResult
var last_cover_damage: Dictionary = {}
var session_manager
var squad_inventory
var loot_settlement
var selected_unit: PrototypeUnit
var units_by_id: Dictionary = {}
var enemy_alerts: Dictionary = {}
var enemy_patrols: Dictionary = {}
var encounter_by_unit: Dictionary = {}
var encounter_members: Dictionary = {}
var resolved_encounters: Dictionary = {}
var all_player_ids: Array[StringName] = []
var all_enemy_ids: Array[StringName] = []
var active_encounter_id: StringName = &""
var discovering_enemy_ids: Array[StringName] = []
var suspicious_investigations: Dictionary = {}
var opaque_cells: Dictionary = {}
var object_placements: Dictionary = {}
var environment_objects_by_placement_id: Dictionary = {}
var environment_objects_by_instance_id: Dictionary = {}
var environment_views_by_placement_id: Dictionary = {}
var environment_visuals_by_placement_id: Dictionary = {}
var loot_nodes_by_id: Dictionary = {}
var loot_containers: Dictionary = {}
var extraction_cells: Array[Vector3i] = []
var open_loot_container_id: StringName = &""
var world_tick := 0
var input_locked := false
var debug_reveal_all := false
var show_enemy_vision := false
var action_mode: int = ACTION_MODE_MOVE
const VISION_BLOCK_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const ENEMY_OUTER_VISION_COLOR := Color(0.95, 0.75, 0.15, 0.22)
const ENEMY_INNER_VISION_COLOR := Color(0.95, 0.22, 0.22, 0.35)
const ENEMY_VISION_COLOR := ENEMY_OUTER_VISION_COLOR
var inventory_body_collapsed := true
var _restore_inventory_after_loot := false
var _runtime_content_ready := false
var _undo_restoring := false
var _hover_cursor: MeshInstance3D = null
var _hovered_cell: Vector3i = Vector3i(-1, -1, -1)
var _cursor_indicators_root: Node3D = null
var _cursor_mesh_pool: Array[MeshInstance3D] = []
var _cover_indicators_root: Node3D = null
var _cover_icon_pool: Array[Sprite3D] = []
var _unit_cover_indicators_root: Node3D = null
var _unit_cover_icon_pool: Array[Sprite3D] = []
## Shared, lazily-built highlight resources so whole-map overlay rebuilds reuse
## one Mesh + one Material per color instead of allocating per cell, which
## otherwise exhausts the D3D12 RESOURCES descriptor heap on large maps.
var _highlight_mesh_cache: Dictionary = {}
var _highlight_material_cache: Dictionary = {}
## Keep the collapsed panel below the top-left status panel. The main scene
## reserves a compact panel there; the runtime top follows the status panel's
## actual content height. Expanded height is calculated from visible content.
const INVENTORY_PANEL_LAYOUT_GAP := 10.0
const INVENTORY_PANEL_COLLAPSED_HEIGHT := 56.0
## This is the intrinsic height of the authored inventory body at the fixed
## HUD width. Do not derive it from PanelContainer.get_combined_minimum_size():
## once the panel is assigned this height, that outer minimum can include the
## assigned size and feed back into an ever-growing rectangle.
const INVENTORY_PANEL_EXPANDED_HEIGHT := 410.0
var _inventory_layout_sync_queued := false

@onready var units_root: Node3D = $Units
@onready var camera_rig: TacticalCameraRig = $TacticalCameraRig
@onready var highlights_root: Node3D = $MoveHighlights
@onready var attack_highlights_root: Node3D = $AttackHighlights
@onready var object_highlights_root: Node3D = $ObjectHighlights
@onready var vision_highlights_root: Node3D = $VisionHighlights
@onready var audio_discover: AudioStreamPlayer = get_node_or_null("AudioDiscover") as AudioStreamPlayer
@onready var selection_label: Label = $HUD/TopLeftPanel/Margin/VBox/SelectionLabel
@onready var phase_label: Label = $HUD/TopLeftPanel/Margin/VBox/PhaseLabel
@onready var alert_label: Label = $HUD/TopLeftPanel/Margin/VBox/AlertLabel
@onready var hint_label: Label = $HUD/TopLeftPanel/Margin/VBox/HintLabel
@onready var top_left_panel: PanelContainer = $HUD/TopLeftPanel
@onready var end_turn_button: Button = $HUD/TopLeftPanel/Margin/VBox/EndTurnButton
@onready var undo_step_button: Button = $HUD/TopLeftPanel/Margin/VBox/UndoStepButton
@onready var undo_turn_button: Button = $HUD/TopLeftPanel/Margin/VBox/UndoTurnButton
@onready var action_bar: PanelContainer = $HUD/ActionBar
@onready var move_action_button: Button = $HUD/ActionBar/Margin/Buttons/MoveButton
@onready var attack_action_button: Button = $HUD/ActionBar/Margin/Buttons/AttackButton
@onready var action_bar_ap_label: Label = $HUD/ActionBar/Margin/Buttons/ApLabel
@onready var inventory_summary_label: Label = $HUD/InventoryPanel/Margin/VBox/InventorySummary
@onready var inventory_hint_label: Label = $HUD/InventoryPanel/Margin/VBox/InventoryHint
@onready var inventory_panel: PanelContainer = $HUD/InventoryPanel
@onready var inventory_collapse_button: Button = $HUD/InventoryPanel/Margin/VBox/HeaderRow/CollapseButton
@onready var inventory_grid: InventoryGridControl = $HUD/InventoryPanel/Margin/VBox/InventoryItems
@onready var loot_overview_label: Label = $HUD/InventoryPanel/Margin/VBox/LootOverview
@onready var loot_panel: PanelContainer = $HUD/LootPanel
@onready var loot_title_label: Label = $HUD/LootPanel/Margin/VBox/LootTitle
@onready var loot_grid: LootGridControl = $HUD/LootPanel/Margin/VBox/LootItems
@onready var loot_all_button: Button = $HUD/LootPanel/Margin/VBox/LootButtons/LootAllButton
@onready var loot_close_button: Button = $HUD/LootPanel/Margin/VBox/LootButtons/LootCloseButton
@onready var extraction_panel: PanelContainer = $HUD/ExtractionPanel
@onready var extraction_confirm_button: Button = $HUD/ExtractionPanel/Margin/VBox/Buttons/ConfirmButton
@onready var extraction_cancel_button: Button = $HUD/ExtractionPanel/Margin/VBox/Buttons/CancelButton
@onready var result_panel: PanelContainer = $HUD/ResultPanel
@onready var result_title_label: Label = $HUD/ResultPanel/Margin/VBox/ResultTitle
@onready var result_items_label: Label = $HUD/ResultPanel/Margin/VBox/ResultItems
@onready var result_value_label: Label = $HUD/ResultPanel/Margin/VBox/ResultValue
@onready var restart_button: Button = $HUD/ResultPanel/Margin/VBox/RestartButton


func _load_authoring_scene() -> void:
	if map_definition == null or map_definition.authoring_scene_path.is_empty():
		push_warning("No authoring_scene_path in map definition; skipping visual load.")
		return
	var scene_resource := load(map_definition.authoring_scene_path)
	if scene_resource == null:
		push_error("Failed to load authoring scene: %s" % map_definition.authoring_scene_path)
		return
	_environment_root = scene_resource.instantiate() as Node3D
	_environment_root.name = "Environment"
	add_child(_environment_root)
	move_child(_environment_root, 0)


func _ready() -> void:
	grid = GridModel.new()
	if map_definition == null:
		push_error("PrototypeController requires a valid TacticalMapDefinition.")
		return
	_load_authoring_scene()
	if not grid.configure_from_definition(map_definition):
		push_error("Failed to configure grid from map definition.")
		return
	_apply_camera_bounds()
	_configure_runtime_instances()
	if cover_combat_settings == null:
		cover_combat_settings = CoverCombatSettingsScript.load_default()
	session_manager = GameStateManagerScript.new()
	_configure_action_executor()
	squad_inventory = SquadInventoryScript.new(
		SquadInventoryScript.DEFAULT_WIDTH,
		SquadInventoryScript.DEFAULT_HEIGHT,
		&"squad_inventory",
		item_instance_factory
	)
	loot_settlement = null
	session_manager.state_changed.connect(_on_session_state_changed)
	session_manager.result_changed.connect(_on_session_result_changed)
	_index_map_objects()
	_apply_map_rules()
	_spawn_initial_units()
	_configure_encounter_models()
	_configure_inventory_ui()
	session_manager.start_exploration()
	_configure_undo_manager()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	if is_instance_valid(undo_step_button):
		undo_step_button.pressed.connect(_on_undo_step_pressed)
	if is_instance_valid(undo_turn_button):
		undo_turn_button.pressed.connect(_on_undo_turn_pressed)
	move_action_button.pressed.connect(_on_move_action_pressed)
	attack_action_button.pressed.connect(_on_attack_action_pressed)
	loot_all_button.pressed.connect(_on_loot_all_button_pressed)
	loot_close_button.pressed.connect(_close_loot_panel)
	extraction_confirm_button.pressed.connect(_on_extraction_confirm_pressed)
	extraction_cancel_button.pressed.connect(_on_extraction_cancel_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	_update_enemy_visibility()
	var player_cells := map_definition.get_player_spawn_cells()
	if not player_cells.is_empty():
		_select_unit(_find_player_at(player_cells[0]))
	_evaluate_detection()
	_init_hover_cursor()
	_update_hud("探索中：用底部按钮切换移动/攻击；移动模式看蓝格，攻击模式看红格。")


func _configure_inventory_ui() -> void:
	if is_instance_valid(inventory_grid):
		inventory_grid.configure(squad_inventory, Callable(self, "preview_inventory_command"), Callable(self, "handle_inventory_command"))
	if is_instance_valid(loot_grid):
		loot_grid.configure(
			Callable(self, "_place_loot_first_fit"),
			Callable(self, "_place_loot_first_fit"),
			Callable(self, "return_inventory_instance_to_loot"),
			Callable(self, "_can_return_inventory_instance_to_loot")
		)


func _configure_action_executor() -> void:
	action_executor = ActionExecutorScript.new()
	action_executor.register_handler(ACTION_MOVE, Callable(self, "_handle_move_action"))
	action_executor.register_handler(ACTION_ATTACK, Callable(self, "_handle_attack_action"))
	action_executor.register_handler(ACTION_INTERACT, Callable(self, "_handle_interact_action"))
	action_executor.register_handler(ACTION_LOOT, Callable(self, "_handle_loot_action"))


func _configure_undo_manager() -> void:
	tactical_undo_manager = TacticalUndoManagerScript.new()
	if not tactical_undo_manager.configure(
		Callable(self, "_capture_undo_state"),
		Callable(self, "_restore_undo_state")
	):
		push_error("Failed to configure TacticalUndoManager callbacks.")
		tactical_undo_manager = null
		return
	tactical_undo_manager.availability_changed.connect(_on_undo_availability_changed)
	# The first exploration state is the first player-operable turn.
	_capture_undo_turn_checkpoint()
	_refresh_undo_buttons()


func _should_track_player_action(actor: PrototypeUnit) -> bool:
	if tactical_undo_manager == null or _undo_restoring or not is_instance_valid(actor):
		return false
	if actor.faction != &"player" or session_manager == null or not session_manager.is_active():
		return false
	var state: int = session_manager.get_state()
	return state == GameStateManagerScript.State.EXPLORATION \
		or (state == GameStateManagerScript.State.COMBAT \
		and turn_manager != null and turn_manager.is_player_turn())


func _begin_undo_player_action(actor: PrototypeUnit) -> bool:
	if not _should_track_player_action(actor):
		return false
	return tactical_undo_manager.begin_player_action()


func _finish_undo_player_action(started: bool, succeeded: bool) -> void:
	if not started or tactical_undo_manager == null:
		return
	if succeeded:
		if not tactical_undo_manager.commit_player_action():
			# The gameplay mutation has already passed the executor's synchronous
			# commit point.  This should only be reachable for a broken manager
			# lifecycle, so surface it instead of silently replacing a checkpoint.
			push_error("TacticalUndoManager failed to commit a successful player action.")
	else:
		tactical_undo_manager.cancel_player_action()


func _can_undo_in_current_context() -> bool:
	if _undo_restoring or input_locked or session_manager == null or not session_manager.is_active():
		return false
	if turn_manager == null:
		return false
	var state: int = session_manager.get_state()
	if state == GameStateManagerScript.State.EXPLORATION:
		return turn_manager.get_phase() == TurnManager.Phase.EXPLORATION
	if state == GameStateManagerScript.State.COMBAT:
		return turn_manager.is_player_turn()
	# EXTRACTION and RESULT are intentionally not undoable.
	return false


func _refresh_undo_buttons() -> void:
	var context_allowed := _can_undo_in_current_context()
	if tactical_undo_manager != null:
		tactical_undo_manager.set_locked(not context_allowed)
	var can_step := context_allowed and tactical_undo_manager != null and tactical_undo_manager.can_undo_step()
	var can_turn := context_allowed and tactical_undo_manager != null and tactical_undo_manager.can_undo_turn()
	if is_instance_valid(undo_step_button):
		undo_step_button.disabled = not can_step
	if is_instance_valid(undo_turn_button):
		undo_turn_button.disabled = not can_turn


func _on_undo_availability_changed(_can_step: bool = false, _can_turn: bool = false) -> void:
	_refresh_undo_buttons()


func _capture_undo_turn_checkpoint() -> bool:
	if tactical_undo_manager == null or _undo_restoring:
		return false
	# A phase callback can arrive immediately after enemy input is released;
	# refresh the temporary lock before asking the core manager to capture.
	_refresh_undo_buttons()
	return tactical_undo_manager.capture_turn_checkpoint()


func _on_undo_step_pressed() -> void:
	_perform_undo(false)


func _on_undo_turn_pressed() -> void:
	_perform_undo(true)


func _perform_undo(to_turn: bool) -> void:
	if tactical_undo_manager == null or not _can_undo_in_current_context():
		return
	if (to_turn and not tactical_undo_manager.can_undo_turn()) \
		or (not to_turn and not tactical_undo_manager.can_undo_step()):
		return
	_undo_restoring = true
	input_locked = true
	_clear_highlights()
	_hide_hover_cursor()
	var restored := tactical_undo_manager.undo_turn() if to_turn else tactical_undo_manager.undo_step()
	_undo_restoring = false
	input_locked = false
	_refresh_undo_buttons()
	if not restored:
		_update_hud("撤回失败，当前状态未改变。")
		return
	_post_undo_restore()
	_update_hud("已撤回至回合开始状态。" if to_turn else "已撤回上一步。")


func _post_undo_restore() -> void:
	# Panels and feedback are presentation state, never part of the domain
	# checkpoint.  Close all transient interaction surfaces before rebuilding.
	if is_instance_valid(loot_panel):
		loot_panel.visible = false
	if is_instance_valid(extraction_panel):
		extraction_panel.visible = false
	if is_instance_valid(result_panel):
		result_panel.visible = false
	open_loot_container_id = &""
	_restore_inventory_after_loot = false
	if is_instance_valid(loot_grid):
		loot_grid.clear_container()
	if is_instance_valid(inventory_panel):
		_set_inventory_body_collapsed(true)
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if not is_instance_valid(unit):
			continue
		unit.set_selected(false)
		if unit.is_attack_feedback_playing:
			unit.call("_interrupt_attack_feedback")
		else:
			unit.call("_reset_attack_feedback_visuals")
	var restored_selection := selected_unit
	if is_instance_valid(restored_selection):
		restored_selection.set_selected(true)
	_update_enemy_visibility()
	_refresh_inventory_ui()
	_refresh_highlights()


func _configure_runtime_instances() -> void:
	definition_registry = GameDefinitionRegistryScript.new()
	var manifest = load("res://resources/content/game_content_manifest.tres")
	_runtime_content_ready = false
	if manifest != null:
		var registry_result: Dictionary = definition_registry.configure(manifest)
		_runtime_content_ready = bool(registry_result.get(&"valid", false))
		if not _runtime_content_ready:
			push_warning("Game content manifest is not fully valid; the runtime factory will reject unresolved definitions.")
	else:
		push_warning("Game content manifest is unavailable; runtime unit creation will be rejected.")
	runtime_instance_registry = RuntimeInstanceRegistryScript.new()
	var map_token := StringName(String(map_definition.map_id).strip_edges())
	if map_token.is_empty():
		map_token = &"prototype"
	instance_id_generator = InstanceIdGeneratorScript.new(StringName("prototype_%s" % map_token))
	# ItemInstanceFactory receives the shared definition/identity dependencies;
	# its constructor is kept adjacent to the runtime setup so inventory and all
	# Loot containers cannot accidentally create a second factory or ID stream.
	item_instance_factory = ItemInstanceFactoryScript.new(
		instance_id_generator,
		definition_registry,
		runtime_instance_registry
	)
	unit_instance_factory = UnitInstanceFactoryScript.new(
		definition_registry,
		runtime_instance_registry,
		instance_id_generator
	)
	environment_object_factory = EnvironmentObjectFactoryScript.new(
		definition_registry,
		runtime_instance_registry,
		instance_id_generator
	)


func _execute_runtime_action(request: Variant, actor: PrototypeUnit = null) -> ActionResult:
	if action_executor == null or request == null:
		last_action_result = ActionResultScript.rejected(&"invalid_request")
		return last_action_result
	var undo_started := _begin_undo_player_action(actor)
	var current_ap := actor.current_action_points if is_instance_valid(actor) else 0
	var context = ActionExecutionContextScript.new(current_ap)
	if is_instance_valid(actor):
		var ap_committer := Callable(actor, "spend_action_points")
		# An explosive object may synchronously kill the attacking unit before
		# the executor reaches its post-handler AP commit.  Still call the same
		# unit API; a dead actor has no future AP to spend, so that terminal
		# commit is considered complete instead of turning a resolved explosion
		# into an ap_commit_failed result.
		if request is ActionRequest and request.action_type == ACTION_ATTACK \
			and request.payload.get(&"environment_object", null) != null:
			ap_committer = Callable(self, "_commit_environment_action_points").bind(actor)
		context.set_ap_committer(ap_committer)
	last_action_result = action_executor.execute(request, context)
	_finish_undo_player_action(undo_started, last_action_result != null and last_action_result.success)
	_refresh_undo_buttons()
	return last_action_result


func _commit_environment_action_points(cost: int, actor: PrototypeUnit) -> bool:
	if not is_instance_valid(actor):
		return false
	var committed := actor.spend_action_points(cost)
	return committed or not actor.is_alive()


## The undo manager stores this detached-by-convention dictionary.  Runtime
## state, item instances and Nodes are retained by identity, while every
## mutable value needed to restore them is copied as scalar/vector data.  No
## visual transform is treated as authoritative.
func _capture_undo_state() -> Dictionary:
	var unit_entries: Array[Dictionary] = []
	var occupancy: Array[Dictionary] = []
	var unit_keys: Array = units_by_id.keys()
	unit_keys.sort_custom(func(first: Variant, second: Variant) -> bool:
		return String(first) < String(second)
	)
	for raw_unit_id in unit_keys:
		var unit := units_by_id[raw_unit_id] as PrototypeUnit
		if not is_instance_valid(unit):
			continue
		var state := unit.runtime_state
		var state_snapshot: Variant = state.to_snapshot() if state != null else null
		var unit_entry: Dictionary = {
			&"unit": unit,
			&"runtime_state": state,
			&"state_snapshot": state_snapshot,
			&"archetype": state.archetype if state != null else unit.archetype,
			&"weapon_instance": state.weapon_instance if state != null else null,
			&"unit_id": unit.unit_id,
			&"visual_color": unit.visual_color,
			&"visible": unit.visible,
			&"process_mode": unit.process_mode,
			&"legacy_cell": unit.grid_cell,
			&"legacy_faction": unit.faction,
			&"legacy_hp": unit.current_hp,
			&"legacy_ap": unit.current_action_points,
		}
		unit_entries.append(unit_entry)
		if unit.is_alive():
			occupancy.append({&"cell": unit.grid_cell, &"unit_id": unit.unit_id})
	var selected_id: StringName = selected_unit.unit_id if is_instance_valid(selected_unit) else &""
	var turn_snapshot: Dictionary = turn_manager.capture_state() if turn_manager != null else {}
	var session_snapshot: Dictionary = session_manager.capture_state() \
		if session_manager != null and session_manager.has_method("capture_state") else {}
	return {
		&"schema_version": 1,
		&"units": unit_entries,
		&"grid_occupancy": occupancy,
		&"turn": turn_snapshot,
		&"session": session_snapshot,
		&"world_tick": world_tick,
		&"enemy_alerts": _capture_undo_alerts(),
		&"enemy_patrols": _capture_undo_patrols(),
		&"encounter_by_unit": encounter_by_unit.duplicate(true),
		&"encounter_members": encounter_members.duplicate(true),
		&"resolved_encounters": resolved_encounters.duplicate(true),
		&"all_player_ids": all_player_ids.duplicate(),
		&"all_enemy_ids": all_enemy_ids.duplicate(),
		&"active_encounter_id": active_encounter_id,
		&"discovering_enemy_ids": discovering_enemy_ids.duplicate(),
		&"suspicious_investigations": suspicious_investigations.duplicate(true),
		&"environment_objects": _capture_undo_environment_objects(),
		&"inventory": _capture_undo_inventory(),
		&"instance_id_generator": instance_id_generator.capture_state() \
			if instance_id_generator != null and instance_id_generator.has_method("capture_state") else {},
		&"loot_settlement": loot_settlement,
		&"selected_unit_id": selected_id,
		&"open_loot_container_id": open_loot_container_id,
		&"restore_inventory_after_loot": _restore_inventory_after_loot,
	}


func _capture_undo_environment_objects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var placement_ids: Array = environment_objects_by_placement_id.keys()
	placement_ids.sort_custom(func(first: Variant, second: Variant) -> bool:
		return String(first) < String(second)
	)
	for raw_placement_id in placement_ids:
		var state := environment_objects_by_placement_id[raw_placement_id] as EnvironmentObjectRuntimeState
		if state == null:
			continue
		result.append({
			&"placement_id": StringName(raw_placement_id),
			&"state": state,
			&"snapshot": state.to_snapshot(),
		})
	return result


func _capture_undo_inventory() -> Dictionary:
	var result: Dictionary = {
		&"present": squad_inventory != null,
		&"width": 0,
		&"height": 0,
		&"inventory_id": &"",
		&"placements": [],
		&"containers": [],
	}
	if squad_inventory != null:
		result[&"width"] = squad_inventory.width
		result[&"height"] = squad_inventory.height
		result[&"inventory_id"] = squad_inventory.inventory_id
		var placement_entries: Array[Dictionary] = []
		for placement in squad_inventory.get_placements():
			if placement == null or placement.instance == null:
				continue
			placement_entries.append({
				&"instance": placement.instance,
				&"anchor": placement.anchor,
				&"rotation": placement.rotation,
			})
		result[&"placements"] = placement_entries
	var container_entries: Array[Dictionary] = []
	var container_ids: Array = loot_containers.keys()
	container_ids.sort_custom(func(first: Variant, second: Variant) -> bool:
		return String(first) < String(second)
	)
	for raw_container_id in container_ids:
		var container = loot_containers[raw_container_id]
		if container == null:
			continue
		container_entries.append({
			&"container": container,
			&"container_id": StringName(raw_container_id),
			&"items": container.get_contents_instances(),
			&"opened": container.is_opened(),
			&"depleted": container.is_depleted(),
		})
	result[&"containers"] = container_entries
	return result


func _capture_undo_alerts() -> Dictionary:
	var result: Dictionary = {}
	for raw_unit_id in enemy_alerts.keys():
		var alert := enemy_alerts[raw_unit_id] as AlertState
		if alert == null:
			continue
		result[raw_unit_id] = {
			&"instance": alert,
			&"level": int(alert.get_level()),
			&"target_id": alert.get_target_id(),
			&"last_known_cell": alert.get_last_known_cell(),
		}
	return result


func _capture_undo_patrols() -> Dictionary:
	var result: Dictionary = {}
	for raw_unit_id in enemy_patrols.keys():
		var route := enemy_patrols[raw_unit_id] as PatrolRoute
		if route == null:
			continue
		result[raw_unit_id] = {
			&"instance": route,
			&"points": route._points.duplicate(),
			&"current_index": route._current_index,
			&"direction": route._direction,
			&"loop": route._loop,
		}
	return result


func _restore_undo_state(checkpoint: Variant) -> bool:
	if not checkpoint is Dictionary:
		return false
	# A failed restore must leave the live state usable.  Checkpoints generated
	# by this controller are valid, but retaining a rollback makes a later core
	# schema/API mismatch fail atomically from the player's point of view.
	var rollback := _capture_undo_state()
	_undo_restoring = true
	var restored := _restore_undo_state_internal(checkpoint as Dictionary)
	if not restored:
		_restore_undo_state_internal(rollback)
		_undo_restoring = false
		return false
	_undo_restoring = false
	return restored


func _restore_undo_state_internal(checkpoint: Dictionary) -> bool:
	if int(checkpoint.get(&"schema_version", -1)) != 1:
		return false
	var raw_units: Variant = checkpoint.get(&"units", null)
	if not raw_units is Array:
		return false
	var old_unit_ids: Array = units_by_id.keys()
	var restored_units: Dictionary = {}
	# Release every currently equipped runtime weapon before hydrating the
	# checkpoint.  This makes restoration order-independent when a valid action
	# has swapped two externally-created WeaponInstances between units.
	for current_unit_value in units_by_id.values():
		var current_unit := current_unit_value as PrototypeUnit
		if not is_instance_valid(current_unit) or current_unit.runtime_state == null:
			continue
		if current_unit.runtime_state.weapon_instance != null \
			and not current_unit.runtime_state.unequip():
			return false
	for raw_entry in raw_units:
		if not raw_entry is Dictionary:
			return false
		var entry: Dictionary = raw_entry
		var unit := entry.get(&"unit") as PrototypeUnit
		if not is_instance_valid(unit):
			return false
		var state := entry.get(&"runtime_state") as UnitRuntimeState
		if state != null:
			var archetype := entry.get(&"archetype") as UnitArchetype
			var weapon_instance := entry.get(&"weapon_instance") as WeaponInstance
			if not state.hydrate_from_snapshot(entry.get(&"state_snapshot"), archetype, weapon_instance):
				return false
			unit.visual_color = entry.get(&"visual_color", unit.visual_color)
			if unit.runtime_state != state:
				if not unit.bind_runtime_state(state, unit.visual_color):
					return false
			elif unit.is_node_ready():
				unit.call("_apply_weapon_stats")
				unit.call("_refresh_weapon_model")
				unit.call("_capture_feedback_rest_pose")
				unit.call("_apply_visual_color")
				unit.call("_update_status_label")
				unit.call("_update_alert_badge")
		else:
			# Compatibility-only unbound views are restored through their public
			# adapter properties and never manufacture a runtime identity.
			if unit.runtime_state != null:
				unit.unbind_runtime_state()
			unit.grid_cell = entry.get(&"legacy_cell", unit.grid_cell)
			unit.faction = entry.get(&"legacy_faction", unit.faction)
			unit.current_hp = int(entry.get(&"legacy_hp", unit.current_hp))
			unit.current_action_points = int(entry.get(&"legacy_ap", unit.current_action_points))
			unit.visual_color = entry.get(&"visual_color", unit.visual_color)
		var unit_id := unit.unit_id
		if unit_id == &"":
			unit_id = StringName(entry.get(&"unit_id", &""))
		if unit_id == &"":
			return false
		restored_units[unit_id] = unit
		unit.set_selected(false)
		if unit.is_attack_feedback_playing:
			unit.call("_interrupt_attack_feedback")
		else:
			unit.call("_reset_attack_feedback_visuals")
		unit.visible = bool(entry.get(&"visible", unit.is_alive())) if unit.is_alive() else false
		unit.process_mode = int(entry.get(&"process_mode", Node.PROCESS_MODE_INHERIT)) \
			if unit.is_alive() else Node.PROCESS_MODE_DISABLED
		if grid != null:
			unit.global_position = grid.cell_to_world(unit.grid_cell)
	units_by_id = restored_units

	var player_ids: Variant = _coerce_undo_id_array(checkpoint.get(&"all_player_ids", null))
	var enemy_ids: Variant = _coerce_undo_id_array(checkpoint.get(&"all_enemy_ids", null))
	var discovering_ids: Variant = _coerce_undo_id_array(checkpoint.get(&"discovering_enemy_ids", null))
	if player_ids == null or enemy_ids == null or discovering_ids == null:
		return false
	all_player_ids = player_ids
	all_enemy_ids = enemy_ids
	discovering_enemy_ids = discovering_ids
	encounter_by_unit = (checkpoint.get(&"encounter_by_unit", {}) as Dictionary).duplicate(true)
	encounter_members = (checkpoint.get(&"encounter_members", {}) as Dictionary).duplicate(true)
	resolved_encounters = (checkpoint.get(&"resolved_encounters", {}) as Dictionary).duplicate(true)
	suspicious_investigations = (checkpoint.get(&"suspicious_investigations", {}) as Dictionary).duplicate(true)
	var active_raw: Variant = checkpoint.get(&"active_encounter_id", &"")
	active_encounter_id = StringName(active_raw) if active_raw is String or active_raw is StringName else &""
	world_tick = int(checkpoint.get(&"world_tick", 0))

	if not _restore_undo_alerts(checkpoint.get(&"enemy_alerts", null)):
		return false
	if not _restore_undo_patrols(checkpoint.get(&"enemy_patrols", null)):
		return false

	if grid != null:
		var ids_to_release: Dictionary = {}
		for raw_id in old_unit_ids:
			ids_to_release[StringName(raw_id)] = true
		for raw_id in units_by_id.keys():
			ids_to_release[StringName(raw_id)] = true
		for raw_id in all_player_ids:
			ids_to_release[raw_id] = true
		for raw_id in all_enemy_ids:
			ids_to_release[raw_id] = true
		for raw_id in ids_to_release.keys():
			grid.release_occupant(StringName(raw_id))
		var raw_occupancy: Variant = checkpoint.get(&"grid_occupancy", null)
		if not raw_occupancy is Array:
			return false
		for raw_occupant in raw_occupancy:
			if not raw_occupant is Dictionary:
				return false
			var occupant: Dictionary = raw_occupant
			var cell: Variant = occupant.get(&"cell", null)
			var occupant_id: Variant = occupant.get(&"unit_id", null)
			if not cell is Vector3i or not (occupant_id is StringName or occupant_id is String):
				return false
			if not grid.occupy(cell, StringName(occupant_id)):
				return false

	if not _restore_undo_environment_objects(checkpoint.get(&"environment_objects", [])):
		return false
	_rebuild_dynamic_environment_rules()

	if not _restore_undo_inventory(checkpoint.get(&"inventory", null)):
		return false
	var generator_snapshot: Variant = checkpoint.get(&"instance_id_generator", {})
	if instance_id_generator != null and instance_id_generator.has_method("restore_state"):
		if not generator_snapshot is Dictionary or not instance_id_generator.restore_state(generator_snapshot):
			return false
	if turn_manager != null:
		var turn_snapshot: Variant = checkpoint.get(&"turn", null)
		if not turn_snapshot is Dictionary or not turn_manager.restore_state(turn_snapshot):
			return false
	if session_manager != null and session_manager.has_method("restore_state"):
		var session_snapshot: Variant = checkpoint.get(&"session", null)
		if not session_snapshot is Dictionary or not session_manager.restore_state(session_snapshot):
			return false

	var selected_raw: Variant = checkpoint.get(&"selected_unit_id", &"")
	var selected_id := StringName(selected_raw) if selected_raw is String or selected_raw is StringName else &""
	selected_unit = _unit_by_id(selected_id)
	if not is_instance_valid(selected_unit) or selected_unit.faction != &"player" or not selected_unit.is_alive():
		selected_unit = null
	else:
		selected_unit.set_selected(true)
	open_loot_container_id = StringName(checkpoint.get(&"open_loot_container_id", &""))
	_restore_inventory_after_loot = bool(checkpoint.get(&"restore_inventory_after_loot", false))
	loot_settlement = checkpoint.get(&"loot_settlement", null)
	last_action_result = null
	last_cover_query = null
	last_cover_damage.clear()
	return true


func _restore_undo_environment_objects(raw_objects: Variant) -> bool:
	if not raw_objects is Array:
		return false
	var seen: Dictionary = {}
	for raw_entry in raw_objects:
		if not raw_entry is Dictionary:
			return false
		var entry: Dictionary = raw_entry
		var raw_placement_id: Variant = entry.get(&"placement_id", null)
		if not (raw_placement_id is StringName or raw_placement_id is String):
			return false
		var placement_id := StringName(raw_placement_id)
		if placement_id.is_empty() or seen.has(placement_id):
			return false
		seen[placement_id] = true
		var state := environment_objects_by_placement_id.get(placement_id) as EnvironmentObjectRuntimeState
		var snapshot: Variant = entry.get(&"snapshot", null)
		if state == null or not state.hydrate_from_snapshot(snapshot, state.definition):
			return false
		var captured_state := entry.get(&"state") as EnvironmentObjectRuntimeState
		if captured_state != null and captured_state != state:
			return false
		_sync_environment_object_views()
	return true


func _restore_undo_alerts(raw_alerts: Variant) -> bool:
	if not raw_alerts is Dictionary:
		return false
	enemy_alerts.clear()
	for raw_unit_id in raw_alerts.keys():
		var entry: Variant = raw_alerts[raw_unit_id]
		if not entry is Dictionary:
			return false
		var alert := (entry as Dictionary).get(&"instance") as AlertState
		if alert == null:
			alert = AlertState.new()
		alert._level = int((entry as Dictionary).get(&"level", AlertState.Level.UNAWARE))
		alert._target_id = StringName((entry as Dictionary).get(&"target_id", &""))
		var cell: Variant = (entry as Dictionary).get(&"last_known_cell", AlertState.INVALID_CELL)
		if not cell is Vector3i:
			return false
		alert._last_known_cell = cell
		enemy_alerts[StringName(raw_unit_id)] = alert
	return true


func _restore_undo_patrols(raw_patrols: Variant) -> bool:
	if not raw_patrols is Dictionary:
		return false
	enemy_patrols.clear()
	for raw_unit_id in raw_patrols.keys():
		var entry: Variant = raw_patrols[raw_unit_id]
		if not entry is Dictionary:
			return false
		var route := (entry as Dictionary).get(&"instance") as PatrolRoute
		if route == null:
			return false
		var points: Array[Vector3i] = []
		var raw_points: Variant = (entry as Dictionary).get(&"points", [])
		if not raw_points is Array:
			return false
		for raw_point in raw_points:
			if not raw_point is Vector3i:
				return false
			points.append(raw_point)
		route.configure(points, bool((entry as Dictionary).get(&"loop", true)))
		if not route._points.is_empty():
			route._current_index = clampi(int((entry as Dictionary).get(&"current_index", 0)), 0, route._points.size() - 1)
		else:
			route._current_index = 0
		route._direction = -1 if int((entry as Dictionary).get(&"direction", 1)) < 0 else 1
		enemy_patrols[StringName(raw_unit_id)] = route
	return true


func _restore_undo_inventory(raw_inventory: Variant) -> bool:
	if not raw_inventory is Dictionary:
		return false
	var snapshot: Dictionary = raw_inventory
	if not bool(snapshot.get(&"present", false)):
		return squad_inventory == null
	if squad_inventory == null:
		return false
	# Release current ownership before reattaching the exact instance objects
	# captured by the checkpoint.  This avoids registry unregister/re-register
	# collisions and preserves stable item IDs.
	squad_inventory.clear()
	for raw_container_id in loot_containers.keys():
		var container = loot_containers[raw_container_id]
		if container == null:
			continue
		var owner := StringName("loot:" + String(raw_container_id))
		for item in container.get_contents_instances():
			if item != null and item.is_owned() and item.get_owner_id() == owner:
				item.release_owner(owner)
		container._items.clear()
	squad_inventory.width = int(snapshot.get(&"width", squad_inventory.width))
	squad_inventory.height = int(snapshot.get(&"height", squad_inventory.height))
	squad_inventory.inventory_id = StringName(snapshot.get(&"inventory_id", squad_inventory.inventory_id))
	var raw_placements: Variant = snapshot.get(&"placements", null)
	if not raw_placements is Array:
		return false
	for raw_placement in raw_placements:
		if not raw_placement is Dictionary:
			return false
		var placement: Dictionary = raw_placement
		var item := placement.get(&"instance") as InventoryItemInstance
		var anchor: Variant = placement.get(&"anchor", null)
		if item == null or not anchor is Vector2i:
			return false
		if not squad_inventory.place(item, anchor, int(placement.get(&"rotation", 0)), true):
			return false
	var raw_containers: Variant = snapshot.get(&"containers", null)
	if not raw_containers is Array:
		return false
	for raw_container_entry in raw_containers:
		if not raw_container_entry is Dictionary:
			return false
		var entry: Dictionary = raw_container_entry
		var container = entry.get(&"container")
		if container == null:
			container = loot_containers.get(StringName(entry.get(&"container_id", &"")))
		if container == null:
			return false
		var container_id := StringName(entry.get(&"container_id", container.container_id))
		var owner := StringName("loot:" + String(container_id))
		var raw_items: Variant = entry.get(&"items", null)
		if not raw_items is Array:
			return false
		for item in raw_items:
			if not item is InventoryItemInstance or item.is_owned() or not item.claim_owner(owner):
				return false
			container._items.append(item)
		container.opened = bool(entry.get(&"opened", false))
		container.depleted = bool(entry.get(&"depleted", false))
	return true


func _coerce_undo_id_array(raw_ids: Variant) -> Variant:
	if not raw_ids is Array:
		return null
	var result: Array[StringName] = []
	for raw_id in raw_ids:
		if not (raw_id is StringName or raw_id is String):
			return null
		var id := StringName(raw_id)
		if id == &"":
			return null
		result.append(id)
	return result


func _handle_move_action(request: Variant, _context: Variant) -> Variant:
	var payload: Dictionary = request.payload
	var unit := payload.get(&"unit") as PrototypeUnit
	var start_cell: Vector3i = payload.get(&"start_cell", Vector3i(-1, -1, -1))
	var destination: Vector3i = payload.get(&"destination", Vector3i(-1, -1, -1))
	if not is_instance_valid(unit) or start_cell == destination:
		return false
	if not grid.vacate(start_cell, unit.unit_id):
		return false
	if not grid.occupy(destination, unit.unit_id):
		grid.occupy(start_cell, unit.unit_id)
		return false
	unit.grid_cell = destination
	return true


func _handle_attack_action(request: Variant, _context: Variant) -> Variant:
	var payload: Dictionary = request.payload
	var environment_target := payload.get(&"environment_object") as EnvironmentObjectRuntimeState
	if environment_target != null:
		return _handle_environment_attack_action(request, environment_target)
	var attacker := payload.get(&"attacker") as PrototypeUnit
	var target := payload.get(&"target") as PrototypeUnit
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return false
	if payload.get(&"enter_combat", false) and not _start_combat(true, target, attacker.grid_cell, attacker.unit_id):
		return _action_rejected(&"wrong_phase", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	var accepted := ActionResultScript.accepted(request.actor_id, request.target_id, request.ap_cost, ACTION_ATTACK)
	var requested_damage := int(payload.get(ActionExecutorScript.KEY_DAMAGE, attacker.attack_damage))
	var resolved := CombatResolver.resolve_attack(accepted, target.current_hp, requested_damage)
	var cover_metadata: Variant = payload.get(&"cover_metadata", {})
	if cover_metadata is Dictionary:
		resolved.metadata = cover_metadata.duplicate(true)
	var applied := target.take_damage(resolved.damage, false)
	return resolved


func _handle_environment_attack_action(request: Variant, target: EnvironmentObjectRuntimeState) -> Variant:
	var payload: Dictionary = request.payload
	var attacker := payload.get(&"attacker") as PrototypeUnit
	if not is_instance_valid(attacker) or target == null or not target.can_receive_damage():
		return _action_rejected(&"target_unavailable", ACTION_ATTACK, request.actor_id, request.target_id)
	if target.definition == null or not target.definition.targetable or not target.definition.damageable:
		return _action_rejected(&"target_unavailable", ACTION_ATTACK, request.actor_id, request.target_id)
	var accepted := ActionResultScript.accepted(request.actor_id, request.target_id, request.ap_cost, ACTION_ATTACK)
	var requested_damage := int(payload.get(ActionExecutorScript.KEY_DAMAGE, attacker.attack_damage))
	var resolved := CombatResolver.resolve_attack(accepted, target.current_hp, requested_damage)
	var cover_metadata: Variant = payload.get(&"cover_metadata", {})
	if cover_metadata is Dictionary:
		resolved.metadata = cover_metadata.duplicate(true)
	var applied := target.apply_damage(resolved.damage)
	if not applied.success:
		return _action_rejected(&"target_unavailable", ACTION_ATTACK, request.actor_id, request.target_id)
	var destruction: Dictionary = {}
	if target.destroyed:
		destruction = _resolve_environment_destruction(target)
	else:
		var target_view := _get_environment_view(target.placement_id)
		if target_view != null:
			target_view.play_damage_feedback()
	_sync_environment_object_views()
	_rebuild_dynamic_environment_rules()
	resolved.metadata[&"environment_object_id"] = target.instance_id
	resolved.metadata[&"placement_id"] = target.placement_id
	resolved.metadata[&"remaining_hp"] = target.current_hp
	resolved.metadata[&"destroyed"] = target.destroyed
	for key in destruction.keys():
		resolved.metadata[key] = destruction[key]
	return resolved


## Applies one-shot environment effects breadth-first.  Each runtime object is
## guarded by its stable instance ID, so chain reactions cannot re-enter the
## same object or loop indefinitely.
func _resolve_environment_destruction(source: EnvironmentObjectRuntimeState) -> Dictionary:
	var summary: Dictionary = {
		&"explosion_hit_count": 0,
		&"explosion_hit_ids": [],
		&"chain_count": 0,
		&"chain_object_ids": [],
		&"unit_damage": {},
		&"destroyed_object_ids": [],
	}
	if source == null or not source.destroyed or not source.trigger_destroy_effects():
		return summary
	var destroyed_object_ids: Array = summary[&"destroyed_object_ids"]
	destroyed_object_ids.append(source.instance_id)
	var pending: Array[Dictionary] = []
	for effect_value in source.get_destroy_effects():
		if effect_value is ExplosionEffectDefinition:
			var effect := effect_value as ExplosionEffectDefinition
			if effect.is_valid():
				pending.append({
					&"source_cell": source.cell,
					&"effect": effect,
					&"allow_chain": effect.allow_chain,
				})
	var chain_guard: Dictionary = {source.instance_id: true}
	while not pending.is_empty():
		var event: Dictionary = pending.pop_front()
		var effect := event.get(&"effect") as ExplosionEffectDefinition
		var source_cell: Variant = event.get(&"source_cell", null)
		if effect == null or not source_cell is Vector3i:
			continue
		var hits := EnvironmentEffectResolverScript.resolve_area_damage(
			effect,
			source_cell,
			_environment_effect_candidates()
		)
		var hit_ids: Array = summary[&"explosion_hit_ids"]
		for hit in hits:
			var hit_id := StringName(hit.get(&"target_id", &""))
			if hit_id == &"":
				continue
			hit_ids.append(hit_id)
			var target_type := StringName(hit.get(&"target_type", &""))
			if target_type == &"player" or target_type == &"enemy":
				var unit := _unit_by_id(hit_id)
				if not is_instance_valid(unit) or not unit.is_alive():
					continue
				var damage_done := unit.take_damage(int(hit.get(&"damage", effect.damage)))
				var unit_damage: Dictionary = summary[&"unit_damage"]
				unit_damage[hit_id] = int(unit_damage.get(hit_id, 0)) + damage_done
				continue
			var environment_target := environment_objects_by_instance_id.get(hit_id) as EnvironmentObjectRuntimeState
			if environment_target == null or not environment_target.can_receive_damage():
				continue
			var damage_result := environment_target.apply_damage(int(hit.get(&"damage", effect.damage)))
			if not damage_result.success:
				continue
			if environment_target.destroyed:
				var destroyed_ids: Array = summary[&"destroyed_object_ids"]
				if not destroyed_ids.has(environment_target.instance_id):
					destroyed_ids.append(environment_target.instance_id)
				var parent_allows_chain: bool = bool(event.get(&"allow_chain", false))
				if parent_allows_chain and not chain_guard.has(environment_target.instance_id) \
					and environment_target.trigger_destroy_effects():
					chain_guard[environment_target.instance_id] = true
					var chain_ids: Array = summary[&"chain_object_ids"]
					chain_ids.append(environment_target.instance_id)
					summary[&"chain_count"] = int(summary[&"chain_count"]) + 1
					for chain_effect_value in environment_target.get_destroy_effects():
						if chain_effect_value is ExplosionEffectDefinition:
							var chain_effect := chain_effect_value as ExplosionEffectDefinition
							if chain_effect.is_valid():
								pending.append({
									&"source_cell": environment_target.cell,
									&"effect": chain_effect,
									&"allow_chain": chain_effect.allow_chain,
								})
			_sync_environment_object_views()
			_rebuild_dynamic_environment_rules()
		summary[&"explosion_hit_ids"] = hit_ids
		summary[&"explosion_hit_count"] = hit_ids.size()
	return summary


func _environment_effect_candidates() -> Array:
	var candidates: Array = []
	for player_id in _living_player_ids():
		var player := _unit_by_id(player_id)
		if is_instance_valid(player) and player.is_alive():
			candidates.append({
				&"target_id": player.unit_id,
				&"cell": player.grid_cell,
				&"target_type": &"player",
				&"active": true,
			})
	for enemy_id in _living_enemy_ids():
		var enemy := _unit_by_id(enemy_id)
		if is_instance_valid(enemy) and enemy.is_alive():
			candidates.append({
				&"target_id": enemy.unit_id,
				&"cell": enemy.grid_cell,
				&"target_type": &"enemy",
				&"active": true,
			})
	for raw_state in environment_objects_by_instance_id.values():
		var state := raw_state as EnvironmentObjectRuntimeState
		if state != null and state.active and not state.destroyed:
			candidates.append({
				&"target_id": state.instance_id,
				&"cell": state.cell,
				&"target_type": &"environment",
				&"active": true,
			})
	return candidates


func _handle_interact_action(request: Variant, _context: Variant) -> Variant:
	var operation: StringName = StringName(request.payload.get(&"operation", &""))
	match operation:
		&"loot_open":
			var container = loot_containers.get(request.target_id)
			if container == null or not container.open():
				return _action_rejected(&"container_unavailable", ACTION_INTERACT, request.actor_id, request.target_id)
			open_loot_container_id = request.target_id
			_refresh_loot_panel()
			loot_panel.visible = true
			if inventory_body_collapsed:
				_restore_inventory_after_loot = true
				_set_inventory_body_collapsed(false)
			return true
		&"extraction_prompt":
			if not session_manager.start_extraction():
				return _action_rejected(&"wrong_phase", ACTION_INTERACT, request.actor_id, request.target_id)
			extraction_panel.visible = true
			return true
		&"extraction_confirm":
			if not session_manager.confirm_extraction():
				return _action_rejected(&"wrong_phase", ACTION_INTERACT, request.actor_id, request.target_id)
			return true
	return _action_rejected(&"invalid_target", ACTION_INTERACT, request.actor_id, request.target_id)


func _handle_loot_action(request: Variant, _context: Variant) -> Variant:
	var operation: StringName = StringName(request.payload.get(&"operation", &""))
	var container = loot_containers.get(request.target_id)
	if container == null:
		return _action_rejected(&"invalid_container", ACTION_LOOT, request.actor_id, request.target_id)
	if operation == &"place_item":
		var index := int(request.payload.get(&"index", -1))
		var anchor: Vector2i = request.payload.get(&"anchor", Vector2i(-1, -1))
		var rotation := int(request.payload.get(&"rotation", 0))
		if not container.transfer_to_inventory_at(index, squad_inventory, anchor, rotation):
			return _action_rejected(&"inventory_full", ACTION_LOOT, request.actor_id, request.target_id)
		return true
	if operation == &"loot_all":
		if not container.transfer_all_to_inventory(squad_inventory):
			return _action_rejected(&"inventory_full", ACTION_LOOT, request.actor_id, request.target_id)
		return true
	return _action_rejected(&"invalid_target", ACTION_LOOT, request.actor_id, request.target_id)


func _process(_delta: float) -> void:
	if _is_cursor_visible() and not input_locked and not _is_terminal():
		var viewport := get_viewport()
		if is_instance_valid(viewport):
			_update_hover_cursor(viewport.get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if input_locked or _is_terminal():
		_hide_hover_cursor()
		return
	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		_update_hover_cursor(motion_event.position)
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_X:
				_set_debug_reveal_all(not debug_reveal_all)
				return
			elif key_event.keycode == KEY_Z:
				_set_show_enemy_vision(not show_enemy_vision)
				return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_handle_world_click(mouse_event.position)


func _set_debug_reveal_all(enabled: bool) -> void:
	debug_reveal_all = enabled
	_update_enemy_visibility()
	_refresh_highlights()


func _set_show_enemy_vision(enabled: bool) -> void:
	show_enemy_vision = enabled
	_refresh_highlights()
	_update_hud("敌人视野显示：%s。" % ("开启" if show_enemy_vision else "关闭"))


func _on_move_action_pressed() -> void:
	_set_action_mode(ACTION_MODE_MOVE)


func _on_attack_action_pressed() -> void:
	_set_action_mode(ACTION_MODE_ATTACK)


func _set_action_mode(mode: int) -> void:
	if mode != ACTION_MODE_MOVE and mode != ACTION_MODE_ATTACK:
		return
	action_mode = mode
	if action_mode != ACTION_MODE_MOVE:
		_hide_cover_preview()
	elif is_instance_valid(grid) and grid.has_cell(_hovered_cell) and _is_cursor_visible():
		_update_cover_preview(_hovered_cell)
	_refresh_highlights()
	_update_hud("行动模式：移动。" if mode == ACTION_MODE_MOVE else "行动模式：攻击。")

func _index_map_objects() -> void:
	object_placements.clear()
	environment_objects_by_placement_id.clear()
	environment_objects_by_instance_id.clear()
	environment_views_by_placement_id.clear()
	environment_visuals_by_placement_id.clear()
	loot_nodes_by_id.clear()
	loot_containers.clear()
	extraction_cells.clear()
	_index_loot_visual_nodes()
	for placement in map_definition.objects:
		if placement == null or placement.object_id == &"":
			continue
		object_placements[placement.object_id] = placement
		if placement.kind == MapObjectPlacement.Kind.EXTRACTION:
			if not extraction_cells.has(placement.cell):
				extraction_cells.append(placement.cell)
		elif placement.kind == MapObjectPlacement.Kind.LOOT:
			if not _runtime_content_ready:
				push_error("Loot placement %s skipped: Game content manifest is invalid or unavailable." % placement.object_id)
				continue
			var table = _placement_property(placement, &"loot_table")
			if table == null:
				push_warning("Loot placement %s has no loot_table; container skipped." % placement.object_id)
				continue
			var seed := int(_placement_property(placement, &"loot_seed", -1))
			var container := LootContainerScript.new(item_instance_factory)
			if table != null and container.initialize(placement.object_id, table, seed, null, item_instance_factory):
				loot_containers[placement.object_id] = container
			else:
				push_warning("Loot placement %s has an invalid loot_table; container skipped." % placement.object_id)
		else:
			if not _runtime_content_ready or environment_object_factory == null:
				push_error("Environment placement %s skipped: Game content manifest is invalid or unavailable." % placement.object_id)
				continue
			var creation := environment_object_factory.create_from_placement_result(placement, _runtime_map_id())
			if not creation.success:
				push_warning("Environment placement %s skipped: %s (%s)." % [
					placement.object_id, creation.message, creation.reason_code
				])
				continue
			var environment_state := creation.value as EnvironmentObjectRuntimeState
			if environment_state == null:
				push_warning("Environment placement %s skipped: factory returned no runtime state." % placement.object_id)
				continue
			environment_objects_by_placement_id[placement.object_id] = environment_state
			environment_objects_by_instance_id[environment_state.instance_id] = environment_state
	_index_environment_visual_nodes()
	_sync_environment_object_views()


func _index_loot_visual_nodes() -> void:
	var environment := get_node_or_null("Environment")
	if not is_instance_valid(environment):
		return
	var pending: Array[Node] = [environment]
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		if node is MapObjectMarker3D:
			var marker := node as MapObjectMarker3D
			if marker.kind == MapObjectPlacement.Kind.LOOT and marker.object_id != &"":
				loot_nodes_by_id[marker.object_id] = marker
		for child in node.get_children():
			pending.append(child)


func _index_environment_visual_nodes() -> void:
	var environment := get_node_or_null("Environment")
	if not is_instance_valid(environment):
		return
	var pending: Array[Node] = [environment]
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		if node is MapObjectMarker3D:
			var marker := node as MapObjectMarker3D
			var placement_id := marker.object_id
			if environment_objects_by_placement_id.has(placement_id):
				var visual := _find_environment_view(node)
				if visual != null and (not is_instance_valid(visual) \
					or visual.is_queued_for_deletion() or not visual.is_inside_tree()):
					visual = null
				if visual == null:
					var placement := object_placements.get(placement_id) as MapObjectPlacement
					if placement != null and placement.scene != null:
						var instance := placement.scene.instantiate()
						if instance is Node3D:
							var instance_node := instance as Node3D
							if is_instance_valid(instance_node) and not instance_node.is_queued_for_deletion():
								instance_node.name = "_RuntimeEnvironmentView"
								node.add_child(instance_node)
								if is_instance_valid(instance_node) and not instance_node.is_queued_for_deletion() \
									and instance_node.is_inside_tree():
									visual = instance_node
								else:
									instance_node.free()
							else:
								if is_instance_valid(instance):
									instance.free()
						else:
							# PackedScene roots are not guaranteed to be Node3D.  Free
							# that temporary immediately so preview fallback cannot leak.
							if instance != null:
								instance.free()
				var raw_visual: Variant = visual
				if is_instance_valid(raw_visual) and raw_visual is Node3D:
					var stable_visual := raw_visual as Node3D
					if not stable_visual.is_queued_for_deletion() and stable_visual.is_inside_tree():
						environment_visuals_by_placement_id[placement_id] = stable_visual
						var raw_view: Variant = stable_visual
						if is_instance_valid(raw_view) and raw_view is EnvironmentObjectView:
							var typed_view := raw_view as EnvironmentObjectView
							if not typed_view.is_queued_for_deletion() and typed_view.is_inside_tree():
								environment_views_by_placement_id[placement_id] = typed_view
		for child in node.get_children():
			pending.append(child)


func _find_environment_view(root: Node) -> Node3D:
	if not is_instance_valid(root):
		return null
	if root is EnvironmentObjectView:
		var raw_view: Variant = root
		if not is_instance_valid(raw_view) or not raw_view is EnvironmentObjectView:
			return null
		var view := raw_view as EnvironmentObjectView
		if view.is_queued_for_deletion() or not view.is_inside_tree():
			return null
		return view
	for child in root.get_children():
		var found := _find_environment_view(child)
		if found != null:
			return found
	return null


func _get_environment_view(placement_id: StringName) -> EnvironmentObjectView:
	var raw_view: Variant = environment_views_by_placement_id.get(placement_id, null)
	if not is_instance_valid(raw_view):
		environment_views_by_placement_id.erase(placement_id)
		return null
	if not raw_view is EnvironmentObjectView:
		environment_views_by_placement_id.erase(placement_id)
		return null
	var view := raw_view as EnvironmentObjectView
	if view.is_queued_for_deletion() or not view.is_inside_tree():
		environment_views_by_placement_id.erase(placement_id)
		return null
	return view


func _get_environment_visual(placement_id: StringName) -> Node3D:
	var raw_visual: Variant = environment_visuals_by_placement_id.get(placement_id, null)
	if not is_instance_valid(raw_visual):
		environment_visuals_by_placement_id.erase(placement_id)
		return null
	if not raw_visual is Node3D:
		environment_visuals_by_placement_id.erase(placement_id)
		return null
	var visual := raw_visual as Node3D
	if visual.is_queued_for_deletion() or not visual.is_inside_tree():
		environment_visuals_by_placement_id.erase(placement_id)
		return null
	return visual


func _sync_environment_object_views() -> void:
	var needs_reindex := false
	for raw_placement_id in environment_objects_by_placement_id.keys():
		var placement_id := StringName(raw_placement_id)
		if _get_environment_view(placement_id) == null and _get_environment_visual(placement_id) == null:
			needs_reindex = true
			break
	if needs_reindex:
		_index_environment_visual_nodes()
	for raw_placement_id in environment_objects_by_placement_id.keys():
		var placement_id := StringName(raw_placement_id)
		var state := environment_objects_by_placement_id[raw_placement_id] as EnvironmentObjectRuntimeState
		var typed_view := _get_environment_view(placement_id)
		if typed_view != null:
			typed_view.sync_from_runtime_state(state)
		else:
			var visual := _get_environment_visual(placement_id)
			if visual != null:
				visual.visible = state != null and state.active and not state.destroyed


func _runtime_map_id() -> StringName:
	if map_definition == null:
		return &"prototype"
	var result := StringName(String(map_definition.map_id).strip_edges())
	return result if not result.is_empty() else &"prototype"


func _placement_has_property(placement: Object, property_name: StringName) -> bool:
	for property_info in placement.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			return true
	return false


func _placement_property(placement: Object, property_name: StringName, default_value: Variant = null) -> Variant:
	if _placement_has_property(placement, property_name):
		return placement.get(property_name)
	return placement.get_meta(property_name, default_value)


func _apply_camera_bounds() -> void:
	if not is_instance_valid(camera_rig):
		return
	var bounds_min := Vector2(map_definition.origin.x, map_definition.origin.z)
	var bounds_max := bounds_min + Vector2(
		float(map_definition.footprint_size.x) * map_definition.cell_size.x,
		float(map_definition.footprint_size.y) * map_definition.cell_size.z
	)
	camera_rig.set_map_bounds(bounds_min, bounds_max)


func _apply_map_rules() -> void:
	_rebuild_dynamic_environment_rules()


## Rebuilds only the dynamic overlay on top of the baked cell rules.  Destroying
## an environment object therefore removes its own blocker while preserving
## the authored floor, structure and any other live object at that cell.
func _rebuild_dynamic_environment_rules() -> void:
	if map_definition == null or grid == null:
		return
	var base_walkable: Dictionary = {}
	var base_los: Dictionary = {}
	var base_projectile: Dictionary = {}
	for cell_data in map_definition.cells:
		if cell_data == null:
			continue
		var cell: Vector3i = cell_data.coordinate
		var blocks_los := cell_data.blocks_los or cell_data.sight_block >= 1.0
		var blocks_projectile := cell_data.projectile_block >= 1.0
		base_walkable[cell] = cell_data.walkable
		base_los[cell] = blocks_los
		base_projectile[cell] = blocks_projectile
		grid.set_walkable(cell, cell_data.walkable)
		grid.set_cell_blockers(cell, blocks_los, blocks_projectile)

	opaque_cells.clear()
	for cell in base_los.keys():
		if base_los[cell]:
			opaque_cells[cell] = true
	for raw_placement_id in object_placements.keys():
		var placement := object_placements[raw_placement_id] as MapObjectPlacement
		if placement == null or placement.kind == MapObjectPlacement.Kind.LOOT \
			or placement.kind == MapObjectPlacement.Kind.EXTRACTION:
			continue
		var placement_id := StringName(raw_placement_id)
		var environment_state := environment_objects_by_placement_id.get(placement_id) as EnvironmentObjectRuntimeState
		var active := true
		var blocks_movement := placement.blocks_movement
		var blocks_los := placement.blocks_los
		if environment_state != null:
			active = environment_state.active and not environment_state.destroyed
			if environment_state.definition != null:
				blocks_movement = environment_state.definition.blocks_movement
				blocks_los = environment_state.definition.blocks_los
		if not active:
			continue
		if blocks_movement:
			base_walkable[placement.cell] = false
			if not grid.is_occupied(placement.cell):
				grid.set_walkable(placement.cell, false)
		if blocks_los:
			base_los[placement.cell] = true
			opaque_cells[placement.cell] = true
	# Re-apply combined line blockers after all object overlays are known.  The
	# two channels are intentionally independent: a projectile-only object does
	# not become opaque to perception.
	for cell in base_los.keys():
		grid.set_cell_blockers(cell, bool(base_los[cell]), bool(base_projectile.get(cell, false)))


func _spawn_initial_units() -> void:
	for index in map_definition.spawns.size():
		var spawn: MapSpawnData = map_definition.spawns[index]
		_spawn_unit_from_spawn(spawn, index)


func _spawn_unit(unit_name: StringName, cell: Vector3i, faction: StringName, color: Color, archetype: UnitArchetype = null, weapon: WeaponDefinition = null) -> PrototypeUnit:
	# Compatibility entry for callers that still provide the legacy argument
	# list.  It still goes through the same Factory and never derives an ID
	# from a Node/Object instance ID.
	var spawn := MapSpawnData.new()
	spawn.spawn_id = StringName("compat_%s" % String(unit_name))
	spawn.unit_name = unit_name
	spawn.cell = cell
	spawn.faction = faction
	spawn.visual_color = color
	spawn.archetype = archetype
	spawn.weapon = weapon
	return _spawn_unit_from_spawn(spawn, -1)


func _spawn_unit_from_spawn(spawn: MapSpawnData, legacy_index: int = -1) -> PrototypeUnit:
	if unit_instance_factory == null or spawn == null:
		push_error("Cannot spawn a unit without UnitInstanceFactory and MapSpawnData.")
		return null
	var map_id := StringName(String(map_definition.map_id).strip_edges())
	if map_id.is_empty():
		map_id = &"prototype"
	var creation := unit_instance_factory.create_from_spawn_result(spawn, map_id, legacy_index)
	if not creation.success:
		push_error("Failed to create unit '%s': %s (%s)" % [spawn.unit_name, creation.message, creation.reason_code])
		return null
	var state := creation.value as UnitRuntimeState
	if state == null:
		push_error("Unit factory returned no UnitRuntimeState for '%s'." % spawn.unit_name)
		return null
	var color := spawn.visual_color
	if color == Color.WHITE:
		color = PLAYER_COLOR if spawn.faction == &"player" else ENEMY_COLOR
	var unit := UNIT_SCENE.instantiate() as PrototypeUnit
	if unit == null or not unit.bind_runtime_state(state, color):
		_rollback_runtime_unit(state)
		push_error("Failed to bind runtime state for unit '%s'." % spawn.unit_name)
		return null
	unit.name = spawn.unit_name if not spawn.unit_name.is_empty() else StringName("Unit_%d" % legacy_index)
	units_root.add_child(unit)
	unit.global_position = grid.cell_to_world(state.cell)
	unit.action_points_changed.connect(_on_unit_state_changed)
	unit.health_changed.connect(_on_unit_state_changed)
	unit.died.connect(_on_unit_died)
	if not grid.occupy(state.cell, state.instance_id):
		_rollback_runtime_unit(state)
		unit.queue_free()
		push_error("Failed to occupy %s for %s" % [state.cell, unit.name])
		return null
	units_by_id[unit.unit_id] = unit
	return unit


func _rollback_runtime_unit(state: UnitRuntimeState) -> void:
	if state == null or runtime_instance_registry == null:
		return
	runtime_instance_registry.unregister(state.instance_id)
	if state.weapon_instance_id != &"":
		runtime_instance_registry.unregister(state.weapon_instance_id)


func _configure_encounter_models() -> void:
	var player_ids: Array[StringName] = []
	var enemy_ids: Array[StringName] = []
	all_player_ids.clear()
	all_enemy_ids.clear()
	encounter_by_unit.clear()
	encounter_members.clear()
	resolved_encounters.clear()
	active_encounter_id = &""
	discovering_enemy_ids.clear()
	suspicious_investigations.clear()
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == &"player":
			player_ids.append(unit.unit_id)
			all_player_ids.append(unit.unit_id)
		else:
			enemy_ids.append(unit.unit_id)
			all_enemy_ids.append(unit.unit_id)
	turn_manager = TurnManager.new()
	# Exploration has no active enemy roster. A detection or proactive attack
	# loads exactly one encounter group into TurnManager.
	turn_manager.configure(player_ids, [])
	turn_manager.phase_changed.connect(_on_phase_changed)
	for enemy_id in enemy_ids:
		enemy_alerts[enemy_id] = AlertState.new()
	for spawn in map_definition.spawns:
		if spawn.faction != &"enemy":
			continue
		var enemy := _unit_by_name(spawn.unit_name)
		var encounter_id := spawn.encounter_id if not spawn.encounter_id.is_empty() else &"default"
		if is_instance_valid(enemy):
			encounter_by_unit[enemy.unit_id] = encounter_id
			if not encounter_members.has(encounter_id):
				encounter_members[encounter_id] = []
			(encounter_members[encounter_id] as Array).append(enemy.unit_id)
		if spawn.patrol_route_id == &"":
			continue
		var route_data := map_definition.find_patrol_route(spawn.patrol_route_id)
		if is_instance_valid(enemy) and route_data != null:
			var route := PatrolRoute.new()
			route.configure(route_data.points, route_data.loop)
			enemy_patrols[enemy.unit_id] = route


func _living_player_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for unit_id in all_player_ids:
		var unit := _unit_by_id(unit_id)
		if is_instance_valid(unit) and unit.is_alive():
			result.append(unit_id)
	return result


func _living_enemy_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for unit_id in all_enemy_ids:
		var unit := _unit_by_id(unit_id)
		if is_instance_valid(unit) and unit.is_alive():
			result.append(unit_id)
	return result


func _enemy_ids_for_context() -> Array[StringName]:
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.COMBAT:
		return turn_manager.get_enemy_ids()
	return _living_enemy_ids()


func _activate_encounter_for(alert_enemy: PrototypeUnit) -> bool:
	if not is_instance_valid(alert_enemy):
		return false
	var encounter_id: StringName = encounter_by_unit.get(alert_enemy.unit_id, &"default")
	if encounter_id.is_empty() or resolved_encounters.has(encounter_id):
		return false
	var group_ids: Array[StringName] = []
	for enemy_id in encounter_members.get(encounter_id, []):
		var enemy := _unit_by_id(enemy_id)
		if is_instance_valid(enemy) and enemy.is_alive():
			group_ids.append(enemy_id)
	if group_ids.is_empty():
		return false
	turn_manager.configure(_living_player_ids(), group_ids)
	active_encounter_id = encounter_id
	return true


func _handle_world_click(screen_position: Vector2) -> void:
	if not _player_can_act():
		_update_hud("当前不是玩家行动阶段。")
		return
	var clicked_cell := _screen_to_cell(screen_position)
	if not grid.in_bounds(clicked_cell):
		_update_hud("点击位置在地图范围外。")
		return
	await _handle_cell_click(clicked_cell)


## Stable cell-level input entry used by both the world raycast and tests.
## Unit selection and object handling happen before movement so an extraction
## cell can be approached and confirmed through the same click path.
func _handle_cell_click(clicked_cell: Vector3i) -> void:
	if input_locked or not grid.in_bounds(clicked_cell) or not _player_can_act():
		return
	var clicked_player := _find_player_at(clicked_cell)
	if is_instance_valid(clicked_player):
		_select_unit(clicked_player)
		var extraction_id := _extraction_at_cell(clicked_cell)
		if extraction_id != &"":
			begin_extraction_prompt(extraction_id)
		else:
			_update_hud("已选择 %s。" % clicked_player.name)
		return
	var clicked_enemy := _find_enemy_at(clicked_cell)
	if is_instance_valid(clicked_enemy):
		if action_mode == ACTION_MODE_ATTACK and _can_attack_target(clicked_enemy):
			await _attack_with_unit(selected_unit, clicked_enemy)
		elif action_mode == ACTION_MODE_ATTACK:
			_select_unit(clicked_enemy, true)
			_update_hud("已选择 %s（敌方单位，仅侦察）。" % clicked_enemy.name)
		else:
			_select_unit(clicked_enemy, true)
			_update_hud("已选择 %s（敌方单位，仅侦察）。" % clicked_enemy.name)
		return
	var environment_target := _environment_object_at_cell(clicked_cell)
	if environment_target != null:
		if action_mode == ACTION_MODE_ATTACK:
			await attack_environment_object(selected_unit, environment_target)
		else:
			_update_hud("该环境对象只能在攻击模式下选中。")
		return
	var object_id := _object_at_cell(clicked_cell)
	if object_id != &"":
		var placement = object_placements.get(object_id)
		if placement != null and placement.kind == MapObjectPlacement.Kind.LOOT:
			interact_with_loot(object_id)
			return
		if placement != null and placement.kind == MapObjectPlacement.Kind.EXTRACTION:
			if is_instance_valid(selected_unit) and selected_unit.grid_cell == clicked_cell:
				begin_extraction_prompt(object_id)
				return
			var moved := await _try_move_selected(clicked_cell)
			if moved and is_instance_valid(selected_unit) and selected_unit.grid_cell == clicked_cell and session_manager.get_state() == GameStateManagerScript.State.EXPLORATION:
				begin_extraction_prompt(object_id)
			return
	if action_mode != ACTION_MODE_MOVE:
		_select_unit(null)
		_update_hud("左键选择/移动；底部按钮切换移动/攻击；WASD 平移；滚轮缩放；X切换Debug视野。")
		return
	# Only a highlighted (reachable) tile moves the unit; clicking any other
	# tile cancels the current selection instead of issuing a stray move.
	# The reachability gate mirrors the move-highlight gate (AP affordability),
	# so a selection with no AP left always deselects on any tile click.
	var can_move := is_instance_valid(selected_unit) \
		and selected_unit.faction == &"player" \
		and selected_unit.is_alive() \
		and selected_unit.can_spend_action_points(MOVE_ACTION_COST)
	var reachable_cells: Array[Vector3i] = []
	if can_move:
		reachable_cells = grid.get_reachable_cells(selected_unit.grid_cell, selected_unit.move_range)
	if can_move and reachable_cells.has(clicked_cell):
		await _try_move_selected(clicked_cell)
	else:
		_select_unit(null)
		_update_hud("左键选择/移动；底部按钮切换移动/攻击；WASD 平移；滚轮缩放；X切换Debug视野。")


## Stable integration entry for UI/tests. Opening a Loot container is a
## one-AP Interact; ActionExecutor validation runs before the open handler.
func interact_with_loot(container_id: StringName) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", &"interact")
	var container = loot_containers.get(container_id)
	var placement = object_placements.get(container_id)
	var player := selected_unit
	var actor_id: StringName = player.unit_id if is_instance_valid(player) else &""
	var actor_cell: Vector3i = player.grid_cell if is_instance_valid(player) else Vector3i(-1, -1, -1)
	var target_cell: Vector3i = placement.cell if placement != null else Vector3i(-1, -1, -1)
	var request := ActionRequestScript.new(
		ACTION_INTERACT,
		actor_id,
		container_id,
		LOOT_OPEN_ACTION_COST,
		{
			&"operation": &"loot_open",
			ActionExecutorScript.KEY_ACTOR_CELL: actor_cell,
			ActionExecutorScript.KEY_TARGET_CELL: target_cell,
			ActionExecutorScript.KEY_INTERACTION_RANGE: INTERACTION_RANGE,
			ActionExecutorScript.KEY_TARGET_VALID: container != null and placement != null and _is_loot_visible(container_id),
			ActionExecutorScript.KEY_TARGET_AVAILABLE: container != null and not container.is_depleted(),
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		if result.reason == &"target_unavailable" or result.reason == &"container_unavailable":
			_update_hud("Loot 箱已耗尽，不能重复搜刮。")
		else:
			_update_hud(_action_message("无法交互", result.reason))
		return result
	_update_hud("已打开 %s（消耗 1 AP），可单项或全部拾取。" % container_id)
	_log("打开 Loot 箱 %s（消耗 1 AP，%d 件）。" % [container_id, container.get_item_count()])
	_refresh_highlights()
	return result


func interact_with_object(object_id: StringName) -> ActionResult:
	var placement = object_placements.get(object_id)
	if placement == null:
		return _action_rejected(&"invalid_target", ACTION_INTERACT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", object_id)
	if placement.kind == MapObjectPlacement.Kind.LOOT:
		return interact_with_loot(object_id)
	if placement.kind == MapObjectPlacement.Kind.EXTRACTION:
		return begin_extraction_prompt(object_id)
	return _action_rejected(&"invalid_target", ACTION_INTERACT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", object_id)


func loot_item(index: int) -> ActionResult:
	var container = loot_containers.get(open_loot_container_id)
	if container == null:
		return _action_rejected(&"invalid_container", ACTION_LOOT)
	var item: InventoryItemInstance = container.get_item(index)
	if item == null or squad_inventory == null:
		return _action_rejected(&"invalid_target", ACTION_LOOT)
	var allow_owned := _is_current_loot_item(open_loot_container_id, index, item)
	var anchor: Vector2i = squad_inventory.find_first_fit(item, -1, allow_owned)
	if anchor == SquadInventoryScript.NO_FIT:
		_update_hud("空间碎片：背包总空格可能足够，但该形状没有连续合法位置。")
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", open_loot_container_id)
	return place_loot_instance(open_loot_container_id, index, anchor, 0)


func loot_all() -> ActionResult:
	return _loot_all(open_loot_container_id)


## Stable 2D inventory command entry points.  UI drag/drop and tests both use
## these methods; no UI path mutates the core models directly.
func preview_inventory_command(
		container_id: StringName,
		index: int,
		instance_id: StringName,
		anchor: Vector2i,
		rotation: int,
		source_kind: StringName
	) -> Dictionary:
	var cells: Array[Vector2i] = []
	var valid := false
	if not _can_use_loot_action():
		return {"valid": false, "cells": cells, "reason": &"wrong_phase"}
	if source_kind == &"loot":
		if container_id != open_loot_container_id:
			return {"valid": false, "cells": cells, "reason": &"invalid_container"}
		var container = loot_containers.get(container_id)
		var item = container.get_item(index) if container != null else null
		if container == null or not container.is_opened() or container.is_depleted() or item == null or item.instance_id != instance_id:
			return {"valid": false, "cells": cells, "reason": &"invalid_target"}
		if item != null:
			var allow_owned := _is_current_loot_item(container_id, index, item)
			valid = squad_inventory.can_place(item, anchor, rotation, allow_owned)
			cells = _instance_cells(item, anchor, rotation)
	elif source_kind == &"inventory":
		var placement = squad_inventory.get_placement(instance_id)
		if placement != null and placement.instance != null:
			valid = squad_inventory.can_move(instance_id, anchor, rotation)
			cells = _instance_cells(placement.instance, anchor, rotation)
	else:
		return {"valid": false, "cells": cells, "reason": &"invalid_target"}
	return {"valid": valid, "cells": cells, "reason": &"accepted" if valid else &"inventory_full"}


func handle_inventory_command(command: Dictionary) -> Variant:
	var command_type := StringName(command.get("type", &""))
	match command_type:
		&"place_loot":
			return place_loot_instance(
				StringName(command.get("container_id", &"")),
				int(command.get("index", -1)),
				command.get("anchor", Vector2i(-1, -1)),
				int(command.get("rotation", 0))
			)
		&"move_inventory":
			return move_inventory_instance(
				StringName(command.get("instance_id", &"")),
				command.get("anchor", Vector2i(-1, -1)),
				int(command.get("rotation", -1))
			)
		&"rotate_inventory":
			return rotate_inventory_instance(StringName(command.get("instance_id", &"")))
	return _action_rejected(&"invalid_target", &"loot")


func place_loot_instance(container_id: StringName, index: int, anchor: Vector2i, rotation: int = 0) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	var container = loot_containers.get(container_id)
	var placement = object_placements.get(container_id)
	var player := selected_unit
	var item = container.get_item(index) if container != null else null
	var allow_owned := _is_current_loot_item(container_id, index, item)
	var can_receive: bool = allow_owned and squad_inventory != null and squad_inventory.can_place(item, anchor, rotation, allow_owned)
	var request := ActionRequestScript.new(
		ACTION_LOOT,
		player.unit_id,
		container_id,
		LOOT_ACTION_COST,
		{
			&"operation": &"place_item",
			&"index": index,
			&"anchor": anchor,
			&"rotation": rotation,
			ActionExecutorScript.KEY_ACTOR_CELL: player.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: placement.cell if placement != null else Vector3i(-1, -1, -1),
			ActionExecutorScript.KEY_INTERACTION_RANGE: INTERACTION_RANGE,
			ActionExecutorScript.KEY_CONTAINER_VALID: container != null and placement != null and container_id == open_loot_container_id and item != null,
			ActionExecutorScript.KEY_CONTAINER_AVAILABLE: container != null and not container.is_depleted(),
			ActionExecutorScript.KEY_INVENTORY_CAN_RECEIVE: can_receive,
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		if result.reason == &"inventory_full":
			_update_hud("空间碎片或位置冲突：该物品无法放在目标格，Loot 与 AP 未改变。")
		else:
			_update_hud(_action_message("无法放置 Loot", result.reason))
		return result
	_refresh_inventory_ui()
	_update_hud("已将 %s 放入背包（不消耗 AP）。" % item.display_name)
	_log("拾取 %s 放入背包（不消耗 AP）。" % item.display_name)
	_refresh_highlights()
	return result


func move_inventory_instance(instance_id: StringName, anchor: Vector2i, rotation: int = -1) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	var undo_started := _begin_undo_player_action(selected_unit)
	if squad_inventory == null or squad_inventory.get_placement(instance_id) == null:
		_finish_undo_player_action(undo_started, false)
		return _action_rejected(&"invalid_target", ACTION_LOOT, selected_unit.unit_id, instance_id)
	if not squad_inventory.can_move(instance_id, anchor, rotation):
		_finish_undo_player_action(undo_started, false)
		_update_hud("背包位置无效：越界、重叠或形状无法放置。")
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id, instance_id)
	if not squad_inventory.move(instance_id, anchor, rotation):
		_finish_undo_player_action(undo_started, false)
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id, instance_id)
	_finish_undo_player_action(undo_started, true)
	_refresh_inventory_ui()
	_update_hud("已重新排列背包物品。")
	return ActionResultScript.accepted(selected_unit.unit_id, instance_id, 0, ACTION_LOOT)


func rotate_inventory_instance(instance_id: StringName) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	var undo_started := _begin_undo_player_action(selected_unit)
	var placement = squad_inventory.get_placement(instance_id) if squad_inventory != null else null
	if placement == null:
		_finish_undo_player_action(undo_started, false)
		return _action_rejected(&"invalid_target", ACTION_LOOT, selected_unit.unit_id, instance_id)
	if not squad_inventory.can_rotate(instance_id, placement.rotation + 90):
		_finish_undo_player_action(undo_started, false)
		_update_hud("旋转后形状与边界/其他物品冲突。")
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id, instance_id)
	if not squad_inventory.rotate_by(instance_id, 90):
		_finish_undo_player_action(undo_started, false)
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id, instance_id)
	_finish_undo_player_action(undo_started, true)
	_refresh_inventory_ui()
	_update_hud("已旋转物品 90°。")
	return ActionResultScript.accepted(selected_unit.unit_id, instance_id, 0, ACTION_LOOT)


func return_inventory_instance_to_loot(instance_id: StringName, container_id: StringName) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	var undo_started := _begin_undo_player_action(selected_unit)
	var container = loot_containers.get(container_id)
	if container == null or container_id != open_loot_container_id:
		_finish_undo_player_action(undo_started, false)
		return _action_rejected(&"invalid_container", ACTION_LOOT, selected_unit.unit_id, container_id)
	if not container.transfer_from_inventory(instance_id, squad_inventory):
		_finish_undo_player_action(undo_started, false)
		_update_hud("无法将物品放回当前 Loot 箱。")
		return _action_rejected(&"invalid_target", ACTION_LOOT, selected_unit.unit_id, container_id)
	_finish_undo_player_action(undo_started, true)
	if is_instance_valid(loot_grid):
		loot_grid.clear_pending_rotation(instance_id)
	_refresh_inventory_ui()
	_update_hud("已将物品放回 Loot；背包管理不消耗 AP。")
	_log("将 %s 放回 Loot 箱 %s。" % [instance_id, container_id])
	_refresh_highlights()
	return ActionResultScript.accepted(selected_unit.unit_id, container_id, 0, ACTION_LOOT)


func _can_return_inventory_instance_to_loot(instance_id: StringName, container_id: StringName) -> bool:
	return _can_use_loot_action() and container_id == open_loot_container_id \
		and loot_containers.get(container_id) != null \
		and squad_inventory != null and squad_inventory.get_placement(instance_id) != null


func _place_loot_first_fit(container_id: StringName, index: int, rotation: int = -1) -> ActionResult:
	var container = loot_containers.get(container_id)
	var item = container.get_item(index) if container != null else null
	if item == null or squad_inventory == null:
		return _action_rejected(&"invalid_target", ACTION_LOOT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", container_id)
	var allow_owned := _is_current_loot_item(container_id, index, item)
	var anchor: Vector2i = squad_inventory.find_first_fit(item, rotation, allow_owned)
	if anchor == SquadInventoryScript.NO_FIT:
		_update_hud("空间碎片：没有可容纳该形状的连续空间。")
		return _action_rejected(&"inventory_full", ACTION_LOOT, selected_unit.unit_id if is_instance_valid(selected_unit) else &"", container_id)
	return place_loot_instance(container_id, index, anchor, rotation)


func _instance_cells(item: InventoryItemInstance, anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if item == null or item.definition == null:
		return cells
	for relative_cell in item.definition.get_rotated_cells(rotation):
		cells.append(anchor + relative_cell)
	return cells


func _refresh_inventory_ui() -> void:
	if is_instance_valid(inventory_grid):
		inventory_grid.refresh()
	if is_instance_valid(loot_grid):
		loot_grid.refresh()


func begin_extraction_prompt(extraction_id: StringName = &"") -> ActionResult:
	if not _can_use_exploration_action():
		return _action_rejected(&"wrong_phase", ACTION_INTERACT)
	# The prompt itself is a zero-cost Interact, but a player with no AP cannot
	# complete the required one-AP confirmation, so do not open a dead-end panel.
	if selected_unit.current_action_points < INTERACT_ACTION_COST:
		_update_hud("无法开始撤离：AP 不足。")
		return _action_rejected(&"no_ap", ACTION_INTERACT, selected_unit.unit_id, extraction_id)
	var target_id := extraction_id if extraction_id != &"" else _extraction_at_cell(selected_unit.grid_cell if is_instance_valid(selected_unit) else Vector3i(-1, -1, -1))
	var placement = object_placements.get(target_id)
	var player := selected_unit
	var request := ActionRequestScript.new(
		ACTION_INTERACT,
		player.unit_id,
		target_id,
		0,
		{
			&"operation": &"extraction_prompt",
			ActionExecutorScript.KEY_ACTOR_CELL: player.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: placement.cell if placement != null else Vector3i(-1, -1, -1),
			ActionExecutorScript.KEY_INTERACTION_RANGE: 0,
			ActionExecutorScript.KEY_TARGET_VALID: placement != null and placement.kind == MapObjectPlacement.Kind.EXTRACTION,
			ActionExecutorScript.KEY_TARGET_AVAILABLE: true,
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		_update_hud(_action_message("无法开始撤离", result.reason))
		return result
	_update_hud("已进入撤离确认，请确认或取消。")
	_log("%s 请求在 %s 撤离。" % [player.name, target_id])
	_refresh_highlights()
	return result


func confirm_extraction() -> ActionResult:
	if session_manager == null or session_manager.get_state() != GameStateManagerScript.State.EXTRACTION:
		return _action_rejected(&"wrong_phase", ACTION_INTERACT)
	var player := selected_unit
	var target_id := _extraction_at_cell(player.grid_cell if is_instance_valid(player) else Vector3i(-1, -1, -1))
	var placement = object_placements.get(target_id)
	if not is_instance_valid(player):
		return _action_rejected(&"invalid_target", ACTION_INTERACT)
	var request := ActionRequestScript.new(
		ACTION_INTERACT,
		player.unit_id,
		target_id,
		INTERACT_ACTION_COST,
		{
			&"operation": &"extraction_confirm",
			ActionExecutorScript.KEY_ACTOR_CELL: player.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: placement.cell if placement != null else Vector3i(-1, -1, -1),
			ActionExecutorScript.KEY_INTERACTION_RANGE: 0,
			ActionExecutorScript.KEY_TARGET_VALID: placement != null and placement.kind == MapObjectPlacement.Kind.EXTRACTION,
			ActionExecutorScript.KEY_TARGET_AVAILABLE: true,
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		_update_hud(_action_message("无法确认撤离", result.reason))
		return result
	_log("确认撤离：%s 从 %s 撤离。" % [player.name, target_id])
	return result


func cancel_extraction() -> bool:
	if session_manager == null or not session_manager.cancel_extraction():
		return false
	extraction_panel.visible = false
	_update_hud("已取消撤离，可继续探索。")
	_log("取消撤离，继续探索。")
	_refresh_highlights()
	return true


func _try_move_selected(destination: Vector3i) -> bool:
	if not is_instance_valid(selected_unit) or selected_unit.faction != &"player" or not selected_unit.is_alive():
		_update_hud("请先选择一个蓝色单位。")
		return false
	var path := grid.find_path(selected_unit.grid_cell, destination)
	var moved := await _move_unit(selected_unit, destination, path, MOVE_ACTION_COST)
	_evaluate_detection()
	return moved


func _move_selected_unit(destination: Vector3i) -> void:
	await _try_move_selected(destination)


func _move_unit(unit: PrototypeUnit, destination: Vector3i, path: Array[Vector3i], ap_cost: int) -> bool:
	if not is_instance_valid(unit) or path.size() < 2:
		return false
	var start_cell := unit.grid_cell
	var actor_id := unit.unit_id
	var target_id := StringName("cell_%d_%d_%d" % [destination.x, destination.y, destination.z])
	var request := ActionRequestScript.new(
		ACTION_MOVE,
		actor_id,
		target_id,
		ap_cost,
		{
			ActionExecutorScript.KEY_PATH: path,
			ActionExecutorScript.KEY_PATH_LENGTH: maxi(grid.get_path_cost(path), 0),
			ActionExecutorScript.KEY_MAX_DISTANCE: unit.move_range,
			ActionExecutorScript.KEY_DESTINATION_AVAILABLE: grid.is_walkable(destination) and not grid.is_occupied(destination),
			&"unit": unit,
			&"start_cell": start_cell,
			&"destination": destination,
		}
	)
	var previous_input_locked := input_locked
	input_locked = true
	end_turn_button.disabled = true
	_clear_highlights()
	var result := _execute_runtime_action(request, unit)
	if not result.success:
		input_locked = previous_input_locked
		_refresh_undo_buttons()
		_refresh_highlights()
		_update_hud("无法移动：%s。" % result.reason)
		return false
	var world_points: Array[Vector3] = []
	for index in range(1, path.size()):
		world_points.append(grid.cell_to_world(path[index]))
	await unit.move_along_world_path(world_points, destination)
	input_locked = previous_input_locked
	_refresh_undo_buttons()
	_update_enemy_visibility()
	_refresh_highlights()
	_update_hud("%s 移动到 %s，消耗 %d AP。" % [unit.name, destination, ap_cost])
	_log("%s 移动 %s → %s（消耗 %d AP）。" % [unit.name, start_cell, destination, ap_cost])
	return true


func _attack_with_unit(attacker: PrototypeUnit, target: PrototypeUnit) -> ActionResult:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return _action_rejected(&"invalid_target", ACTION_ATTACK)
	if _is_terminal() or session_manager == null:
		return _action_rejected(&"terminal", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION and attacker.faction != &"player":
		return _action_rejected(&"wrong_phase", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	if turn_manager.is_player_turn() and attacker.faction != &"player":
		return _action_rejected(&"wrong_phase", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	if turn_manager.is_enemy_turn() and attacker.faction != &"enemy":
		return _action_rejected(&"wrong_phase", ACTION_ATTACK, attacker.unit_id, target.unit_id)
	var cover_query := query_attack_cover(attacker.grid_cell, target.grid_cell)
	last_cover_query = cover_query
	var cover_damage := CoverResolverScript.resolve_damage(
		attacker.attack_damage,
		cover_query.profile,
		cover_combat_settings,
		cover_query.source_edge
	)
	var cover_summary := CoverResolverScript.build_debug_summary(cover_query, cover_damage)
	cover_damage[&"cover_debug_summary"] = cover_summary
	last_cover_damage = cover_damage.duplicate(true)
	var has_los := cover_query.can_attack()
	var request := ActionRequestScript.new(
		ACTION_ATTACK,
		attacker.unit_id,
		target.unit_id,
		attacker.attack_ap_cost,
		{
			&"attacker": attacker,
			&"target": target,
			&"enter_combat": turn_manager.get_phase() == TurnManager.Phase.EXPLORATION,
			ActionExecutorScript.KEY_ACTOR_CELL: attacker.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: target.grid_cell,
			ActionExecutorScript.KEY_ATTACK_RANGE: attacker.attack_range,
			ActionExecutorScript.KEY_TARGET_ALIVE: target.is_alive(),
			ActionExecutorScript.KEY_HOSTILE: attacker.faction != target.faction,
			ActionExecutorScript.KEY_HAS_LOS: has_los,
			ActionExecutorScript.KEY_DAMAGE: int(cover_damage.get(&"effective_damage", attacker.attack_damage)),
			&"cover_metadata": cover_damage,
		}
	)
	var previous_input_locked := input_locked
	input_locked = true
	end_turn_button.disabled = true
	_clear_highlights()
	var result := _execute_runtime_action(request, attacker)
	if not result.success:
		# Preserve the executor's stable ActionResult.reason.  Cover-specific
		# diagnostics are presentation metadata, not a second action taxonomy.
		result.metadata = cover_damage.duplicate(true)
		input_locked = previous_input_locked
		_refresh_undo_buttons()
		_refresh_highlights()
		if cover_query.is_blocked():
			var block_reason: StringName = StringName(cover_summary.get(&"block_reason", result.reason))
			_update_hud(_action_message("无法攻击", block_reason))
			_log("%s 攻击 %s 被阻挡：%s；%s" % [
				attacker.name,
				target.name,
				_action_message("原因", block_reason).trim_suffix("。"),
				CoverResolverScript.format_debug_summary(cover_summary),
			])
		else:
			_update_hud(_action_message("无法攻击", result.reason))
		return result
	result.metadata = cover_damage.duplicate(true)
	var applied := result.damage
	attacker.look_at_cell(target.grid_cell)
	if attacker.faction == &"enemy" and enemy_aim_duration > 0.0 and is_inside_tree():
		await get_tree().create_timer(enemy_aim_duration).timeout
	if result.killed and is_instance_valid(target):
		target.visible = true

	var is_step_out := cover_query.is_step_out and is_instance_valid(grid)
	if is_step_out:
		var step_world_pos := grid.cell_to_world(cover_query.step_out_cell)
		var peek_pos := attacker.global_position.lerp(step_world_pos, 0.75)
		await attacker.step_out_to(peek_pos, 0.15)

	var on_impact := func() -> void:
		if is_instance_valid(target) and applied > 0:
			if result.killed:
				target.play_death_sound()
				target.visible = false
			else:
				target.play_hit_sound()
	_schedule_attack_impact(on_impact)
	await attacker.play_attack_feedback()

	if is_step_out:
		await attacker.step_back(0.15)

	if attacker.faction == &"enemy" and enemy_post_attack_delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(enemy_post_attack_delay).timeout
	input_locked = previous_input_locked
	_refresh_undo_buttons()
	var cover_level_name := String(cover_summary.get(&"cover_level_name", &"NONE"))
	var reduction_percent := int(cover_summary.get(&"damage_reduction_percent", 0))
	var step_out_note := "（探出射击）" if cover_query.is_step_out else ""
	if bool(cover_summary.get(&"has_cover", false)):
		_update_hud("%s%s 命中 %s：基础 %d → %s（减伤 %d%%）→ 最终 %d%s。" % [
			attacker.name,
			step_out_note,
			target.name,
			int(cover_summary.get(&"base_damage", attacker.attack_damage)),
			cover_level_name,
			reduction_percent,
			applied,
			"，击杀目标" if result.killed else "",
		])
	else:
		_update_hud("%s%s 命中 %s，造成 %d 伤害%s。" % [
			attacker.name, step_out_note, target.name, applied, "并击杀目标" if result.killed else ""
		])
	_log("%s%s 攻击 %s：%s；实际造成 %d 伤害%s。" % [
		attacker.name,
		step_out_note,
		target.name,
		CoverResolverScript.format_debug_summary(cover_summary),
		applied,
		"，目标阵亡" if result.killed else "",
	])
	_refresh_highlights()
	return result


func _schedule_attack_impact(impact_callback: Callable) -> void:
	if not is_inside_tree() or not impact_callback.is_valid():
		if impact_callback.is_valid():
			impact_callback.call()
		return
	await get_tree().create_timer(0.06).timeout
	if impact_callback.is_valid():
		impact_callback.call()


func play_discover_sound() -> void:
	if discover_sfx == null or not is_inside_tree():
		return
	if audio_discover == null:
		audio_discover = get_node_or_null("AudioDiscover") as AudioStreamPlayer
	if audio_discover == null:
		audio_discover = AudioStreamPlayer.new()
		audio_discover.name = "AudioDiscover"
		add_child(audio_discover)
	if not audio_discover.playing:
		audio_discover.stream = discover_sfx
		audio_discover.play()


## Public environment-object attack entry.  It uses the same ActionExecutor,
## line/cover query and feedback path as a unit attack; only the damage target
## adapter differs.
func attack_environment_object(
		attacker: PrototypeUnit,
		target: EnvironmentObjectRuntimeState
) -> ActionResult:
	if not is_instance_valid(attacker) or target == null:
		return _action_rejected(&"invalid_target", ACTION_ATTACK)
	if _is_terminal() or session_manager == null:
		return _action_rejected(&"terminal", ACTION_ATTACK, attacker.unit_id, target.instance_id)
	var precondition_reason := _environment_attack_precondition_reason(attacker, target)
	# Keep target/session guards local, but defer AP and range validation to the
	# same ActionExecutor path used by unit attacks.  This keeps rejected object
	# attacks observable as ordinary ActionResults and guarantees no handler or
	# feedback runs before the executor's atomic validation.
	if precondition_reason != &"" and precondition_reason != &"no_ap" \
		and precondition_reason != &"out_of_range":
		var precondition_result := _action_rejected(precondition_reason, ACTION_ATTACK, attacker.unit_id, target.instance_id)
		_update_hud(_action_message("无法攻击环境对象", precondition_result.reason))
		return precondition_result
	var cover_query := query_attack_cover(attacker.grid_cell, target.cell)
	last_cover_query = cover_query
	var cover_damage := CoverResolverScript.resolve_damage(
		attacker.attack_damage,
		cover_query.profile,
		cover_combat_settings,
		cover_query.source_edge
	)
	var cover_summary := CoverResolverScript.build_debug_summary(cover_query, cover_damage)
	cover_damage[&"cover_debug_summary"] = cover_summary
	last_cover_damage = cover_damage.duplicate(true)
	var request := ActionRequestScript.new(
		ACTION_ATTACK,
		attacker.unit_id,
		target.instance_id,
		attacker.attack_ap_cost,
		{
			&"attacker": attacker,
			&"environment_object": target,
			&"enter_combat": false,
			ActionExecutorScript.KEY_ACTOR_CELL: attacker.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: target.cell,
			ActionExecutorScript.KEY_ATTACK_RANGE: attacker.attack_range,
			ActionExecutorScript.KEY_TARGET_ALIVE: target.can_receive_damage(),
			ActionExecutorScript.KEY_HOSTILE: true,
			ActionExecutorScript.KEY_HAS_LOS: cover_query.can_attack(),
			ActionExecutorScript.KEY_DAMAGE: int(cover_damage.get(&"effective_damage", attacker.attack_damage)),
			&"cover_metadata": cover_damage,
		}
	)
	var previous_input_locked := input_locked
	input_locked = true
	if is_instance_valid(end_turn_button):
		end_turn_button.disabled = true
	_clear_highlights()
	var result := _execute_runtime_action(request, attacker)
	if not result.success:
		result.metadata = cover_damage.duplicate(true)
		input_locked = previous_input_locked
		_refresh_undo_buttons()
		_refresh_highlights()
		if cover_query.is_blocked():
			var block_reason: StringName = StringName(cover_summary.get(&"block_reason", result.reason))
			_update_hud(_action_message("无法攻击环境对象", block_reason))
			_log("%s 攻击环境对象 %s 被阻挡：%s；%s" % [
				attacker.name,
				target.placement_id,
				_action_message("原因", block_reason).trim_suffix("。"),
				CoverResolverScript.format_debug_summary(cover_summary),
			])
		else:
			_update_hud(_action_message("无法攻击环境对象", result.reason))
		return result
	result.metadata = result.metadata.duplicate(true)
	attacker.look_at_cell(target.cell)
	await attacker.play_attack_feedback()
	input_locked = previous_input_locked
	_refresh_undo_buttons()
	var destruction_summary := result.metadata
	var destroyed_text := ""
	if bool(destruction_summary.get(&"destroyed", false)):
		destroyed_text = "，对象已摧毁"
	_update_hud("%s 命中环境对象 %s：基础 %d → %s（减伤 %d%%）→ 最终 %d%s。" % [
		attacker.name,
		target.placement_id,
		int(cover_summary.get(&"base_damage", attacker.attack_damage)),
		String(cover_summary.get(&"cover_level_name", &"NONE")),
		int(cover_summary.get(&"damage_reduction_percent", 0)),
		result.damage,
		destroyed_text,
	])
	_log("%s 攻击环境对象 %s：%s；实际造成 %d 伤害%s，剩余 HP %d。" % [
		attacker.name,
		target.placement_id,
		CoverResolverScript.format_debug_summary(cover_summary),
		result.damage,
		"，对象已摧毁" if target.destroyed else "",
		target.current_hp,
	])
	_refresh_highlights()
	return result


func _can_attack_environment_target_for_unit(
		attacker: PrototypeUnit,
		target: EnvironmentObjectRuntimeState
) -> bool:
	if _environment_attack_precondition_reason(attacker, target) != &"":
		return false
	return can_attack_line(attacker.grid_cell, target.cell, attacker.attack_range)


func _environment_attack_precondition_reason(
		attacker: PrototypeUnit,
		target: EnvironmentObjectRuntimeState
) -> StringName:
	if not is_instance_valid(attacker) or target == null or _is_terminal() or session_manager == null:
		return &"invalid_target"
	if not attacker.is_alive() or not target.can_receive_damage() or target.definition == null:
		return &"target_unavailable"
	if not target.definition.targetable or not target.definition.damageable:
		return &"target_unavailable"
	if turn_manager != null:
		if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION and attacker.faction != &"player":
			return &"wrong_phase"
		if turn_manager.is_player_turn() and attacker.faction != &"player":
			return &"wrong_phase"
		if turn_manager.is_enemy_turn() and attacker.faction != &"enemy":
			return &"wrong_phase"
	if not attacker.can_spend_action_points(attacker.attack_ap_cost):
		return &"no_ap"
	if _manhattan(attacker.grid_cell, target.cell) > attacker.attack_range:
		return &"out_of_range"
	return &""


func can_attack_environment_object(
		attacker: PrototypeUnit,
		target: EnvironmentObjectRuntimeState
) -> bool:
	return _can_attack_environment_target_for_unit(attacker, target)


## Public debug/test entry and the single authority used by player, AI and
## attack highlighting.  It deliberately delegates to the shared line query;
## callers must not recreate LOS or edge-cover rules.
func query_attack_cover(attacker_cell: Vector3i, target_cell: Vector3i, allow_step_out: bool = true) -> CoverQueryResult:
	if grid == null:
		return CoverQueryResult.new()
	var direct_query := CoverQueryScript.query(
		attacker_cell,
		target_cell,
		grid,
		grid.get_edge_index(),
		cover_combat_settings,
		opaque_cells
	)
	if direct_query.can_attack() or not allow_step_out:
		return direct_query

	var step_out_result := TacticalStepOutScript.find_step_out(
		attacker_cell,
		target_cell,
		-1,
		grid,
		grid.get_edge_index(),
		cover_combat_settings,
		opaque_cells
	)
	if step_out_result != null and step_out_result.can_attack():
		return step_out_result

	return direct_query


func _perception_edge_index() -> TacticalEdgeIndex:
	return null if grid == null else grid.get_edge_index()


func _can_detect_with_grid(
	observer: Vector3i,
	target: Vector3i,
	vision_range: int
) -> bool:
	return DetectionRules.can_detect(
		observer,
		target,
		vision_range,
		opaque_cells,
		grid,
		_perception_edge_index()
	)


func _evaluate_detection_tier_with_grid(
	observer: Vector3i,
	target: Vector3i,
	inner_vision_range: int,
	outer_vision_range: int
) -> DetectionRules.DetectionTier:
	return DetectionRules.evaluate_detection_tier(
		observer,
		target,
		inner_vision_range,
		outer_vision_range,
		opaque_cells,
		grid,
		_perception_edge_index()
	)


func _can_player_see_with_grid(observer: Vector3i, target: Vector3i, vision_range: int) -> bool:
	return DetectionRules.can_player_see(
		observer,
		target,
		vision_range,
		opaque_cells,
		grid,
		_perception_edge_index()
	)


func can_attack_line(attacker_cell: Vector3i, target_cell: Vector3i, attack_range: int) -> bool:
	if attack_range < 0 or _manhattan(attacker_cell, target_cell) > attack_range:
		return false
	var query := query_attack_cover(attacker_cell, target_cell, true)
	if query.can_attack():
		if query.is_step_out:
			if _manhattan(query.step_out_cell, target_cell) > attack_range:
				return false
		return true
	return false


func _has_any_engaged_enemy() -> bool:
	for enemy_id in _living_enemy_ids():
		var alert := enemy_alerts.get(enemy_id) as AlertState
		if alert != null and alert.is_engaged():
			return true
	return false


func _run_exploration_tick() -> void:
	world_tick += 1
	for enemy_id in _living_enemy_ids():
		var enemy := _unit_by_id(enemy_id)
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var alert := enemy_alerts.get(enemy_id) as AlertState
		var patrol_route := enemy_patrols.get(enemy_id) as PatrolRoute
		var invest_info: Dictionary = suspicious_investigations.get(enemy_id, {})
		var plan := EnemyTacticalAI.plan_exploration_step(
			enemy.grid_cell, alert, patrol_route, invest_info, grid, enemy.move_range
		)
		suspicious_investigations[enemy_id] = plan.get(&"updated_investigation", invest_info)
		match plan.get(&"intent"):
			EnemyTacticalAI.IntentType.INVESTIGATE_STEP:
				var next_cell: Vector3i = plan[&"destination"]
				var path: Array[Vector3i] = []
				path.assign(plan[&"path"])
				if not grid.is_occupied(next_cell) or next_cell == enemy.grid_cell:
					await _move_unit(enemy, next_cell, path, 0)
					if _evaluate_detection():
						break
			EnemyTacticalAI.IntentType.PATROL_STEP:
				var next_cell: Vector3i = plan[&"destination"]
				var path: Array[Vector3i] = []
				path.assign(plan[&"path"])
				await _move_unit(enemy, next_cell, path, 0)
				if is_instance_valid(patrol_route):
					patrol_route.advance()
				if _evaluate_detection():
					break
			EnemyTacticalAI.IntentType.CALM_DOWN:
				if alert != null:
					alert.calm_down()
				suspicious_investigations.erase(enemy_id)
				_log("%s 未在可疑位置发现异常，解除警戒。" % enemy.name)
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == &"player":
			unit.reset_action_points()


func _evaluate_detection() -> bool:
	if turn_manager.get_phase() != TurnManager.Phase.EXPLORATION:
		return false
	for enemy_id in _living_enemy_ids():
		var enemy := _unit_by_id(enemy_id)
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		for player_id in turn_manager.get_player_ids():
			var player := _unit_by_id(player_id)
			if not is_instance_valid(player) or not player.is_alive():
				continue
			var tier := _evaluate_detection_tier_with_grid(
				enemy.grid_cell, player.grid_cell,
				enemy.inner_vision_range, enemy.vision_range
			)
			match tier:
				DetectionRules.DetectionTier.INNER_DISCOVERY:
					var alert := enemy_alerts.get(enemy.unit_id) as AlertState
					if alert != null:
						alert.become_alerted(player.unit_id, player.grid_cell)
					if not discovering_enemy_ids.has(enemy.unit_id):
						discovering_enemy_ids.append(enemy.unit_id)
					play_discover_sound()
					_start_combat(true, enemy, player.grid_cell, player.unit_id, "发现玩家（暗杀击杀窗口）")
					_update_enemy_visibility()
					_refresh_highlights()
					_update_hud()
					return true
				DetectionRules.DetectionTier.OUTER_ALERT:
					var alert := enemy_alerts.get(enemy.unit_id) as AlertState
					if alert != null:
						if alert.is_unaware():
							alert.become_suspicious(player.grid_cell)
							suspicious_investigations[enemy.unit_id] = {
								&"target_cell": player.grid_cell,
								&"idle_ticks": 0,
							}
							_log("%s 注意到了可疑动静，进入警戒状态并前往探查 %s。" % [enemy.name, player.grid_cell])
							_update_enemy_visibility()
							_refresh_highlights()
							_update_hud()
						elif alert.is_suspicious():
							if alert.get_last_known_cell() != player.grid_cell:
								alert.become_suspicious(player.grid_cell)
								suspicious_investigations[enemy.unit_id] = {
									&"target_cell": player.grid_cell,
									&"idle_ticks": 0,
								}
	return false


func _start_combat(player_first: bool, alert_enemy: PrototypeUnit, known_cell: Vector3i, target_id: StringName = &"", reason: String = "") -> bool:
	if turn_manager.get_phase() != TurnManager.Phase.EXPLORATION or session_manager == null:
		return false
	if not is_instance_valid(alert_enemy):
		return false
	if not _activate_encounter_for(alert_enemy):
		return false
	var reason_text := reason if reason != "" else ("被玩家主动攻击" if player_first else "发现玩家")
	_log("进入交战：%s%s（位置 %s）。" % [alert_enemy.name, reason_text, known_cell])
	var effective_target := target_id
	if effective_target.is_empty() and is_instance_valid(selected_unit):
		effective_target = selected_unit.unit_id
	var alert := enemy_alerts.get(alert_enemy.unit_id) as AlertState
	if alert != null:
		if not alert.is_alerted():
			alert.engage(effective_target, known_cell)
	if alert == null or not alert.is_alerted():
		for enemy_id in turn_manager.get_enemy_ids():
			if enemy_alerts.has(enemy_id) and enemy_id != alert_enemy.unit_id:
				(enemy_alerts[enemy_id] as AlertState).become_suspicious(known_cell)
	if not session_manager.start_combat():
		turn_manager.configure(_living_player_ids(), [])
		active_encounter_id = &""
		return false
	if not turn_manager.start_combat(player_first):
		turn_manager.configure(_living_player_ids(), [])
		active_encounter_id = &""
		session_manager.resolve_combat()
		return false
	if not player_first:
		_run_enemy_turn.call_deferred()
	if reason.begins_with("发现玩家") or (not player_first and reason == ""):
		play_discover_sound()
	return true


func _run_enemy_turn() -> void:
	if not turn_manager.is_enemy_turn() or turn_manager.is_terminal():
		return
	input_locked = true
	_refresh_undo_buttons()
	end_turn_button.disabled = true
	_clear_highlights()
	for enemy_id in turn_manager.get_enemy_ids().duplicate():
		var enemy := _unit_by_id(enemy_id)
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		enemy.reset_action_points()
		var action_attempts := 0
		var max_action_attempts := maxi(enemy.max_action_points + 1, 1)
		while enemy.current_action_points > 0 and turn_manager.is_enemy_turn() and action_attempts < max_action_attempts:
			action_attempts += 1
			var living_players: Array = []
			for player_id in _living_player_ids():
				var player := _unit_by_id(player_id)
				if is_instance_valid(player) and player.is_alive():
					living_players.append(player)
			if living_players.is_empty():
				break
			var can_attack_checker := func(from_c: Vector3i, to_c: Vector3i, r: int) -> bool:
				return can_attack_line(from_c, to_c, r)
			var plan := EnemyTacticalAI.plan_combat_action(
				enemy.grid_cell,
				enemy.current_action_points,
				enemy.attack_damage,
				enemy.attack_range,
				enemy.attack_ap_cost,
				enemy.move_range,
				MOVE_ACTION_COST,
				living_players,
				grid,
				can_attack_checker
			)
			match plan.get(&"intent"):
				EnemyTacticalAI.IntentType.ATTACK:
					var target := _unit_by_id(plan[&"target_id"])
					if not is_instance_valid(target):
						break
					var attack_result := await _attack_with_unit(enemy, target)
					if not attack_result.success:
						break
					if enemy.attack_ap_cost <= 0 or enemy.current_action_points < enemy.attack_ap_cost:
						break
					if enemy_attack_interval > 0.0 and is_inside_tree():
						await get_tree().create_timer(enemy_attack_interval).timeout
						if not turn_manager.is_enemy_turn() or turn_manager.is_terminal():
							break
					continue
				EnemyTacticalAI.IntentType.MOVE:
					var destination: Vector3i = plan[&"destination"]
					var path: Array[Vector3i] = []
					path.assign(plan[&"path"])
					var ap_cost: int = plan[&"ap_cost"]
					if not await _move_unit(enemy, destination, path, ap_cost):
						break
					if enemy_move_interval > 0.0 and is_inside_tree():
						await get_tree().create_timer(enemy_move_interval).timeout
						if not turn_manager.is_enemy_turn() or turn_manager.is_terminal():
							break
				_:
					break
		if enemy_switch_interval > 0.0 and is_inside_tree() and turn_manager.is_enemy_turn() and not turn_manager.is_terminal():
			await get_tree().create_timer(enemy_switch_interval).timeout
	input_locked = false
	_refresh_undo_buttons()
	if turn_manager.is_enemy_turn():
		if turn_manager.end_enemy_turn():
			_reset_faction_ap(&"player")
			# The turn checkpoint must include the AP reset performed between
			# enemy and player turns.  Capturing from phase_changed would be too
			# early and would preserve the previous player's depleted AP.
			_capture_undo_turn_checkpoint()
	end_turn_button.disabled = turn_manager.is_terminal()
	_refresh_undo_buttons()
	_refresh_highlights()


func _select_unit(unit: PrototypeUnit, allow_enemy: bool = false) -> void:
	if is_instance_valid(unit):
		if unit.faction == &"player":
			if not unit.is_alive():
				unit = null
		elif not allow_enemy:
			unit = null
	if is_instance_valid(selected_unit):
		selected_unit.set_selected(false)
	selected_unit = unit
	if is_instance_valid(selected_unit):
		selected_unit.set_selected(true)
		if selected_unit.faction == &"player":
			action_mode = ACTION_MODE_MOVE
	_refresh_highlights()
	_update_hud()


func _refresh_highlights() -> void:
	_clear_highlights()
	_update_object_visibility()
	var can_show_tactical_highlights := _can_show_tactical_highlights()
	var can_show_move_highlights := can_show_tactical_highlights \
		and action_mode == ACTION_MODE_MOVE \
		and selected_unit.can_spend_action_points(MOVE_ACTION_COST)
	var can_show_attack_highlights := can_show_tactical_highlights \
		and action_mode == ACTION_MODE_ATTACK \
		and selected_unit.can_spend_action_points(selected_unit.attack_ap_cost)
	if is_instance_valid(highlights_root):
		highlights_root.visible = can_show_move_highlights
	if is_instance_valid(attack_highlights_root):
		attack_highlights_root.visible = can_show_attack_highlights
	if is_instance_valid(object_highlights_root):
		object_highlights_root.visible = can_show_tactical_highlights
	if can_show_move_highlights:
		for cell in grid.get_reachable_cells(selected_unit.grid_cell, selected_unit.move_range):
			if cell != selected_unit.grid_cell:
				_add_highlight(highlights_root, cell, MOVE_HIGHLIGHT_COLOR)
	if can_show_attack_highlights:
		for enemy_id in _enemy_ids_for_context():
			var enemy := _unit_by_id(enemy_id)
			if _can_attack_target(enemy):
				_add_highlight(attack_highlights_root, enemy.grid_cell, ATTACK_HIGHLIGHT_COLOR)
		for environment_state in _sorted_environment_object_states():
			if _can_attack_environment_target_for_unit(selected_unit, environment_state) \
				and _is_environment_object_visible(environment_state.placement_id):
				_add_highlight(attack_highlights_root, environment_state.cell, ATTACK_HIGHLIGHT_COLOR)
	_refresh_object_highlights()
	_refresh_vision_overlay()
	_refresh_unit_cover_icons()
	if can_show_move_highlights and is_instance_valid(grid) and grid.has_cell(_hovered_cell) and _is_cursor_visible():
		_update_cover_preview(_hovered_cell)
	var enemies_to_display: Array[PrototypeUnit] = []
	if show_enemy_vision:
		for enemy_id in _living_enemy_ids():
			var enemy := _unit_by_id(enemy_id)
			if is_instance_valid(enemy) and enemy.is_alive() and enemy.visible and enemy.faction == &"enemy":
				if not enemies_to_display.has(enemy):
					enemies_to_display.append(enemy)
	if is_instance_valid(selected_unit) and selected_unit.faction == &"enemy" and selected_unit.is_alive():
		if not enemies_to_display.has(selected_unit):
			enemies_to_display.append(selected_unit)
	if not enemies_to_display.is_empty():
		_refresh_enemies_range_overlays(enemies_to_display)
	_refresh_action_bar()


func _can_attack_target(target: PrototypeUnit) -> bool:
	if not _can_show_tactical_highlights() or not is_instance_valid(target):
		return false
	if not target.is_alive() or target.faction == selected_unit.faction or not target.visible:
		return false
	if not _enemy_ids_for_context().has(target.unit_id):
		return false
	if not selected_unit.can_spend_action_points(selected_unit.attack_ap_cost):
		return false
	return can_attack_line(selected_unit.grid_cell, target.grid_cell, selected_unit.attack_range)


## Tints the cells that the given enemies can actually detect (vision range + line of sight)
## matching the detection rules used to trigger combat.
## Overlapping cells between multiple enemies take the highest threat tier (INNER_DISCOVERY > OUTER_ALERT).
func _refresh_enemies_range_overlays(enemies: Array) -> void:
	if enemies.is_empty() or not is_instance_valid(grid):
		return
	var cell_tiers: Dictionary = {}
	var footprint := grid.get_grid_size()
	for enemy_val in enemies:
		var enemy := enemy_val as PrototypeUnit
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var origin := enemy.grid_cell
		for level in range(grid.get_level_count()):
			for z in range(footprint.y):
				for x in range(footprint.x):
					var cell := Vector3i(x, level, z)
					if not grid.has_cell(cell) or cell == origin:
						continue
					if cell_tiers.get(cell, DetectionRules.DetectionTier.NONE) == DetectionRules.DetectionTier.INNER_DISCOVERY:
						continue
					var tier := _evaluate_detection_tier_with_grid(
						origin, cell,
						enemy.inner_vision_range, enemy.vision_range
					)
					if tier != DetectionRules.DetectionTier.NONE:
						var current_highest: int = cell_tiers.get(cell, DetectionRules.DetectionTier.NONE)
						if tier > current_highest:
							cell_tiers[cell] = tier

	for cell in cell_tiers:
		var tier: int = cell_tiers[cell]
		match tier:
			DetectionRules.DetectionTier.INNER_DISCOVERY:
				_add_highlight(vision_highlights_root, cell, ENEMY_INNER_VISION_COLOR, 0.045)
			DetectionRules.DetectionTier.OUTER_ALERT:
				_add_highlight(vision_highlights_root, cell, ENEMY_OUTER_VISION_COLOR, 0.045)


## When an enemy unit is selected, tints the cells it can actually detect
## (vision range + line of sight) so the overlay matches the detection
## rules used to trigger combat.
func _refresh_enemy_range_overlays(enemy: PrototypeUnit) -> void:
	if is_instance_valid(enemy):
		_refresh_enemies_range_overlays([enemy])


func _refresh_move_highlights() -> void:
	_refresh_highlights()


func _refresh_action_bar() -> void:
	if not is_instance_valid(move_action_button) or not is_instance_valid(attack_action_button):
		return
	var has_player_selection := is_instance_valid(selected_unit) \
		and selected_unit.faction == &"player" \
		and selected_unit.is_alive()
	if is_instance_valid(action_bar):
		action_bar.visible = has_player_selection \
		and (not is_instance_valid(loot_panel) or not loot_panel.visible)
	if is_instance_valid(action_bar_ap_label):
		if has_player_selection:
			action_bar_ap_label.text = "AP：%d/%d" % [selected_unit.current_action_points, selected_unit.max_action_points]
		else:
			action_bar_ap_label.text = "AP：0/0"
	var can_show_actions := _can_show_tactical_highlights()
	move_action_button.disabled = not can_show_actions \
		or not selected_unit.can_spend_action_points(MOVE_ACTION_COST)
	attack_action_button.disabled = not can_show_actions \
		or not selected_unit.can_spend_action_points(selected_unit.attack_ap_cost)
	move_action_button.button_pressed = action_mode == ACTION_MODE_MOVE
	attack_action_button.button_pressed = action_mode == ACTION_MODE_ATTACK


func _init_hover_cursor() -> void:
	if not is_instance_valid(grid):
		return
	if not is_instance_valid(_cursor_indicators_root):
		_cursor_indicators_root = Node3D.new()
		_cursor_indicators_root.name = "CursorIndicators"
		add_child(_cursor_indicators_root)
	if not is_instance_valid(_cover_indicators_root):
		_cover_indicators_root = Node3D.new()
		_cover_indicators_root.name = "CoverIndicators"
		add_child(_cover_indicators_root)
	if not is_instance_valid(_unit_cover_indicators_root):
		_unit_cover_indicators_root = Node3D.new()
		_unit_cover_indicators_root.name = "UnitCoverIndicators"
		add_child(_unit_cover_indicators_root)
	_hover_cursor = _get_or_create_cursor_mesh(0)


func _is_cursor_visible() -> bool:
	if _cursor_mesh_pool.is_empty():
		return is_instance_valid(_hover_cursor) and _hover_cursor.visible
	return _cursor_mesh_pool[0].visible


func _update_hover_cursor(screen_position: Vector2) -> void:
	if not is_instance_valid(grid) or input_locked or _is_terminal():
		_hide_hover_cursor()
		return
	var cell := _screen_to_cell(screen_position)
	if not grid.has_cell(cell) or not grid.in_bounds(cell):
		_hide_hover_cursor()
		return
	var cell_changed := _hovered_cell != cell
	_hovered_cell = cell
	if cell_changed or not _is_cursor_visible():
		_update_cursor_highlights(cell)
		if _can_show_move_highlights():
			_update_cover_preview(cell)
		else:
			_hide_cover_preview()


func _hide_hover_cursor() -> void:
	_hovered_cell = grid.invalid_cell() if is_instance_valid(grid) else Vector3i(-1, -1, -1)
	_hide_cursor_highlights()
	_hide_cover_preview()


func _update_cursor_highlights(center_cell: Vector3i) -> void:
	_hide_cursor_highlights()
	if not is_instance_valid(grid) or not is_instance_valid(_cursor_indicators_root):
		return

	var material := _get_cached_highlight_material(CURSOR_HIGHLIGHT_COLOR)
	var highlight := _get_or_create_cursor_mesh(0)
	highlight.material_override = material
	var target_pos := grid.cell_to_world(center_cell) + Vector3.UP * CURSOR_SURFACE_OFFSET
	if is_inside_tree():
		highlight.global_position = target_pos
	else:
		highlight.position = target_pos
	highlight.visible = true
	_hover_cursor = highlight


func _hide_cursor_highlights() -> void:
	for highlight in _cursor_mesh_pool:
		if is_instance_valid(highlight):
			highlight.visible = false


func _get_or_create_cursor_mesh(index: int) -> MeshInstance3D:
	while index >= _cursor_mesh_pool.size():
		var highlight := MeshInstance3D.new()
		highlight.name = "HoverCursor_%d" % _cursor_mesh_pool.size()
		highlight.mesh = _get_cached_highlight_mesh(
			Vector3(grid.cell_dimensions.x * 0.92, 0.04, grid.cell_dimensions.z * 0.92)
		)
		highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		highlight.visible = false
		_cursor_indicators_root.add_child(highlight)
		_cursor_mesh_pool.append(highlight)
	return _cursor_mesh_pool[index]


func _update_cover_preview(center_cell: Vector3i) -> void:
	_hide_cover_preview()
	if not is_instance_valid(grid) or not is_instance_valid(_cover_indicators_root):
		return
	var edge_index := grid.get_edge_index()
	if edge_index == null:
		return

	var icon_index := 0
	var level := center_cell.y
	for dx in range(-COVER_PREVIEW_DISTANCE, COVER_PREVIEW_DISTANCE + 1):
		for dz in range(-COVER_PREVIEW_DISTANCE, COVER_PREVIEW_DISTANCE + 1):
			var dist := absi(dx) + absi(dz)
			if dist > COVER_PREVIEW_DISTANCE:
				continue
			var cell := Vector3i(center_cell.x + dx, level, center_cell.z + dz)
			if not grid.has_cell(cell) or not grid.is_walkable(cell):
				continue

			var cell_world := grid.cell_to_world(cell)
			var alpha_factor: float = COVER_DISTANCE_ALPHA_FACTORS[dist] if dist < COVER_DISTANCE_ALPHA_FACTORS.size() else 0.35
			for dir in GridModel.CARDINAL_DIRECTIONS:
				var neighbor := cell + dir
				var edge := edge_index.get_edge(cell, neighbor)
				if edge == null:
					continue
				var side := 0 if edge.cell_a == cell else 1
				var profile := edge.resolve_profile(side, cover_combat_settings)
				if profile == null or profile.cover_level == 0:
					continue

				var texture: Texture2D = HALF_COVER_TEXTURE if profile.cover_level == 1 else FULL_COVER_TEXTURE
				var sprite := _get_or_create_cover_sprite(icon_index)
				icon_index += 1

				sprite.texture = texture
				sprite.modulate = Color(1.0, 1.0, 1.0, alpha_factor)
				var dir_vector := Vector3(float(dir.x), 0.0, float(dir.z))
				var sprite_pos := cell_world + dir_vector * (grid.cell_dimensions.x * COVER_ICON_EDGE_OFFSET_RATIO) + Vector3.UP * COVER_ICON_SURFACE_OFFSET
				if is_inside_tree():
					sprite.global_position = sprite_pos
				else:
					sprite.position = sprite_pos
				sprite.visible = true


func _hide_cover_preview() -> void:
	for sprite in _cover_icon_pool:
		if is_instance_valid(sprite):
			sprite.visible = false


func _get_or_create_cover_sprite(index: int) -> Sprite3D:
	while index >= _cover_icon_pool.size():
		var sprite := Sprite3D.new()
		sprite.name = "CoverIcon_%d" % _cover_icon_pool.size()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.pixel_size = COVER_ICON_PIXEL_SIZE
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.render_priority = 10
		sprite.visible = false
		_cover_indicators_root.add_child(sprite)
		_cover_icon_pool.append(sprite)
	return _cover_icon_pool[index]


func _refresh_unit_cover_icons() -> void:
	_hide_unit_cover_icons()
	if not is_instance_valid(grid) or not is_instance_valid(_unit_cover_indicators_root):
		return
	var edge_index := grid.get_edge_index()
	if edge_index == null:
		return

	var icon_index := 0
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if not is_instance_valid(unit) or not unit.is_alive():
			continue
		if unit.faction != &"player" and not unit.visible:
			continue

		var cell := unit.grid_cell
		if not grid.has_cell(cell):
			continue
		var cell_world := grid.cell_to_world(cell)

		for dir in GridModel.CARDINAL_DIRECTIONS:
			var neighbor := cell + dir
			var edge := edge_index.get_edge(cell, neighbor)
			if edge == null:
				continue
			var side := 0 if edge.cell_a == cell else 1
			var profile := edge.resolve_profile(side, cover_combat_settings)
			if profile == null or profile.cover_level == 0:
				continue

			var texture: Texture2D = HALF_COVER_TEXTURE if profile.cover_level == 1 else FULL_COVER_TEXTURE
			var sprite := _get_or_create_unit_cover_sprite(icon_index)
			icon_index += 1

			sprite.texture = texture
			sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
			var dir_vector := Vector3(float(dir.x), 0.0, float(dir.z))
			var sprite_pos := cell_world + dir_vector * (grid.cell_dimensions.x * COVER_ICON_EDGE_OFFSET_RATIO) + Vector3.UP * COVER_ICON_SURFACE_OFFSET
			if is_inside_tree():
				sprite.global_position = sprite_pos
			else:
				sprite.position = sprite_pos
			sprite.visible = true


func _hide_unit_cover_icons() -> void:
	for sprite in _unit_cover_icon_pool:
		if is_instance_valid(sprite):
			sprite.visible = false


func _get_or_create_unit_cover_sprite(index: int) -> Sprite3D:
	while index >= _unit_cover_icon_pool.size():
		var sprite := Sprite3D.new()
		sprite.name = "UnitCoverIcon_%d" % _unit_cover_icon_pool.size()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.pixel_size = COVER_ICON_PIXEL_SIZE
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.render_priority = 10
		sprite.visible = false
		_unit_cover_indicators_root.add_child(sprite)
		_unit_cover_icon_pool.append(sprite)
	return _unit_cover_icon_pool[index]


func get_hovered_cell() -> Vector3i:
	return _hovered_cell


func _add_highlight(parent: Node3D, cell: Vector3i, color: Color, height_offset: float = MOVE_HIGHLIGHT_SURFACE_OFFSET) -> void:
	if not is_instance_valid(parent):
		return
	var material := _get_cached_highlight_material(color)
	var mesh := _get_cached_highlight_mesh(
		Vector3(grid.cell_dimensions.x * 0.88, 0.035, grid.cell_dimensions.z * 0.88))
	var highlight := MeshInstance3D.new()
	highlight.name = "Cell_%d_%d_%d" % [cell.x, cell.y, cell.z]
	highlight.mesh = mesh
	highlight.material_override = material
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.set_meta(&"grid_cell", cell)
	parent.add_child(highlight)
	if highlight.is_inside_tree():
		highlight.global_position = grid.cell_to_world(cell) + Vector3.UP * height_offset
	else:
		highlight.position = grid.cell_to_world(cell) + Vector3.UP * height_offset
	highlight.visible = true


## Reuses one translucent unshaded material per color instead of allocating a
## fresh StandardMaterial3D for every highlight cell.
func _get_cached_highlight_material(color: Color) -> StandardMaterial3D:
	if _highlight_material_cache.has(color):
		return _highlight_material_cache[color]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_material_cache[color] = material
	return material


## Reuses one BoxMesh per size for all highlight cells, since every cell on a
## fixed grid shares the same footprint.
func _get_cached_highlight_mesh(size: Vector3) -> BoxMesh:
	if _highlight_mesh_cache.has(size):
		return _highlight_mesh_cache[size]
	var mesh := BoxMesh.new()
	mesh.size = size
	_highlight_mesh_cache[size] = mesh
	return mesh


func _refresh_object_highlights() -> void:
	if not is_instance_valid(object_highlights_root):
		return
	if input_locked:
		return
	if session_manager == null or not _player_can_act():
		return
	if not is_instance_valid(selected_unit) or selected_unit.faction != &"player" or not selected_unit.is_alive():
		return
	var state: int = session_manager.get_state()
	var can_loot: bool = state == GameStateManagerScript.State.EXPLORATION \
		or (state == GameStateManagerScript.State.COMBAT and turn_manager.is_player_turn())
	var can_extract: bool = state == GameStateManagerScript.State.EXPLORATION
	for object_id in loot_containers.keys():
		var container = loot_containers[object_id]
		var placement = object_placements.get(object_id)
		if placement == null or container == null or container.is_depleted():
			continue
		if can_loot and _manhattan(selected_unit.grid_cell, placement.cell) <= INTERACTION_RANGE:
			_add_highlight(object_highlights_root, placement.cell, LOOT_HIGHLIGHT_COLOR)
	for cell in extraction_cells:
		if can_extract and _manhattan(selected_unit.grid_cell, cell) <= INTERACTION_RANGE:
			_add_highlight(object_highlights_root, cell, EXTRACTION_HIGHLIGHT_COLOR)


func _clear_highlights() -> void:
	if is_instance_valid(highlights_root):
		_clear_children(highlights_root)
	if is_instance_valid(attack_highlights_root):
		_clear_children(attack_highlights_root)
	if is_instance_valid(object_highlights_root):
		_clear_children(object_highlights_root)
	_hide_cover_preview()
	_hide_unit_cover_icons()


## Darkens every cell NOT visible to any living player unit (range + LOS)
## with a semi-transparent black overlay, always on. Rebuilds on every
## highlight refresh.
func _refresh_vision_overlay() -> void:
	if not is_instance_valid(vision_highlights_root):
		return
	_clear_children(vision_highlights_root)
	if debug_reveal_all:
		return
	var observers: Array = []
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == &"player" and unit.is_alive():
			observers.append([unit.grid_cell, unit.vision_range])
	if observers.is_empty():
		return
	var footprint := grid.get_grid_size()
	for level in range(grid.get_level_count()):
		for z in range(footprint.y):
			for x in range(footprint.x):
				var cell := Vector3i(x, level, z)
				if not grid.has_cell(cell):
					continue
				var visible := false
				for observer in observers:
					if _can_player_see_with_grid(observer[0], cell, observer[1]):
						visible = true
						break
				if not visible:
					_add_highlight(vision_highlights_root, cell, VISION_BLOCK_COLOR)


func _clear_move_highlights() -> void:
	_clear_highlights()


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _on_end_turn_pressed() -> void:
	if input_locked or _is_terminal() or session_manager == null:
		return
	if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION:
		await _run_exploration_tick()
		_evaluate_detection()
		if session_manager.get_state() == GameStateManagerScript.State.EXPLORATION:
			_capture_undo_turn_checkpoint()
		_update_hud("探索世界 Tick %d。" % world_tick)
		_log("世界 Tick %d：敌人巡逻，玩家 AP 重置。" % world_tick)
		return

	# If any enemy in discovering_enemy_ids or active combat is alive in ALERTED/ENGAGED state, sound alarm to whole squad!
	var alarmed_encounters: Dictionary = {}
	var alarm_sources: Array[StringName] = []

	for enemy_id in discovering_enemy_ids:
		var enemy := _unit_by_id(enemy_id)
		if is_instance_valid(enemy) and enemy.is_alive():
			var alert := enemy_alerts.get(enemy_id) as AlertState
			if alert != null and alert.is_alerted():
				var encounter_id: StringName = encounter_by_unit.get(enemy_id, &"default")
				if not alarmed_encounters.has(encounter_id):
					alarmed_encounters[encounter_id] = true
					alarm_sources.append(enemy_id)

	for enemy_id in turn_manager.get_enemy_ids():
		var enemy := _unit_by_id(enemy_id)
		if is_instance_valid(enemy) and enemy.is_alive():
			var alert := enemy_alerts.get(enemy_id) as AlertState
			if alert != null and (alert.is_alerted() or alert.is_engaged()):
				var encounter_id: StringName = encounter_by_unit.get(enemy_id, &"default")
				if not alarmed_encounters.has(encounter_id):
					var has_unengaged_member := false
					for member_id in encounter_members.get(encounter_id, []):
						var member_alert := enemy_alerts.get(member_id) as AlertState
						if member_alert != null and not member_alert.is_engaged():
							has_unengaged_member = true
							break
					if has_unengaged_member:
						alarmed_encounters[encounter_id] = true
						alarm_sources.append(enemy_id)

	if not alarm_sources.is_empty():
		for source_enemy_id in alarm_sources:
			var source_enemy := _unit_by_id(source_enemy_id)
			var source_alert := enemy_alerts.get(source_enemy_id) as AlertState
			var target_player_id := source_alert.get_target_id() if source_alert != null else &""
			var target_cell := source_alert.get_last_known_cell() if source_alert != null else AlertState.INVALID_CELL
			if target_player_id.is_empty() and not _living_player_ids().is_empty():
				target_player_id = _living_player_ids()[0]
				var player_unit := _unit_by_id(target_player_id)
				if is_instance_valid(player_unit):
					target_cell = player_unit.grid_cell
			if source_alert != null:
				source_alert.engage(target_player_id, target_cell)
			var encounter_id: StringName = encounter_by_unit.get(source_enemy_id, &"default")
			for member_id in encounter_members.get(encounter_id, []):
				var member := _unit_by_id(member_id)
				if is_instance_valid(member) and member.is_alive():
					if enemy_alerts.has(member_id):
						(enemy_alerts[member_id] as AlertState).engage(target_player_id, target_cell)
			_log("【警报扩散】%s 发出警报，整个小组进入战斗状态！" % (source_enemy.name if is_instance_valid(source_enemy) else String(source_enemy_id)))
		discovering_enemy_ids.clear()
		_update_enemy_visibility()

	if turn_manager.end_player_turn():
		await _run_enemy_turn()


func _on_unit_died(unit: PrototypeUnit) -> void:
	_log("%s 阵亡（HP 归零）。" % unit.name)
	grid.vacate(unit.grid_cell, unit.unit_id)
	turn_manager.remove_unit(unit.unit_id)
	# Keep the View and runtime state indexed after death.  TurnManager still
	# removes the ID from the living turn roster, while undo can later restore
	# the same state/object without inventing a duplicate identity.
	discovering_enemy_ids.erase(unit.unit_id)
	if selected_unit == unit:
		selected_unit = null
	unit.set_selected(false)
	unit.visible = false
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	if unit.faction == &"player" and _living_player_count() == 0:
		if session_manager != null:
			session_manager.report_team_defeated()
	elif unit.faction == &"enemy":
		if discovering_enemy_ids.is_empty() and not _has_any_engaged_enemy():
			if turn_manager.get_phase() == TurnManager.Phase.PLAYER_TURN and session_manager != null and session_manager.get_state() == GameStateManagerScript.State.COMBAT:
				_log("【暗杀成功】发现你的敌人已被击杀，警报解除，敌方小队未被惊动！")
				turn_manager.reset_to_exploration()
				turn_manager.configure(_living_player_ids(), [])
				active_encounter_id = &""
				session_manager.resolve_combat()
	_update_enemy_visibility()
	_refresh_highlights()
	_update_hud()


func _on_phase_changed(_previous: TurnManager.Phase, _current: TurnManager.Phase) -> void:
	if _undo_restoring:
		return
	match _current:
		TurnManager.Phase.PLAYER_TURN:
			_log("—— 玩家回合开始 ——")
		TurnManager.Phase.ENEMY_TURN:
			_log("—— 敌方回合开始 ——")
		TurnManager.Phase.VICTORY:
			_log("—— 交战结束：敌方全灭 ——")
		TurnManager.Phase.DEFEAT:
			_log("—— 交战结束：小队全灭 ——")
	if _current == TurnManager.Phase.VICTORY and session_manager != null and session_manager.get_state() == GameStateManagerScript.State.COMBAT:
		var resolved_id := active_encounter_id
		turn_manager.reset_to_exploration()
		if not resolved_id.is_empty():
			resolved_encounters[resolved_id] = true
		active_encounter_id = &""
		turn_manager.configure(_living_player_ids(), [])
		session_manager.resolve_combat()
	elif _current == TurnManager.Phase.DEFEAT and session_manager != null:
		session_manager.report_team_defeated()
	_update_enemy_visibility()
	_refresh_highlights()
	_update_hud()


func _on_unit_state_changed(_current: int, _maximum: int) -> void:
	_refresh_highlights()
	_update_hud()


func _reset_faction_ap(faction: StringName) -> void:
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.faction == faction and unit.is_alive():
			unit.reset_action_points()


func _find_player_at(cell: Vector3i) -> PrototypeUnit:
	return _find_faction_at(cell, &"player")


func _find_enemy_at(cell: Vector3i) -> PrototypeUnit:
	var enemy := _find_faction_at(cell, &"enemy")
	return enemy if is_instance_valid(enemy) and enemy.visible else null


func _find_faction_at(cell: Vector3i, faction: StringName) -> PrototypeUnit:
	var occupant_id := grid.get_occupant(cell)
	var unit := _unit_by_id(occupant_id)
	return unit if is_instance_valid(unit) and unit.faction == faction else null


func _unit_by_id(unit_id: StringName) -> PrototypeUnit:
	if unit_id.is_empty() or not units_by_id.has(unit_id):
		return null
	return units_by_id[unit_id] as PrototypeUnit


func _unit_by_name(unit_name: StringName) -> PrototypeUnit:
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if unit.name == unit_name:
			return unit
	return null


func _nearest_living_player(from_cell: Vector3i) -> PrototypeUnit:
	var result: PrototypeUnit
	var best_distance := 1_000_000
	for player_id in _living_player_ids():
		var player := _unit_by_id(player_id)
		if not is_instance_valid(player):
			continue
		var distance := _manhattan(from_cell, player.grid_cell)
		if distance < best_distance:
			best_distance = distance
			result = player
	return result


func _living_player_count() -> int:
	var count := 0
	for unit_value in units_by_id.values():
		var unit := unit_value as PrototypeUnit
		if is_instance_valid(unit) and unit.faction == &"player" and unit.is_alive():
			count += 1
	return count


func _object_at_cell(cell: Vector3i) -> StringName:
	for object_id in object_placements.keys():
		var placement = object_placements[object_id]
		if placement != null and placement.cell == cell:
			return object_id
	return &""


func _environment_object_at_cell(cell: Vector3i) -> EnvironmentObjectRuntimeState:
	for state in _sorted_environment_object_states():
		if state != null and state.active and not state.destroyed and state.cell == cell:
			return state
	return null


func _sorted_environment_object_states() -> Array[EnvironmentObjectRuntimeState]:
	var ids: Array = environment_objects_by_placement_id.keys()
	ids.sort_custom(func(first: Variant, second: Variant) -> bool:
		return String(first) < String(second)
	)
	var result: Array[EnvironmentObjectRuntimeState] = []
	for raw_id in ids:
		var state := environment_objects_by_placement_id[raw_id] as EnvironmentObjectRuntimeState
		if state != null:
			result.append(state)
	return result


func _is_environment_object_visible(placement_id: StringName) -> bool:
	if debug_reveal_all:
		return true
	var visual := _get_environment_visual(placement_id)
	if visual != null:
		return visual.visible
	var typed_view := _get_environment_view(placement_id)
	return true if typed_view == null else typed_view.visible


func _extraction_at_cell(cell: Vector3i) -> StringName:
	for object_id in object_placements.keys():
		var placement = object_placements[object_id]
		if placement != null and placement.kind == MapObjectPlacement.Kind.EXTRACTION and placement.cell == cell:
			return object_id
	return &""


## Loot / inventory management is allowed during exploration AND during the
## player's turn in combat (enemy turns block it via _player_can_act).
func _can_use_loot_action() -> bool:
	if not is_instance_valid(selected_unit) or not selected_unit.is_alive() or session_manager == null:
		return false
	if not _player_can_act():
		return false
	var state: int = session_manager.get_state()
	return state == GameStateManagerScript.State.EXPLORATION \
		or (state == GameStateManagerScript.State.COMBAT and turn_manager.is_player_turn())


func _is_current_loot_container(container_id: StringName) -> bool:
	if container_id == &"" or container_id != open_loot_container_id:
		return false
	var container = loot_containers.get(container_id)
	return container != null and container.is_opened() and not container.is_depleted()


func _is_current_loot_item(container_id: StringName, index: int, item: Variant) -> bool:
	if not _is_current_loot_container(container_id) or item == null or index < 0:
		return false
	var container = loot_containers.get(container_id)
	return container.get_item(index) == item


## Extraction confirmation remains an exploration-only action.
func _can_use_exploration_action() -> bool:
	return is_instance_valid(selected_unit) and selected_unit.is_alive() and session_manager != null \
		and session_manager.get_state() == GameStateManagerScript.State.EXPLORATION \
		and _player_can_act()


func _loot_item(container_id: StringName, index: int) -> ActionResult:
	if container_id != open_loot_container_id:
		return _action_rejected(&"invalid_container", ACTION_LOOT)
	var container = loot_containers.get(container_id)
	var item = container.get_item(index) if container != null else null
	if item == null or squad_inventory == null:
		return _action_rejected(&"invalid_target", ACTION_LOOT)
	var allow_owned := _is_current_loot_item(container_id, index, item)
	var anchor: Vector2i = squad_inventory.find_first_fit(item, -1, allow_owned)
	if anchor == SquadInventoryScript.NO_FIT:
		_update_hud("空间碎片：该物品没有连续合法位置，Loot 与 AP 未改变。")
		return _action_rejected(&"inventory_full", ACTION_LOOT)
	return place_loot_instance(container_id, index, anchor, 0)


func _loot_all(container_id: StringName) -> ActionResult:
	if not _can_use_loot_action():
		return _action_rejected(&"wrong_phase", ACTION_LOOT)
	var container = loot_containers.get(container_id)
	var placement = object_placements.get(container_id)
	var player := selected_unit
	var contents: Array = container.get_contents_instances() if container != null else []
	var allow_owned := _is_current_loot_container(container_id)
	var request := ActionRequestScript.new(
		ACTION_LOOT,
		player.unit_id,
		container_id,
		LOOT_ACTION_COST,
		{
			&"operation": &"loot_all",
			ActionExecutorScript.KEY_ACTOR_CELL: player.grid_cell,
			ActionExecutorScript.KEY_TARGET_CELL: placement.cell if placement != null else Vector3i(-1, -1, -1),
			ActionExecutorScript.KEY_INTERACTION_RANGE: INTERACTION_RANGE,
			ActionExecutorScript.KEY_CONTAINER_VALID: container != null and placement != null and container_id == open_loot_container_id,
			ActionExecutorScript.KEY_CONTAINER_AVAILABLE: container != null and not container.is_depleted(),
			ActionExecutorScript.KEY_INVENTORY_CAN_RECEIVE: squad_inventory != null and container != null and squad_inventory.can_add_items(contents, allow_owned),
		}
	)
	var result := _execute_runtime_action(request, player)
	if not result.success:
		_update_hud(_action_message("无法全部拾取", result.reason))
		return result
	_refresh_inventory_ui()
	_update_hud("已全部拾取（不消耗 AP）。")
	_log("全部拾取 %s（%d 件，不消耗 AP）。" % [container_id, contents.size()])
	_refresh_highlights()
	return result


func _on_loot_item_pressed(index: int) -> void:
	loot_item(index)


func _on_loot_all_button_pressed() -> void:
	loot_all()


func _refresh_loot_panel() -> void:
	if not is_instance_valid(loot_grid):
		return
	var container = loot_containers.get(open_loot_container_id)
	if container == null:
		loot_title_label.text = "Loot"
		loot_all_button.disabled = true
		loot_grid.clear_container()
		return
	loot_title_label.text = "%s | %d 件" % [open_loot_container_id, container.get_item_count()]
	loot_all_button.disabled = container.is_depleted()
	loot_grid.set_container(container)
	if container.is_depleted():
		loot_title_label.text += " | 已耗尽"


func _close_loot_panel() -> void:
	if is_instance_valid(loot_panel):
		loot_panel.visible = false
	open_loot_container_id = &""
	_restore_inventory_after_loot_state()
	_refresh_action_bar()


func _on_extraction_confirm_pressed() -> void:
	confirm_extraction()


func _on_extraction_cancel_pressed() -> void:
	cancel_extraction()


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


func _on_inventory_collapse_pressed() -> void:
	_set_inventory_body_collapsed(not inventory_body_collapsed)


func _set_inventory_body_collapsed(collapsed: bool) -> void:
	inventory_body_collapsed = collapsed
	var body_visible := not collapsed
	inventory_summary_label.visible = body_visible
	inventory_hint_label.visible = body_visible
	inventory_grid.visible = body_visible
	loot_overview_label.visible = body_visible
	inventory_collapse_button.text = "展开" if collapsed else "收起"
	_sync_inventory_panel_layout()


func _sync_inventory_panel_layout() -> void:
	if not is_instance_valid(top_left_panel) or not is_instance_valid(inventory_panel):
		return
	# Both panels are siblings under HUD, so the top-left offset plus its
	# effective content height is the stable coordinate for the next panel.
	# Include the current size as well because a Container may have already
	# expanded beyond its reported minimum during the same layout pass.
	var top_left_height := maxf(top_left_panel.get_combined_minimum_size().y, top_left_panel.size.y)
	var panel_top := top_left_panel.offset_top + top_left_height + INVENTORY_PANEL_LAYOUT_GAP
	inventory_panel.offset_top = panel_top
	if inventory_body_collapsed:
		inventory_panel.offset_bottom = panel_top + INVENTORY_PANEL_COLLAPSED_HEIGHT
	else:
		# Use the stable authored content height rather than the outer panel's
		# combined minimum, whose value can include the panel's current size.
		inventory_panel.offset_bottom = panel_top + INVENTORY_PANEL_EXPANDED_HEIGHT


func _queue_inventory_panel_layout_sync() -> void:
	if _inventory_layout_sync_queued:
		return
	_inventory_layout_sync_queued = true
	call_deferred("_run_deferred_inventory_panel_layout_sync")


func _run_deferred_inventory_panel_layout_sync() -> void:
	_inventory_layout_sync_queued = false
	_sync_inventory_panel_layout()


func _restore_inventory_after_loot_state() -> void:
	if not _restore_inventory_after_loot:
		return
	_restore_inventory_after_loot = false
	_set_inventory_body_collapsed(true)


func _on_session_state_changed(_previous: int, current: int) -> void:
	if _undo_restoring:
		return
	if current != GameStateManagerScript.State.EXTRACTION and is_instance_valid(extraction_panel):
		extraction_panel.visible = false
	if current != GameStateManagerScript.State.RESULT and is_instance_valid(result_panel):
		result_panel.visible = false
	if current != GameStateManagerScript.State.EXPLORATION and current != GameStateManagerScript.State.COMBAT and is_instance_valid(loot_panel):
		loot_panel.visible = false
		open_loot_container_id = &""
		_restore_inventory_after_loot_state()
	if is_instance_valid(inventory_grid):
		inventory_grid.refresh()
	if is_instance_valid(loot_grid) and current != GameStateManagerScript.State.EXPLORATION:
		loot_grid.clear_container()
	_refresh_highlights()
	_update_hud()


func _on_session_result_changed(result: RefCounted) -> void:
	if _undo_restoring:
		return
	if result.success:
		loot_settlement = LootSettlementScript.from_inventory(true, squad_inventory)
		_log("结算：撤离成功，带出 %d 件物品，总价值 %d。" % [loot_settlement.get_items().size(), loot_settlement.get_total_value()])
	else:
		loot_settlement = LootSettlementScript.failure_snapshot()
		_log("结算：任务失败，小队全灭，Loot 全部丢失。")
	_refresh_result_panel()
	_update_hud("撤离成功，结算已完成。" if result.success else "小队全灭，Loot 全部丢失。")


func _refresh_result_panel() -> void:
	if not is_instance_valid(result_panel):
		return
	result_panel.visible = true
	var successful: bool = loot_settlement != null and loot_settlement.is_successful()
	result_title_label.text = "任务成功" if successful else "任务失败"
	result_value_label.text = "带出总价值：%d" % (loot_settlement.get_total_value() if loot_settlement != null else 0)
	var names: Array[String] = []
	if loot_settlement != null:
		for item in loot_settlement.get_items():
			names.append("%s（占%d格，%d°）" % [item.display_name, item.slot_size, _inventory_item_rotation(item)])
	result_items_label.text = "带出物品：" + ("、".join(names) if not names.is_empty() else "无")


func _inventory_item_rotation(item: InventoryItemInstance) -> int:
	## InventoryItemPlacement owns orientation.  InventoryItemInstance.rotation is
	## only a legacy compatibility hint and must not drive settlement UI.
	if item == null or squad_inventory == null:
		return 0
	var placement = squad_inventory.get_placement(item)
	return int(placement.rotation) if placement != null else 0


func _action_rejected(reason: StringName, action_type: StringName, actor_id: StringName = &"", target_id: StringName = &"") -> ActionResult:
	last_action_result = ActionResultScript.rejected(reason, actor_id, target_id, action_type)
	return last_action_result


func _action_message(prefix: String, reason: StringName) -> String:
	var messages := {
		&"invalid_target": "目标无效",
		&"invalid_container": "容器无效",
		&"target_unavailable": "目标不可用",
		&"container_unavailable": "容器已耗尽",
		&"no_ap": "AP 不足",
		&"out_of_range": "距离过远",
		&"inventory_full": "背包空间不足",
		&"wrong_phase": "当前阶段不可操作",
		&"sight_blocked": "视线被掩体阻挡",
		&"projectile_blocked": "弹道被掩体阻挡",
	}
	return "%s：%s。" % [prefix, messages.get(reason, String(reason))]


func _update_enemy_visibility() -> void:
	if not is_instance_valid(turn_manager):
		return
	for enemy_id in _living_enemy_ids():
		var enemy := _unit_by_id(enemy_id)
		if not is_instance_valid(enemy):
			continue
		var alert := enemy_alerts.get(enemy_id) as AlertState
		if alert != null:
			enemy.set_alert_level(alert.get_level())
		else:
			enemy.set_alert_level(AlertState.Level.UNAWARE)
		var visible_to_player := debug_reveal_all
		for player_id in _living_player_ids():
			if visible_to_player:
				break
			var player := _unit_by_id(player_id)
			if is_instance_valid(player) and _can_player_see_with_grid(
				player.grid_cell, enemy.grid_cell, player.vision_range
			):
				visible_to_player = true
				break
		enemy.visible = visible_to_player


func _update_object_visibility() -> void:
	# Visibility refreshes are also a safe reconciliation point for editor/map
	# previews that were freed or queued while the controller still held a
	# dictionary reference.  The helpers clear stale entries before any cast.
	_sync_environment_object_views()
	for object_id in loot_containers.keys():
		var visual := loot_nodes_by_id.get(object_id) as Node3D
		var placement := object_placements.get(object_id) as MapObjectPlacement
		if not is_instance_valid(visual) or placement == null:
			continue
		var visible_to_player := debug_reveal_all
		for player_id in _living_player_ids():
			if visible_to_player:
				break
			var player := _unit_by_id(player_id)
			if is_instance_valid(player) and _can_player_see_with_grid(
				player.grid_cell, placement.cell, player.vision_range
			):
				visible_to_player = true
				break
		visual.visible = visible_to_player
	for raw_placement_id in environment_objects_by_placement_id.keys():
		var placement_id := StringName(raw_placement_id)
		var state := environment_objects_by_placement_id[raw_placement_id] as EnvironmentObjectRuntimeState
		var placement := object_placements.get(placement_id) as MapObjectPlacement
		if state == null or placement == null:
			continue
		var visible_to_player := debug_reveal_all
		if not visible_to_player:
			for player_id in _living_player_ids():
				var player := _unit_by_id(player_id)
				if is_instance_valid(player) and _can_player_see_with_grid(
					player.grid_cell, placement.cell, player.vision_range
				):
					visible_to_player = true
					break
		var typed_view := _get_environment_view(placement_id)
		if typed_view != null:
			typed_view.set_visibility_allowed(visible_to_player)
		else:
			var visual := _get_environment_visual(placement_id)
			if visual != null:
				visual.visible = visible_to_player and state.active and not state.destroyed


func _is_loot_visible(container_id: StringName) -> bool:
	var visual := loot_nodes_by_id.get(container_id) as Node3D
	return is_instance_valid(visual) and visual.visible


func _screen_to_cell(screen_position: Vector2) -> Vector3i:
	var viewport := get_viewport()
	if not is_instance_valid(viewport):
		return grid.invalid_cell() if is_instance_valid(grid) else Vector3i(-1, -1, -1)
	var camera := viewport.get_camera_3d()
	if not is_instance_valid(camera):
		return grid.invalid_cell() if is_instance_valid(grid) else Vector3i(-1, -1, -1)
	var world_3d := get_world_3d()
	if not is_instance_valid(world_3d) or world_3d.direct_space_state == null:
		return grid.invalid_cell() if is_instance_valid(grid) else Vector3i(-1, -1, -1)
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000.0)
	query.collide_with_areas = true
	# FloorGrid and traversal surfaces are layer 1; blocking gameplay objects
	# may also be layer 2. Resolve any hit back to the nearest standable surface.
	query.collision_mask = 3
	var hit := world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return grid.invalid_cell() if is_instance_valid(grid) else Vector3i(-1, -1, -1)
	return grid.world_to_existing_cell(hit[&"position"])


func _player_can_act() -> bool:
	return is_instance_valid(turn_manager) and session_manager != null and session_manager.is_active() and (
		session_manager.get_state() != GameStateManagerScript.State.EXTRACTION and (
			turn_manager.get_phase() == TurnManager.Phase.EXPLORATION or turn_manager.is_player_turn()
		)
	)


func _can_show_tactical_highlights() -> bool:
	return not input_locked \
		and is_instance_valid(selected_unit) \
		and selected_unit.faction == &"player" \
		and selected_unit.is_alive() \
		and _player_can_act()


func _can_show_move_highlights() -> bool:
	return _can_show_tactical_highlights() \
		and action_mode == ACTION_MODE_MOVE \
		and selected_unit.can_spend_action_points(MOVE_ACTION_COST)


func _is_terminal() -> bool:
	return session_manager != null and session_manager.is_terminal()


func _manhattan(a: Vector3i, b: Vector3i) -> int:
	return GridVisibility.tactical_distance(a, b)


func _cell_less(a: Vector3i, b: Vector3i) -> bool:
	return a.y < b.y or (a.y == b.y and (a.z < b.z or (a.z == b.z and a.x < b.x)))


func _alert_summary() -> String:
	var suspicious := 0
	var alerted := 0
	var engaged := 0
	for alert_value in enemy_alerts.values():
		var alert := alert_value as AlertState
		if alert == null:
			continue
		match alert.get_level():
			AlertState.Level.ENGAGED:
				engaged += 1
			AlertState.Level.ALERTED:
				alerted += 1
			AlertState.Level.SUSPICIOUS:
				suspicious += 1
	if engaged > 0:
		var extra := ""
		if alerted > 0 and suspicious > 0:
			extra = " · 发现 %d · 警戒 %d" % [alerted, suspicious]
		elif alerted > 0:
			extra = " · 发现 %d" % alerted
		elif suspicious > 0:
			extra = " · 警戒 %d" % suspicious
		return "交战 %d%s" % [engaged, extra]
	if alerted > 0:
		return "发现 %d (击杀倒计时)" % alerted if suspicious == 0 else "发现 %d · 警戒 %d" % [alerted, suspicious]
	if suspicious > 0:
		return "警戒 %d" % suspicious
	return "未警戒"


## Prints a structured combat/exploration line to the Godot Output log,
## prefixed with the current side and world tick.
func _log(message: String) -> void:
	print("[%s · T%d] %s" % [_log_side_name(), world_tick, message])


func _log_side_name() -> String:
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.COMBAT and turn_manager != null:
		match turn_manager.get_phase():
			TurnManager.Phase.PLAYER_TURN: return "玩家回合"
			TurnManager.Phase.ENEMY_TURN: return "敌方回合"
		return "交战"
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.EXTRACTION:
		return "撤离"
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.RESULT:
		return "结算"
	return "探索"


func _phase_name() -> String:
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.RESULT:
		return "结果"
	if session_manager != null and session_manager.get_state() == GameStateManagerScript.State.EXTRACTION:
		return "撤离确认"
	match turn_manager.get_phase():
		TurnManager.Phase.EXPLORATION: return "探索阶段"
		TurnManager.Phase.PLAYER_TURN: return "交战 · 玩家回合"
		TurnManager.Phase.ENEMY_TURN: return "交战 · 敌方回合"
		TurnManager.Phase.VICTORY: return "胜利 · 敌方全灭"
		TurnManager.Phase.DEFEAT: return "失败 · 小队全灭"
	return "未知阶段"


func _update_hud(message: String = "") -> void:
	if not is_instance_valid(turn_manager):
		return
	if is_instance_valid(phase_label):
		phase_label.text = "%s · 世界 Tick %d" % [_phase_name(), world_tick]
	if is_instance_valid(alert_label):
		alert_label.text = "敌方警戒：%s" % _alert_summary()
	if is_instance_valid(selection_label):
		if is_instance_valid(selected_unit):
			if selected_unit.faction == &"enemy":
				var alert_text := "未警戒"
				if enemy_alerts.has(selected_unit.unit_id):
					var alert := enemy_alerts[selected_unit.unit_id] as AlertState
					match alert.get_level():
						AlertState.Level.SUSPICIOUS: alert_text = "警戒"
						AlertState.Level.ALERTED: alert_text = "发现!"
						AlertState.Level.ENGAGED: alert_text = "交战"
				selection_label.text = "%s | HP %d/%d | 移动 %d | 伤害 %d (危险 %d) | 视野 外%d/内%d | %s" % [
					selected_unit.name, selected_unit.current_hp, selected_unit.max_hp,
					selected_unit.move_range, selected_unit.attack_damage,
					selected_unit.attack_range, selected_unit.vision_range, selected_unit.inner_vision_range, alert_text,
				]
			else:
				var archetype_name := selected_unit.archetype.display_name if selected_unit.archetype != null else "未配置原型"
				selection_label.text = "%s | 原型 %s | 武器 %s\n伤害 %d | 射程 %d | 攻击 AP %d\nHP %d/%d | AP %d/%d | 格 %s" % [
					selected_unit.name, archetype_name, selected_unit.get_weapon_display_name(),
					selected_unit.attack_damage, selected_unit.attack_range, selected_unit.attack_ap_cost,
					selected_unit.current_hp, selected_unit.max_hp,
					selected_unit.current_action_points, selected_unit.max_action_points,
					selected_unit.grid_cell,
				]
		else:
			selection_label.text = "未选择单位"
	if is_instance_valid(end_turn_button):
		end_turn_button.text = "推进探索 Tick" if turn_manager.get_phase() == TurnManager.Phase.EXPLORATION else "结束玩家回合"
		end_turn_button.disabled = input_locked or _is_terminal() or turn_manager.is_enemy_turn() or (session_manager != null and session_manager.get_state() == GameStateManagerScript.State.EXTRACTION)
	_refresh_action_bar()
	if is_instance_valid(inventory_summary_label) and squad_inventory != null:
		inventory_summary_label.text = "背包 6×8 · %d/%d | 总价值 %d" % [squad_inventory.used, squad_inventory.capacity, squad_inventory.total_value()]
	if is_instance_valid(inventory_grid) and squad_inventory != null:
		inventory_grid.refresh()
	if is_instance_valid(loot_overview_label):
		var available := 0
		for container_value in loot_containers.values():
			var container = container_value
			if container != null and not container.is_depleted():
				available += 1
		loot_overview_label.text = "Loot 容器：%d 个可搜刮" % available
	if not message.is_empty() and is_instance_valid(hint_label):
		hint_label.text = message
	_sync_inventory_panel_layout()
	_queue_inventory_panel_layout_sync()
	_refresh_undo_buttons()
