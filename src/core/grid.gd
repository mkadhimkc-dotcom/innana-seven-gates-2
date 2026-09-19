class_name Grid
extends RefCounted

## Fundamental spatial and temporal constants (spec sections 5, 6, 9).
##
## Every gameplay quantity in this project is an integer. Positions are stored
## in FIXED-POINT SUBUNITS so that movement can be sub-world-unit smooth while
## remaining exactly reproducible on every device. Nothing in the simulation
## layer is permitted to use float maths.

## World units per tile edge.
const TILE: int = 16

## Standard puzzle screen, in tiles.
const SCREEN_W: int = 16
const SCREEN_H: int = 12

## Standard puzzle screen, in world units.
const VIEW_W: int = TILE * SCREEN_W   # 256
const VIEW_H: int = TILE * SCREEN_H   # 192

## Fixed-point resolution: subunits per world unit.
const SUB: int = 16

## Subunits per tile edge.
const TILE_SUB: int = TILE * SUB      # 256

## Simulation rate. The renderer may run faster or slower; the simulation
## never does.
const TICK_HZ: int = 60

## Player bounding box, world units (spec section 9).
const BODY_W: int = 12
const BODY_H: int = 14
const BODY_W_SUB: int = BODY_W * SUB  # 192
const BODY_H_SUB: int = BODY_H * SUB  # 224


## Convert world units to subunits.
static func wu(v: int) -> int:
	return v * SUB


## Convert tiles to subunits.
static func tiles(v: int) -> int:
	return v * TILE_SUB


## Floor-divide that behaves correctly for negative operands. GDScript's `/`
## truncates toward zero, which would make tile lookups asymmetric across the
## origin and break collision on the left/top edges of a level.
static func fdiv(a: int, b: int) -> int:
	var q: int = a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Modulo that always returns a non-negative result for a positive divisor.
static func fmod_i(a: int, b: int) -> int:
	var r: int = a % b
	if r < 0:
		r += b
	return r


## Subunit coordinate -> tile index.
static func to_tile(sub: int) -> int:
	return fdiv(sub, TILE_SUB)


## Tile index -> subunit coordinate of the tile's top-left corner.
static func tile_origin(t: int) -> int:
	return t * TILE_SUB


## Tile index -> subunit coordinate of the tile's horizontal centre.
static func tile_center(t: int) -> int:
	return t * TILE_SUB + TILE_SUB / 2


## Snap a subunit coordinate to the nearest tile centre.
static func snap_to_center(sub: int) -> int:
	return tile_center(to_tile(sub))


## Snap a subunit coordinate down to the tile boundary at or below it.
static func snap_to_boundary(sub: int) -> int:
	return tile_origin(to_tile(sub))


## Subunits -> float pixels, for the render layer only.
static func to_px(sub: int) -> float:
	return float(sub) / float(SUB)
