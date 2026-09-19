extends TestSuite

## Grid maths, the tile registry and the deterministic RNG.


func run() -> void:
	suite_name = "core"
	_test_grid()
	_test_negative_division()
	_test_tiles()
	_test_rng()
	_test_input_frame()


func _test_grid() -> void:
	test("grid constants")
	check_eq(Grid.VIEW_W, 256, "standard screen is 256 world units wide")
	check_eq(Grid.VIEW_H, 192, "standard screen is 192 world units high")
	check_eq(Grid.TILE_SUB, 256, "one tile is 256 subunits")
	check_eq(Grid.BODY_W_SUB, 192, "body box is 12 world units wide")
	check_eq(Grid.BODY_H_SUB, 224, "body box is 14 world units tall")

	test("tile conversion")
	check_eq(Grid.to_tile(0), 0, "origin is tile 0")
	check_eq(Grid.to_tile(255), 0, "last subunit of tile 0")
	check_eq(Grid.to_tile(256), 1, "first subunit of tile 1")
	check_eq(Grid.tile_center(3), 3 * 256 + 128, "tile centre")
	check_eq(Grid.snap_to_center(3 * 256 + 5), 3 * 256 + 128, "snap to centre")
	check_eq(Grid.snap_to_boundary(3 * 256 + 5), 3 * 256, "snap to boundary")


func _test_negative_division() -> void:
	## GDScript integer division truncates toward zero, which would make tile
	## lookups asymmetric across the origin. This is the guard for that.
	test("floor division across the origin")
	check_eq(Grid.fdiv(-1, 256), -1, "-1 subunit is in tile -1, not tile 0")
	check_eq(Grid.fdiv(-256, 256), -1, "exact negative boundary")
	check_eq(Grid.fdiv(-257, 256), -2, "one past the negative boundary")
	check_eq(Grid.to_tile(-1), -1, "to_tile agrees")
	check_eq(Grid.fmod_i(-1, 256), 255, "modulo stays non-negative")
	check_eq(Grid.fmod_i(-256, 256), 0, "exact negative multiple")


func _test_tiles() -> void:
	test("tile flags")
	check(TileDB.has(TileDB.T.TEMPLE_WALL, TileDB.F_SOLID), "wall is solid")
	check(not TileDB.has(TileDB.T.LADDER, TileDB.F_SOLID), "ladder is not solid")
	check(TileDB.has(TileDB.T.LADDER, TileDB.F_CLIMB), "ladder is climbable")
	check(TileDB.has(TileDB.T.MUD_BRICK_FLOOR, TileDB.F_SUPPORT), "floor supports")
	check(TileDB.has(TileDB.T.SPIKES, TileDB.F_HAZARD), "spikes are a hazard")
	check(not TileDB.has(TileDB.T.SPIKES, TileDB.F_SOLID), "spikes do not block")
	check(TileDB.has(TileDB.T.MOVABLE_BLOCK, TileDB.F_PUSHABLE), "block is pushable")
	check_eq(TileDB.flags_of(TileDB.T.EMPTY), 0, "empty has no flags")

	test("tile registry is extensible")
	## Spec section 7: a new tile type must not require an engine change.
	TileDB.register(64, "TEST_REED_MAT", TileDB.F_SUPPORT | TileDB.F_TRIGGER, "brick")
	check(TileDB.has(64, TileDB.F_SUPPORT), "registered tile carries its flags")
	check_eq(TileDB.name_of(64), "TEST_REED_MAT", "registered tile keeps its name")
	check_eq(TileDB.flags_of(999), 0, "unknown id is inert rather than fatal")


func _test_rng() -> void:
	test("deterministic rng")
	var a: DetRng = DetRng.new(12345)
	var b: DetRng = DetRng.new(12345)
	var same: bool = true
	for _i: int in 500:
		if a.next_u32() != b.next_u32():
			same = false
			break
	check(same, "same seed produces the same stream")

	var c: DetRng = DetRng.new(999)
	var in_range: bool = true
	var saw_low: bool = false
	var saw_high: bool = false
	for _i: int in 2000:
		var v: int = c.next_range(3, 7)
		if v < 3 or v > 7:
			in_range = false
		if v == 3:
			saw_low = true
		if v == 7:
			saw_high = true
	check(in_range, "next_range stays within bounds")
	check(saw_low and saw_high, "next_range reaches both endpoints")

	test("zero seed is handled")
	var z: DetRng = DetRng.new(0)
	check_ne(z.next_u32(), 0, "a zero seed does not collapse the stream")


func _test_input_frame() -> void:
	test("input frame")
	var f: InputFrame = InputFrame.from_mask(InputFrame.B_LEFT | InputFrame.B_JUMP, 0)
	check(f.is_held(InputFrame.B_LEFT), "held reports left")
	check(f.just_pressed(InputFrame.B_JUMP), "jump registers as newly pressed")
	check_eq(f.axis_x(), -1, "left is -1 on the x axis")

	var f2: InputFrame = InputFrame.from_mask(
			InputFrame.B_LEFT | InputFrame.B_JUMP, InputFrame.B_JUMP)
	check(not f2.just_pressed(InputFrame.B_JUMP), "held jump is not pressed again")

	test("opposing directions cancel")
	var f3: InputFrame = InputFrame.from_mask(
			InputFrame.B_LEFT | InputFrame.B_RIGHT, 0)
	check_eq(f3.axis_x(), 0, "left and right together cancel")
	var f4: InputFrame = InputFrame.from_mask(InputFrame.B_UP | InputFrame.B_DOWN, 0)
	check_eq(f4.axis_y(), 0, "up and down together cancel")
