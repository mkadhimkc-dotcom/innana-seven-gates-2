class_name PlayerHooks
extends RefCounted

## The narrow interface through which the player FSM is allowed to affect the
## world (spec section 10).
##
## Section 10 forbids unrelated systems from reaching into player movement.
## This is the mirror of that rule: the player reaches out through exactly
## these four calls and nothing else. WorldSim binds them to its own methods;
## tests bind them to stubs. Callables rather than inheritance, so that
## PlayerSim and WorldSim never have to reference each other.

## can_push(tile: Vector2i, dir: int) -> bool
## May the player displace the pushable tile one step in `dir`? WorldSim
## answers this by validating the resulting state, which is what makes a
## route-sealing push impossible (spec section 17).
var can_push_fn: Callable = Callable()

## do_push(tile: Vector2i, dir: int) -> void
## Commit the push. Only ever called after can_push() returned true.
var do_push_fn: Callable = Callable()

## try_interact(tile: Vector2i, facing: int) -> bool
## Context-sensitive action. Returns true if something actually happened,
## which is what tells the FSM to enter INTERACTING rather than swing.
var try_interact_fn: Callable = Callable()

## try_attack(tile: Vector2i, facing: int) -> bool
## Melee swing resolution. Returns true if the swing connected.
var try_attack_fn: Callable = Callable()


func can_push(tile: Vector2i, dir: int) -> bool:
	return can_push_fn.call(tile, dir) if can_push_fn.is_valid() else false


func do_push(tile: Vector2i, dir: int) -> void:
	if do_push_fn.is_valid():
		do_push_fn.call(tile, dir)


func try_interact(tile: Vector2i, facing: int) -> bool:
	return try_interact_fn.call(tile, facing) if try_interact_fn.is_valid() else false


func try_attack(tile: Vector2i, facing: int) -> bool:
	return try_attack_fn.call(tile, facing) if try_attack_fn.is_valid() else false
