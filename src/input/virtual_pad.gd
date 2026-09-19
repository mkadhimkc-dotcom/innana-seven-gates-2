class_name VirtualPad
extends Control

## On-screen controls (spec section 11).
##
## The game must be fully playable on a phone with no physical controller, so
## this is a first-class input path rather than a debug convenience. Buttons
## are drawn procedurally at logical resolution and are deliberately larger
## than their artwork: a thumb that lands slightly off target still registers.

const DEAD_ZONE: float = 0.18

## Extra hit radius beyond the drawn button, in world units.
const TOUCH_SLOP: float = 6.0

signal mask_changed(mask: int)

var mask: int = 0

var _buttons: Array[Dictionary] = []
var _touches: Dictionary = {}     ## finger index -> button name
var _opacity: float = 0.6
var _scale: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process_unhandled_input(true)
	_apply_settings()
	if Settings.has_signal("changed"):
		Settings.changed.connect(_apply_settings)


func _apply_settings() -> void:
	visible = Settings.touch_enabled
	_opacity = clampf(float(Settings.pad_opacity) / 100.0, 0.1, 1.0)
	_scale = clampf(float(Settings.pad_scale) / 100.0, 0.6, 2.0)
	_layout()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


## Buttons are positioned in the logical 256x192 space and mirrored for
## left-handed players.
func _layout() -> void:
	var m: float = float(Settings.pad_margin)
	var r: float = 13.0 * _scale
	var pad_x: float = m + r
	var act_x: float = float(Grid.VIEW_W) - m - r
	if Settings.pad_left_handed:
		var tmp: float = pad_x
		pad_x = act_x
		act_x = tmp
	var base_y: float = float(Grid.VIEW_H) - m - r

	_buttons = [
		{"name": "left", "bit": InputFrame.B_LEFT,
			"c": Vector2(pad_x - r * 1.1, base_y), "r": r, "glyph": "left"},
		{"name": "right", "bit": InputFrame.B_RIGHT,
			"c": Vector2(pad_x + r * 1.1, base_y), "r": r, "glyph": "right"},
		{"name": "up", "bit": InputFrame.B_UP,
			"c": Vector2(pad_x, base_y - r * 1.5), "r": r, "glyph": "up"},
		{"name": "down", "bit": InputFrame.B_DOWN,
			"c": Vector2(pad_x, base_y + r * 0.4), "r": r * 0.9, "glyph": "down"},
		{"name": "jump", "bit": InputFrame.B_JUMP,
			"c": Vector2(act_x, base_y), "r": r * 1.15, "glyph": "jump"},
		{"name": "action", "bit": InputFrame.B_ACTION,
			"c": Vector2(act_x - r * 1.7, base_y - r * 1.1), "r": r, "glyph": "action"},
	]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
		accept_event()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		_press(d.index, d.position)
		accept_event()
	elif event is InputEventMouseButton and OS.has_feature("editor"):
		## Mouse stands in for a single finger while developing on desktop.
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(-1, mb.position)
			else:
				_release(-1)


func _press(finger: int, screen_pos: Vector2) -> void:
	var p: Vector2 = _to_logical(screen_pos)
	var hit: String = ""
	for b: Dictionary in _buttons:
		var c: Vector2 = b["c"]
		if p.distance_to(c) <= float(b["r"]) + TOUCH_SLOP:
			hit = b["name"]
			break
	if hit.is_empty():
		_release(finger)
		return
	_touches[finger] = hit
	_rebuild_mask()


func _release(finger: int) -> void:
	if _touches.erase(finger):
		_rebuild_mask()


func _rebuild_mask() -> void:
	var m: int = 0
	var active: Dictionary = {}
	for f: Variant in _touches:
		active[_touches[f]] = true
	for b: Dictionary in _buttons:
		if active.has(b["name"]):
			m |= int(b["bit"])
	## Opposing directions cancel at the source so the simulation never sees
	## an ambiguous frame.
	if (m & InputFrame.B_LEFT) != 0 and (m & InputFrame.B_RIGHT) != 0:
		m &= ~(InputFrame.B_LEFT | InputFrame.B_RIGHT)
	if m == mask:
		return
	mask = m
	mask_changed.emit(mask)
	queue_redraw()


func _to_logical(screen_pos: Vector2) -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return screen_pos
	return Vector2(screen_pos.x / vp.x * float(Grid.VIEW_W),
			screen_pos.y / vp.y * float(Grid.VIEW_H))


func _draw() -> void:
	var scale_v: Vector2 = get_viewport_rect().size / Vector2(Grid.VIEW_W, Grid.VIEW_H)
	var active: Dictionary = {}
	for f: Variant in _touches:
		active[_touches[f]] = true

	for b: Dictionary in _buttons:
		var c: Vector2 = (b["c"] as Vector2) * scale_v
		var r: float = float(b["r"]) * minf(scale_v.x, scale_v.y)
		var down: bool = active.has(b["name"])
		var fill: Color = Palette.UI_PAD_DOWN if down else Palette.UI_PAD
		fill.a *= _opacity
		var edge: Color = Palette.UI_PAD_EDGE
		edge.a *= _opacity
		draw_circle(c, r, fill)
		draw_arc(c, r, 0.0, TAU, 24, edge, 1.5 * minf(scale_v.x, scale_v.y))
		_draw_glyph(str(b["glyph"]), c, r, edge)


func _draw_glyph(glyph: String, c: Vector2, r: float, col: Color) -> void:
	var s: float = r * 0.45
	match glyph:
		"left":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(s, -s), c + Vector2(s, s), c + Vector2(-s, 0)]), col)
		"right":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s, -s), c + Vector2(-s, s), c + Vector2(s, 0)]), col)
		"up":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s, s), c + Vector2(s, s), c + Vector2(0, -s)]), col)
		"down":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(0, s)]), col)
		"jump":
			## Upward chevron, reading as "leap" rather than "north".
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s, s * 0.4), c + Vector2(0, -s),
				c + Vector2(s, s * 0.4), c + Vector2(0, -s * 0.1)]), col)
		"action":
			## A small blade, the dagger Inanna carries.
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.25, s), c + Vector2(s * 0.25, s),
				c + Vector2(s * 0.25, -s * 0.3), c + Vector2(0, -s),
				c + Vector2(-s * 0.25, -s * 0.3)]), col)
