extends SceneTree

## Development tool: measure the jump arc against how long the button is held.
##
##   godot --headless --path . --script res://tools/jump_profile.gd
##
## "The jump feels inconsistent" is a measurable claim, so measure it. This
## prints the height and distance of a jump for every hold duration from a
## single tick up to a full hold, on flat ground with RIGHT held throughout.
##
## The number that matters is DISTANCE, because levels are authored against
## "a jump clears one tile of gap" and a tile is 16 world units.

const FLAT: Array = [
	"####################",
	"#..................#",
	"#..................#",
	"#..................#",
	"#BBBBBBBBBBBBBBBBBB#",
	"####################",
]


func _initialize() -> void:
	var m: CollisionMap = _map()
	print("")
	print("hold  apex(wu)  distance(wu)  distance(tiles)  airborne(ticks)")
	print("----  --------  ------------  ---------------  ---------------")
	for hold: int in [1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 30, 45]:
		var r: Dictionary = _jump(m, hold)
		print("%4d  %8.1f  %12.1f  %15.2f  %15d"
				% [hold, r["apex"], r["dist"], r["dist"] / 16.0, r["ticks"]])
	print("")
	print("A one-tile gap needs the anchor to travel from the middle of the")
	print("departure tile to the middle of the landing tile: 2.0 tiles.")
	print("")
	quit(0)


func _map() -> CollisionMap:
	var h: int = FLAT.size()
	var w: int = str(FLAT[0]).length()
	var m: CollisionMap = CollisionMap.new(w, h)
	for y: int in h:
		var row: String = str(FLAT[y])
		for x: int in w:
			m.set_at(x, y, int(LevelData.DEFAULT_LEGEND.get(row.substr(x, 1),
					TileDB.T.EMPTY)))
	return m


## Jump with RIGHT held throughout and JUMP held for `hold` ticks.
func _jump(m: CollisionMap, hold: int) -> Dictionary:
	var p: PlayerSim = PlayerSim.new(m)
	p.spawn_at_tile(Vector2i(2, 3))
	var ground_y: int = p.pos.y
	var start_x: int = p.pos.x
	var apex: int = ground_y
	var airborne: int = 0
	var prev: int = 0

	for i: int in 120:
		var mask: int = InputFrame.B_RIGHT
		if i < hold:
			mask |= InputFrame.B_JUMP
		p.tick(InputFrame.from_mask(mask, prev))
		prev = mask
		apex = mini(apex, p.pos.y)
		if p.state == PlayerSim.S.JUMPING or p.state == PlayerSim.S.FALLING:
			airborne += 1
		elif airborne > 0:
			break

	return {
		"apex": float(ground_y - apex) / float(Grid.SUB),
		"dist": float(p.pos.x - start_x) / float(Grid.SUB),
		"ticks": airborne,
	}
