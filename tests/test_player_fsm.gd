extends TestSuite

## The player finite state machine and movement contract (spec sections 9, 10, 12).

const FLAT: Array = [
	"################",
	"#..............#",
	"#..............#",
	"#.....BBB......#",
	"#.........BBB..#",
	"#BBBBBBBBBBBBBB#",
	"################",
]

## The ladder's topmost tile IS the floor tile it passes through, which is the
## pattern every real level uses: climbing it leaves her feet flush with that
## floor so she can step off sideways.
const LADDER: Array = [
	"######",
	"#....#",
	"#....#",
	"#BHBB#",
	"#.H..#",
	"#BBBB#",
	"######",
]

## Two right-ascending stairs, each handing off to the next: (5,4) tops out at
## the level (6,3) starts from, and (6,3) tops out level with the floor at
## (7,3).
const STAIRS: Array = [
	"##########",
	"#........#",
	"#........#",
	"#...../BB#",
	"#..../...#",
	"#BBBB....#",
	"##########",
]


func run() -> void:
	suite_name = "player"
	_test_transition_table()
	_test_spawn_and_idle()
	_test_walk_and_snap()
	_test_gravity()
	_test_jump_height()
	_test_ladder()
	_test_stairs()
	_test_never_wedged()
	_test_damage_and_death()
	_test_snapshot_roundtrip()


## Every state must have an entry, and every listed target must be a real
## state. A typo here would silently allow an illegal transition.
func _test_transition_table() -> void:
	test("transition table is complete")
	var count: int = PlayerSim.STATE_NAMES.size()
	check_eq(PlayerSim.TRANSITIONS.size(), count, "every state has a transition list")
	var all_valid: bool = true
	var reachable: Dictionary = {}
	for from: Variant in PlayerSim.TRANSITIONS:
		if int(from) < 0 or int(from) >= count:
			all_valid = false
		for to: Variant in (PlayerSim.TRANSITIONS[from] as Array):
			if int(to) < 0 or int(to) >= count:
				all_valid = false
			reachable[int(to)] = true
	check(all_valid, "no transition names a state that does not exist")

	test("no orphan states")
	var orphans: PackedStringArray = PackedStringArray()
	for s: int in count:
		if s != PlayerSim.S.IDLE and not reachable.has(s):
			orphans.append(PlayerSim.STATE_NAMES[s])
	check(orphans.is_empty(), "unreachable states: %s" % ", ".join(orphans))

	test("terminal states are constrained")
	check_eq((PlayerSim.TRANSITIONS[PlayerSim.S.DYING] as Array).size(), 1,
			"DYING leads only to DEAD")
	check(not (PlayerSim.TRANSITIONS[PlayerSim.S.DEAD] as Array).has(PlayerSim.S.WALKING),
			"DEAD cannot walk away")


func _test_spawn_and_idle() -> void:
	test("spawn")
	var m: CollisionMap = map_from(FLAT)
	var p: PlayerSim = PlayerSim.new(m)
	p.spawn_at_tile(Vector2i(2, 4))
	check_eq(p.pos.x, Grid.tile_center(2), "spawn is horizontally centred")
	check_eq(p.pos.y, Grid.tile_origin(5), "feet rest on the floor boundary")
	check_eq(p.state, PlayerSim.S.IDLE, "spawns idle")
	check_eq(p.tile(), Vector2i(2, 4), "occupies the tile above the floor")

	hold(p, 0, 30)
	check_eq(p.state, PlayerSim.S.IDLE, "stays idle with no input")
	check_eq(p.pos.y, Grid.tile_origin(5), "does not sink through the floor")


func _test_walk_and_snap() -> void:
	test("walking")
	var m: CollisionMap = map_from(FLAT)
	var p: PlayerSim = PlayerSim.new(m)
	p.spawn_at_tile(Vector2i(2, 4))
	var start_x: int = p.pos.x
	hold(p, InputFrame.B_RIGHT, 16)
	check_eq(p.pos.x - start_x, Grid.TILE_SUB, "16 ticks of walking covers one tile")
	check_eq(p.state, PlayerSim.S.WALKING, "is walking")
	check_eq(p.facing, 1, "faces the direction of travel")

	test("alignment rule on stop")
	## Spec section 9: stopping must snap to the grid, never straddle it.
	hold(p, InputFrame.B_RIGHT, 7)
	hold(p, 0, 1)
	check_eq(p.state, PlayerSim.S.IDLE, "returns to idle")
	check_eq(Grid.fmod_i(p.pos.x, Grid.TILE_SUB), Grid.TILE_SUB / 2,
			"anchor snapped to a tile centre")

	test("running is faster than walking")
	var walker: PlayerSim = PlayerSim.new(map_from(FLAT))
	walker.spawn_at_tile(Vector2i(2, 4))
	var runner: PlayerSim = PlayerSim.new(map_from(FLAT))
	runner.spawn_at_tile(Vector2i(2, 4))
	hold(walker, InputFrame.B_RIGHT, 10)
	hold(runner, InputFrame.B_RIGHT | InputFrame.B_RUN, 10)
	check(runner.pos.x > walker.pos.x, "running covers more ground")
	check_eq(runner.state, PlayerSim.S.RUNNING, "enters RUNNING")

	test("walls stop movement")
	var w: PlayerSim = PlayerSim.new(map_from(FLAT))
	w.spawn_at_tile(Vector2i(1, 4))
	hold(w, InputFrame.B_LEFT, 60)
	check_eq(w.state, PlayerSim.S.IDLE, "idles against the wall")
	check(not w.map.body_blocked(w.pos.x, w.pos.y), "never ends inside a wall")
	check(w.pos.x >= Grid.tile_origin(1), "does not pass the boundary wall")


func _test_gravity() -> void:
	test("falling")
	var m: CollisionMap = map_from(FLAT)
	var p: PlayerSim = PlayerSim.new(m)
	## Drop her from above the floor.
	p.spawn_at_tile(Vector2i(3, 1))
	p.pos.y = Grid.tile_origin(2)
	hold(p, 0, 1)
	check_eq(p.state, PlayerSim.S.FALLING, "unsupported means falling")
	hold(p, 0, 60)
	check_eq(p.pos.y, Grid.tile_origin(5), "lands flush on the floor boundary")
	check(p.state == PlayerSim.S.IDLE or p.state == PlayerSim.S.LANDING,
			"settles after landing, got %s" % p.state_name())

	test("terminal velocity is bounded")
	var q: PlayerSim = PlayerSim.new(map_from(FLAT))
	q.spawn_at_tile(Vector2i(3, 1))
	q.pos.y = Grid.tile_origin(2)
	var peak: int = 0
	for _i: int in 40:
		q.tick(InputFrame.from_mask(0, 0))
		peak = maxi(peak, q.vel_y)
	check(peak <= PlayerSim.TERMINAL_V, "never exceeds terminal velocity")


func _test_jump_height() -> void:
	test("a jump clears one tile")
	var p: PlayerSim = PlayerSim.new(map_from(FLAT))
	p.spawn_at_tile(Vector2i(9, 4))
	press(p, InputFrame.B_JUMP | InputFrame.B_RIGHT, 40)
	hold(p, 0, 10)
	check_eq(p.pos.y, Grid.tile_origin(4),
			"lands on the one-tile ledge (got y=%d)" % p.pos.y)

	test("a jump does not clear two tiles")
	var q: PlayerSim = PlayerSim.new(map_from(FLAT))
	q.spawn_at_tile(Vector2i(4, 4))
	press(q, InputFrame.B_JUMP | InputFrame.B_RIGHT, 40)
	hold(q, 0, 20)
	check_ne(q.pos.y, Grid.tile_origin(3), "cannot reach the two-tile ledge")
	check_eq(q.pos.y, Grid.tile_origin(5), "falls back to the floor")

	test("variable jump height")
	var tall: PlayerSim = PlayerSim.new(map_from(FLAT))
	tall.spawn_at_tile(Vector2i(2, 4))
	var short: PlayerSim = PlayerSim.new(map_from(FLAT))
	short.spawn_at_tile(Vector2i(2, 4))
	var tall_peak: int = tall.pos.y
	var short_peak: int = short.pos.y
	var prev: int = 0
	for i: int in 30:
		tall.tick(InputFrame.from_mask(InputFrame.B_JUMP, prev))
		## The short hop releases after three ticks.
		var mask: int = InputFrame.B_JUMP if i < 3 else 0
		short.tick(InputFrame.from_mask(mask, prev))
		prev = InputFrame.B_JUMP
		tall_peak = mini(tall_peak, tall.pos.y)
		short_peak = mini(short_peak, short.pos.y)
	check(tall_peak < short_peak, "holding jump goes higher than tapping it")


func _test_ladder() -> void:
	test("climbing")
	var m: CollisionMap = map_from(LADDER)
	var p: PlayerSim = PlayerSim.new(m)
	p.spawn_at_tile(Vector2i(2, 4))
	check_eq(p.pos.y, Grid.tile_origin(5), "starts on the lower floor")

	hold(p, InputFrame.B_UP, 1)
	check_eq(p.state, PlayerSim.S.CLIMBING, "up on a ladder climbs")
	check_eq(p.pos.x, Grid.tile_center(2), "snaps to the ladder column")

	hold(p, InputFrame.B_UP, 60)
	check_eq(p.pos.y, Grid.tile_origin(3),
			"rests flush with the floor the ladder serves (got y=%d)" % p.pos.y)

	test("stepping off the top of a ladder")
	hold(p, InputFrame.B_RIGHT, 20)
	check_eq(p.state, PlayerSim.S.IDLE, "steps off onto the upper floor")
	check_eq(p.pos.y, Grid.tile_origin(3), "stands on the upper floor surface")
	check(p.pos.x > Grid.tile_center(2), "actually moved off the ladder")

	test("descending")
	var d: PlayerSim = PlayerSim.new(map_from(LADDER))
	d.spawn_at_tile(Vector2i(2, 2))
	hold(d, InputFrame.B_DOWN, 1)
	check_eq(d.state, PlayerSim.S.DESCENDING, "down into a ladder descends")
	hold(d, InputFrame.B_DOWN, 60)
	check_eq(d.pos.y, Grid.tile_origin(5), "reaches the lower floor")
	check_eq(d.state, PlayerSim.S.IDLE, "settles on the floor")

	test("a ladder is not a wall")
	var w: PlayerSim = PlayerSim.new(map_from(LADDER))
	w.spawn_at_tile(Vector2i(1, 4))
	hold(w, InputFrame.B_RIGHT, 40)
	check(w.pos.x > Grid.tile_center(2), "walks past the ladder at floor level")


func _test_stairs() -> void:
	test("stairs ascend diagonally")
	var m: CollisionMap = map_from(STAIRS)
	check_eq(m.stair_dir(5, 4), 1, "the legend parsed a right-ascending stair")
	var p: PlayerSim = PlayerSim.new(m)
	p.spawn_at_tile(Vector2i(4, 4))
	var y0: int = p.pos.y
	hold(p, InputFrame.B_RIGHT, 48)
	check(p.pos.y < y0, "gained height by walking right (y %d -> %d)" % [y0, p.pos.y])
	check(p.state != PlayerSim.S.FALLING, "did not fall off the staircase")

	test("stair surface is a pure function of x")
	## This is what guarantees she can never be wedged on a staircase.
	var a: int = p.stair_surface_y(5, 4, Grid.tile_center(5))
	var b: int = p.stair_surface_y(5, 4, Grid.tile_center(5))
	check_eq(a, b, "same x gives the same surface height")
	var left_edge: int = p.stair_surface_y(5, 4, Grid.tile_origin(5))
	var right_edge: int = p.stair_surface_y(5, 4, Grid.tile_origin(5) + Grid.TILE_SUB - 1)
	check(right_edge < left_edge, "a right-ascending stair rises toward the right")


## Spec section 9: the player must never become partially trapped between
## grid positions. This soaks a long scripted input sequence and asserts the
## invariant after every single tick.
func _test_never_wedged() -> void:
	test("never trapped between grid positions")
	var m: CollisionMap = map_from(FLAT)
	var p: PlayerSim = PlayerSim.new(m)
	p.spawn_at_tile(Vector2i(2, 4))

	var script: Array = [
		[InputFrame.B_RIGHT, 40], [InputFrame.B_JUMP | InputFrame.B_RIGHT, 12],
		[InputFrame.B_LEFT, 25], [InputFrame.B_JUMP, 8],
		[InputFrame.B_RIGHT | InputFrame.B_RUN, 60], [0, 10],
		[InputFrame.B_LEFT | InputFrame.B_JUMP, 30], [InputFrame.B_UP, 12],
		[InputFrame.B_DOWN, 12], [InputFrame.B_RIGHT, 90], [0, 20],
	]
	var masks: PackedInt32Array = InputRouter.script_to_masks(script)
	var prev: int = 0
	var inside_wall: int = -1
	var idle_unsnapped: int = -1
	for i: int in masks.size():
		p.tick(InputFrame.from_mask(masks[i], prev))
		prev = masks[i]
		if m.body_blocked(p.pos.x, p.pos.y) and inside_wall < 0:
			inside_wall = i
		if p.state == PlayerSim.S.IDLE and idle_unsnapped < 0:
			if Grid.fmod_i(p.pos.x, Grid.TILE_SUB) != Grid.TILE_SUB / 2:
				idle_unsnapped = i
	check_eq(inside_wall, -1, "body never overlapped a solid tile")
	check_eq(idle_unsnapped, -1, "idle always leaves the anchor snapped")
	check(p.state != PlayerSim.S.DEAD, "survived the soak")


func _test_damage_and_death() -> void:
	test("damage and invulnerability")
	var p: PlayerSim = PlayerSim.new(map_from(FLAT))
	p.spawn_at_tile(Vector2i(2, 4))
	check(p.apply_damage(1, 1), "first hit lands")
	check_eq(p.health, PlayerSim.MAX_HEALTH - 1, "health drops by one")
	check_eq(p.state, PlayerSim.S.HURT, "enters HURT")
	check(not p.apply_damage(1, 1), "a second hit is refused while invulnerable")
	check_eq(p.health, PlayerSim.MAX_HEALTH - 1, "health unchanged")

	test("death")
	var q: PlayerSim = PlayerSim.new(map_from(FLAT))
	q.spawn_at_tile(Vector2i(2, 4))
	q.kill()
	check_eq(q.state, PlayerSim.S.DYING, "kill enters DYING")
	check(not q.is_alive(), "no longer alive")
	hold(q, InputFrame.B_RIGHT, PlayerSim.DYING_TICKS + 2)
	check_eq(q.state, PlayerSim.S.DEAD, "DYING resolves to DEAD")
	check(q.state == PlayerSim.S.DEAD, "input cannot resurrect her")


func _test_snapshot_roundtrip() -> void:
	test("snapshot round trip")
	var p: PlayerSim = PlayerSim.new(map_from(FLAT))
	p.spawn_at_tile(Vector2i(2, 4))
	hold(p, InputFrame.B_RIGHT, 9)
	var snap: Dictionary = p.snapshot()
	var pos: Vector2i = p.pos
	var st: int = p.state

	hold(p, InputFrame.B_RIGHT, 40)
	check_ne(p.pos, pos, "moved away from the snapshot")

	p.restore(snap)
	check_eq(p.pos, pos, "restore returns the exact anchor")
	check_eq(p.state, st, "restore returns the exact state")
