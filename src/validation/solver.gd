class_name Solver
extends RefCounted

## Automated level solvability validation (spec sections 17, 20).
##
## The solver answers one question: from this exact world state, can the
## player still reach the exit having satisfied every requirement?
##
## It is used in three places:
##   * offline, as the gate a level must pass before it can be CERTIFIED;
##   * before committing a push, so a block can never seal the only route;
##   * before accepting a checkpoint, so no impossible state is ever saved.
##
## Movement model
## --------------
## Traversal is deliberately CONSERVATIVE: the solver only allows moves it is
## certain the player controller can perform. It under-approximates jumps
## (one tile of height, two of distance, with clearance checks) and ignores
## enemy timing entirely. A level the solver calls solvable is therefore
## solvable in fact; a level it calls unsolvable may in rare cases be beatable
## by an expert route, which is why failures are reported rather than fatal.
##
## Puzzle model
## ------------
## Reachability and acquisition are computed as a monotone fixpoint: reach
## what you can, take what you find, throw every switch you can touch, open
## what that unlocks, repeat until nothing changes. This is exact for levels
## whose switches only ever open things. Levels that use a switch to CLOSE a
## required route must declare that in validation_rules (see LEVEL_RULES.md)
## so the solver treats the route as conditional instead.

class Report extends RefCounted:
	var solvable: bool = false
	var exit_reachable: bool = false
	var reached_tiles: int = 0
	var acquired: Dictionary = {}          ## object id -> true
	var missing_objects: PackedStringArray = PackedStringArray()
	var missing_treasures: PackedStringArray = PackedStringArray()
	var unreachable_checkpoints: PackedStringArray = PackedStringArray()
	var errors: PackedStringArray = PackedStringArray()

	func summary() -> String:
		if solvable:
			return "SOLVABLE (%d tiles reachable)" % reached_tiles
		var why: PackedStringArray = PackedStringArray()
		if not exit_reachable:
			why.append("exit unreachable")
		if missing_objects.size() > 0:
			why.append("cannot obtain: %s" % ", ".join(missing_objects))
		if missing_treasures.size() > 0:
			why.append("cannot collect required treasure: %s"
					% ", ".join(missing_treasures))
		for e: String in errors:
			why.append(e)
		return "UNSOLVABLE (%s)" % "; ".join(why)


## Jump reach envelope, relative to the departure tile.
##
## Derived from the controller, not guessed: JUMP_V of -60 against GRAVITY of
## 4 rises 26 world units (one tile, never two), and horizontal travel at
## WALK_SPEED over the airborne window reaches just under two tiles at ground
## level. Gaining height costs distance, so a one-tile rise is only credited
## for a one-tile gap. Kept deliberately short of what the controller can
## actually do, so anything the solver calls reachable genuinely is.
const JUMP_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1),
	Vector2i(2, 0), Vector2i(-2, 0),
	Vector2i(2, 1), Vector2i(-2, 1),
]


## Validate a level from its authored start state.
static func validate_level(lv: LevelData) -> Report:
	var map: CollisionMap = CollisionMap.from_level(lv)
	return validate_state(lv, map, lv.player_start, {}, {})


## Validate an arbitrary in-progress world state. `held` is the set of object
## ids already carried; `opened` the set of door ids already open.
static func validate_state(lv: LevelData, map: CollisionMap, start: Vector2i,
		held: Dictionary, opened: Dictionary) -> Report:
	var rep: Report = Report.new()
	var work: CollisionMap = map.clone()
	var acquired: Dictionary = held.duplicate()
	var open_doors: Dictionary = opened.duplicate()
	var thrown: Dictionary = {}
	var exit_unsealed: bool = false

	_apply_open_doors(lv, work, open_doors)

	var reach: Dictionary = {}
	var changed: bool = true
	var guard: int = 0
	while changed:
		changed = false
		guard += 1
		if guard > 64:
			rep.errors.append("fixpoint did not converge (cyclic door logic?)")
			break

		reach = reachable_tiles(work, start)

		for t: Dictionary in lv.required_objects:
			var oid: String = t["id"]
			if not acquired.has(oid) and reach.has(t["pos"]):
				acquired[oid] = true
				changed = true

		for s: Dictionary in lv.switches:
			var sid: String = s["id"]
			if thrown.has(sid):
				continue
			## A plate must be stood on; a lever is worked from beside it.
			var within_reach: bool = (reach.has(s["pos"])
					if str(s.get("type", "lever")) == "plate"
					else _reach_adjacent(reach, s["pos"]))
			if not within_reach:
				continue
			if not _requirements_met(s.get("requires", []), acquired):
				continue
			thrown[sid] = true
			changed = true
			for target: Variant in s.get("targets", []):
				open_doors[str(target)] = true

		for d: Dictionary in lv.doors:
			var did: String = d["id"]
			if open_doors.has(did):
				continue
			## A door with no requirements is switch-operated only; it never
			## opens on contact. This mirrors WorldSim._refresh_doors.
			var reqs: Array = d.get("requires", [])
			if reqs.is_empty():
				continue
			## A locked door tile is solid, so it can never be *stood in*.
			## What matters is whether the player can get next to it.
			if _requirements_met(reqs, acquired) and _reach_adjacent(reach, d["pos"]):
				open_doors[did] = true
				changed = true

		## The exit gate is sealed until its conditions are met, so it only
		## becomes passable once the fixpoint has actually acquired what it
		## asks for. Opening it unconditionally would let the solver route
		## through a locked gate to reach whatever lies beyond it.
		if not exit_unsealed and _requirements_met(
				lv.validation_rules.get("exit_requires", []), acquired):
			exit_unsealed = true
			changed = true
			work.set_at(lv.exit_tile.x, lv.exit_tile.y, TileDB.T.OPEN_GATE)

		if changed:
			_apply_open_doors(lv, work, open_doors)

	rep.reached_tiles = reach.size()
	rep.acquired = acquired

	for t: Dictionary in lv.required_objects:
		if not acquired.has(str(t["id"])):
			rep.missing_objects.append(str(t["id"]))

	for t: Dictionary in lv.treasures:
		if bool(t.get("required", false)) and not reach.has(t["pos"]):
			rep.missing_treasures.append(str(t["id"]))

	for c: Dictionary in lv.checkpoints:
		if not reach.has(c["pos"]):
			rep.unreachable_checkpoints.append(str(c["id"]))

	## The exit counts as reached when the player can stand in its tile and
	## every exit requirement is satisfied.
	var exit_open: bool = _requirements_met(
			lv.validation_rules.get("exit_requires", []), acquired)
	if bool(lv.validation_rules.get("exit_requires_all_treasure", false)):
		for t: Dictionary in lv.treasures:
			var tid: String = str(t["id"])
			if not reach.has(t["pos"]) and not rep.missing_treasures.has(tid):
				exit_open = false
				rep.missing_treasures.append(tid)
	rep.exit_reachable = reach.has(lv.exit_tile) and exit_open

	rep.solvable = (rep.exit_reachable
			and rep.missing_objects.is_empty()
			and rep.missing_treasures.is_empty()
			and rep.errors.is_empty())
	return rep


static func _apply_open_doors(lv: LevelData, map: CollisionMap,
		open_doors: Dictionary) -> void:
	for d: Dictionary in lv.doors:
		if open_doors.has(str(d["id"])):
			var p: Vector2i = d["pos"]
			map.set_at(p.x, p.y, TileDB.T.OPEN_GATE)


## Can the player stand in this tile, or in one orthogonally next to it?
static func _reach_adjacent(reach: Dictionary, t: Vector2i) -> bool:
	if reach.has(t):
		return true
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if reach.has(t + d):
			return true
	return false


static func _requirements_met(reqs: Variant, acquired: Dictionary) -> bool:
	if reqs == null:
		return true
	if typeof(reqs) != TYPE_ARRAY:
		return true
	for r: Variant in (reqs as Array):
		if not acquired.has(str(r)):
			return false
	return true


## Flood fill of every tile the player can occupy, keyed by Vector2i.
## The value is the number of moves taken to get there, which the debug
## overlay draws as a heat map.
static func reachable_tiles(map: CollisionMap, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	var origin: Vector2i = _settle(map, start)
	if not _standable(map, origin):
		return seen
	seen[origin] = 0
	var queue: Array[Vector2i] = [origin]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var depth: int = seen[cur]
		for nxt: Vector2i in _neighbours(map, cur):
			if seen.has(nxt):
				continue
			seen[nxt] = depth + 1
			queue.append(nxt)
	return seen


## Where the player ends up if dropped into this tile: fall until supported.
static func _settle(map: CollisionMap, t: Vector2i) -> Vector2i:
	var p: Vector2i = t
	while p.y < map.height:
		if _supported(map, p) or map.is_climb(p.x, p.y):
			return p
		p.y += 1
	return t


static func _supported(map: CollisionMap, t: Vector2i) -> bool:
	return map.is_support(t.x, t.y + 1) or map.is_stair(t.x, t.y)


## A tile the player body can occupy at all.
##
## The body is 14 world units tall inside a 16 unit tile, so with her feet on
## a tile boundary she fits entirely within one row and the tile above does
## not need to be clear. A one-tile crawl space is genuinely passable, and the
## collision code agrees.
static func _standable(map: CollisionMap, t: Vector2i) -> bool:
	return map.in_bounds(t.x, t.y) and not map.is_solid(t.x, t.y)


static func _neighbours(map: CollisionMap, t: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var grounded: bool = _supported(map, t)
	var on_ladder: bool = map.is_climb(t.x, t.y)

	## Walk / step along a surface, including one-tile steps up and down that
	## stairs make walkable.
	for dx: int in [-1, 1]:
		var side: Vector2i = Vector2i(t.x + dx, t.y)
		if _standable(map, side):
			if _supported(map, side) or map.is_climb(side.x, side.y):
				out.append(side)
			elif grounded or on_ladder:
				## Stepping into thin air: fall to whatever is below.
				var landed: Vector2i = _settle(map, side)
				if _standable(map, landed) and landed != side:
					out.append(landed)
				elif _standable(map, side):
					out.append(side)
		## Stairs connect diagonally.
		var up: Vector2i = Vector2i(t.x + dx, t.y - 1)
		if map.is_stair(t.x, t.y) or map.is_stair(up.x, up.y):
			if _standable(map, up) and _supported(map, up):
				out.append(up)

	## Ladders.
	if on_ladder or map.is_climb(t.x, t.y - 1):
		var up_l: Vector2i = Vector2i(t.x, t.y - 1)
		if _standable(map, up_l):
			out.append(up_l)
	if map.is_climb(t.x, t.y + 1):
		var down_l: Vector2i = Vector2i(t.x, t.y + 1)
		if _standable(map, down_l):
			out.append(down_l)

	## Free fall.
	if not grounded and not on_ladder:
		var landed_down: Vector2i = _settle(map, Vector2i(t.x, t.y + 1))
		if _standable(map, landed_down):
			out.append(landed_down)

	## Jump, only from a standing position.
	if grounded:
		for off: Vector2i in JUMP_OFFSETS:
			var dest: Vector2i = t + off
			if not _standable(map, dest):
				continue
			if not _jump_path_clear(map, t, dest):
				continue
			var final_tile: Vector2i = _settle(map, dest)
			if _standable(map, final_tile):
				out.append(final_tile)
	return out


## Conservative arc check.
##
## The body is 14 world units tall inside a 16 unit tile, so the arc of a jump
## effectively occupies one row at a time. Two conditions are enough: there is
## room to leave the ground, and the whole landing row between departure and
## destination is clear.
##
## Deliberately does NOT require the row above the arc to be clear. A ceiling
## two rows up only cuts the jump short, and she is already high enough to
## land after rising a single tile — demanding headroom there would wrongly
## rule out every jump in a covered corridor.
static func _jump_path_clear(map: CollisionMap, from: Vector2i, to: Vector2i) -> bool:
	if map.is_solid(from.x, from.y - 1):
		return false
	var x0: int = mini(from.x, to.x)
	var x1: int = maxi(from.x, to.x)
	for x: int in range(x0, x1 + 1):
		if map.is_solid(x, to.y):
			return false
	return true
