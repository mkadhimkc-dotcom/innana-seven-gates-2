class_name TestSuite
extends RefCounted

## Minimal assertion framework for the headless test runner.
##
## Deliberately tiny and dependency-free: the tests exist to protect the
## deterministic simulation, and a test harness that needs its own harness is
## not worth the risk.

var suite_name: String = "suite"
var passed: int = 0
var failures: PackedStringArray = PackedStringArray()

var _current: String = ""


## Overridden by each suite.
func run() -> void:
	pass


func test(name: String) -> void:
	_current = name


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append("%s / %s: %s" % [suite_name, _current, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (got %s, expected %s)"
			% [message, str(actual), str(expected)])


func check_ne(actual: Variant, unexpected: Variant, message: String) -> void:
	check(actual != unexpected, "%s (got %s)" % [message, str(actual)])


# --- shared fixtures ------------------------------------------------------

## Build a CollisionMap from an ASCII sketch, using the standard legend.
static func map_from(rows: Array) -> CollisionMap:
	var h: int = rows.size()
	var w: int = 0
	for r: Variant in rows:
		w = maxi(w, str(r).length())
	var m: CollisionMap = CollisionMap.new(w, h)
	for y: int in h:
		var row: String = str(rows[y])
		for x: int in w:
			var ch: String = row.substr(x, 1) if x < row.length() else "."
			m.set_at(x, y, int(LevelData.DEFAULT_LEGEND.get(ch, TileDB.T.EMPTY)))
	return m


## Run a player for N ticks against a fixed button mask.
static func hold(p: PlayerSim, mask: int, ticks: int) -> void:
	var prev: int = 0
	for _i: int in ticks:
		p.tick(InputFrame.from_mask(mask, prev))
		prev = mask


## As above, but the first tick reports the buttons as newly pressed.
static func press(p: PlayerSim, mask: int, ticks: int) -> void:
	var prev: int = 0
	for _i: int in ticks:
		p.tick(InputFrame.from_mask(mask, prev))
		prev = mask
