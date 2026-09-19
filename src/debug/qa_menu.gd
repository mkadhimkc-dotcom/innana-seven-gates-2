class_name QaMenu
extends Control

## Development QA menu (spec section 21).
##
## Built in code rather than as a scene so it can never be accidentally added
## to a shipped scene tree, and gated on Settings.qa_tools, which is only ever
## true in a debug build. F12 opens it; the game pauses while it is open.

signal action_requested(action: String, arg: Variant)

var world: WorldSim = null
var game: Node = null

var _list: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(20, 14)
	panel.custom_minimum_size = Vector2(216, 164)
	add_child(panel)

	var root: VBoxContainer = VBoxContainer.new()
	panel.add_child(root)

	var title: Label = Label.new()
	title.text = "QA TOOLS  (development build)"
	root.add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_list = VBoxContainer.new()
	root.add_child(_list)

	_add_button("Reset room", "reset_room")
	_add_button("Restart from checkpoint", "recover")
	_add_button("Reload level", "reload_level")
	_add_button("Grant all required objects", "give_all")
	_add_button("Complete level", "complete")
	_add_button("Kill player", "kill")
	_add_button("Validate level now", "__validate")
	_add_button("Toggle invulnerability", "__invuln")
	_add_button("Reveal reachable tiles", "__reach")
	_add_button("Close", "__close")


func _add_button(text: String, action: String) -> void:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(_on_pressed.bind(action))
	_list.add_child(b)


func bind(w: WorldSim, g: Node) -> void:
	world = w
	game = g
	_refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _refresh() -> void:
	if world == null:
		return
	var rep: Solver.Report = Solver.validate_state(
			world.level, world.map, world.player.tile(), world.held, world.open_doors)
	_status.text = "%s  [%s]\n%s" % [world.level.id, world.level.qa_name(),
			rep.summary()]


func _on_pressed(action: String) -> void:
	match action:
		"__close":
			visible = false
			action_requested.emit("closed", null)
		"__validate":
			_refresh()
		"__invuln":
			## 24 hours of invulnerability is simpler than a separate flag and
			## cannot leak into a release build.
			world.player.invuln = Grid.TICK_HZ * 60 * 60 * 24
			_refresh()
		"__reach":
			## The overlay belongs to the game, not to this menu. Ask rather
			## than reach into it.
			visible = false
			action_requested.emit("reveal_reach", null)
		_:
			action_requested.emit(action, null)
			_refresh()
