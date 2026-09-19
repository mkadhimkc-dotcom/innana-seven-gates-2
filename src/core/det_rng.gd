class_name DetRng
extends RefCounted

## Deterministic seeded random source (spec sections 6, 38).
##
## Godot's built-in RandomNumberGenerator is not guaranteed stable across
## engine versions, so procedural variation and NG+ modifiers use this
## xorshift32 instead. Same seed, same call order, same results, forever.

const MASK: int = 0xFFFFFFFF

var state: int = 1


func _init(seed_value: int = 1) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	state = seed_value & MASK
	if state == 0:
		state = 0x9E3779B9


## Raw 32-bit draw.
func next_u32() -> int:
	var x: int = state
	x ^= (x << 13) & MASK
	x ^= (x >> 17)
	x ^= (x << 5) & MASK
	state = x & MASK
	return state


## Uniform integer in [lo, hi] inclusive. Rejection-sampled so the
## distribution does not skew with range size.
func next_range(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	var span: int = hi - lo + 1
	var limit: int = MASK - (MASK % span)
	var r: int = next_u32()
	while r >= limit:
		r = next_u32()
	return lo + (r % span)


## True with probability numerator/denominator.
func chance(numerator: int, denominator: int) -> bool:
	return next_range(1, denominator) <= numerator


## Fisher-Yates, in place. Mutates and returns the same array.
func shuffle(arr: Array) -> Array:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = next_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr


func fork(tag: int) -> DetRng:
	return DetRng.new((state ^ (tag * 0x85EBCA6B)) & MASK)
