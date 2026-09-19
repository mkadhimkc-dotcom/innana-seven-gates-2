class_name InputRouter
extends Node

## Turns every input source into one InputFrame per simulation tick
## (spec sections 6, 11).
##
## Keyboard, gamepad and the on-screen pad all feed the same button mask, so
## the simulation cannot tell them apart. A recorded mask sequence replays
## identically, which is what the determinism tests and the replay system rely
## on.

## Extra button mask contributed by the virtual pad this tick.
var touch_mask: int = 0

var _prev_mask: int = 0
var _recording: bool = false
var _record: PackedInt32Array = PackedInt32Array()
var _playback: PackedInt32Array = PackedInt32Array()
var _playback_i: int = -1


## Build this tick's frame. Called exactly once per simulation tick.
func poll() -> InputFrame:
	var mask: int = _playback_mask() if is_playing_back() else _live_mask()
	if _recording:
		_record.append(mask)
	var frame: InputFrame = InputFrame.from_mask(mask, _prev_mask)
	_prev_mask = mask
	return frame


func _live_mask() -> int:
	var m: int = touch_mask
	if Input.is_action_pressed("move_left"):
		m |= InputFrame.B_LEFT
	if Input.is_action_pressed("move_right"):
		m |= InputFrame.B_RIGHT
	if Input.is_action_pressed("move_up"):
		m |= InputFrame.B_UP
	if Input.is_action_pressed("move_down"):
		m |= InputFrame.B_DOWN
	if Input.is_action_pressed("jump"):
		m |= InputFrame.B_JUMP
	if Input.is_action_pressed("action"):
		m |= InputFrame.B_ACTION
	if Input.is_action_pressed("run"):
		m |= InputFrame.B_RUN
	return m


# --- recording and replay -------------------------------------------------

func start_recording() -> void:
	_record = PackedInt32Array()
	_recording = true


func stop_recording() -> PackedInt32Array:
	_recording = false
	return _record


func play(masks: PackedInt32Array) -> void:
	_playback = masks
	_playback_i = 0
	_prev_mask = 0


func is_playing_back() -> bool:
	return _playback_i >= 0 and _playback_i < _playback.size()


func _playback_mask() -> int:
	var m: int = _playback[_playback_i]
	_playback_i += 1
	return m


func stop_playback() -> void:
	_playback = PackedInt32Array()
	_playback_i = -1


## Build a frame sequence from a compact script, for tests and for the QA
## menu. Each entry is [button mask, tick count].
static func script_to_masks(steps: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for s: Variant in steps:
		var pair: Array = s as Array
		for _i: int in int(pair[1]):
			out.append(int(pair[0]))
	return out
