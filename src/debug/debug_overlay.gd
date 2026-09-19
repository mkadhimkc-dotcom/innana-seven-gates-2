class_name DebugOverlay
extends Node2D

## Visual debugging (spec section 22).
##
## The requirement is that a developer can look at the screen and immediately
## see why a puzzle or a collision is behaving wrongly. Modes are cycled with
## F11 rather than shown all at once, because six overlays on top of each
## other tell you nothing.

enum Mode { OFF, COLLISION, ENTITIES, REACHABILITY, CRITICAL_PATH, ALL }

const MODE_NAMES: Array[String] = [
	"OFF", "COLLISION", "ENTITIES", "REACHABILITY", "CRITICAL PATH", "ALL",
]

var mode: int = Mode.OFF
var world: WorldSim = null

var _font: Font = null
var _reach_cache: Dictionary = {}
var _reach_stamp: int = -1


func _ready() -> void:
	z_index = 100
	_font = ThemeDB.fallback_font
	set_process(true)


func bind(w: WorldSim) -> void:
	world = w
	_reach_stamp = -1


func cycle_mode() -> void:
	mode = (mode + 1) % MODE_NAMES.size()
	_reach_stamp = -1


func _process(_delta: float) -> void:
	if mode != Mode.OFF:
		queue_redraw()


func _draw() -> void:
	if world == null or mode == Mode.OFF:
		return
	var all: bool = mode == Mode.ALL
	if all or mode == Mode.COLLISION:
		_draw_grid()
		_draw_collision()
	if all or mode == Mode.ENTITIES:
		_draw_entities()
	if all or mode == Mode.REACHABILITY:
		_draw_reachability()
	if all or mode == Mode.CRITICAL_PATH:
		_draw_critical_path()
	_draw_readout()


func _draw_grid() -> void:
	var w: float = float(world.map.width * Grid.TILE)
	var h: float = float(world.map.height * Grid.TILE)
	for x: int in world.map.width + 1:
		draw_line(Vector2(float(x * Grid.TILE), 0), Vector2(float(x * Grid.TILE), h),
				Palette.DBG_GRID, 1.0)
	for y: int in world.map.height + 1:
		draw_line(Vector2(0, float(y * Grid.TILE)), Vector2(w, float(y * Grid.TILE)),
				Palette.DBG_GRID, 1.0)


func _draw_collision() -> void:
	for ty: int in world.map.height:
		for tx: int in world.map.width:
			var id_value: int = world.map.at(tx, ty)
			var r: Rect2 = Rect2(float(tx * Grid.TILE), float(ty * Grid.TILE),
					float(Grid.TILE), float(Grid.TILE))
			if TileDB.has(id_value, TileDB.F_HAZARD):
				draw_rect(r, Palette.DBG_HAZARD, false, 1.0)
			elif TileDB.has(id_value, TileDB.F_SOLID):
				draw_rect(r, Palette.DBG_COLLISION, false, 1.0)
			elif TileDB.has(id_value, TileDB.F_CLIMB):
				draw_line(r.position + Vector2(r.size.x * 0.5, 0),
						r.position + Vector2(r.size.x * 0.5, r.size.y),
						Palette.DBG_COLLISION, 1.0)
			elif TileDB.has(id_value, TileDB.F_TRIGGER):
				draw_rect(r, Palette.DBG_TRIGGER, false, 1.0)

	## Player hitbox, drawn from the same numbers collision uses.
	var pl: PlayerSim = world.player
	var box: Rect2 = Rect2(
			Grid.to_px(world.map.body_left(pl.pos.x)),
			Grid.to_px(world.map.body_top(pl.pos.y)),
			float(Grid.BODY_W), float(Grid.BODY_H))
	draw_rect(box, Palette.DBG_PLAYER, false, 1.0)
	## Anchor point.
	draw_circle(Vector2(Grid.to_px(pl.pos.x), Grid.to_px(pl.pos.y)), 1.2,
			Palette.DBG_PLAYER)

	for e: EnemySim in world.enemies:
		if not e.alive:
			continue
		var eb: Rect2 = Rect2(
				Grid.to_px(e.pos.x - EnemySim.BODY_W_SUB / 2),
				Grid.to_px(e.pos.y - EnemySim.BODY_H_SUB),
				Grid.to_px(EnemySim.BODY_W_SUB), Grid.to_px(EnemySim.BODY_H_SUB))
		draw_rect(eb, Palette.DBG_ENEMY, false, 1.0)
		## Patrol direction.
		var c: Vector2 = eb.position + eb.size * 0.5
		draw_line(c, c + Vector2(float(e.dir) * 8.0, 0), Palette.DBG_ENEMY, 1.0)


func _draw_entities() -> void:
	_label_all(world.level.treasures, Palette.GOLD, "T")
	_label_all(world.level.required_objects, Palette.LAPIS_LIGHT, "K")
	_label_all(world.level.doors, Palette.CARNELIAN, "D")
	_label_all(world.level.switches, Palette.DBG_TRIGGER, "S")
	_label_all(world.level.checkpoints, Palette.SHELL, "C")
	_mark(world.level.player_start, Palette.DBG_PLAYER, "start")
	_mark(world.level.exit_tile, Palette.GOLD, "exit")


func _label_all(rows: Array[Dictionary], col: Color, prefix: String) -> void:
	for r: Dictionary in rows:
		var p: Vector2i = r["pos"]
		var o: Vector2 = Vector2(float(p.x * Grid.TILE), float(p.y * Grid.TILE))
		draw_rect(Rect2(o, Vector2(float(Grid.TILE), float(Grid.TILE))), col, false, 1.0)
		draw_string(_font, o + Vector2(1, 7), "%s:%s" % [prefix, str(r["id"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 5, col)


func _mark(t: Vector2i, col: Color, text: String) -> void:
	var o: Vector2 = Vector2(float(t.x * Grid.TILE), float(t.y * Grid.TILE))
	draw_rect(Rect2(o + Vector2(2, 2), Vector2(12, 12)), col, false, 1.0)
	draw_string(_font, o + Vector2(1, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, col)


## Everything the player can currently reach, from where she is standing.
## Anything the level needs that is NOT shaded is a bug in the level.
func _draw_reachability() -> void:
	if _reach_stamp != world.tick_count / 15:
		_reach_stamp = world.tick_count / 15
		_reach_cache = Solver.reachable_tiles(world.map, world.player.tile())
	for t: Variant in _reach_cache:
		var p: Vector2i = t
		draw_rect(Rect2(float(p.x * Grid.TILE), float(p.y * Grid.TILE),
				float(Grid.TILE), float(Grid.TILE)), Palette.DBG_REACH, true)


func _draw_critical_path() -> void:
	var prev: Vector2i = world.level.player_start
	var i: int = 0
	for step: Dictionary in world.level.critical_path:
		if not step.has("pos"):
			continue
		var p: Vector2i = LevelLoader._to_vec(step["pos"], Vector2i.ZERO)
		var a: Vector2 = Vector2(float(prev.x * Grid.TILE) + 8.0,
				float(prev.y * Grid.TILE) + 8.0)
		var b: Vector2 = Vector2(float(p.x * Grid.TILE) + 8.0,
				float(p.y * Grid.TILE) + 8.0)
		draw_line(a, b, Palette.DBG_PATH, 1.5)
		draw_circle(b, 2.5, Palette.DBG_PATH)
		draw_string(_font, b + Vector2(2, -2), "%d %s" % [i + 1,
				str(step.get("label", ""))], HORIZONTAL_ALIGNMENT_LEFT, -1, 5,
				Palette.DBG_PATH)
		prev = p
		i += 1


func _draw_readout() -> void:
	var pl: PlayerSim = world.player
	var lines: Array[String] = [
		"%s  tick %d" % [MODE_NAMES[mode], world.tick_count],
		"%s  t%s  %s" % [pl.state_name(), str(pl.tile()), pl.last_transition],
		"anchor %d,%d  vy %d" % [pl.pos.x, pl.pos.y, pl.vel_y],
		"held %d  gems %d/%d  audit %s" % [world.held.size(),
				world.collected.size(), world.level.treasures.size(),
				"ok" if world.last_audit_ok else "FAIL"],
	]
	var y: float = float(Grid.VIEW_H) - 4.0 - float(lines.size()) * 6.0
	draw_rect(Rect2(0, y - 4.0, 130.0, float(lines.size()) * 6.0 + 6.0),
			Palette.UI_PANEL, true)
	for line: String in lines:
		draw_string(_font, Vector2(2, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 5,
				Palette.UI_TEXT)
		y += 6.0
