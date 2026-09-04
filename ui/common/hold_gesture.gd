class_name HoldGesture
extends RefCounted

## Hold-to-confirm, shared by every control that asks for one: the commit
## button on a dangerous action, the abort lever on a destructive pull. The
## owner feeds it a begin on press, ticks it every frame while held and cancels
## it on release, pointer exit, focus loss or window unfocus; the gesture keeps
## the clock and reports progress and the one frame it completes on.
##
## Deliberately dumb about input: what counts as "press" and "release" differs
## between a Button and a lever, so the owner decides that and this only times.

signal completed
signal cancelled
signal progress_changed(ratio: float)

## The spec's default: 650 ms.
const DEFAULT_SECONDS := 0.65

var seconds: float = DEFAULT_SECONDS
var _elapsed: float = 0.0
var _holding: bool = false
var _done: bool = false


func _init(hold_seconds: float = DEFAULT_SECONDS) -> void:
	seconds = maxf(0.05, hold_seconds)


## Starts the clock. A hold already in progress is left alone.
func begin() -> void:
	if _holding:
		return
	_holding = true
	_done = false
	_elapsed = 0.0
	progress_changed.emit(0.0)


## Advances the clock; returns true on the frame the hold completes. Once
## complete the gesture stays complete (no second emit) until `reset()`.
func tick(delta: float) -> bool:
	if not _holding or _done:
		return false
	_elapsed += maxf(0.0, delta)
	var ratio: float = progress()
	progress_changed.emit(ratio)
	if ratio >= 1.0:
		_done = true
		_holding = false
		completed.emit()
		return true
	return false


## Abandons a hold in progress. A completed hold is not "cancelled": the
## release after a completed hold is the finger coming off, not a change of
## mind, so only an unfinished hold reports one.
func cancel() -> void:
	if _holding and not _done:
		_holding = false
		_elapsed = 0.0
		progress_changed.emit(0.0)
		cancelled.emit()
	_holding = false


## Clears a completed hold so the next press starts a fresh one.
func reset() -> void:
	_holding = false
	_done = false
	_elapsed = 0.0


func is_holding() -> bool:
	return _holding and not _done


func is_done() -> bool:
	return _done


func progress() -> float:
	if _done:
		return 1.0
	if not _holding:
		return 0.0
	return clampf(_elapsed / seconds, 0.0, 1.0)
