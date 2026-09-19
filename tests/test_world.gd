extends TestSuite

## World simulation, determinism, anti-deadlock and checkpoints
## (spec sections 6, 17, 18, 19).

## A corridor with a low-ceilinged pinch point at column 5.
##
## As authored the block sits at (3,2) in the open part, so the player can hop
## onto it and drop down the far side to reach the key and the gate. Push it
## one tile right and it lands at (4,2), where the ceiling above is still
## open — but from the ledge it creates she can only reach (4,1), and the
## solid ceiling at (5,1) leaves no way past. That push seals the level, which
## is exactly what spec section 17 forbids.
const CORRIDOR_JSON: String = """
{
  "id": "t_corridor",
  "name": "Corridor Fixture",
  "gate": 1,
  "map": [
    "##########",
    "#....#...#",
    "#..X....G#",
    "#BBBBBBBB#",
    "##########"
  ],
  "player_start": [1, 2],
  "exit": [8, 2],
  "treasures": [{ "id": "t1", "pos": [2, 2], "tier": "common", "value": 5 }],
  "required_objects": [{ "id": "key", "kind": "key", "pos": [6, 2] }],
  "checkpoints": [{ "id": "cp", "pos": [1, 2] }],
  "validation_rules": { "exit_requires": ["key"] }
}
"""

## Open room, so a push is harmless and must be allowed.
const OPEN_JSON: String = """
{
  "id": "t_open",
  "name": "Open Fixture",
  "gate": 1,
  "map": [
    "##########",
    "#........#",
    "#..X.....#",
    "#BBBBBBBB#",
    "##########"
  ],
  "player_start": [6, 2],
  "exit": [1, 2],
  "treasures": [],
  "required_objects": [],
  "validation_rules": {}
}
"""


func run() -> void:
	suite_name = "world"
	_test_loader()
	_test_exit_sealed_until_key()
	_test_treasure_pickup()
	_test_anti_deadlock_push()
	_test_legal_push()
	_test_determinism()
	_test_snapshot_restore()
	_test_checkpoint_validation()
	_test_hazard_and_recovery()


func _level(json: String) -> LevelData:
	var parsed: LevelLoader.ParseResult = LevelLoader.parse(json, "<fixture>")
	check(parsed.errors.is_empty(), "fixture parsed cleanly: %s"
			% ", ".join(parsed.errors))
	return parsed.level


func _test_loader() -> void:
	test("level loader")
	var lv: LevelData = _level(CORRIDOR_JSON)
	check_eq(lv.width, 10, "width from the map rows")
	check_eq(lv.height, 5, "height from the map rows")
	check_eq(lv.tile_at(0, 0), TileDB.T.TEMPLE_WALL, "hash is a wall")
	check_eq(lv.tile_at(3, 2), TileDB.T.MOVABLE_BLOCK, "X is a movable block")
	check_eq(lv.tile_at(1, 3), TileDB.T.MUD_BRICK_FLOOR, "B is floor")
	check_eq(lv.player_start, Vector2i(1, 2), "player start parsed")
	check_eq(lv.treasures.size(), 1, "treasure table parsed")
	check_eq(lv.required_objects[0]["pos"], Vector2i(6, 2), "object pos is a Vector2i")

	test("loader reports errors rather than throwing")
	var bad: LevelLoader.ParseResult = LevelLoader.parse("{ not json", "<bad>")
	check(bad.errors.size() > 0, "malformed JSON is reported")
	check(bad.level == null, "no level is produced")

	var ragged: LevelLoader.ParseResult = LevelLoader.parse(
			'{"id":"r","map":["####","##"],"player_start":[1,1],"exit":[2,1]}', "<r>")
	check(ragged.errors.size() > 0, "a ragged map row is reported")


func _test_exit_sealed_until_key() -> void:
	test("the gate is sealed until its condition is met")
	var w: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	check_eq(w.map.at(8, 2), TileDB.T.LOCKED_GATE, "exit starts locked")
	check(w.map.is_solid(8, 2), "a locked gate blocks the body")

	w.held["key"] = true
	w._refresh_exit()
	check_eq(w.map.at(8, 2), TileDB.T.OPEN_GATE, "holding the key opens it")
	check(not w.map.is_solid(8, 2), "an open gate is passable")


func _test_treasure_pickup() -> void:
	test("treasure and objects are collected on overlap")
	var w: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	## The treasure sits one tile to the right of the start.
	var prev: int = 0
	for _i: int in 40:
		w.tick(InputFrame.from_mask(InputFrame.B_RIGHT, prev))
		prev = InputFrame.B_RIGHT
	check(w.collected.has("t1"), "walked over the treasure and took it")
	check_eq(w.treasure_value, 5, "value accumulated")

	test("treasure is taken only once")
	var before: int = w.treasure_value
	for _i: int in 30:
		w.tick(InputFrame.from_mask(InputFrame.B_LEFT, InputFrame.B_LEFT))
	check_eq(w.treasure_value, before, "walking back does not re-award it")


## Spec section 17, the non-negotiable one.
func _test_anti_deadlock_push() -> void:
	test("a push that would seal the level is refused")
	var w: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	w.held["key"] = true
	w._refresh_exit()

	var rep: Solver.Report = Solver.validate_state(
			w.level, w.map, Vector2i(1, 2), w.held, w.open_doors)
	check(rep.solvable, "the fixture is solvable before anything moves: %s"
			% rep.summary())

	## Pushing the block right walls off the only corridor to the gate.
	var allowed: bool = w._can_push(Vector2i(3, 2), 1)
	check(not allowed, "the sealing push is refused")
	check(w.last_push_refused, "the refusal is recorded for the UI")
	check_eq(w.map.at(3, 2), TileDB.T.MOVABLE_BLOCK, "the block did not move")

	test("the refusal survives the full player path")
	## Drive the player into the block and hold. She must never displace it.
	var prev: int = 0
	for _i: int in 240:
		w.tick(InputFrame.from_mask(InputFrame.B_RIGHT, prev))
		prev = InputFrame.B_RIGHT
	check_eq(w.map.at(3, 2), TileDB.T.MOVABLE_BLOCK,
			"holding right for four seconds never moves the block")
	check(w.player.tile().x < 3, "she is still stuck behind it")

	test("the audit agrees the level is still winnable")
	check(w.last_audit_ok, "no softlock was ever reported")


func _test_legal_push() -> void:
	test("a harmless push is allowed")
	var w: WorldSim = WorldSim.new(_level(OPEN_JSON))
	check(w._can_push(Vector2i(3, 2), 1), "pushing into open floor is fine")
	w._do_push(Vector2i(3, 2), 1)
	check_eq(w.map.at(3, 2), TileDB.T.EMPTY, "the old cell is cleared")
	check_eq(w.map.at(4, 2), TileDB.T.MOVABLE_BLOCK, "the block moved one tile")

	test("a block is never pushed into occupied space")
	var w2: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	check(not w2._can_push(Vector2i(1, 3), 1),
			"pushing into a floor tile is refused, so terrain is never overwritten")
	check(not w2._can_push(Vector2i(7, 2), 1),
			"pushing into the gate tile is refused")


## Spec section 6. Same level, same seed, same input: byte-identical result.
func _test_determinism() -> void:
	test("identical input produces identical state")
	var script: Array = [
		[InputFrame.B_RIGHT, 30], [InputFrame.B_JUMP | InputFrame.B_RIGHT, 14],
		[0, 6], [InputFrame.B_LEFT, 22], [InputFrame.B_UP, 10],
		[InputFrame.B_RIGHT | InputFrame.B_RUN, 45], [InputFrame.B_ACTION, 5],
		[0, 18],
	]
	var masks: PackedInt32Array = InputRouter.script_to_masks(script)

	var a: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	var b: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	var diverged: int = -1
	var prev: int = 0
	for i: int in masks.size():
		var fa: InputFrame = InputFrame.from_mask(masks[i], prev)
		var fb: InputFrame = InputFrame.from_mask(masks[i], prev)
		prev = masks[i]
		a.tick(fa)
		b.tick(fb)
		if a.state_hash() != b.state_hash() and diverged < 0:
			diverged = i
	check_eq(diverged, -1, "two runs stayed in lockstep for %d ticks" % masks.size())
	check_eq(a.player.pos, b.player.pos, "final anchors match")

	test("a different input diverges")
	var c: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	for i: int in masks.size():
		c.tick(InputFrame.from_mask(0, 0))
	check_ne(c.state_hash(), a.state_hash(), "doing nothing is not the same run")


func _test_snapshot_restore() -> void:
	test("world snapshot round trip")
	var w: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	var prev: int = 0
	for _i: int in 50:
		w.tick(InputFrame.from_mask(InputFrame.B_RIGHT, prev))
		prev = InputFrame.B_RIGHT
	var snap: Dictionary = w.capture_snapshot()
	var hash_at_snap: int = w.state_hash()

	for _i: int in 60:
		w.tick(InputFrame.from_mask(InputFrame.B_LEFT, InputFrame.B_LEFT))
	check_ne(w.state_hash(), hash_at_snap, "state moved on")

	w.restore_snapshot(snap)
	check_eq(w.state_hash(), hash_at_snap, "restore reproduces the exact state")

	test("restoring then replaying is deterministic")
	var after_restore: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	after_restore.restore_snapshot(snap)
	for _i: int in 30:
		w.tick(InputFrame.from_mask(InputFrame.B_RIGHT, InputFrame.B_RIGHT))
		after_restore.tick(InputFrame.from_mask(InputFrame.B_RIGHT, InputFrame.B_RIGHT))
	check_eq(w.state_hash(), after_restore.state_hash(),
			"a restored world continues identically")


## Spec section 19: a checkpoint must never preserve an unwinnable state.
func _test_checkpoint_validation() -> void:
	test("a valid checkpoint is accepted")
	var w: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	w._take_checkpoint("cp")
	check(w.checkpoints_taken.has("cp"), "checkpoint taken in a solvable state")
	check(not w.checkpoint.is_empty(), "the snapshot was stored")

	test("an impossible checkpoint is rejected")
	var w2: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	## Wall the corridor off by hand, simulating a state the game should never
	## reach, and confirm the checkpoint gate catches it anyway.
	w2.map.set_at(5, 2, TileDB.T.TEMPLE_WALL)
	w2._take_checkpoint("cp")
	check(not w2.checkpoints_taken.has("cp"), "checkpoint refused")
	check(w2.checkpoint.is_empty(), "nothing impossible was stored")

	test("recovery falls back to the level start when there is no checkpoint")
	var w3: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	var prev: int = 0
	for _i: int in 40:
		w3.tick(InputFrame.from_mask(InputFrame.B_RIGHT, prev))
		prev = InputFrame.B_RIGHT
	w3.recover()
	check_eq(w3.player.tile(), Vector2i(1, 2), "returned to the start tile")
	check(w3.collected.is_empty(), "level state was reset with her")


func _test_hazard_and_recovery() -> void:
	test("the softlock audit repairs an impossible state")
	var w: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	w._take_checkpoint("cp")
	check(not w.checkpoint.is_empty(), "checkpoint in hand")

	## Force an unwinnable world, then let the periodic audit run.
	w.map.set_at(5, 2, TileDB.T.TEMPLE_WALL)
	w._audit()
	check(w.map.at(5, 2) != TileDB.T.TEMPLE_WALL,
			"the audit restored the checkpoint and undid the seal")

	test("death is counted and does not lose held objects on recovery")
	var w2: WorldSim = WorldSim.new(_level(CORRIDOR_JSON))
	w2.held["key"] = true
	w2._refresh_exit()
	w2._take_checkpoint("cp")
	w2.player.kill()
	for _i: int in PlayerSim.DYING_TICKS + 4:
		w2.tick(InputFrame.from_mask(0, 0))
	check_eq(w2.status, WorldSim.Status.DEAD, "death was registered")
	check_eq(w2.deaths, 1, "death counted once")
	w2.recover()
	check(w2.held.has("key"), "the key survived death")
