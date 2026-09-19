extends TestSuite

## Adversarial QA (spec section 43, Test 3) against real shipped levels.
##
## Test 3 is the one that matters most and the one a human is worst at: it
## asks whether ANY sequence of inputs can break a level. A person can try
## twenty orderings; a seeded fuzzer can try a hundred thousand ticks and
## check the invariants after every single one.
##
## What this asserts, continuously:
##
##   * she is never inside a solid tile;
##   * she is never outside the map while alive;
##   * the softlock audit never fires - not "recovers cleanly", never fires,
##     because a recovery means the level DID become unwinnable;
##   * the level never completes without its required objects;
##   * a sealed gate is never passable;
##   * the FSM never takes an illegal transition. NOTE: the assert in
##     _set_state prints but does NOT halt, so this is checked through
##     PlayerSim.illegal_transitions. Relying on the assert alone let a
##     genuinely broken transition table report green.
##
## The fuzzer is a DetRng, so a failure is reproducible from its seed. It
## also reports where it managed to get, because a fuzz run that never left
## the first room proves nothing.

const LEVEL_PATH: String = "res://levels/gate1/g1_l1_threshold.json"

## Held for a few ticks at a time. Single-tick random input just vibrates on
## the spot and never climbs a ladder or commits to a jump.
const HOLD_MIN: int = 3
const HOLD_MAX: int = 22

const BUTTONS: Array[int] = [
	InputFrame.B_LEFT, InputFrame.B_RIGHT, InputFrame.B_UP, InputFrame.B_DOWN,
	InputFrame.B_JUMP, InputFrame.B_ACTION, InputFrame.B_RUN,
]


func run() -> void:
	suite_name = "adversarial"
	_test_sealed_gate_holds()
	_test_fuzz(11, 24000)
	_test_fuzz(2718, 24000)
	_test_fuzz(90210, 24000)
	_test_death_recovery_keeps_progress()
	_test_falling_is_survivable()
	_test_guardian_is_contained()
	_test_guardian_can_be_dealt_with()


func _load() -> LevelData:
	var parsed: LevelLoader.ParseResult = LevelLoader.load_file(LEVEL_PATH)
	check(parsed.errors.is_empty(), "level parsed: %s" % ", ".join(parsed.errors))
	return parsed.level


## The gate must be impassable until its condition is met, as a property of
## the tile rather than as a check at the moment of touching it.
func _test_sealed_gate_holds() -> void:
	test("a sealed gate is solid")
	var lv: LevelData = _load()
	if lv == null:
		return
	var w: WorldSim = WorldSim.new(lv)
	var e: Vector2i = lv.exit_tile
	check(w.map.is_solid(e.x, e.y), "the exit tile blocks the body while sealed")
	check_eq(w.status, WorldSim.Status.PLAYING, "and the level is not complete")

	test("the exit is unreachable without the key")
	var reach: Dictionary = Solver.reachable_tiles(w.map, lv.player_start)
	check(not reach.has(e), "no route to the exit tile exists yet")
	var needed: Array = lv.validation_rules.get("exit_requires", [])
	check(needed.size() > 0, "the level actually gates its exit")


func _test_fuzz(seed_value: int, ticks: int) -> void:
	test("fuzz seed %d, %d ticks" % [seed_value, ticks])
	var lv: LevelData = _load()
	if lv == null:
		return
	var w: WorldSim = WorldSim.new(lv)
	var rng: DetRng = DetRng.new(seed_value)

	var mask: int = 0
	var prev: int = 0
	var hold_left: int = 0

	var inside_solid: int = -1
	var out_of_bounds: int = -1
	var softlocks: int = 0
	var completed_without_key: int = -1
	var deaths: int = 0
	var visited: Dictionary = {}

	for i: int in ticks:
		if hold_left <= 0:
			## A fresh combination: one or two buttons, occasionally nothing.
			mask = 0
			if not rng.chance(1, 8):
				mask |= BUTTONS[rng.next_range(0, BUTTONS.size() - 1)]
				if rng.chance(1, 3):
					mask |= BUTTONS[rng.next_range(0, BUTTONS.size() - 1)]
			hold_left = rng.next_range(HOLD_MIN, HOLD_MAX)
		hold_left -= 1

		w.tick(InputFrame.from_mask(mask, prev))
		prev = mask

		var p: PlayerSim = w.player
		visited[p.tile()] = true

		if p.is_alive() and w.map.body_blocked(p.pos.x, p.pos.y) and inside_solid < 0:
			inside_solid = i
		if p.is_alive() and out_of_bounds < 0:
			var t: Vector2i = p.tile()
			if t.x < 0 or t.y < 0 or t.x >= lv.width or t.y >= lv.height:
				out_of_bounds = i

		for ev: Dictionary in w.drain_events():
			match str(ev["type"]):
				"softlock_detected":
					softlocks += 1
				"death":
					deaths += 1
				"level_complete":
					for r: Variant in lv.validation_rules.get("exit_requires", []):
						if not w.held.has(str(r)) and completed_without_key < 0:
							completed_without_key = i

		## Deaths are allowed; being stuck dead is not. Recover and continue
		## attacking, the way a player would.
		if w.status == WorldSim.Status.DEAD:
			w.recover()
		elif w.status == WorldSim.Status.COMPLETE:
			w.reset_level()

	check_eq(inside_solid, -1, "never overlapped a solid tile")
	check_eq(out_of_bounds, -1, "never left the map alive")
	check_eq(softlocks, 0, "the softlock audit never fired")
	check_eq(w.player.illegal_transitions, 0,
			"no illegal FSM transition (last: %s)" % w.player.last_illegal)
	check_eq(completed_without_key, -1, "never finished without the required object")

	## A fuzz run that never went anywhere proves nothing, so report reach.
	test("fuzz seed %d actually explored the level" % seed_value)
	check(visited.size() >= 12,
			"visited %d distinct tiles (deaths: %d)" % [visited.size(), deaths])


## Spec section 18: a death must cost time, not progress.
func _test_death_recovery_keeps_progress() -> void:
	test("death does not cost collected items")
	var lv: LevelData = _load()
	if lv == null:
		return
	var w: WorldSim = WorldSim.new(lv)

	## Walk far enough right to take the first treasure and the checkpoint.
	var prev: int = 0
	for _i: int in 70:
		w.tick(InputFrame.from_mask(InputFrame.B_RIGHT, prev))
		prev = InputFrame.B_RIGHT
	var treasures_before: int = w.collected.size()
	check(treasures_before > 0, "picked something up before dying")
	check(not w.checkpoint.is_empty(), "and banked a checkpoint")

	w.player.kill()
	for _i: int in PlayerSim.DYING_TICKS + 4:
		w.tick(InputFrame.from_mask(0, 0))
	check_eq(w.status, WorldSim.Status.DEAD, "died")
	w.recover()

	check_eq(w.collected.size(), treasures_before, "treasure survived the death")
	check(w.player.is_alive(), "and she is alive again")
	check_eq(w.player.health, PlayerSim.MAX_HEALTH, "restored at full health")

	test("the restored position is a safe one")
	check(not w.map.body_blocked(w.player.pos.x, w.player.pos.y),
			"not restored inside geometry")
	check(not w.map.feet_in_hazard(w.player.pos.x, w.player.pos.y),
			"not restored standing on a hazard")
	var rep: Solver.Report = Solver.validate_state(
			lv, w.map, w.player.tile(), w.held, w.open_doors)
	check(rep.solvable, "the level is still winnable from there: %s" % rep.summary())


## Gate I is difficulty 1-2. The route across the terrace must not punish a
## player for imprecision: overshooting the upper ladder has to be harmless.
## Deliberately walking off the far end of the terrace is a different matter
## and does cost health, which is the intended lesson.
func _test_falling_is_survivable() -> void:
	test("overshooting the upper ladder is harmless")
	var lv: LevelData = _load()
	if lv == null:
		return
	var w: WorldSim = WorldSim.new(lv)

	## Walk her along the terrace and one tile past the upper ladder at x=10,
	## which is what a player hunting for the way up will do.
	##
	## Note the left end of the terrace is against the boundary wall, so
	## walking LEFT proves nothing - an earlier version of this test did
	## exactly that and reported green without ever leaving the floor.
	## Stand the guardian down for this one. The check is about terrace
	## GEOMETRY; leaving a patrolling enemy in it would measure the enemy.
	for e: EnemySim in w.enemies:
		e.alive = false
	w.player.spawn_at_tile(Vector2i(8, 4))
	var start_health: int = w.player.health
	var prev: int = 0
	for _i: int in 50:
		w.tick(InputFrame.from_mask(InputFrame.B_RIGHT, prev))
		prev = InputFrame.B_RIGHT

	check(w.player.tile().x > 10, "walked past the ladder column")
	check_eq(w.player.pos.y, Grid.tile_origin(5), "still standing on the terrace")
	check_eq(w.player.health, start_health,
			"overshooting cost no health (lost %d)"
			% (start_health - w.player.health))

	test("the terrace has real margin past the ladder")
	var m: CollisionMap = CollisionMap.from_level(lv)
	check(m.is_support(11, 5) and m.is_support(12, 5),
			"at least two tiles of floor continue past the upper ladder")


## The first enemy in the game must be contained. A patrol that can wander
## onto the ground floor could camp the spawn, and a tutorial that kills you
## before you have moved is not a tutorial.
func _test_guardian_is_contained() -> void:
	test("the guardian stays on the terrace")
	var lv: LevelData = _load()
	if lv == null:
		return
	var w: WorldSim = WorldSim.new(lv)
	check(w.enemies.size() > 0, "the level actually has an enemy")
	if w.enemies.is_empty():
		return

	var min_x: int = 99
	var max_x: int = -99
	var rows: Dictionary = {}
	## Let it walk a long time with the player standing still at the spawn.
	for _i: int in 6000:
		w.tick(InputFrame.from_mask(0, 0))
		var t: Vector2i = w.enemies[0].tile()
		min_x = mini(min_x, t.x)
		max_x = maxi(max_x, t.x)
		rows[t.y] = true

	check_eq(rows.size(), 1, "never left its floor (rows seen: %d)" % rows.size())
	check(rows.has(4), "and that floor is the terrace")
	check(min_x >= 1, "never walked through the west wall (min x %d)" % min_x)
	check(max_x <= 12, "never walked off the terrace ledge (max x %d)" % max_x)
	check(max_x > min_x + 2, "it actually patrols (x %d..%d)" % [min_x, max_x])

	test("and never reaches the player standing at the spawn")
	check(w.player.health == PlayerSim.MAX_HEALTH,
			"a motionless player on the ground floor is never touched")


## The player must have both answers available: avoid it, or kill it.
func _test_guardian_can_be_dealt_with() -> void:
	test("the dagger kills the guardian")
	var lv: LevelData = _load()
	if lv == null:
		return
	var w: WorldSim = WorldSim.new(lv)
	if w.enemies.is_empty():
		return
	var g: EnemySim = w.enemies[0]

	## Stand her one tile to the left of it, facing right, and swing.
	var gt: Vector2i = g.tile()
	w.player.spawn_at_tile(Vector2i(gt.x - 1, gt.y))
	w.player.facing = 1
	g.pos.x = Grid.tile_center(gt.x)

	var prev: int = 0
	var killed: bool = false
	for _i: int in 20:
		w.tick(InputFrame.from_mask(InputFrame.B_ACTION, prev))
		prev = InputFrame.B_ACTION
		if not g.alive:
			killed = true
			break
	check(killed, "one swing from the adjacent tile kills it")
	check(w.player.is_alive(), "and she survives doing it")

	test("the guardian can be cleared from the route")
	var rep: Solver.Report = Solver.validate_state(
			lv, w.map, w.player.tile(), w.held, w.open_doors)
	check(rep.solvable, "the level remains winnable afterwards: %s" % rep.summary())
