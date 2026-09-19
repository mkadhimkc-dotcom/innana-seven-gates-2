class_name InputFrame
extends RefCounted

## One tick's worth of player intent (spec sections 6, 11).
##
## The simulation reads InputFrame and nothing else. Keyboard, gamepad, touch
## controls, replay playback and automated tests all produce the same struct,
## which is what makes recorded input reproducible.

const B_LEFT: int   = 1 << 0
const B_RIGHT: int  = 1 << 1
const B_UP: int     = 1 << 2
const B_DOWN: int   = 1 << 3
const B_JUMP: int   = 1 << 4
const B_ACTION: int = 1 << 5
const B_RUN: int    = 1 << 6

## Bitmask of buttons held this tick.
var held: int = 0
## Bitmask of buttons that went down on this exact tick.
var pressed: int = 0


func _init(held_mask: int = 0, prev_mask: int = 0) -> void:
	held = held_mask
	pressed = held_mask & ~prev_mask


func is_held(b: int) -> bool:
	return (held & b) != 0


func just_pressed(b: int) -> bool:
	return (pressed & b) != 0


## -1, 0 or +1. Opposing inputs cancel, which keeps the player from
## vibrating between tiles when both directions are held.
func axis_x() -> int:
	var l: bool = is_held(B_LEFT)
	var r: bool = is_held(B_RIGHT)
	if l == r:
		return 0
	return -1 if l else 1


func axis_y() -> int:
	var u: bool = is_held(B_UP)
	var d: bool = is_held(B_DOWN)
	if u == d:
		return 0
	return -1 if u else 1


func duplicate_frame() -> InputFrame:
	var f: InputFrame = InputFrame.new()
	f.held = held
	f.pressed = pressed
	return f


static func from_mask(held_mask: int, prev_mask: int) -> InputFrame:
	return InputFrame.new(held_mask, prev_mask)
