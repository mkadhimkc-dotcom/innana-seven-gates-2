extends TestSuite

## The solvability validator (spec sections 17, 20).
##
## The solver is the thing that certifies levels, so its own movement model
## has to be pinned down by tests. The rule it must never break: if it says a
## tile is reachable, the player controller can actually get there.


func run() -> void:
	suite_name = "solver"
	_test_flat_reachability()
	_test_walls_block()
	_test_gap_envelope()
	_test_step_height()
	_test_ladders()
	_test_key_gates_exit()
	_test_unreachable_key()
	_test_monotone_fixpoint()


func _test_flat_reachability() -> void:
	test("flat room")
	var m: CollisionMap = map_from([
		"########",
		"#......#",
		"#BBBBBB#",
		"########",
	])
	var reach: Dictionary = Solver.reachable_tiles(m, Vector2i(1, 1))
	check_eq(reach.size(), 6, "all six floor tiles are reachable")
	check(reach.has(Vector2i(6, 1)), "the far end is reachable")
	check(not reach.has(Vector2i(0, 1)), "the wall is not")


func _test_walls_block() -> void:
	test("a wall divides the room")
	var m: CollisionMap = map_from([
		"########",
		"#..#...#",
		"#BBBBBB#",
		"########",
	])
	var reach: Dictionary = Solver.reachable_tiles(m, Vector2i(1, 1))
	check(reach.has(Vector2i(2, 1)), "the near side is reachable")
	check(not reach.has(Vector2i(4, 1)), "the far side is walled off")


## The envelope must match the controller: a standing jump crosses one tile of
## empty floor, never two.
## The pits below are three tiles deep on purpose. A shallow pit can be
## climbed out of on the far side, which would make the gap width irrelevant.
func _test_gap_envelope() -> void:
	test("one-tile gap is crossable")
	var one: CollisionMap = map_from([
		"########",
		"#......#",
		"#......#",
		"#BB.BBB#",
		"#BB.BBB#",
		"#BB.BBB#",
		"########",
	])
	var r1: Dictionary = Solver.reachable_tiles(one, Vector2i(1, 2))
	check(r1.has(Vector2i(4, 2)), "cleared a single-tile gap")

	test("two-tile gap is not")
	var two: CollisionMap = map_from([
		"##########",
		"#........#",
		"#........#",
		"#BB..BBBB#",
		"#BB..BBBB#",
		"#BB..BBBB#",
		"##########",
	])
	var r2: Dictionary = Solver.reachable_tiles(two, Vector2i(1, 2))
	check(not r2.has(Vector2i(5, 2)),
			"a two-tile gap is beyond a standing jump, so the far side is cut off")
	check(r2.has(Vector2i(4, 5)), "she can still fall into the pit")


func _test_step_height() -> void:
	test("a one-tile step up is climbable")
	var m: CollisionMap = map_from([
		"########",
		"#......#",
		"#...BBB#",
		"#BBBBBB#",
		"########",
	])
	var reach: Dictionary = Solver.reachable_tiles(m, Vector2i(1, 2))
	check(reach.has(Vector2i(4, 1)), "jumped onto the one-tile ledge")

	test("a two-tile step up is not")
	var tall: CollisionMap = map_from([
		"########",
		"#......#",
		"#...BBB#",
		"#...BBB#",
		"#BBBBBB#",
		"########",
	])
	var r2: Dictionary = Solver.reachable_tiles(tall, Vector2i(1, 3))
	check(not r2.has(Vector2i(4, 1)), "cannot reach a two-tile ledge")
	check(r2.has(Vector2i(3, 3)), "but the floor below it is fine")


func _test_ladders() -> void:
	test("ladders connect floors")
	var m: CollisionMap = map_from([
		"######",
		"#....#",
		"#.H..#",
		"#BHBB#",
		"#.H..#",
		"#BBBB#",
		"######",
	])
	var reach: Dictionary = Solver.reachable_tiles(m, Vector2i(1, 4))
	check(reach.has(Vector2i(2, 2)), "climbed the ladder")
	check(reach.has(Vector2i(3, 2)), "stepped off onto the upper floor")
	check(reach.has(Vector2i(1, 2)), "and to the other side")

	test("without the ladder the upper floor is cut off")
	var m2: CollisionMap = map_from([
		"######",
		"#....#",
		"#....#",
		"#BBBB#",
		"#....#",
		"#BBBB#",
		"######",
	])
	var r2: Dictionary = Solver.reachable_tiles(m2, Vector2i(1, 4))
	check(not r2.has(Vector2i(1, 2)), "no route upward")


func _test_key_gates_exit() -> void:
	test("a sealed exit opens only once its key is taken")
	var json: String = """
	{
	  "id": "t_gate", "gate": 1,
	  "map": ["######", "#....#", "#....#", "#BBBB#", "######"],
	  "player_start": [1, 2],
	  "exit": [4, 2],
	  "required_objects": [{ "id": "k", "kind": "key", "pos": [3, 2] }],
	  "validation_rules": { "exit_requires": ["k"] }
	}
	"""
	var parsed: LevelLoader.ParseResult = LevelLoader.parse(json, "<gate>")
	check(parsed.errors.is_empty(), "fixture parsed: %s" % ", ".join(parsed.errors))
	var rep: Solver.Report = Solver.validate_level(parsed.level)
	check(rep.solvable, "solvable once the key is collected: %s" % rep.summary())
	check(rep.acquired.has("k"), "the solver found the key")


func _test_unreachable_key() -> void:
	test("a walled-in key makes the level unsolvable")
	var json: String = """
	{
	  "id": "t_bad", "gate": 1,
	  "map": ["########", "#....#.#", "#BBBB#.#", "#BBBBBB#", "########"],
	  "player_start": [1, 1],
	  "exit": [4, 1],
	  "required_objects": [{ "id": "k", "kind": "key", "pos": [6, 1] }],
	  "validation_rules": { "exit_requires": ["k"] }
	}
	"""
	var parsed: LevelLoader.ParseResult = LevelLoader.parse(json, "<bad>")
	var rep: Solver.Report = Solver.validate_level(parsed.level)
	check(not rep.solvable, "reported unsolvable")
	check(rep.missing_objects.has("k"), "named the key it cannot reach")
	check(rep.summary().contains("cannot obtain"), "the summary explains why")


func _test_monotone_fixpoint() -> void:
	test("a switch chain resolves")
	## Key opens door A; standing on the plate behind door A opens door B,
	## which is the way out. The fixpoint has to iterate twice to see it.
	var json: String = """
	{
	  "id": "t_chain", "gate": 1,
	  "map": [
	    "##########",
	    "#..G...G.#",
	    "#BBBBBBBB#",
	    "##########"
	  ],
	  "player_start": [1, 1],
	  "exit": [8, 1],
	  "required_objects": [{ "id": "k", "kind": "key", "pos": [2, 1] }],
	  "doors": [
	    { "id": "doorA", "pos": [3, 1], "requires": ["k"] },
	    { "id": "doorB", "pos": [7, 1], "requires": [] }
	  ],
	  "switches": [
	    { "id": "plate1", "type": "plate", "pos": [5, 1], "targets": ["doorB"] }
	  ],
	  "validation_rules": {}
	}
	"""
	var parsed: LevelLoader.ParseResult = LevelLoader.parse(json, "<chain>")
	check(parsed.errors.is_empty(), "fixture parsed: %s" % ", ".join(parsed.errors))
	var rep: Solver.Report = Solver.validate_level(parsed.level)
	check(rep.solvable, "the chain resolves: %s" % rep.summary())

	test("breaking the chain is detected")
	var broken: String = json.replace('"requires": ["k"]', '"requires": ["missing"]')
	var p2: LevelLoader.ParseResult = LevelLoader.parse(broken, "<broken>")
	var rep2: Solver.Report = Solver.validate_level(p2.level)
	check(not rep2.solvable, "an unopenable door blocks the level")
