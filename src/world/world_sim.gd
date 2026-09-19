class_name WorldSim
extends RefCounted

## The authoritative runtime state of one level (spec sections 6, 14-20).
##
## WorldSim owns the tile grid, the puzzle state, the player and the enemies,
## and advances all of them by exactly one deterministic tick at a time. The
## render layer, the audio layer and the UI observe it; none of them may
## mutate it.
##
## Anti-deadlock (spec section 17) is enforced here rather than patched later:
##   * a push is only committed if the resulting state still validates;
##   * required objects are never droppable, so they cannot be lost;
##   * collapsed floors rebuild themselves, so a route is never destroyed;
##   * checkpoints are validated before they are accepted;
##   * a periodic audit catches any softlock that slips through and triggers
##     recovery (spec section 18).

enum Status { PLAYING, DEAD, COMPLETE }

## Ticks a collapsing floor survives once stood on, and how long until it
## rebuilds. Rebuilding is what keeps a collapse from destroying a route.
const COLLAPSE_DELAY: int = 34
const COLLAPSE_RESPAWN: int = 190

## How often the softlock audit runs. Cheap on a 16x12 grid, but there is no
## reason to pay for it every tick.
const AUDIT_INTERVAL: int = 45

var level: LevelData = null
var map: CollisionMap = null
var player: PlayerSim = null
var hooks: PlayerHooks = null
var rng: DetRng = null

var tick_count: int = 0
var status: int = Status.PLAYING

## Puzzle state.
var held: Dictionary = {}              ## required object id -> true
var collected: Dictionary = {}         ## treasure id -> true
var open_doors: Dictionary = {}        ## door id -> true
var switch_state: Dictionary = {}      ## switch id -> bool
var enemies: Array[EnemySim] = []
var collapsing: Dictionary = {}        ## Vector2i -> ticks remaining
var rebuilding: Dictionary = {}        ## Vector2i -> ticks until restored

## Score and progression counters (spec section 32).
var treasure_value: int = 0
var deaths: int = 0

## Checkpoint (spec section 19). Always a validated state.
var checkpoint: Dictionary = {}
var checkpoints_taken: Dictionary = {}

## Observable events, drained each tick by the presentation layer.
var events: Array[Dictionary] = []

## Diagnostics for the QA overlay.
var last_audit_ok: bool = true
var last_push_refused: bool = false


func _init(lv: LevelData, seed_override: int = -1) -> void:
	level = lv
	map = CollisionMap.from_level(lv)
	rng = DetRng.new(seed_override if seed_override >= 0 else lv.seed_value)
	hooks = PlayerHooks.new()
	hooks.can_push_fn = _can_push
	hooks.do_push_fn = _do_push
	hooks.try_interact_fn = _try_interact
	hooks.try_attack_fn = _try_attack
	player = PlayerSim.new(map, hooks)
	reset_level()


# --- lifecycle ------------------------------------------------------------

func reset_level() -> void:
	map = CollisionMap.from_level(level)
	player.map = map
	held.clear()
	collected.clear()
	open_doors.clear()
	switch_state.clear()
	collapsing.clear()
	rebuilding.clear()
	treasure_value = 0
	tick_count = 0
	status = Status.PLAYING
	events.clear()
	checkpoint.clear()
	checkpoints_taken.clear()

	enemies.clear()
	for e: Dictionary in level.enemies:
		enemies.append(EnemySim.from_dict(e))

	_seal_exit()
	player.spawn_at_tile(level.player_start)
	_emit("level_start", {"id": level.id})


## Puzzle recovery (spec section 18): return to the last validated checkpoint,
## or to the level start if none has been taken.
func recover() -> void:
	if checkpoint.is_empty():
		var dcount: int = deaths
		reset_level()
		deaths = dcount
		_emit("recovered", {"to": "level_start"})
		return
	restore_snapshot(checkpoint)
	_emit("recovered", {"to": "checkpoint"})


# --- main tick ------------------------------------------------------------

func tick(inp: InputFrame) -> void:
	if status != Status.PLAYING:
		## The player still animates through DYING so the death reads clearly.
		if player.state == PlayerSim.S.DYING:
			player.tick(inp)
		return

	tick_count += 1
	player.tick(inp)

	for e: EnemySim in enemies:
		e.tick(map, player.pos)

	_tick_collapsing()
	_resolve_overlaps()
	_resolve_enemies()
	_check_exit()
	_check_death()

	if tick_count % AUDIT_INTERVAL == 0:
		_audit()


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events.duplicate()
	events.clear()
	return out


func _emit(type: String, data: Dictionary = {}) -> void:
	var e: Dictionary = data.duplicate()
	e["type"] = type
	e["tick"] = tick_count
	events.append(e)


# --- tile overlap resolution ---------------------------------------------

func _resolve_overlaps() -> void:
	if not player.is_alive():
		return
	var body: Array[Vector2i] = map.body_tiles(player.pos.x, player.pos.y)

	for t: Dictionary in level.treasures:
		var tid: String = t["id"]
		if collected.has(tid):
			continue
		if body.has(t["pos"]):
			collected[tid] = true
			treasure_value += int(t.get("value", 1))
			_emit("treasure", {"id": tid, "tier": str(t.get("tier", "common")),
					"value": int(t.get("value", 1))})
			_refresh_exit()

	## Required objects are picked up permanently and can never be dropped.
	## That single rule removes the entire "key lost in a pit" family of
	## softlocks (spec section 17).
	for o: Dictionary in level.required_objects:
		var oid: String = o["id"]
		if held.has(oid):
			continue
		if body.has(o["pos"]):
			held[oid] = true
			_emit("object", {"id": oid, "kind": str(o.get("kind", "key"))})
			_refresh_doors()

	for s: Dictionary in level.switches:
		if str(s.get("type", "lever")) != "plate":
			continue
		var sid: String = s["id"]
		var standing: bool = body.has(s["pos"]) or (
				player.tile() + Vector2i(0, 1)) == s["pos"]
		var was: bool = bool(switch_state.get(sid, false))
		if standing and not was:
			_set_switch(sid, true, s)
		elif not standing and was and str(s.get("mode", "hold")) == "hold":
			_set_switch(sid, false, s)

	for c: Dictionary in level.checkpoints:
		var cid: String = c["id"]
		if checkpoints_taken.has(cid):
			continue
		if body.has(c["pos"]):
			_take_checkpoint(cid)

	if map.body_on_hazard(player.pos.x, player.pos.y):
		if player.apply_damage(1, 0):
			_emit("hazard_hit", {})

	_start_collapse_under_player()


func _resolve_enemies() -> void:
	if not player.is_alive() or player.invuln > 0:
		return
	for e: EnemySim in enemies:
		if e.overlaps(player.pos):
			var dir: int = 1 if e.pos.x > player.pos.x else -1
			if player.apply_damage(e.damage, dir):
				_emit("enemy_hit", {"id": e.id})
			return


func _check_death() -> void:
	## Falling out of the bottom of the level is always fatal.
	if player.pos.y > Grid.tiles(level.height + 1):
		player.kill()
	if player.state == PlayerSim.S.DEAD and status == Status.PLAYING:
		status = Status.DEAD
		deaths += 1
		_emit("death", {"deaths": deaths})


func _check_exit() -> void:
	if status != Status.PLAYING or not player.is_alive():
		return
	var t: Vector2i = player.tile()
	if map.at(t.x, t.y) != TileDB.T.OPEN_GATE:
		return
	if not _exit_requirements_met():
		return
	status = Status.COMPLETE
	player.complete_level()
	_emit("level_complete", {
		"treasure_value": treasure_value,
		"treasures": collected.size(),
		"total_treasures": level.treasures.size(),
		"ticks": tick_count,
		"deaths": deaths,
	})


# --- doors, switches, gates ----------------------------------------------

func _exit_requirements_met() -> bool:
	for r: Variant in level.validation_rules.get("exit_requires", []):
		if not held.has(str(r)):
			return false
	if bool(level.validation_rules.get("exit_requires_all_treasure", false)):
		return collected.size() >= level.treasures.size()
	return true


func _seal_exit() -> void:
	## The exit reads as a locked gate until its conditions are met, so the
	## player can always see where they are going (spec section 3).
	if _exit_requirements_met():
		map.set_at(level.exit_tile.x, level.exit_tile.y, TileDB.T.OPEN_GATE)
	else:
		map.set_at(level.exit_tile.x, level.exit_tile.y, TileDB.T.LOCKED_GATE)


func _refresh_exit() -> void:
	var was_open: bool = map.at(level.exit_tile.x, level.exit_tile.y) == TileDB.T.OPEN_GATE
	_seal_exit()
	var now_open: bool = map.at(level.exit_tile.x, level.exit_tile.y) == TileDB.T.OPEN_GATE
	if now_open and not was_open:
		_emit("exit_opened", {})


func _refresh_doors() -> void:
	for d: Dictionary in level.doors:
		var did: String = d["id"]
		if open_doors.has(did):
			continue
		var reqs: Array = d.get("requires", [])
		var met: bool = true
		for r: Variant in reqs:
			if not held.has(str(r)):
				met = false
				break
		## A key-operated door opens on contact, which is why this only fires
		## when the player is adjacent to it.
		if met and reqs.size() > 0 and _player_adjacent(d["pos"]):
			_open_door(did, d)


func _player_adjacent(t: Vector2i) -> bool:
	var p: Vector2i = player.tile()
	return absi(p.x - t.x) <= 1 and absi(p.y - t.y) <= 1


func _open_door(did: String, d: Dictionary) -> void:
	open_doors[did] = true
	var p: Vector2i = d["pos"]
	map.set_at(p.x, p.y, TileDB.T.OPEN_GATE)
	if bool(d.get("consumes_key", false)):
		## Consuming is opt-in and the validator accounts for it, but the key
		## stays in the inventory display so the player can see what it did.
		pass
	_emit("door_opened", {"id": did})


func _set_switch(sid: String, on: bool, s: Dictionary) -> void:
	switch_state[sid] = on
	_emit("switch", {"id": sid, "on": on})
	for target: Variant in s.get("targets", []):
		var tid: String = str(target)
		var door: Dictionary = _find(level.doors, tid)
		if door.is_empty():
			continue
		if on:
			_open_door(tid, door)
		elif str(s.get("mode", "hold")) == "hold":
			open_doors.erase(tid)
			var p: Vector2i = door["pos"]
			## Never close a door on top of the player: that is a softlock and
			## in the worst case a crush (spec section 17).
			if player.tile() != p:
				map.set_at(p.x, p.y, TileDB.T.LOCKED_GATE)
				_emit("door_closed", {"id": tid})


static func _find(rows: Array[Dictionary], id_value: String) -> Dictionary:
	for r: Dictionary in rows:
		if str(r["id"]) == id_value:
			return r
	return {}


# --- collapsing floors ----------------------------------------------------

func _start_collapse_under_player() -> void:
	if not map.on_ground(player.pos.x, player.pos.y):
		return
	var ty: int = Grid.to_tile(player.pos.y)
	for tx: int in [Grid.to_tile(map.body_left(player.pos.x)),
			Grid.to_tile(map.body_right(player.pos.x))]:
		var t: Vector2i = Vector2i(tx, ty)
		if map.at(tx, ty) == TileDB.T.COLLAPSING_FLOOR and not collapsing.has(t):
			collapsing[t] = COLLAPSE_DELAY
			_emit("collapse_start", {"pos": t})


func _tick_collapsing() -> void:
	for t: Vector2i in collapsing.keys():
		var left: int = collapsing[t] - 1
		if left > 0:
			collapsing[t] = left
			continue
		collapsing.erase(t)
		map.set_at(t.x, t.y, TileDB.T.EMPTY)
		rebuilding[t] = COLLAPSE_RESPAWN
		_emit("collapse", {"pos": t})

	for t: Vector2i in rebuilding.keys():
		var left2: int = rebuilding[t] - 1
		if left2 > 0:
			rebuilding[t] = left2
			continue
		## Do not rebuild underneath the player: materialising a floor inside
		## her body would push her through the world.
		if map.body_tiles(player.pos.x, player.pos.y).has(t):
			rebuilding[t] = 12
			continue
		rebuilding.erase(t)
		map.set_at(t.x, t.y, TileDB.T.COLLAPSING_FLOOR)
		_emit("collapse_rebuilt", {"pos": t})


# --- player hooks ---------------------------------------------------------

## Anti-deadlock in one place: a push is simulated, the resulting world is
## validated, and the push is only allowed if the level is still solvable.
func _can_push(t: Vector2i, dir: int) -> bool:
	last_push_refused = false
	var dest: Vector2i = t + Vector2i(dir, 0)
	## Only genuinely empty space accepts a block. Anything looser would let a
	## push overwrite a ladder, a gate or a treasure tile and destroy the
	## level from underneath the player.
	if not map.in_bounds(dest.x, dest.y) or map.at(dest.x, dest.y) != TileDB.T.EMPTY:
		return false

	var trial: CollisionMap = map.clone()
	trial.set_at(t.x, t.y, TileDB.T.EMPTY)
	trial.set_at(dest.x, dest.y, TileDB.T.MOVABLE_BLOCK)
	var landing: Vector2i = _push_landing(trial, dest)
	if landing != dest:
		trial.set_at(dest.x, dest.y, TileDB.T.EMPTY)
		trial.set_at(landing.x, landing.y, TileDB.T.MOVABLE_BLOCK)

	var from_tile: Vector2i = t - Vector2i(dir, 0)
	var rep: Solver.Report = Solver.validate_state(
			level, trial, from_tile, held, open_doors)
	if not rep.solvable:
		last_push_refused = true
		_emit("push_refused", {"pos": t, "reason": rep.summary()})
		return false
	return true


func _do_push(t: Vector2i, dir: int) -> void:
	var dest: Vector2i = t + Vector2i(dir, 0)
	map.set_at(t.x, t.y, TileDB.T.EMPTY)
	var landing: Vector2i = _push_landing(map, dest)
	map.set_at(landing.x, landing.y, TileDB.T.MOVABLE_BLOCK)
	_emit("push", {"from": t, "to": landing})


## Where a block pushed into `dest` comes to rest. It falls only through
## genuinely empty tiles, so it can never pass through a ladder or a gate.
static func _push_landing(m: CollisionMap, dest: Vector2i) -> Vector2i:
	var landing: Vector2i = dest
	while landing.y + 1 < m.height:
		if m.at(landing.x, landing.y + 1) != TileDB.T.EMPTY:
			break
		landing.y += 1
	return landing


func _try_interact(t: Vector2i, _facing: int) -> bool:
	for s: Dictionary in level.switches:
		if s["pos"] != t or str(s.get("type", "lever")) != "lever":
			continue
		var sid: String = s["id"]
		var mode: String = str(s.get("mode", "toggle"))
		var was: bool = bool(switch_state.get(sid, false))
		if mode == "once" and was:
			return false
		for r: Variant in s.get("requires", []):
			if not held.has(str(r)):
				_emit("locked", {"id": sid, "needs": str(r)})
				return true
		_set_switch(sid, not was, s)
		return true

	for d: Dictionary in level.doors:
		if d["pos"] != t or open_doors.has(str(d["id"])):
			continue
		var met: bool = true
		for r: Variant in d.get("requires", []):
			if not held.has(str(r)):
				met = false
				break
		if met:
			_open_door(str(d["id"]), d)
		else:
			_emit("locked", {"id": str(d["id"])})
		return true
	return false


func _try_attack(t: Vector2i, _facing: int) -> bool:
	for e: EnemySim in enemies:
		if not e.alive:
			continue
		if e.tile() == t:
			e.alive = false
			_emit("enemy_defeated", {"id": e.id})
			return true
	return false


# --- checkpoints and auditing --------------------------------------------

func _take_checkpoint(cid: String) -> void:
	var snap: Dictionary = capture_snapshot()
	## Spec section 19: never preserve an unrecoverable state.
	var rep: Solver.Report = Solver.validate_state(
			level, map, player.tile(), held, open_doors)
	if not rep.solvable:
		_emit("checkpoint_rejected", {"id": cid, "reason": rep.summary()})
		return
	checkpoints_taken[cid] = true
	checkpoint = snap
	player.enter_checkpoint()
	_emit("checkpoint", {"id": cid})


## Periodic softlock audit (spec sections 17, 18).
func _audit() -> void:
	if status != Status.PLAYING or not player.is_alive():
		return
	var rep: Solver.Report = Solver.validate_state(
			level, map, player.tile(), held, open_doors)
	last_audit_ok = rep.solvable
	if rep.solvable:
		return
	_emit("softlock_detected", {"reason": rep.summary()})
	recover()


# --- snapshots ------------------------------------------------------------

func capture_snapshot() -> Dictionary:
	var enemy_states: Array[Dictionary] = []
	for e: EnemySim in enemies:
		enemy_states.append(e.snapshot())
	return {
		"tick": tick_count,
		"tiles": map.tiles.duplicate(),
		"held": held.duplicate(),
		"collected": collected.duplicate(),
		"open_doors": open_doors.duplicate(),
		"switch_state": switch_state.duplicate(),
		"treasure_value": treasure_value,
		"player": player.snapshot(),
		"enemies": enemy_states,
		"rng": rng.state,
		"collapsing": collapsing.duplicate(),
		"rebuilding": rebuilding.duplicate(),
		"checkpoints_taken": checkpoints_taken.duplicate(),
	}


func restore_snapshot(s: Dictionary) -> void:
	tick_count = int(s["tick"])
	map.tiles = (s["tiles"] as PackedByteArray).duplicate()
	held = (s["held"] as Dictionary).duplicate()
	collected = (s["collected"] as Dictionary).duplicate()
	open_doors = (s["open_doors"] as Dictionary).duplicate()
	switch_state = (s["switch_state"] as Dictionary).duplicate()
	treasure_value = int(s["treasure_value"])
	collapsing = (s["collapsing"] as Dictionary).duplicate()
	rebuilding = (s["rebuilding"] as Dictionary).duplicate()
	checkpoints_taken = (s["checkpoints_taken"] as Dictionary).duplicate()
	rng.state = int(s["rng"])
	player.restore(s["player"] as Dictionary)
	var states: Array = s["enemies"] as Array
	for i: int in mini(states.size(), enemies.size()):
		enemies[i].restore(states[i] as Dictionary)
	status = Status.PLAYING


## Cheap state fingerprint, used by the determinism tests.
func state_hash() -> int:
	var h: int = 1469598103
	h = (h * 31 + tick_count) & 0x7FFFFFFF
	h = (h * 31 + player.pos.x) & 0x7FFFFFFF
	h = (h * 31 + player.pos.y) & 0x7FFFFFFF
	h = (h * 31 + player.state) & 0x7FFFFFFF
	h = (h * 31 + player.health) & 0x7FFFFFFF
	h = (h * 31 + treasure_value) & 0x7FFFFFFF
	h = (h * 31 + held.size() * 7 + collected.size() * 13) & 0x7FFFFFFF
	for b: int in map.tiles:
		h = (h * 31 + b) & 0x7FFFFFFF
	for e: EnemySim in enemies:
		h = (h * 31 + e.pos.x + e.pos.y * 3 + e.dir) & 0x7FFFFFFF
	return h
