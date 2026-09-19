class_name TileDB
extends RefCounted

## The world tile system (spec section 7).
##
## Tile behaviour is expressed as a bitmask of capabilities rather than as a
## `match` over tile IDs, so a new tile type is a single `register()` call and
## never requires touching the movement, collision or validation code.

## Capability flags.
const F_SOLID: int          = 1 << 0   ## Blocks the body box outright.
const F_SUPPORT: int        = 1 << 1   ## Can be stood upon from above.
const F_CLIMB: int          = 1 << 2   ## Vertical traversal lane.
const F_STAIR_L: int        = 1 << 3   ## Ascends to the up-left.
const F_STAIR_R: int        = 1 << 4   ## Ascends to the up-right.
const F_HAZARD: int         = 1 << 5   ## Damages on contact.
const F_DESTRUCTIBLE: int   = 1 << 6   ## May be removed by gameplay.
const F_CONDITIONAL: int    = 1 << 7   ## Solidity depends on runtime state.
const F_SWIM: int           = 1 << 8   ## Traversed by swimming, not walking.
const F_TRIGGER: int        = 1 << 9   ## Reports overlap to the puzzle layer.
const F_EXIT: int           = 1 << 10  ## Completes the level on overlap.
const F_OCCLUDE: int        = 1 << 11  ## Blocks line of sight / light.
const F_PUSHABLE: int       = 1 << 12  ## Can be displaced by the player.
const F_DARK: int           = 1 << 13  ## Requires a light source to see.

## Base tile identifiers (spec section 7). Values are stable and must not be
## renumbered: level files store them by value.
enum T {
	EMPTY = 0,
	TEMPLE_WALL = 1,
	MUD_BRICK_FLOOR = 2,
	LADDER = 3,
	STAIR_LEFT = 4,
	STAIR_RIGHT = 5,
	LOCKED_GATE = 6,
	OPEN_GATE = 7,
	SPIKES = 8,
	COLLAPSING_FLOOR = 9,
	WATER = 10,
	PILLAR = 11,
	PRESSURE_PLATE = 12,
	MOVABLE_BLOCK = 13,
	HIDDEN_PASSAGE = 14,
	DARKNESS_ZONE = 15,
}

## id -> { name, flags, palette_key }
static var _defs: Dictionary = {}
static var _ready: bool = false


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	register(T.EMPTY, "EMPTY", 0, "empty")
	register(T.TEMPLE_WALL, "TEMPLE_WALL", F_SOLID | F_SUPPORT | F_OCCLUDE, "wall")
	register(T.MUD_BRICK_FLOOR, "MUD_BRICK_FLOOR",
			F_SOLID | F_SUPPORT | F_OCCLUDE | F_DESTRUCTIBLE, "brick")
	register(T.LADDER, "LADDER", F_CLIMB, "ladder")
	register(T.STAIR_LEFT, "STAIR_LEFT", F_STAIR_L | F_SUPPORT, "stair")
	register(T.STAIR_RIGHT, "STAIR_RIGHT", F_STAIR_R | F_SUPPORT, "stair")
	register(T.LOCKED_GATE, "LOCKED_GATE", F_SOLID | F_CONDITIONAL, "gate_locked")
	register(T.OPEN_GATE, "OPEN_GATE", F_EXIT | F_TRIGGER, "gate_open")
	register(T.SPIKES, "SPIKES", F_HAZARD | F_TRIGGER, "spikes")
	register(T.COLLAPSING_FLOOR, "COLLAPSING_FLOOR",
			F_SOLID | F_SUPPORT | F_CONDITIONAL | F_DESTRUCTIBLE, "collapse")
	register(T.WATER, "WATER", F_SWIM | F_TRIGGER, "water")
	register(T.PILLAR, "PILLAR", F_SOLID | F_OCCLUDE, "pillar")
	register(T.PRESSURE_PLATE, "PRESSURE_PLATE", F_TRIGGER | F_SUPPORT, "plate")
	register(T.MOVABLE_BLOCK, "MOVABLE_BLOCK",
			F_SOLID | F_SUPPORT | F_PUSHABLE, "block")
	register(T.HIDDEN_PASSAGE, "HIDDEN_PASSAGE",
			F_SOLID | F_CONDITIONAL | F_OCCLUDE, "hidden")
	register(T.DARKNESS_ZONE, "DARKNESS_ZONE", F_DARK, "dark")


## Add or replace a tile definition. Gates beyond the base set register their
## own tiles at load time; ids 64+ are reserved for that.
static func register(id: int, tile_name: String, flags: int, palette_key: String) -> void:
	_defs[id] = {"name": tile_name, "flags": flags, "palette": palette_key}


static func flags_of(id: int) -> int:
	_ensure()
	var d: Variant = _defs.get(id)
	if d == null:
		return 0
	return (d as Dictionary)["flags"]


static func name_of(id: int) -> String:
	_ensure()
	var d: Variant = _defs.get(id)
	if d == null:
		return "UNKNOWN(%d)" % id
	return (d as Dictionary)["name"]


static func palette_of(id: int) -> String:
	_ensure()
	var d: Variant = _defs.get(id)
	if d == null:
		return "empty"
	return (d as Dictionary)["palette"]


static func has(id: int, flag: int) -> bool:
	return (flags_of(id) & flag) != 0


static func all_ids() -> Array:
	_ensure()
	return _defs.keys()
