class_name TacticalUndoManager
extends RefCounted

## Small, scene-independent checkpoint manager for player actions.
##
## The manager owns at most one completed-action checkpoint and one player-turn
## checkpoint.  Capture and restore are injected so the manager never becomes
## the owner of gameplay state or depends on a scene node.

signal availability_changed(can_step: bool, can_turn: bool)

var _capture_callable: Callable
var _restore_callable: Callable
var _pending_checkpoint: Variant = null
var _step_checkpoint: Variant = null
var _turn_checkpoint: Variant = null
var _turn_has_successful_action: bool = false
var _action_in_progress: bool = false
var _locked: bool = false
var _restoring: bool = false
var _last_can_step: bool = false
var _last_can_turn: bool = false


## Installs the state callbacks and starts with no checkpoints.
##
## Reconfiguration deliberately invalidates old checkpoints because they may
## belong to a different state owner.  The return value is a convenience for
## callers that want to fail fast when either callback is missing.
func configure(capture_callable: Callable, restore_callable: Callable) -> bool:
	_capture_callable = capture_callable
	_restore_callable = restore_callable
	_pending_checkpoint = null
	_step_checkpoint = null
	_turn_checkpoint = null
	_turn_has_successful_action = false
	_action_in_progress = false
	_emit_availability_if_changed()
	return _capture_callable.is_valid() and _restore_callable.is_valid()


## Captures the state at the beginning of a player-operable turn.
## A successful new turn capture starts that turn with no step checkpoint.
func capture_turn_checkpoint() -> bool:
	if _locked or _restoring or _action_in_progress:
		return false
	var snapshot: Variant = _capture_snapshot()
	if snapshot == null:
		return false
	_turn_checkpoint = snapshot
	_pending_checkpoint = null
	_step_checkpoint = null
	_turn_has_successful_action = false
	_emit_availability_if_changed()
	return true


## Opens the transaction for one player state-changing action.
func begin_player_action() -> bool:
	if _locked or _restoring or _action_in_progress:
		return false
	var snapshot: Variant = _capture_snapshot()
	if snapshot == null:
		return false
	_pending_checkpoint = snapshot
	_action_in_progress = true
	_emit_availability_if_changed()
	return true


## Commits a successfully completed player action by promoting its detached
## pre-action snapshot to the step checkpoint.  The caller must only invoke
## this after the gameplay mutation and its validation have succeeded.
func commit_player_action() -> bool:
	if not _action_in_progress or _pending_checkpoint == null:
		return false
	_action_in_progress = false
	_step_checkpoint = _pending_checkpoint
	_pending_checkpoint = null
	_turn_has_successful_action = _turn_checkpoint != null
	_emit_availability_if_changed()
	return true


## Cancels the open action without changing either existing checkpoint.
func cancel_player_action() -> bool:
	if not _action_in_progress:
		return false
	_action_in_progress = false
	_pending_checkpoint = null
	_emit_availability_if_changed()
	return true


func can_undo_step() -> bool:
	return not _locked and not _restoring and not _action_in_progress and _step_checkpoint != null


func can_undo_turn() -> bool:
	return not _locked and not _restoring and not _action_in_progress and _turn_checkpoint != null and _turn_has_successful_action


## Restores the last completed action.  A failed restore retains the checkpoint.
func undo_step() -> bool:
	if not can_undo_step():
		return false
	var checkpoint: Variant = _step_checkpoint
	if not _restore_snapshot(checkpoint):
		return false
	_step_checkpoint = null
	_emit_availability_if_changed()
	return true


## Restores the player-turn entry state and consumes both checkpoints.
## A failed restore retains both checkpoints for a later retry.
func undo_turn() -> bool:
	if not can_undo_turn():
		return false
	var checkpoint: Variant = _turn_checkpoint
	if not _restore_snapshot(checkpoint):
		return false
	_step_checkpoint = null
	_turn_checkpoint = null
	_turn_has_successful_action = false
	_emit_availability_if_changed()
	return true


## Temporarily hides both undo actions without discarding their checkpoints.
func set_locked(value: bool) -> void:
	if _locked == value:
		return
	_locked = value
	_emit_availability_if_changed()


## Drops all checkpoints and any open transaction.
func invalidate_all() -> void:
	_pending_checkpoint = null
	_step_checkpoint = null
	_turn_checkpoint = null
	_turn_has_successful_action = false
	_action_in_progress = false
	_emit_availability_if_changed()


func _capture_snapshot() -> Variant:
	if not _capture_callable.is_valid():
		return null
	var captured: Variant = _capture_callable.call()
	if captured == null:
		return null
	return _duplicate_snapshot(captured)


func _restore_snapshot(checkpoint: Variant) -> bool:
	if not _restore_callable.is_valid():
		return false
	_restoring = true
	var result: Variant = _restore_callable.call(_duplicate_snapshot(checkpoint))
	_restoring = false
	return result is bool and result


func _emit_availability_if_changed() -> void:
	var next_can_step := can_undo_step()
	var next_can_turn := can_undo_turn()
	if next_can_step == _last_can_step and next_can_turn == _last_can_turn:
		return
	_last_can_step = next_can_step
	_last_can_turn = next_can_turn
	availability_changed.emit(next_can_step, next_can_turn)


## Deep-copy container snapshots so later gameplay mutations cannot alter a
## checkpoint held by this manager.  Core snapshots are Dictionaries/Arrays;
## scalar values are immutable and can be returned directly.
static func _duplicate_snapshot(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value
