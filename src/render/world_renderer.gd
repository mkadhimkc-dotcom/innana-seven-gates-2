class_name WorldRenderer
extends Node2D

## Draws the simulation (spec sections 25, 26).
##
## Everything here is procedural vector work at logical resolution, so the
## project has a complete visual identity with no binary art dependencies yet.
## Sprite sheets will replace the tile and actor drawing functions one at a
## time; the layout, palette and silhouette language they have to match are
## defined here and in docs/ART_BIBLE.md.
##
## The renderer never mutates the simulation. It only reads it, and it
## interpolates between the previous and current tick so motion stays smooth
## on displays that do not run at exactly 60Hz.

var world: WorldSim = null
var palette: Dictionary = {}

## Interpolation between the last two simulation ticks, 0..1.
var alpha: float = 1.0

var _prev_player: Vector2i = Vector2i.ZERO
var _prev_enemies: Array[Vector2i] = []
var _anim_tick: int = 0
var _shake: float = 0.0


func bind(w: WorldSim) -> void:
	world = w
	palette = Palette.gate(w.level.palette)
	_prev_player = w.player.pos
	_prev_enemies.clear()
	for e: EnemySim in w.enemies:
		_prev_enemies.append(e.pos)


## Called by the game loop immediately before each simulation tick, so the
## renderer keeps the pose it is interpolating away from.
func capture_previous() -> void:
	if world == null:
		return
	_prev_player = world.player.pos
	_prev_enemies.clear()
	for e: EnemySim in world.enemies:
		_prev_enemies.append(e.pos)


func _process(delta: float) -> void:
	_anim_tick += 1
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 6.0)
	queue_redraw()


func kick_shake(amount: float = 1.0) -> void:
	if Settings.screen_shake:
		_shake = minf(2.5, _shake + amount)


func _draw() -> void:
	if world == null:
		return
	var offset: Vector2 = Vector2.ZERO
	if _shake > 0.0:
		## Deterministic shake: driven by the animation counter, never random,
		## so it can never desync a replay.
		offset = Vector2(sin(float(_anim_tick) * 1.7), cos(float(_anim_tick) * 2.3)) * _shake
	draw_set_transform(offset, 0.0, Vector2.ONE)

	_draw_background()
	_draw_tiles()
	_draw_treasures()
	_draw_objects()
	_draw_checkpoints()
	_draw_enemies()
	_draw_player()


# --- environment ----------------------------------------------------------

func _draw_background() -> void:
	var w: float = float(world.map.width * Grid.TILE)
	var h: float = float(world.map.height * Grid.TILE)
	draw_rect(Rect2(0, 0, w, h), palette["bg"], true)
	## A faint horizon band, so empty space reads as architecture rather than
	## void. Reed-mat courses, the oldest Mesopotamian wall decoration there is.
	var far: Color = palette["bg_far"]
	for y: int in range(0, world.map.height, 3):
		draw_rect(Rect2(0, float(y * Grid.TILE), w, float(Grid.TILE)), far, true)
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.0), false)


func _draw_tiles() -> void:
	for ty: int in world.map.height:
		for tx: int in world.map.width:
			var id_value: int = world.map.at(tx, ty)
			if id_value == TileDB.T.EMPTY:
				continue
			_draw_tile(tx, ty, id_value)


func _draw_tile(tx: int, ty: int, id_value: int) -> void:
	var o: Vector2 = Vector2(float(tx * Grid.TILE), float(ty * Grid.TILE))
	var t: float = float(Grid.TILE)
	var c: Color = Palette.tile_color(palette, id_value)

	match id_value:
		TileDB.T.TEMPLE_WALL:
			draw_rect(Rect2(o, Vector2(t, t)), c, true)
			draw_rect(Rect2(o, Vector2(t, 1.0)), palette["wall_hi"], true)
		TileDB.T.MUD_BRICK_FLOOR, TileDB.T.HIDDEN_PASSAGE:
			_draw_brick(o, t, c)
		TileDB.T.COLLAPSING_FLOOR:
			_draw_brick(o, t, c)
			## Cracks, and a visible tremor once the countdown starts.
			var cracking: bool = world.collapsing.has(Vector2i(tx, ty))
			var crack_col: Color = palette["bg"]
			crack_col.a = 0.9 if cracking else 0.55
			var jitter: float = 0.0
			if cracking:
				jitter = float((_anim_tick / 2) % 2)
			draw_line(o + Vector2(3 + jitter, 4), o + Vector2(7, 11), crack_col, 1.0)
			draw_line(o + Vector2(9, 3), o + Vector2(13 - jitter, 12), crack_col, 1.0)
		TileDB.T.LADDER:
			var rail: float = 3.0
			draw_rect(Rect2(o + Vector2(rail, 0), Vector2(1.5, t)), c, true)
			draw_rect(Rect2(o + Vector2(t - rail - 1.5, 0), Vector2(1.5, t)), c, true)
			for i: int in 3:
				draw_rect(Rect2(o + Vector2(rail, 3.0 + float(i) * 5.0),
						Vector2(t - rail * 2.0, 1.5)), c, true)
		TileDB.T.STAIR_LEFT, TileDB.T.STAIR_RIGHT:
			_draw_stair(o, t, c, id_value == TileDB.T.STAIR_RIGHT)
		TileDB.T.LOCKED_GATE:
			_draw_gate(o, t, c, false)
		TileDB.T.OPEN_GATE:
			_draw_gate(o, t, c, true)
		TileDB.T.SPIKES:
			## Upturned reed stakes, set into the floor.
			for i: int in 4:
				var x: float = float(i) * 4.0 + 2.0
				draw_colored_polygon(PackedVector2Array([
					o + Vector2(x - 2.0, t), o + Vector2(x + 2.0, t),
					o + Vector2(x, t - 9.0)]), c)
		TileDB.T.WATER:
			var wc: Color = c
			wc.a = 0.75
			draw_rect(Rect2(o, Vector2(t, t)), wc, true)
			var ripple: float = float((_anim_tick / 8 + tx) % 4)
			draw_line(o + Vector2(2.0 + ripple, 3.0), o + Vector2(t - 3.0, 3.0),
					palette["brick_hi"], 1.0)
		TileDB.T.PILLAR:
			draw_rect(Rect2(o + Vector2(2, 0), Vector2(t - 4.0, t)), c, true)
			draw_rect(Rect2(o + Vector2(1, 0), Vector2(t - 2.0, 2.0)),
					palette["wall_hi"], true)
			draw_rect(Rect2(o + Vector2(1, t - 2.0), Vector2(t - 2.0, 2.0)),
					palette["wall_hi"], true)
		TileDB.T.PRESSURE_PLATE:
			var pressed: bool = _plate_pressed(Vector2i(tx, ty))
			var y: float = t - (2.0 if pressed else 4.0)
			draw_rect(Rect2(o + Vector2(2, y), Vector2(t - 4.0, t - y)), c, true)
			draw_rect(Rect2(o + Vector2(1, y), Vector2(t - 2.0, 1.0)),
					palette["brick_hi"], true)
		TileDB.T.MOVABLE_BLOCK:
			draw_rect(Rect2(o + Vector2(1, 1), Vector2(t - 2.0, t - 2.0)), c, true)
			draw_rect(Rect2(o + Vector2(1, 1), Vector2(t - 2.0, 1.5)),
					palette["brick_hi"], true)
			## A carved cylinder-seal band, so a pushable block never reads as
			## ordinary masonry.
			draw_rect(Rect2(o + Vector2(3, 6), Vector2(t - 6.0, 4.0)),
					palette["brick_lo"], true)
		TileDB.T.DARKNESS_ZONE:
			var dc: Color = c
			dc.a = 0.92
			draw_rect(Rect2(o, Vector2(t, t)), dc, true)
		_:
			draw_rect(Rect2(o, Vector2(t, t)), c, true)


func _draw_brick(o: Vector2, t: float, c: Color) -> void:
	draw_rect(Rect2(o, Vector2(t, t)), c, true)
	draw_rect(Rect2(o, Vector2(t, 1.0)), palette["brick_hi"], true)
	draw_rect(Rect2(o + Vector2(0, t - 1.0), Vector2(t, 1.0)), palette["brick_lo"], true)
	## Two courses of mud brick, offset, the way they were actually laid.
	draw_line(o + Vector2(0, t * 0.5), o + Vector2(t, t * 0.5), palette["brick_lo"], 1.0)
	draw_line(o + Vector2(t * 0.5, 0), o + Vector2(t * 0.5, t * 0.5),
			palette["brick_lo"], 1.0)
	draw_line(o + Vector2(t * 0.25, t * 0.5), o + Vector2(t * 0.25, t),
			palette["brick_lo"], 1.0)
	draw_line(o + Vector2(t * 0.75, t * 0.5), o + Vector2(t * 0.75, t),
			palette["brick_lo"], 1.0)


func _draw_stair(o: Vector2, t: float, c: Color, ascends_right: bool) -> void:
	var steps: int = 4
	var step: float = t / float(steps)
	for i: int in steps:
		var h: float = step * float(i + 1)
		var x: float = step * float(i) if ascends_right else t - step * float(i + 1)
		draw_rect(Rect2(o + Vector2(x, t - h), Vector2(step, h)), c, true)
		draw_rect(Rect2(o + Vector2(x, t - h), Vector2(step, 1.0)),
				palette["brick_hi"], true)


func _draw_gate(o: Vector2, t: float, c: Color, is_open: bool) -> void:
	## A trilithon doorway: two jambs and a lintel, the Mesopotamian gate form.
	draw_rect(Rect2(o, Vector2(2.0, t)), c, true)
	draw_rect(Rect2(o + Vector2(t - 2.0, 0), Vector2(2.0, t)), c, true)
	draw_rect(Rect2(o, Vector2(t, 3.0)), c, true)
	if is_open:
		var glow: Color = c
		glow.a = 0.30 + 0.12 * sin(float(_anim_tick) * 0.08)
		draw_rect(Rect2(o + Vector2(2, 3), Vector2(t - 4.0, t - 3.0)), glow, true)
	else:
		## Barred. The bars are what the player reads as "not yet".
		for i: int in 3:
			draw_rect(Rect2(o + Vector2(3.0 + float(i) * 4.0, 3),
					Vector2(1.5, t - 3.0)), c, true)


func _plate_pressed(t: Vector2i) -> bool:
	for s: Dictionary in world.level.switches:
		if s["pos"] == t:
			return bool(world.switch_state.get(str(s["id"]), false))
	return false


# --- entities -------------------------------------------------------------

func _draw_treasures() -> void:
	for t: Dictionary in world.level.treasures:
		if world.collected.has(str(t["id"])):
			continue
		var p: Vector2i = t["pos"]
		var o: Vector2 = Vector2(float(p.x * Grid.TILE), float(p.y * Grid.TILE))
		var tier: String = str(t.get("tier", "common"))
		var c: Color = Palette.treasure_color(tier)
		var bob: float = sin(float(_anim_tick) * 0.07 + float(p.x)) * 1.0
		var ctr: Vector2 = o + Vector2(8.0, 9.0 + bob)
		match tier:
			"legendary":
				## An eight-pointed star: Inanna's own sign.
				_draw_star(ctr, 6.0, 2.6, 8, c)
			"valuable":
				## A cylinder seal, seen end on.
				draw_rect(Rect2(ctr - Vector2(2.5, 4.0), Vector2(5.0, 8.0)), c, true)
				draw_rect(Rect2(ctr - Vector2(2.5, 4.0), Vector2(5.0, 1.0)),
						Palette.SHELL, true)
			_:
				## A clay tablet.
				draw_rect(Rect2(ctr - Vector2(3.5, 3.0), Vector2(7.0, 6.0)), c, true)
				draw_line(ctr + Vector2(-2.0, -1.0), ctr + Vector2(2.0, -1.0),
						Palette.BITUMEN, 1.0)
				draw_line(ctr + Vector2(-2.0, 1.0), ctr + Vector2(1.0, 1.0),
						Palette.BITUMEN, 1.0)


func _draw_objects() -> void:
	for o_def: Dictionary in world.level.required_objects:
		if world.held.has(str(o_def["id"])):
			continue
		var p: Vector2i = o_def["pos"]
		var o: Vector2 = Vector2(float(p.x * Grid.TILE), float(p.y * Grid.TILE))
		var bob: float = sin(float(_anim_tick) * 0.06 + float(p.y)) * 1.0
		var ctr: Vector2 = o + Vector2(8.0, 9.0 + bob)
		var c: Color = Palette.GOLD
		match str(o_def.get("kind", "key")):
			"seal":
				draw_rect(Rect2(ctr - Vector2(2.0, 4.5), Vector2(4.0, 9.0)), c, true)
				draw_rect(Rect2(ctr - Vector2(3.0, -1.0), Vector2(6.0, 1.0)),
						Palette.LAPIS_LIGHT, true)
			"ritual":
				_draw_star(ctr, 5.0, 2.0, 6, Palette.LAPIS_LIGHT)
			_:
				## A key: a bronze pin with a toothed bit.
				draw_rect(Rect2(ctr - Vector2(0.75, 4.5), Vector2(1.5, 9.0)), c, true)
				draw_arc(ctr - Vector2(0, 4.5), 2.5, 0.0, TAU, 10, c, 1.2)
				draw_rect(Rect2(ctr + Vector2(0.75, 2.0), Vector2(2.5, 1.2)), c, true)
				draw_rect(Rect2(ctr + Vector2(0.75, 4.0), Vector2(1.8, 1.2)), c, true)


func _draw_checkpoints() -> void:
	for c_def: Dictionary in world.level.checkpoints:
		var p: Vector2i = c_def["pos"]
		var o: Vector2 = Vector2(float(p.x * Grid.TILE), float(p.y * Grid.TILE))
		var lit: bool = world.checkpoints_taken.has(str(c_def["id"]))
		## A votive brazier: dark bowl when passed by, flame when claimed.
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(4, 16), o + Vector2(12, 16),
			o + Vector2(10.5, 11), o + Vector2(5.5, 11)]), Palette.BRONZE)
		if lit:
			var f: float = 2.0 + sin(float(_anim_tick) * 0.18 + float(p.x)) * 1.2
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(6.5, 11), o + Vector2(9.5, 11),
				o + Vector2(8.0, 11.0 - 4.0 - f)]), Palette.GOLD)


func _draw_enemies() -> void:
	for i: int in world.enemies.size():
		var e: EnemySim = world.enemies[i]
		if not e.alive:
			continue
		var prev: Vector2i = _prev_enemies[i] if i < _prev_enemies.size() else e.pos
		var p: Vector2 = _lerp_pos(prev, e.pos)
		match e.kind:
			EnemySim.Kind.SPIRIT:
				_draw_spirit(p, e)
			EnemySim.Kind.STATUE:
				_draw_statue(p, e)
			_:
				_draw_guardian(p, e)


func _draw_guardian(p: Vector2, e: EnemySim) -> void:
	## A temple guardian: a broad, low, helmeted silhouette, clearly not human.
	var body: Color = Palette.BRONZE
	var trim: Color = Palette.GOLD_DEEP
	draw_rect(Rect2(p + Vector2(-5, -13), Vector2(10, 13)), body, true)
	draw_rect(Rect2(p + Vector2(-6, -15), Vector2(12, 3)), trim, true)
	## Eyes face the direction of travel, so the player can read its turn.
	var ex: float = 2.0 * float(e.dir)
	draw_rect(Rect2(p + Vector2(ex - 2.5, -11), Vector2(2.0, 2.0)), Palette.CARNELIAN, true)
	draw_rect(Rect2(p + Vector2(ex + 0.5, -11), Vector2(2.0, 2.0)), Palette.CARNELIAN, true)


func _draw_statue(p: Vector2, e: EnemySim) -> void:
	var body: Color = Palette.SHELL if e.awake else Palette.UI_DIM
	draw_rect(Rect2(p + Vector2(-5, -14), Vector2(10, 14)), body, true)
	draw_rect(Rect2(p + Vector2(-6, -16), Vector2(12, 2)), Palette.GOLD_DEEP, true)
	if e.awake:
		draw_rect(Rect2(p + Vector2(-3, -12), Vector2(6, 1.5)), Palette.CARNELIAN, true)


func _draw_spirit(p: Vector2, _e: EnemySim) -> void:
	var glow: Color = Palette.LAPIS_LIGHT
	glow.a = 0.55 + 0.2 * sin(float(_anim_tick) * 0.12)
	draw_circle(p + Vector2(0, -8), 7.0, glow)
	draw_circle(p + Vector2(0, -8), 3.5, Palette.SHELL)


# --- Inanna ---------------------------------------------------------------

func _draw_player() -> void:
	var pl: PlayerSim = world.player
	if pl.state == PlayerSim.S.DEAD:
		return
	var p: Vector2 = _lerp_pos(_prev_player, pl.pos)

	## Invulnerability flicker, driven by the tick counter so it is identical
	## in a replay.
	if pl.invuln > 0 and (pl.invuln / 4) % 2 == 0:
		return

	var skin: Color = Palette.SHELL
	var robe: Color = Palette.CARNELIAN
	var trim: Color = Palette.GOLD
	var f: float = float(pl.facing)

	## Gate progression (spec section 24): Inanna surrenders one possession at
	## each gate, and the silhouette gets plainer as she descends.
	var regalia: int = maxi(0, 8 - world.level.gate)

	var lean: float = 0.0
	if pl.state in [PlayerSim.S.WALKING, PlayerSim.S.RUNNING]:
		lean = f * 1.0
	elif pl.state == PlayerSim.S.PUSHING:
		lean = f * 2.0

	## Robe (lost at Gate V and beyond).
	if regalia >= 3:
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-4.5, 0), p + Vector2(4.5, 0),
			p + Vector2(3.0 + lean, -9), p + Vector2(-3.0 + lean, -9)]), robe)
	else:
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-3.0, 0), p + Vector2(3.0, 0),
			p + Vector2(2.5 + lean, -9), p + Vector2(-2.5 + lean, -9)]), skin)

	## Torso and breastplate (lost at Gate IV and beyond).
	draw_rect(Rect2(p + Vector2(-2.5 + lean, -13), Vector2(5.0, 5.0)), skin, true)
	if regalia >= 4:
		draw_rect(Rect2(p + Vector2(-3.0 + lean, -12), Vector2(6.0, 2.5)), trim, true)

	## Head.
	draw_rect(Rect2(p + Vector2(-2.5 + lean, -18), Vector2(5.0, 5.0)), skin, true)
	## Hair, dark, falling behind her.
	draw_rect(Rect2(p + Vector2(-3.0 + lean - f * 0.5, -18), Vector2(6.0, 2.0)),
			Palette.BITUMEN, true)

	## Necklace (lost at Gate III and beyond).
	if regalia >= 5:
		draw_rect(Rect2(p + Vector2(-2.0 + lean, -13.5), Vector2(4.0, 1.0)),
				Palette.LAPIS_LIGHT, true)

	## Horned crown, the mark of a Mesopotamian deity (lost at Gate II).
	if regalia >= 6:
		draw_rect(Rect2(p + Vector2(-3.0 + lean, -19.5), Vector2(6.0, 1.5)), trim, true)
		draw_line(p + Vector2(-3.0 + lean, -19.5), p + Vector2(-4.5 + lean, -21.5),
				trim, 1.2)
		draw_line(p + Vector2(3.0 + lean, -19.5), p + Vector2(4.5 + lean, -21.5),
				trim, 1.2)

	## The dagger, raised only on the swing.
	if pl.state == PlayerSim.S.ATTACKING:
		var reach: float = 5.0 + 4.0 * clampf(float(pl.state_ticks) / 4.0, 0.0, 1.0)
		draw_rect(Rect2(p + Vector2(f * 2.0 - (0.0 if f > 0.0 else reach), -11),
				Vector2(reach, 1.8)), trim, true)

	## Legs: a two-frame stride, stepped from the tick counter.
	var stride: bool = (pl.state in [PlayerSim.S.WALKING, PlayerSim.S.RUNNING]
			and (world.tick_count / 6) % 2 == 0)
	if stride:
		draw_rect(Rect2(p + Vector2(-3.0, -2.0), Vector2(2.0, 2.0)), Palette.BITUMEN, true)
		draw_rect(Rect2(p + Vector2(1.5, -2.0), Vector2(2.0, 2.0)), Palette.BITUMEN, true)


func _lerp_pos(prev: Vector2i, cur: Vector2i) -> Vector2:
	var a: Vector2 = Vector2(Grid.to_px(prev.x), Grid.to_px(prev.y))
	var b: Vector2 = Vector2(Grid.to_px(cur.x), Grid.to_px(cur.y))
	return a.lerp(b, clampf(alpha, 0.0, 1.0))


func _draw_star(c: Vector2, outer: float, inner: float, points: int, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in points * 2:
		var r: float = outer if i % 2 == 0 else inner
		var a: float = float(i) * PI / float(points) - PI * 0.5
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
