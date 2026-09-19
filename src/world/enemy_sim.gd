class_name EnemySim
extends RefCounted

## Deterministic enemy movement (spec sections 27, 28).
##
## Enemies exist to create timing and routing problems, not to be fought. Every
## behaviour here is fully predictable from the tick count: a patient player can
## always read an enemy and plan around it, and the solvability validator can
## reason about worst-case timing without simulating.

enum Kind {
	GUARDIAN,    ## walks a floor, reverses at walls and ledges
	STATUE,      ## stationary, wakes when the player crosses its line
	SPIRIT,      ## drifts along a fixed waypoint loop, ignores geometry
	SHADE,       ## like GUARDIAN but will follow the player down ladders
}

const KIND_NAMES: Dictionary = {
	"guardian": Kind.GUARDIAN,
	"statue": Kind.STATUE,
	"spirit": Kind.SPIRIT,
	"shade": Kind.SHADE,
}

const BODY_W_SUB: int = 12 * Grid.SUB
const BODY_H_SUB: int = 14 * Grid.SUB
const DEFAULT_SPEED: int = 8          # subunits/tick, half of walking pace

var id: String = ""
var kind: int = Kind.GUARDIAN
var pos: Vector2i = Vector2i.ZERO     ## bottom-centre anchor, subunits
var dir: int = 1
var speed: int = DEFAULT_SPEED
var alive: bool = true
var awake: bool = true
var wake_ticks: int = 0
var damage: int = 1

## Fixed patrol loop for SPIRIT, in subunits. Index advances on arrival.
var waypoints: Array[Vector2i] = []
var waypoint_i: int = 0

## Start pose, so a puzzle reset restores the enemy exactly (spec section 18).
var home_pos: Vector2i = Vector2i.ZERO
var home_dir: int = 1


static func from_dict(d: Dictionary) -> EnemySim:
	var e: EnemySim = EnemySim.new()
	e.id = str(d.get("id", "enemy"))
	e.kind = KIND_NAMES.get(str(d.get("type", "guardian")).to_lower(), Kind.GUARDIAN)
	var t: Vector2i = d.get("pos", Vector2i.ZERO)
	e.pos = Vector2i(Grid.tile_center(t.x), Grid.tile_origin(t.y + 1))
	e.dir = int(d.get("dir", 1))
	if e.dir == 0:
		e.dir = 1
	e.speed = int(d.get("speed", DEFAULT_SPEED))
	e.damage = int(d.get("damage", 1))
	e.awake = e.kind != Kind.STATUE
	if d.has("waypoints"):
		for w: Variant in (d["waypoints"] as Array):
			var a: Array = w as Array
			e.waypoints.append(Vector2i(
					Grid.tile_center(int(a[0])), Grid.tile_origin(int(a[1]) + 1)))
	e.home_pos = e.pos
	e.home_dir = e.dir
	return e


func tile() -> Vector2i:
	return Vector2i(Grid.to_tile(pos.x), Grid.to_tile(pos.y - 1))


func reset() -> void:
	pos = home_pos
	dir = home_dir
	alive = true
	awake = kind != Kind.STATUE
	wake_ticks = 0
	waypoint_i = 0


func tick(map: CollisionMap, player_pos: Vector2i) -> void:
	if not alive:
		return
	match kind:
		Kind.GUARDIAN:
			_patrol(map, false)
		Kind.SHADE:
			_patrol(map, true)
		Kind.STATUE:
			_statue(player_pos)
		Kind.SPIRIT:
			_drift()


func _patrol(map: CollisionMap, follow_down: bool) -> void:
	var nx: int = pos.x + dir * speed
	var ahead_tx: int = Grid.to_tile(nx + dir * (BODY_W_SUB / 2))
	var feet_ty: int = Grid.to_tile(pos.y)
	var body_ty: int = Grid.to_tile(pos.y - 1)

	var blocked: bool = map.is_solid(ahead_tx, body_ty)
	var ledge: bool = not map.is_support(ahead_tx, feet_ty)
	if ledge and follow_down and map.is_climb(ahead_tx, feet_ty):
		ledge = false   # a shade will walk onto a ladder and ride it down

	if blocked or ledge:
		dir = -dir
		return
	pos.x = nx

	## Ride gravity down one tile at a time so a shade that steps onto a
	## ladder lands cleanly rather than hovering.
	if not map.is_support(Grid.to_tile(pos.x), Grid.to_tile(pos.y)):
		var drop: int = map.floor_below(pos.x, pos.y)
		if drop >= 0:
			pos.y = mini(pos.y + speed, drop)


func _statue(player_pos: Vector2i) -> void:
	if awake:
		wake_ticks += 1
		return
	## Wakes when the player shares its row and is within four tiles.
	var same_row: bool = Grid.to_tile(player_pos.y - 1) == Grid.to_tile(pos.y - 1)
	var near: bool = absi(player_pos.x - pos.x) <= Grid.TILE_SUB * 4
	if same_row and near:
		awake = true
		dir = 1 if player_pos.x > pos.x else -1


func _drift() -> void:
	if waypoints.is_empty():
		return
	var target: Vector2i = waypoints[waypoint_i]
	var d: Vector2i = target - pos
	if absi(d.x) <= speed and absi(d.y) <= speed:
		pos = target
		waypoint_i = (waypoint_i + 1) % waypoints.size()
		return
	pos.x += signi(d.x) * mini(speed, absi(d.x))
	pos.y += signi(d.y) * mini(speed, absi(d.y))


## Axis-aligned overlap against the player body box.
func overlaps(player_anchor: Vector2i) -> bool:
	if not alive or not awake:
		return false
	var al: int = pos.x - BODY_W_SUB / 2
	var ar: int = pos.x + BODY_W_SUB / 2 - 1
	var at: int = pos.y - BODY_H_SUB
	var ab: int = pos.y - 1
	var bl: int = player_anchor.x - Grid.BODY_W_SUB / 2
	var br: int = player_anchor.x + Grid.BODY_W_SUB / 2 - 1
	var bt: int = player_anchor.y - Grid.BODY_H_SUB
	var bb: int = player_anchor.y - 1
	return al <= br and ar >= bl and at <= bb and ab >= bt


func snapshot() -> Dictionary:
	return {
		"x": pos.x, "y": pos.y, "dir": dir, "alive": alive,
		"awake": awake, "wake_ticks": wake_ticks, "wp": waypoint_i,
	}


func restore(s: Dictionary) -> void:
	pos = Vector2i(int(s["x"]), int(s["y"]))
	dir = int(s["dir"])
	alive = bool(s["alive"])
	awake = bool(s["awake"])
	wake_ticks = int(s["wake_ticks"])
	waypoint_i = int(s["wp"])
