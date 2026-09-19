class_name WorldRenderer
extends Node2D

## Draws the simulation (spec sections 25, 26).
##
## Everything is procedural vector work at the logical 256x192 resolution,
## which the project scales up with nearest-neighbour filtering. That means
## this is pixel art drawn with a pen rather than painted: whole-pixel
## coordinates, deliberate edges, and no sub-pixel detail that the upscale
## would only turn to mush.
##
## Three things carry the look, and they matter more than any single tile:
##
##   * LIGHT COMES FROM ABOVE. Every solid surface gets a lit top lip, a dark
##     underside, and casts a soft shadow onto the empty space beneath it.
##     This is what turns flat coloured squares into architecture.
##   * MUD BRICK IS IRREGULAR. Each tile takes a deterministic hash of its
##     coordinates and shifts its own tone slightly, so a wall of forty tiles
##     does not read as forty identical stamps.
##   * THE BACKGROUND IS A BUILDING. A ziggurat silhouette, buttress-and-
##     recess niching and reed-mat courses sit behind the play space, so empty
##     tiles read as the inside of a temple rather than as void.
##
## The renderer never mutates the simulation, and never uses randf(): every
## variation is hashed from coordinates and every animation is driven by a
## counter, so nothing here can desync a replay.

var world: WorldSim = null
var palette: Dictionary = {}

## Interpolation between the last two simulation ticks, 0..1.
var alpha: float = 1.0

var _prev_player: Vector2i = Vector2i.ZERO
var _prev_enemies: Array[Vector2i] = []
var _anim_tick: int = 0
var _shake: float = 0.0

## Cast-shadow tint, reused every tile.
const CAST: Color = Color(0, 0, 0, 0.22)


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
		## Deterministic shake, driven by the animation counter rather than
		## random, so it can never desync a replay. Rounded to whole pixels
		## so a shake does not smear the pixel grid.
		offset = Vector2(
			roundf(sin(float(_anim_tick) * 1.7) * _shake),
			roundf(cos(float(_anim_tick) * 2.3) * _shake))
	draw_set_transform(offset, 0.0, Vector2.ONE)

	_draw_background()
	_draw_cast_shadows()
	_draw_tiles()
	_draw_treasures()
	_draw_objects()
	_draw_checkpoints()
	_draw_enemies()
	_draw_player()
	_draw_vignette()


# --- deterministic variation ---------------------------------------------

## Stable per-tile hash. The same tile always gets the same grain, so a wall
## does not shimmer from one frame to the next.
func _hash(tx: int, ty: int) -> int:
	var h: int = (tx * 73856093) ^ (ty * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


## Small symmetric tone shift in roughly [-n, n] percent.
func _grain(tx: int, ty: int, n: int) -> float:
	return float(_hash(tx, ty) % (n * 2 + 1) - n) / 100.0


# --- environment ----------------------------------------------------------

## The background must stay BEHIND the level, in both senses. Its job is to
## say "you are inside a temple" and then get out of the way. Everything here
## is deliberately low contrast and much darker than the solid tiles, so that
## walls and floors read as the brightest, nearest thing on screen.
##
## An earlier version drew the niching at full strength and the room came out
## looking like a cage: the vertical rhythm was louder than the architecture
## the player actually has to read. Detail in the background is a whisper.
func _draw_background() -> void:
	var w: float = float(world.map.width * Grid.TILE)
	var h: float = float(world.map.height * Grid.TILE)
	var top: Color = (palette["bg_far"] as Color).darkened(0.30)
	var bottom: Color = (palette["bg"] as Color).darkened(0.62)

	## Vertical gradient. Deeper is darker, which reads as going underground
	## and gives every room an implied light source overhead.
	var bands: int = 24
	var band: float = h / float(bands)
	for i: int in bands:
		var t: float = float(i) / float(bands - 1)
		draw_rect(Rect2(0.0, float(i) * band, w, ceilf(band)), top.lerp(bottom, t), true)

	_draw_ziggurat(w, h)
	_draw_niches(w, h)


## A stepped ziggurat silhouette across the back of the room, catching a
## little of the light from above. Barely lighter than the wall behind it, so
## it reads as distance rather than as scenery to stand on.
func _draw_ziggurat(w: float, h: float) -> void:
	var lift: Color = Color(1, 1, 1, 0.030)
	var tread: Color = Color(1, 1, 1, 0.045)
	var steps: int = 5
	var step_h: float = 11.0
	var foot: float = h * 0.86
	for i: int in steps:
		var inset: float = 22.0 + float(i) * 18.0
		var y: float = foot - float(i + 1) * step_h
		draw_rect(Rect2(inset, y, w - inset * 2.0, step_h + 1.0), lift, true)
		draw_rect(Rect2(inset, y, w - inset * 2.0, 1.0), tread, true)


## Buttress-and-recess niching: the vertical rhythm of every Sumerian temple
## facade, and the thing that most reliably stops a wall reading as generic
## fantasy dungeon masonry. Drawn as alpha washes rather than opaque colour,
## so its strength is tuned in one place and can never overpower the level.
func _draw_niches(w: float, h: float) -> void:
	var recess: Color = Color(0, 0, 0, 0.16)
	var lip: Color = Color(1, 1, 1, 0.025)
	var x: int = 14
	while float(x) < w:
		draw_rect(Rect2(float(x), 0.0, 9.0, h), recess, true)
		draw_rect(Rect2(float(x) - 1.0, 0.0, 1.0, h), lip, true)
		x += 32

	## Reed-mat courses: the oldest wall decoration in the region. Widely
	## spaced and almost invisible, which is the point.
	var mat: Color = Color(1, 1, 1, 0.018)
	var y: int = 8
	while float(y) < h:
		draw_rect(Rect2(0.0, float(y), w, 1.0), mat, true)
		y += 16


## Soft shadow dropped by every solid tile onto the open space below it.
## Drawn before the tiles, so the tiles keep their crisp edges.
func _draw_cast_shadows() -> void:
	for ty: int in world.map.height:
		for tx: int in world.map.width:
			if _blocks_light(tx, ty) or not _blocks_light(tx, ty - 1):
				continue
			var o: Vector2 = Vector2(float(tx * Grid.TILE), float(ty * Grid.TILE))
			draw_rect(Rect2(o, Vector2(float(Grid.TILE), 3.0)), CAST, true)
			draw_rect(Rect2(o + Vector2(0, 3), Vector2(float(Grid.TILE), 2.0)),
					Color(CAST.r, CAST.g, CAST.b, CAST.a * 0.5), true)


func _blocks_light(tx: int, ty: int) -> bool:
	return TileDB.has(world.map.at(tx, ty), TileDB.F_OCCLUDE)


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
			_draw_masonry(o, t, c, tx, ty, true)
		TileDB.T.MUD_BRICK_FLOOR, TileDB.T.HIDDEN_PASSAGE:
			_draw_masonry(o, t, c, tx, ty, false)
		TileDB.T.COLLAPSING_FLOOR:
			_draw_collapsing(o, t, c, tx, ty)
		TileDB.T.LADDER:
			_draw_ladder(o, t, c, tx, ty)
		TileDB.T.STAIR_LEFT, TileDB.T.STAIR_RIGHT:
			_draw_stair(o, t, c, id_value == TileDB.T.STAIR_RIGHT)
		TileDB.T.LOCKED_GATE:
			_draw_gate(o, t, c, false)
		TileDB.T.OPEN_GATE:
			_draw_gate(o, t, c, true)
		TileDB.T.SPIKES:
			_draw_stakes(o, t, c)
		TileDB.T.WATER:
			_draw_water(o, t, c, tx, ty)
		TileDB.T.PILLAR:
			_draw_pillar(o, t, c)
		TileDB.T.PRESSURE_PLATE:
			_draw_plate(o, t, c, Vector2i(tx, ty))
		TileDB.T.MOVABLE_BLOCK:
			_draw_block(o, t, c)
		TileDB.T.DARKNESS_ZONE:
			var dc: Color = c
			dc.a = 0.92
			draw_rect(Rect2(o, Vector2(t, t)), dc, true)
		_:
			draw_rect(Rect2(o, Vector2(t, t)), c, true)


## Mud brick, laid in offset courses, with per-tile tone variation and
## light-from-above edge treatment.
func _draw_masonry(o: Vector2, t: float, c: Color, tx: int, ty: int,
		is_wall: bool) -> void:
	var g: float = _grain(tx, ty, 6)
	var body: Color = c.lightened(g) if g > 0.0 else c.darkened(-g)
	draw_rect(Rect2(o, Vector2(t, t)), body, true)

	var mortar: Color = body.darkened(0.22)
	var course: float = 8.0
	## Two courses, offset like real brickwork.
	draw_rect(Rect2(o + Vector2(0, course - 1.0), Vector2(t, 1.0)), mortar, true)
	var stagger: float = 8.0 if (tx + ty) % 2 == 0 else 4.0
	draw_rect(Rect2(o + Vector2(stagger, 0), Vector2(1.0, course - 1.0)), mortar, true)
	draw_rect(Rect2(o + Vector2(fmod(stagger + 8.0, t), course),
			Vector2(1.0, t - course)), mortar, true)
	if is_wall:
		draw_rect(Rect2(o, Vector2(t, 1.0)), mortar, true)

	## Straw and grit in the mud. Two flecks per tile is enough to break the
	## flatness without becoming noise.
	var h: int = _hash(tx, ty)
	for i: int in 2:
		var fx: float = float((h >> (i * 5)) % 13) + 1.0
		var fy: float = float((h >> (i * 7 + 3)) % 13) + 1.0
		draw_rect(Rect2(o + Vector2(fx, fy), Vector2(1.0, 1.0)),
				body.lightened(0.12), true)

	_draw_edges(o, t, body, tx, ty)


## The single most important function in this file. Light from above, so: a
## bright lip where the tile is exposed to the sky, a dark underside where it
## overhangs, and contact shading down the exposed sides.
func _draw_edges(o: Vector2, t: float, body: Color, tx: int, ty: int) -> void:
	if not _is_mass(tx, ty - 1):
		draw_rect(Rect2(o, Vector2(t, 1.0)), body.lightened(0.34), true)
		draw_rect(Rect2(o + Vector2(0, 1), Vector2(t, 1.0)), body.lightened(0.14), true)
	else:
		draw_rect(Rect2(o, Vector2(t, 1.0)), body.darkened(0.12), true)

	if not _is_mass(tx, ty + 1):
		draw_rect(Rect2(o + Vector2(0, t - 1.0), Vector2(t, 1.0)),
				body.darkened(0.42), true)
	if not _is_mass(tx - 1, ty):
		draw_rect(Rect2(o, Vector2(1.0, t)), body.darkened(0.16), true)
	if not _is_mass(tx + 1, ty):
		draw_rect(Rect2(o + Vector2(t - 1.0, 0), Vector2(1.0, t)),
				body.darkened(0.26), true)


## Does this tile read as part of the solid mass, for edge purposes? A
## pushable block is excluded: it should always look like a separate object
## sitting against the wall, never welded into it.
func _is_mass(tx: int, ty: int) -> bool:
	var id_value: int = world.map.at(tx, ty)
	return (TileDB.has(id_value, TileDB.F_SOLID)
			and not TileDB.has(id_value, TileDB.F_PUSHABLE))


func _draw_collapsing(o: Vector2, t: float, c: Color, tx: int, ty: int) -> void:
	var cracking: bool = world.collapsing.has(Vector2i(tx, ty))
	var jitter: float = 0.0
	if cracking:
		## Visible tremor once the countdown starts. The warning has to be
		## impossible to miss, because the punishment is a fall.
		jitter = float((_anim_tick / 2) % 2)
	_draw_masonry(o + Vector2(jitter, 0), t, c, tx, ty, false)
	var crack: Color = (palette["bg"] as Color).darkened(0.3)
	crack.a = 0.95 if cracking else 0.6
	draw_line(o + Vector2(3.0 + jitter, 3), o + Vector2(6.0 + jitter, 8), crack, 1.0)
	draw_line(o + Vector2(6.0 + jitter, 8), o + Vector2(4.0 + jitter, 13), crack, 1.0)
	draw_line(o + Vector2(10.0 + jitter, 2), o + Vector2(12.0 + jitter, 9), crack, 1.0)
	if cracking:
		var d: float = float((_anim_tick / 3) % 6)
		draw_rect(Rect2(o + Vector2(5, t + d), Vector2(1, 1)), crack, true)
		draw_rect(Rect2(o + Vector2(11, t + 6.0 - d), Vector2(1, 1)), crack, true)


## A bound-reed ladder: two lashed uprights lit from the left, rungs with a
## shadow under each.
func _draw_ladder(o: Vector2, t: float, c: Color, tx: int, ty: int) -> void:
	var dark: Color = c.darkened(0.45)
	var lit: Color = c.lightened(0.22)
	var rail: float = 3.0
	draw_rect(Rect2(o + Vector2(rail, 0), Vector2(2.0, t)), c, true)
	draw_rect(Rect2(o + Vector2(rail, 0), Vector2(1.0, t)), lit, true)
	draw_rect(Rect2(o + Vector2(t - rail - 2.0, 0), Vector2(2.0, t)),
			c.darkened(0.18), true)
	draw_rect(Rect2(o + Vector2(t - rail - 1.0, 0), Vector2(1.0, t)), dark, true)

	for i: int in 3:
		var y: float = 2.0 + float(i) * 5.0
		draw_rect(Rect2(o + Vector2(rail, y), Vector2(t - rail * 2.0, 2.0)), c, true)
		draw_rect(Rect2(o + Vector2(rail, y), Vector2(t - rail * 2.0, 1.0)), lit, true)
		draw_rect(Rect2(o + Vector2(rail, y + 2.0), Vector2(t - rail * 2.0, 1.0)),
				dark, true)

	if not world.map.is_climb(tx, ty - 1):
		## The top rung of a run is standable, so it is drawn as a lip you
		## could put a foot on. The picture has to agree with the collision.
		draw_rect(Rect2(o + Vector2(1, 0), Vector2(t - 2.0, 2.0)),
				c.lightened(0.30), true)
		draw_rect(Rect2(o + Vector2(1, 2), Vector2(t - 2.0, 1.0)), dark, true)


func _draw_stair(o: Vector2, t: float, c: Color, ascends_right: bool) -> void:
	var steps: int = 4
	var step: float = t / float(steps)
	for i: int in steps:
		var h: float = step * float(i + 1)
		var x: float = step * float(i) if ascends_right else t - step * float(i + 1)
		draw_rect(Rect2(o + Vector2(x, t - h), Vector2(step, h)), c, true)
		## Lit tread and shadowed riser on every step.
		draw_rect(Rect2(o + Vector2(x, t - h), Vector2(step, 1.0)),
				c.lightened(0.34), true)
		var riser_x: float = x + step - 1.0 if ascends_right else x
		draw_rect(Rect2(o + Vector2(riser_x, t - h), Vector2(1.0, h)),
				c.darkened(0.30), true)


## A trilithon doorway: two jambs, a lintel, and a rosette carved into the
## lintel. Barred when sealed, glowing when open.
##
## The frame is deliberately PALE - alabaster tinted by the gate palette -
## because the exit has to be legible from across the room before the player
## knows how to open it (spec section 3). Drawn in the local brown it simply
## disappeared into the mud brick around it. Value contrast is what carries
## at this size, not hue.
func _draw_gate(o: Vector2, t: float, c: Color, is_open: bool) -> void:
	var stone: Color = Palette.SHELL.lerp(c, 0.40)
	var stone_lit: Color = stone.lightened(0.30)
	var stone_dark: Color = stone.darkened(0.35)
	var recess: Color = (palette["bg"] as Color).darkened(0.55)

	## The opening.
	draw_rect(Rect2(o + Vector2(2, 4), Vector2(t - 4.0, t - 4.0)), recess, true)
	if is_open:
		## Warm light spilling out, pulsing slowly.
		var pulse: float = 0.45 + 0.14 * sin(float(_anim_tick) * 0.06)
		var glow: Color = Palette.GOLD
		glow.a = pulse
		draw_rect(Rect2(o + Vector2(2, 4), Vector2(t - 4.0, t - 4.0)), glow, true)
		glow.a = pulse * 0.30
		draw_rect(Rect2(o + Vector2(-3, 2), Vector2(t + 6.0, t)), glow, true)
	else:
		## Bronze bars, dark against the pale frame.
		var bar: Color = Palette.BRONZE.darkened(0.30)
		for i: int in 4:
			var x: float = 3.0 + float(i) * 3.0
			draw_rect(Rect2(o + Vector2(x, 4), Vector2(2.0, t - 4.0)), bar, true)
			draw_rect(Rect2(o + Vector2(x, 4), Vector2(1.0, t - 4.0)),
					bar.lightened(0.28), true)

	## Jambs.
	draw_rect(Rect2(o, Vector2(3.0, t)), stone, true)
	draw_rect(Rect2(o, Vector2(1.0, t)), stone_lit, true)
	draw_rect(Rect2(o + Vector2(2, 0), Vector2(1.0, t)), stone_dark, true)
	draw_rect(Rect2(o + Vector2(t - 3.0, 0), Vector2(3.0, t)), stone, true)
	draw_rect(Rect2(o + Vector2(t - 3.0, 0), Vector2(1.0, t)), stone_lit, true)
	draw_rect(Rect2(o + Vector2(t - 1.0, 0), Vector2(1.0, t)), stone_dark, true)

	## Lintel.
	draw_rect(Rect2(o, Vector2(t, 4.0)), stone, true)
	draw_rect(Rect2(o, Vector2(t, 1.0)), stone_lit, true)
	draw_rect(Rect2(o + Vector2(0, 3), Vector2(t, 1.0)), stone_dark, true)
	## Rosette carved into the lintel: an eight-petal mark, Inanna's sign.
	draw_rect(Rect2(o + Vector2(7, 1), Vector2(2.0, 2.0)), stone_dark, true)
	draw_rect(Rect2(o + Vector2(5, 1.5), Vector2(1.0, 1.0)), stone_dark, true)
	draw_rect(Rect2(o + Vector2(10, 1.5), Vector2(1.0, 1.0)), stone_dark, true)


## Upturned reed stakes bound at the base. Drawn only in the lower half of
## the tile, which is also where the damage is: the picture and the rule
## agree, which is the whole point after the first play test.
func _draw_stakes(o: Vector2, t: float, c: Color) -> void:
	for i: int in 4:
		var x: float = float(i) * 4.0 + 2.0
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(x - 2.0, t), o + Vector2(x + 2.0, t),
			o + Vector2(x, t - 9.0)]), c)
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(x - 2.0, t), o + Vector2(x, t),
			o + Vector2(x, t - 9.0)]), c.lightened(0.22))
	var bind: Color = Palette.BRONZE
	draw_rect(Rect2(o + Vector2(0, t - 3.0), Vector2(t, 2.0)), bind, true)
	draw_rect(Rect2(o + Vector2(0, t - 3.0), Vector2(t, 1.0)),
			bind.lightened(0.25), true)


func _draw_water(o: Vector2, t: float, c: Color, tx: int, ty: int) -> void:
	var wc: Color = c
	wc.a = 0.72
	draw_rect(Rect2(o, Vector2(t, t)), wc, true)
	if world.map.at(tx, ty - 1) != TileDB.T.WATER:
		var phase: int = (_anim_tick / 6 + tx * 3) % 8
		draw_rect(Rect2(o, Vector2(t, 1.0)), c.lightened(0.45), true)
		draw_rect(Rect2(o + Vector2(float(phase), 2.0), Vector2(5.0, 1.0)),
				c.lightened(0.28), true)
	var deep: int = (_anim_tick / 10 + ty * 2) % 10
	draw_rect(Rect2(o + Vector2(float(deep), 9.0), Vector2(4.0, 1.0)),
			c.lightened(0.14), true)


## A fluted column with a capital and a base, inset from the tile edges so it
## reads as standing in front of the wall rather than being part of it.
func _draw_pillar(o: Vector2, t: float, c: Color) -> void:
	draw_rect(Rect2(o + Vector2(3, 0), Vector2(t - 6.0, t)), c, true)
	for i: int in 3:
		draw_rect(Rect2(o + Vector2(4.0 + float(i) * 3.0, 0), Vector2(1.0, t)),
				c.darkened(0.22), true)
	draw_rect(Rect2(o + Vector2(3, 0), Vector2(1.0, t)), c.lightened(0.25), true)
	draw_rect(Rect2(o + Vector2(t - 4.0, 0), Vector2(1.0, t)), c.darkened(0.35), true)
	for y: float in [0.0, t - 3.0]:
		draw_rect(Rect2(o + Vector2(1, y), Vector2(t - 2.0, 3.0)),
				c.lightened(0.12), true)
		draw_rect(Rect2(o + Vector2(1, y), Vector2(t - 2.0, 1.0)),
				c.lightened(0.34), true)
		draw_rect(Rect2(o + Vector2(1, y + 2.0), Vector2(t - 2.0, 1.0)),
				c.darkened(0.35), true)


func _draw_plate(o: Vector2, t: float, c: Color, at: Vector2i) -> void:
	var y: float = t - (2.0 if _plate_pressed(at) else 5.0)
	draw_rect(Rect2(o + Vector2(1, y), Vector2(t - 2.0, t - y)), c, true)
	draw_rect(Rect2(o + Vector2(1, y), Vector2(t - 2.0, 1.0)), c.lightened(0.34), true)
	draw_rect(Rect2(o + Vector2(1, t - 1.0), Vector2(t - 2.0, 1.0)), c.darkened(0.4), true)
	## Pivot blocks at each end, so it reads as a mechanism and not a step.
	draw_rect(Rect2(o + Vector2(0, t - 2.0), Vector2(2.0, 2.0)), Palette.BRONZE, true)
	draw_rect(Rect2(o + Vector2(t - 2.0, t - 2.0), Vector2(2.0, 2.0)),
			Palette.BRONZE, true)


## Masonry plus a carved cylinder-seal band. The band is the whole point: it
## is the only thing telling the player this block can be moved.
func _draw_block(o: Vector2, t: float, c: Color) -> void:
	draw_rect(Rect2(o + Vector2(1, 1), Vector2(t - 2.0, t - 2.0)), c, true)
	draw_rect(Rect2(o + Vector2(1, 1), Vector2(t - 2.0, 1.0)), c.lightened(0.34), true)
	draw_rect(Rect2(o + Vector2(1, t - 2.0), Vector2(t - 2.0, 1.0)),
			c.darkened(0.42), true)
	draw_rect(Rect2(o + Vector2(1, 1), Vector2(1.0, t - 2.0)), c.lightened(0.14), true)
	draw_rect(Rect2(o + Vector2(t - 2.0, 1), Vector2(1.0, t - 2.0)),
			c.darkened(0.26), true)

	draw_rect(Rect2(o + Vector2(2, 5), Vector2(t - 4.0, 6.0)), c.darkened(0.30), true)
	draw_rect(Rect2(o + Vector2(2, 5), Vector2(t - 4.0, 1.0)), c.darkened(0.5), true)
	## Cuneiform-ish wedges rolled into the band.
	var mark: Color = c.lightened(0.30)
	for i: int in 3:
		var x: float = 4.0 + float(i) * 3.0
		draw_rect(Rect2(o + Vector2(x, 6), Vector2(2.0, 1.0)), mark, true)
		draw_rect(Rect2(o + Vector2(x, 8), Vector2(1.0, 2.0)), mark, true)


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
		var bob: float = roundf(sin(float(_anim_tick) * 0.06 + float(p.x)) * 1.5)
		var ctr: Vector2 = o + Vector2(8.0, 9.0 + bob)

		## A faint glow, so treasure separates from the wall behind it without
		## flashing - which would be both ugly and an accessibility problem.
		_draw_glow(ctr, 9.0, c, 1.0)

		match tier:
			"legendary":
				_draw_star(ctr, 6.0, 2.6, 8, c)
				_draw_star(ctr, 3.0, 1.2, 8, c.lightened(0.5))
			"valuable":
				## A cylinder seal: stone drum, shell caps, carved band.
				draw_rect(Rect2(ctr - Vector2(3.0, 4.5), Vector2(6.0, 9.0)), c, true)
				draw_rect(Rect2(ctr - Vector2(3.0, 4.5), Vector2(6.0, 1.0)),
						Palette.SHELL, true)
				draw_rect(Rect2(ctr + Vector2(-3.0, 3.5), Vector2(6.0, 1.0)),
						Palette.SHELL, true)
				draw_rect(Rect2(ctr - Vector2(3.0, 1.5), Vector2(6.0, 3.0)),
						c.darkened(0.35), true)
				draw_rect(Rect2(ctr - Vector2(3.0, 4.5), Vector2(1.0, 9.0)),
						c.lightened(0.3), true)
			_:
				## A clay tablet with two lines of wedges.
				draw_rect(Rect2(ctr - Vector2(4.0, 3.5), Vector2(8.0, 7.0)), c, true)
				draw_rect(Rect2(ctr - Vector2(4.0, 3.5), Vector2(8.0, 1.0)),
						c.lightened(0.3), true)
				draw_rect(Rect2(ctr - Vector2(4.0, 3.0), Vector2(1.0, 6.5)),
						c.lightened(0.18), true)
				for row: int in 2:
					var y: float = -1.0 + float(row) * 2.5
					for i: int in 3:
						draw_rect(Rect2(ctr + Vector2(-2.5 + float(i) * 2.0, y),
								Vector2(1.0, 1.0)), Palette.BITUMEN, true)


func _draw_objects() -> void:
	for o_def: Dictionary in world.level.required_objects:
		if world.held.has(str(o_def["id"])):
			continue
		var p: Vector2i = o_def["pos"]
		var o: Vector2 = Vector2(float(p.x * Grid.TILE), float(p.y * Grid.TILE))
		var bob: float = roundf(sin(float(_anim_tick) * 0.055 + float(p.y)) * 1.5)
		var ctr: Vector2 = o + Vector2(8.0, 9.0 + bob)
		var c: Color = Palette.GOLD

		## Required objects glow harder than treasure, and breathe. Missing one
		## is the difference between finishing the level and not.
		_draw_glow(ctr, 10.0, c, 1.5 + 0.45 * sin(float(_anim_tick) * 0.09))

		match str(o_def.get("kind", "key")):
			"seal":
				draw_rect(Rect2(ctr - Vector2(2.5, 5.0), Vector2(5.0, 10.0)), c, true)
				draw_rect(Rect2(ctr - Vector2(2.5, 5.0), Vector2(1.0, 10.0)),
						c.lightened(0.3), true)
				draw_rect(Rect2(ctr - Vector2(3.5, -0.5), Vector2(7.0, 2.0)),
						Palette.LAPIS_LIGHT, true)
			"ritual":
				_draw_star(ctr, 5.5, 2.2, 6, Palette.LAPIS_LIGHT)
				_draw_star(ctr, 2.5, 1.0, 6, Palette.SHELL)
			_:
				## A bronze key: ring bow, shaft, two teeth.
				draw_arc(ctr - Vector2(0, 4.0), 3.0, 0.0, TAU, 12, c, 1.6)
				draw_rect(Rect2(ctr - Vector2(1.0, 1.0), Vector2(2.0, 7.0)), c, true)
				draw_rect(Rect2(ctr - Vector2(1.0, 1.0), Vector2(1.0, 7.0)),
						c.lightened(0.3), true)
				draw_rect(Rect2(ctr + Vector2(1.0, 2.0), Vector2(3.0, 1.5)), c, true)
				draw_rect(Rect2(ctr + Vector2(1.0, 4.5), Vector2(2.0, 1.5)), c, true)


func _draw_checkpoints() -> void:
	for c_def: Dictionary in world.level.checkpoints:
		var p: Vector2i = c_def["pos"]
		var o: Vector2 = Vector2(float(p.x * Grid.TILE), float(p.y * Grid.TILE))
		var lit: bool = world.checkpoints_taken.has(str(c_def["id"]))

		if lit:
			## Pool of warm light on the surrounding stonework.
			var pool: Color = Palette.GOLD
			pool.a = 0.10 + 0.03 * sin(float(_anim_tick) * 0.11)
			draw_circle(o + Vector2(8, 10), 16.0, pool)
			pool.a += 0.06
			draw_circle(o + Vector2(8, 10), 9.0, pool)

		var bronze: Color = Palette.BRONZE
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(4, 16), o + Vector2(12, 16),
			o + Vector2(10.5, 11), o + Vector2(5.5, 11)]), bronze)
		draw_rect(Rect2(o + Vector2(5, 10), Vector2(6.0, 1.5)),
				bronze.lightened(0.3), true)

		if lit:
			## Three-tone flame, stepped from the animation counter.
			var f: float = float((_anim_tick / 6) % 3)
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(5.5, 11), o + Vector2(10.5, 11),
				o + Vector2(8.0, 5.0 - f)]), Palette.GOLD_DEEP)
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(6.5, 11), o + Vector2(9.5, 11),
				o + Vector2(8.0, 7.0 - f)]), Palette.GOLD)
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(7.2, 11), o + Vector2(8.8, 11),
				o + Vector2(8.0, 9.0 - f * 0.5)]), Palette.SHELL)
		else:
			## Cold ash, so an unclaimed brazier still reads as something to
			## walk into rather than as scenery.
			draw_rect(Rect2(o + Vector2(6, 10), Vector2(4.0, 1.0)),
					bronze.darkened(0.45), true)


func _draw_enemies() -> void:
	for i: int in world.enemies.size():
		var e: EnemySim = world.enemies[i]
		if not e.alive:
			continue
		var prev: Vector2i = _prev_enemies[i] if i < _prev_enemies.size() else e.pos
		var p: Vector2 = _lerp_pos(prev, e.pos)
		_draw_ground_shadow(p, 6.0)
		match e.kind:
			EnemySim.Kind.SPIRIT:
				_draw_spirit(p)
			EnemySim.Kind.STATUE:
				_draw_statue(p, e)
			_:
				_draw_guardian(p, e)


## A temple guardian: broad, low, helmeted, and clearly not human. Its eyes
## face the way it is about to walk, so the player can read the turn coming.
func _draw_guardian(p: Vector2, e: EnemySim) -> void:
	var body: Color = Palette.BRONZE
	var trim: Color = Palette.GOLD_DEEP
	var f: float = float(e.dir)

	draw_rect(Rect2(p + Vector2(-5, -13), Vector2(10.0, 13.0)), body, true)
	draw_rect(Rect2(p + Vector2(-5, -13), Vector2(1.0, 13.0)),
			body.lightened(0.25), true)
	draw_rect(Rect2(p + Vector2(4, -13), Vector2(1.0, 13.0)), body.darkened(0.3), true)
	## Scale-plate skirt, stepped so the walk reads even at this size.
	var step: float = float((world.tick_count / 8) % 2)
	for row: int in 2:
		for i: int in 3:
			draw_rect(Rect2(p + Vector2(-4.0 + float(i) * 3.0 + step,
					-7.0 + float(row) * 3.0), Vector2(2.0, 2.0)),
					body.darkened(0.22), true)
	draw_rect(Rect2(p + Vector2(-6, -16), Vector2(12.0, 3.0)), trim, true)
	draw_rect(Rect2(p + Vector2(-6, -16), Vector2(12.0, 1.0)),
			trim.lightened(0.3), true)
	draw_rect(Rect2(p + Vector2(-1.0 + f * 4.0, -16), Vector2(2.0, 3.0)),
			trim.darkened(0.3), true)
	draw_rect(Rect2(p + Vector2(f * 2.0 - 2.5, -11.5), Vector2(2.0, 2.0)),
			Palette.CARNELIAN, true)
	draw_rect(Rect2(p + Vector2(f * 2.0 + 0.5, -11.5), Vector2(2.0, 2.0)),
			Palette.CARNELIAN, true)


func _draw_statue(p: Vector2, e: EnemySim) -> void:
	var body: Color = Palette.SHELL if e.awake else Palette.UI_DIM
	draw_rect(Rect2(p + Vector2(-5, -14), Vector2(10.0, 14.0)), body, true)
	draw_rect(Rect2(p + Vector2(-5, -14), Vector2(1.0, 14.0)),
			body.lightened(0.2), true)
	draw_rect(Rect2(p + Vector2(4, -14), Vector2(1.0, 14.0)), body.darkened(0.35), true)
	## Folded arms, carved in relief.
	draw_rect(Rect2(p + Vector2(-4, -8), Vector2(8.0, 2.0)), body.darkened(0.25), true)
	draw_rect(Rect2(p + Vector2(-6, -17), Vector2(12.0, 3.0)), Palette.GOLD_DEEP, true)
	draw_rect(Rect2(p + Vector2(-6, -17), Vector2(12.0, 1.0)),
			Palette.GOLD_DEEP.lightened(0.3), true)
	if e.awake:
		draw_rect(Rect2(p + Vector2(-3, -12.5), Vector2(6.0, 1.5)),
				Palette.CARNELIAN, true)


func _draw_spirit(p: Vector2) -> void:
	var glow: Color = Palette.LAPIS_LIGHT
	var pulse: float = 0.16 + 0.06 * sin(float(_anim_tick) * 0.10)
	glow.a = pulse
	draw_circle(p + Vector2(0, -8), 10.0, glow)
	glow.a = pulse + 0.30
	draw_circle(p + Vector2(0, -8), 6.0, glow)
	draw_circle(p + Vector2(0, -8), 3.0, Palette.SHELL)
	for i: int in 3:
		var w: float = float((_anim_tick / 5 + i * 3) % 9)
		var a: Color = Palette.LAPIS_LIGHT
		a.a = 0.35 - float(i) * 0.08
		draw_rect(Rect2(p + Vector2(-1.0, -2.0 + w * 0.5), Vector2(2.0, 2.0)), a, true)


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

	var skin: Color = Palette.SKIN
	var skin_lit: Color = Palette.SKIN_LIT
	var skin_dark: Color = Palette.SKIN_DARK
	var hair: Color = Palette.HAIR
	var robe: Color = Palette.CARNELIAN
	var robe_lit: Color = Palette.CARNELIAN_LIT
	var robe_dark: Color = robe.darkened(0.30)
	var trim: Color = Palette.GOLD
	var f: float = float(pl.facing)

	## Gate progression (spec section 24): Inanna surrenders one possession at
	## each gate, and the silhouette gets plainer as she descends.
	var regalia: int = maxi(0, 8 - world.level.gate)

	var airborne: bool = pl.state in [PlayerSim.S.JUMPING, PlayerSim.S.FALLING]
	var climbing: bool = pl.state in [PlayerSim.S.CLIMBING, PlayerSim.S.DESCENDING]
	var moving: bool = pl.state in [PlayerSim.S.WALKING, PlayerSim.S.RUNNING]

	if not airborne and not climbing:
		_draw_ground_shadow(p, 5.0)

	## Four-phase stride, plus a one-pixel bob that sells the weight of it.
	var phase: int = (world.tick_count / 6) % 4
	var stride: float = 0.0
	var bob: float = 0.0
	if moving:
		stride = [0.0, 1.0, 0.0, -1.0][phase]
		bob = -1.0 if (phase == 1 or phase == 3) else 0.0
	elif climbing:
		stride = 1.0 if (world.tick_count / 8) % 2 == 0 else -1.0

	var lean: float = 0.0
	if moving:
		lean = f
	elif pl.state == PlayerSim.S.PUSHING:
		lean = f * 2.0
	elif airborne:
		lean = f * 0.5

	var b: Vector2 = (p + Vector2(0, bob)).round()

	## She is about 19 pixels tall, so every pixel is a decision. The rule
	## that makes her readable at this size: skin appears ONLY at the face,
	## the arms and the shins. Everything else is robe. An earlier draft gave
	## her a bare torso as well and the head and body merged into one pale
	## blob with a crown on top.

	# --- legs -------------------------------------------------------------
	if climbing:
		draw_rect(Rect2(b + Vector2(-3.5, -4.0), Vector2(2.0, 4.0)), skin_dark, true)
		draw_rect(Rect2(b + Vector2(1.5, -4.0), Vector2(2.0, 4.0)), skin, true)
	elif airborne:
		## Trailing leg tucked, leading leg reaching.
		draw_rect(Rect2(b + Vector2(-2.5 + f, -3.0), Vector2(2.0, 3.0)), skin_dark, true)
		draw_rect(Rect2(b + Vector2(0.5 + f, -4.0), Vector2(2.0, 4.0)), skin, true)
	else:
		draw_rect(Rect2(b + Vector2(-2.5 - stride * 0.5, -3.0), Vector2(2.0, 3.0)),
				skin_dark, true)
		draw_rect(Rect2(b + Vector2(0.5 + stride * 0.5, -3.0), Vector2(2.0, 3.0)),
				skin, true)

	# --- skirt ------------------------------------------------------------
	if regalia >= 3:
		## A tiered flounced skirt: the Sumerian kaunakes. Three tiers, each
		## with a lit upper edge, so it reads as cloth rather than as a cone.
		for tier: int in 3:
			var ty_off: float = -5.0 - float(tier) * 2.0
			var half: float = 4.5 - float(tier) * 0.6
			var sway: float = lean * 0.3 * float(tier)
			draw_rect(Rect2(b + Vector2(-half + sway, ty_off),
					Vector2(half * 2.0, 2.5)), robe, true)
			draw_rect(Rect2(b + Vector2(-half + sway, ty_off),
					Vector2(half * 2.0, 1.0)), robe_lit, true)
			draw_rect(Rect2(b + Vector2(half - 1.0 + sway, ty_off),
					Vector2(1.0, 2.5)), robe_dark, true)
	else:
		## After Gate V the robe is gone: plain cloth, plainer silhouette.
		draw_rect(Rect2(b + Vector2(-3.0, -9.0), Vector2(6.0, 6.0)), skin, true)
		draw_rect(Rect2(b + Vector2(-3.0, -9.0), Vector2(1.0, 6.0)), skin_lit, true)

	# --- torso ------------------------------------------------------------
	var tx_off: float = lean
	if regalia >= 3:
		draw_rect(Rect2(b + Vector2(-2.5 + tx_off, -14.0), Vector2(5.0, 6.0)),
				robe, true)
		draw_rect(Rect2(b + Vector2(-2.5 + tx_off, -14.0), Vector2(1.0, 6.0)),
				robe_lit, true)
		draw_rect(Rect2(b + Vector2(1.5 + tx_off, -14.0), Vector2(1.0, 6.0)),
				robe_dark, true)
	else:
		draw_rect(Rect2(b + Vector2(-2.5 + tx_off, -14.0), Vector2(5.0, 6.0)),
				skin, true)
		draw_rect(Rect2(b + Vector2(-2.5 + tx_off, -14.0), Vector2(1.0, 6.0)),
				skin_lit, true)

	## Breastplate, lost at Gate IV and beyond.
	if regalia >= 4:
		draw_rect(Rect2(b + Vector2(-3.0 + tx_off, -13.0), Vector2(6.0, 2.0)),
				trim, true)
		draw_rect(Rect2(b + Vector2(-3.0 + tx_off, -13.0), Vector2(6.0, 1.0)),
				trim.lightened(0.35), true)

	# --- arm --------------------------------------------------------------
	## Sleeve in robe colour with a skin hand, so the arm does not read as a
	## second pale limb competing with the face.
	var arm_y: float = -13.0 + stride * 0.5
	if pl.state == PlayerSim.S.ATTACKING:
		arm_y = -12.0
	elif climbing:
		arm_y = -15.0
	var arm_x: float = -0.5 + f * 2.5 + tx_off
	if regalia >= 3:
		draw_rect(Rect2(b + Vector2(arm_x, arm_y), Vector2(2.0, 3.5)), robe_dark, true)
		draw_rect(Rect2(b + Vector2(arm_x, arm_y + 3.5), Vector2(2.0, 2.0)),
				skin_dark, true)
	else:
		draw_rect(Rect2(b + Vector2(arm_x, arm_y), Vector2(2.0, 5.5)), skin_dark, true)

	# --- head -------------------------------------------------------------
	## A 4-wide face framed by hair on both sides, which is what keeps it from
	## becoming a blank rectangle.
	var hx: float = lean
	draw_rect(Rect2(b + Vector2(-2.0 + hx, -19.0), Vector2(4.0, 5.0)), skin, true)
	draw_rect(Rect2(b + Vector2(-2.0 + hx, -19.0), Vector2(1.0, 5.0)), skin_lit, true)
	## Neck, one pixel narrower than the head, separating it from the shoulders.
	draw_rect(Rect2(b + Vector2(-1.0 + hx, -14.5), Vector2(2.0, 1.0)), skin_dark, true)

	## Hair: a heavy mass over the crown and down both sides, the way it is
	## shown on the reliefs. The trailing side falls longer.
	draw_rect(Rect2(b + Vector2(-3.0 + hx, -20.0), Vector2(6.0, 2.0)), hair, true)
	## A sheen along the top of the hair, so her head keeps a silhouette
	## even against the near-black walls of Kur.
	draw_rect(Rect2(b + Vector2(-3.0 + hx, -20.0), Vector2(6.0, 1.0)),
			Palette.HAIR_LIT, true)
	draw_rect(Rect2(b + Vector2(-3.0 + hx, -19.0), Vector2(1.0, 4.0)), hair, true)
	draw_rect(Rect2(b + Vector2(2.0 + hx, -19.0), Vector2(1.0, 4.0)), hair, true)
	var back_x: float = 2.0 if f < 0.0 else -3.0
	draw_rect(Rect2(b + Vector2(back_x + hx, -19.0), Vector2(1.0, 7.0)), hair, true)
	## Brow line, which gives the face structure without needing features.
	draw_rect(Rect2(b + Vector2(-2.0 + hx, -18.0), Vector2(4.0, 1.0)),
			hair.lightened(0.10), true)
	## Eye, facing the way she is.
	draw_rect(Rect2(b + Vector2(-0.5 + hx + f * 0.5, -17.0), Vector2(1.0, 1.0)),
			hair, true)

	## Lapis necklace, lost at Gate III and beyond.
	if regalia >= 5:
		draw_rect(Rect2(b + Vector2(-2.5 + hx, -14.5), Vector2(5.0, 1.0)),
				Palette.LAPIS_LIGHT, true)

	## The horned crown: the mark of a Mesopotamian deity, and her strongest
	## silhouette feature - which is exactly why losing it at Gate I lands.
	if regalia >= 6:
		draw_rect(Rect2(b + Vector2(-3.0 + hx, -22.0), Vector2(6.0, 2.0)), trim, true)
		draw_rect(Rect2(b + Vector2(-3.0 + hx, -22.0), Vector2(6.0, 1.0)),
				trim.lightened(0.35), true)
		for side: int in 2:
			var sx: float = -4.0 if side == 0 else 3.0
			draw_rect(Rect2(b + Vector2(sx + hx, -23.0), Vector2(1.0, 1.0)), trim, true)
			draw_rect(Rect2(b + Vector2(sx + hx + (1.0 if side == 0 else 0.0), -24.0),
					Vector2(1.0, 1.0)), trim, true)

	## The dagger, raised only on the swing.
	if pl.state == PlayerSim.S.ATTACKING:
		var reach: float = 5.0 + 5.0 * clampf(float(pl.state_ticks) / 4.0, 0.0, 1.0)
		var x0: float = f * 2.0 if f > 0.0 else f * 2.0 - reach
		draw_rect(Rect2(b + Vector2(x0, -12.0), Vector2(reach, 2.0)), trim, true)
		draw_rect(Rect2(b + Vector2(x0, -12.0), Vector2(reach, 1.0)),
				trim.lightened(0.4), true)


## A soft glow behind a pickup: three concentric circles fading outward.
##
## A single low-alpha circle was tried first and it read as a dirty brown
## coin sitting behind the item, because a hard-edged disc of muddy colour is
## an object, not a light. Stacking a falloff and warming the colour is what
## makes it read as glow.
func _draw_glow(ctr: Vector2, radius: float, col: Color, strength: float) -> void:
	var g: Color = col.lightened(0.30)
	for i: int in 3:
		g.a = (0.035 + float(i) * 0.030) * strength
		draw_circle(ctr, radius - float(i) * 2.5, g)


## Contact shadow. Nothing sells "standing on the floor" like this.
func _draw_ground_shadow(p: Vector2, half_w: float) -> void:
	var s: Color = Color(0, 0, 0, 0.26)
	draw_rect(Rect2(p + Vector2(-half_w, -1.0), Vector2(half_w * 2.0, 1.0)), s, true)
	s.a = 0.14
	draw_rect(Rect2(p + Vector2(-half_w - 1.0, -2.0),
			Vector2(half_w * 2.0 + 2.0, 1.0)), s, true)


# --- post -----------------------------------------------------------------

## A vignette, so the eye is drawn to the middle of the room and the screen
## edge does not end on a hard line. Cheap: eight nested frames.
func _draw_vignette() -> void:
	var w: float = float(world.map.width * Grid.TILE)
	var h: float = float(world.map.height * Grid.TILE)
	var steps: int = 8
	for i: int in steps:
		var a: float = 0.055 * (1.0 - float(i) / float(steps))
		var inset: float = float(i)
		draw_rect(Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0),
				Color(0.0, 0.0, 0.0, a), false, 1.0)


## Whole-pixel positions. The project renders at 256x192 and upscales with
## nearest-neighbour filtering, so a sprite drawn at a fractional coordinate
## crawls between pixels instead of moving cleanly.
func _lerp_pos(prev: Vector2i, cur: Vector2i) -> Vector2:
	var a: Vector2 = Vector2(Grid.to_px(prev.x), Grid.to_px(prev.y))
	var b: Vector2 = Vector2(Grid.to_px(cur.x), Grid.to_px(cur.y))
	return a.lerp(b, clampf(alpha, 0.0, 1.0)).round()


func _draw_star(c: Vector2, outer: float, inner: float, points: int,
		col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in points * 2:
		var r: float = outer if i % 2 == 0 else inner
		var a: float = float(i) * PI / float(points) - PI * 0.5
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
