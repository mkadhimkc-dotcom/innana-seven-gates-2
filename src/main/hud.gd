class_name Hud
extends Control

## In-game HUD (spec section 34).
##
## Minimal on purpose: health, what she is carrying, treasure found, and a
## single line of text that appears only when something has just changed. No
## permanent bars, no counters that never move, nothing the player has already
## learned to ignore.

const ANNOUNCE_TICKS: float = 2.2

var world: WorldSim = null

var _announcement: String = ""
var _announce_left: float = 0.0
var _treasure_flash: float = 0.0
var _object_flash: float = 0.0
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	set_process(true)


func bind(w: WorldSim) -> void:
	world = w
	_announcement = ""
	_announce_left = 0.0


func announce(text: String) -> void:
	_announcement = text
	_announce_left = ANNOUNCE_TICKS


func flash_treasure() -> void:
	_treasure_flash = 0.5


func flash_object(_kind: String) -> void:
	_object_flash = 0.7


func _process(delta: float) -> void:
	_announce_left = maxf(0.0, _announce_left - delta)
	_treasure_flash = maxf(0.0, _treasure_flash - delta)
	_object_flash = maxf(0.0, _object_flash - delta)
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var s: Vector2 = get_viewport_rect().size
	var k: float = minf(s.x / float(Grid.VIEW_W), s.y / float(Grid.VIEW_H))
	var m: float = 6.0 * k

	_draw_health(Vector2(m, m), k)
	_draw_carried(Vector2(m, m + 9.0 * k), k)
	_draw_treasure(Vector2(s.x - m, m), k)

	if _announce_left > 0.0:
		var alpha: float = clampf(_announce_left / 0.6, 0.0, 1.0)
		var col: Color = Palette.UI_TEXT
		col.a = alpha
		var size: int = int(8.0 * k)
		var w: float = _font.get_string_size(_announcement,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(_font, Vector2((s.x - w) * 0.5, s.y * 0.30), _announcement,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_health(o: Vector2, k: float) -> void:
	## Health reads as lamps: lit while she holds them, dark when spent.
	for i: int in PlayerSim.MAX_HEALTH:
		var c: Vector2 = o + Vector2(float(i) * 8.0 * k + 3.0 * k, 3.0 * k)
		var lit: bool = i < world.player.health
		draw_circle(c, 2.6 * k, Palette.GOLD if lit else Palette.UI_PANEL)
		draw_arc(c, 2.6 * k, 0.0, TAU, 12, Palette.UI_DIM, 1.0 * k)


func _draw_carried(o: Vector2, k: float) -> void:
	var i: int = 0
	for obj: Dictionary in world.level.required_objects:
		if not world.held.has(str(obj["id"])):
			continue
		var c: Vector2 = o + Vector2(float(i) * 7.0 * k + 3.0 * k, 3.0 * k)
		var col: Color = Palette.GOLD
		if _object_flash > 0.0:
			col = col.lerp(Palette.SHELL, _object_flash)
		draw_rect(Rect2(c - Vector2(0.7 * k, 3.0 * k), Vector2(1.4 * k, 6.0 * k)),
				col, true)
		draw_arc(c - Vector2(0, 3.0 * k), 1.8 * k, 0.0, TAU, 10, col, 1.0 * k)
		i += 1


func _draw_treasure(anchor: Vector2, k: float) -> void:
	var total: int = world.level.treasures.size()
	if total == 0:
		return
	var text: String = "%d/%d" % [world.collected.size(), total]
	var size: int = int(7.0 * k)
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var col: Color = Palette.UI_TEXT
	if _treasure_flash > 0.0:
		col = col.lerp(Palette.GOLD, _treasure_flash * 2.0)
	draw_string(_font, anchor - Vector2(w, -6.0 * k), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	## A small eight-pointed star marks the counter as treasure, not time.
	var c: Vector2 = anchor - Vector2(w + 7.0 * k, -3.0 * k)
	var pts: PackedVector2Array = PackedVector2Array()
	for j: int in 16:
		var r: float = (3.0 if j % 2 == 0 else 1.3) * k
		var a: float = float(j) * PI / 8.0 - PI * 0.5
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Palette.GOLD)
