class_name CollisionMap
extends RefCounted

## Runtime tile grid and all spatial queries the movement code needs.
##
## Conditional tiles (spec section 7) are *materialised* here: when a gate
## opens the tile genuinely becomes OPEN_GATE, when a floor collapses it
## genuinely becomes EMPTY. Collision therefore never has to consult puzzle
## state, which keeps queries cheap and makes the validator's job tractable.

var width: int = 0
var height: int = 0
var tiles: PackedByteArray = PackedByteArray()


func _init(w: int = 0, h: int = 0) -> void:
	width = w
	height = h
	tiles = PackedByteArray()
	if w > 0 and h > 0:
		tiles.resize(w * h)


static func from_level(lv: LevelData) -> CollisionMap:
	var m: CollisionMap = CollisionMap.new(lv.width, lv.height)
	m.tiles = lv.tiles.duplicate()
	return m


func clone() -> CollisionMap:
	var m: CollisionMap = CollisionMap.new(width, height)
	m.tiles = tiles.duplicate()
	return m


func in_bounds(tx: int, ty: int) -> bool:
	return tx >= 0 and ty >= 0 and tx < width and ty < height


## Out-of-bounds reads as solid wall so the level edge is always a boundary
## (spec section 7: TEMPLE_WALL is the architectural boundary).
func at(tx: int, ty: int) -> int:
	if not in_bounds(tx, ty):
		return TileDB.T.TEMPLE_WALL
	return tiles[ty * width + tx]


func set_at(tx: int, ty: int, id_value: int) -> void:
	if in_bounds(tx, ty):
		tiles[ty * width + tx] = id_value


func has_flag(tx: int, ty: int, flag: int) -> bool:
	return TileDB.has(at(tx, ty), flag)


func is_solid(tx: int, ty: int) -> bool:
	return has_flag(tx, ty, TileDB.F_SOLID)


func is_support(tx: int, ty: int) -> bool:
	return has_flag(tx, ty, TileDB.F_SUPPORT)


func is_climb(tx: int, ty: int) -> bool:
	return has_flag(tx, ty, TileDB.F_CLIMB)


func is_hazard(tx: int, ty: int) -> bool:
	return has_flag(tx, ty, TileDB.F_HAZARD)


func stair_dir(tx: int, ty: int) -> int:
	## +1 when the stair ascends to the right, -1 to the left, 0 if not a stair.
	var id_value: int = at(tx, ty)
	if TileDB.has(id_value, TileDB.F_STAIR_R):
		return 1
	if TileDB.has(id_value, TileDB.F_STAIR_L):
		return -1
	return 0


func is_stair(tx: int, ty: int) -> bool:
	return stair_dir(tx, ty) != 0


# --- subunit-space queries ------------------------------------------------
# The body box is BODY_W x BODY_H world units anchored bottom-centre
# (spec section 9). `ax`/`ay` below are always that anchor, in subunits.

func body_left(ax: int) -> int:
	return ax - Grid.BODY_W_SUB / 2


func body_right(ax: int) -> int:
	## Inclusive right edge. Subtracting one subunit keeps a body whose width
	## exactly spans a tile from reporting an overlap with the next tile over.
	return ax + Grid.BODY_W_SUB / 2 - 1


func body_top(ay: int) -> int:
	return ay - Grid.BODY_H_SUB


func body_bottom(ay: int) -> int:
	return ay - 1


## Does the body box at this anchor overlap any solid tile?
func body_blocked(ax: int, ay: int) -> bool:
	var x0: int = Grid.to_tile(body_left(ax))
	var x1: int = Grid.to_tile(body_right(ax))
	var y0: int = Grid.to_tile(body_top(ay))
	var y1: int = Grid.to_tile(body_bottom(ay))
	for ty: int in range(y0, y1 + 1):
		for tx: int in range(x0, x1 + 1):
			if is_solid(tx, ty):
				return true
	return false


## Does the body box overlap any hazard tile?
func body_on_hazard(ax: int, ay: int) -> bool:
	var x0: int = Grid.to_tile(body_left(ax))
	var x1: int = Grid.to_tile(body_right(ax))
	var y0: int = Grid.to_tile(body_top(ay))
	var y1: int = Grid.to_tile(body_bottom(ay))
	for ty: int in range(y0, y1 + 1):
		for tx: int in range(x0, x1 + 1):
			if is_hazard(tx, ty):
				return true
	return false


## All tiles the body box currently overlaps, top-left to bottom-right.
func body_tiles(ax: int, ay: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0: int = Grid.to_tile(body_left(ax))
	var x1: int = Grid.to_tile(body_right(ax))
	var y0: int = Grid.to_tile(body_top(ay))
	var y1: int = Grid.to_tile(body_bottom(ay))
	for ty: int in range(y0, y1 + 1):
		for tx: int in range(x0, x1 + 1):
			out.append(Vector2i(tx, ty))
	return out


## Standing requires the feet to sit exactly on a tile boundary with a
## supporting tile beneath either foot. Testing both the left and right foot
## (rather than the centre) is what lets the player walk off a ledge only once
## genuinely past it.
func on_ground(ax: int, ay: int) -> bool:
	if Grid.fmod_i(ay, Grid.TILE_SUB) != 0:
		return false
	var ty: int = Grid.to_tile(ay)
	var xl: int = Grid.to_tile(body_left(ax))
	var xr: int = Grid.to_tile(body_right(ax))
	for tx: int in range(xl, xr + 1):
		if is_support(tx, ty):
			return true
	return false


## The ladder the anchor is standing in, if any.
func climb_at_anchor(ax: int, ay: int) -> bool:
	## Ladders are entered from the tile column the player's centre is in,
	## which is why this tests the centre rather than the whole box: a player
	## brushing a ladder with one shoulder should not snap onto it.
	var tx: int = Grid.to_tile(ax)
	var ty_feet: int = Grid.to_tile(ay - 1)
	return is_climb(tx, ty_feet)


## A ladder directly below the feet, used to step down off a ledge onto one.
func climb_below(ax: int, ay: int) -> bool:
	return is_climb(Grid.to_tile(ax), Grid.to_tile(ay))


## The topmost solid surface at or below `ay` in this column, in subunits.
## Returns -1 when the column is bottomless.
func floor_below(ax: int, ay: int) -> int:
	var tx: int = Grid.to_tile(ax)
	var ty: int = Grid.to_tile(ay)
	while ty < height:
		if is_support(tx, ty):
			return Grid.tile_origin(ty)
		ty += 1
	return -1
