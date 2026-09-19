extends Node2D

## The game loop (spec sections 6, 41).
##
## The simulation is advanced from _physics_process, which Godot runs at a
## fixed 60Hz and never at a variable delta. Rendering happens in _process and
## interpolates between the last two ticks. Nothing in the simulation reads a
## frame time, so a slow device produces a slower-looking but identical game.


var world: WorldSim = null
var level: LevelData = null
## Path of the level currently loaded, so the campaign knows what
## comes next.
var level_path: String = ""

var renderer: WorldRenderer = null
var router: InputRouter = null
var pad: VirtualPad = null
var hud: Hud = null
var overlay: DebugOverlay = null
var qa: QaMenu = null

var _paused: bool = false


func _ready() -> void:
	router = InputRouter.new()
	add_child(router)

	renderer = WorldRenderer.new()
	add_child(renderer)

	var ui: CanvasLayer = CanvasLayer.new()
	add_child(ui)

	hud = Hud.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(hud)

	pad = VirtualPad.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mask_changed.connect(func(m: int) -> void: router.touch_mask = m)
	ui.add_child(pad)

	overlay = DebugOverlay.new()
	add_child(overlay)

	if Settings.qa_tools:
		qa = QaMenu.new()
		qa.set_anchors_preset(Control.PRESET_FULL_RECT)
		qa.action_requested.connect(_on_qa_action)
		ui.add_child(qa)

		## Optional capture-and-quit, for checking the renderer from a
		## command line the way the simulation is checked by the tests.
		var shot: AutoScreenshot = AutoScreenshot.from_cmdline()
		if shot != null:
			add_child(shot)

	## Development builds may start on a chosen level, which is how a single
	## room gets rendered or traced without playing to it.
	var start: String = Campaign.first()
	if Settings.qa_tools:
		var args: PackedStringArray = OS.get_cmdline_user_args()
		var i: int = args.find("--level")
		if i >= 0 and i + 1 < args.size():
			start = args[i + 1]
	load_level(start)


func load_level(path: String) -> void:
	var parsed: LevelLoader.ParseResult = LevelLoader.load_file(path)
	for e: String in parsed.errors:
		push_error(e)
	if parsed.level == null:
		return
	level = parsed.level
	level_path = path

	## A level must validate before it is played. In a development build a
	## failure is loud; in a release build only CERTIFIED levels ship, so this
	## should be unreachable there (spec sections 20, 44).
	var rep: Solver.Report = Solver.validate_level(level)
	if not rep.solvable:
		push_error("level %s failed validation: %s" % [level.id, rep.summary()])

	world = WorldSim.new(level)
	renderer.bind(world)
	hud.bind(world)
	overlay.bind(world)
	if qa != null:
		qa.bind(world, self)


func _physics_process(_delta: float) -> void:
	if world == null or _paused:
		return
	renderer.capture_previous()
	var frame: InputFrame = router.poll()
	world.tick(frame)
	_consume_events()


func _process(_delta: float) -> void:
	if renderer != null:
		renderer.alpha = Engine.get_physics_interpolation_fraction()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("debug_toggle") and Settings.qa_tools:
		overlay.cycle_mode()
	elif event.is_action("qa_menu") and qa != null:
		qa.toggle()
		_paused = qa.visible
	elif event.is_action("pause"):
		_paused = not _paused


func _consume_events() -> void:
	for e: Dictionary in world.drain_events():
		match str(e["type"]):
			"treasure":
				hud.flash_treasure()
			"object":
				hud.flash_object(str(e.get("kind", "key")))
			"exit_opened":
				hud.announce("The gate opens")
			"push_refused":
				## The block will not budge, because moving it would seal the
				## level. Told plainly rather than left as a mystery.
				hud.announce("It will not move")
			"locked":
				hud.announce("Sealed")
			"hazard_hit", "enemy_hit":
				renderer.kick_shake(1.4)
			"collapse":
				renderer.kick_shake(0.8)
			"checkpoint":
				hud.announce("Way remembered")
				SaveGame.write_resume(level.id, world.capture_snapshot())
			"checkpoint_rejected":
				push_warning("checkpoint rejected: %s" % str(e.get("reason", "")))
			"softlock_detected":
				push_warning("softlock audit tripped: %s" % str(e.get("reason", "")))
				hud.announce("The stones shift back")
			"death":
				renderer.kick_shake(2.0)
				_queue_recover()
			"level_complete":
				SaveGame.record_completion(level.id, int(e["ticks"]),
						int(e["deaths"]), int(e["treasure_value"]),
						int(e["treasures"]), level.gate)
				_advance()


## Move on to the next level in the campaign, or stop on the last one.
## Before this existed, completing a level printed a line and the game
## simply sat there: the start level was hardcoded and there was no
## route from one level to the next.
func _advance() -> void:
	var next: String = Campaign.next_after(level_path)
	if next.is_empty():
		hud.announce("The last gate holds")
		return
	hud.announce("Gate passed")
	await get_tree().create_timer(1.6).timeout
	if world != null:
		load_level(next)


func _queue_recover() -> void:
	## Let the death animation finish before recovery (spec section 18).
	await get_tree().create_timer(1.2).timeout
	if world != null:
		world.recover()
		renderer.bind(world)


# --- QA hooks (development builds only, spec section 21) ------------------

func _on_qa_action(action: String, arg: Variant) -> void:
	match action:
		"reload_level":
			load_level(level_path)
		"load_level":
			load_level(str(arg))
		"reset_room":
			world.reset_level()
			renderer.bind(world)
		"recover":
			world.recover()
		"teleport":
			world.player.spawn_at_tile(arg as Vector2i)
		"complete":
			world.player.complete_level()
			world.status = WorldSim.Status.COMPLETE
		"give_all":
			for o: Dictionary in level.required_objects:
				world.held[str(o["id"])] = true
			world._refresh_exit()
		"kill":
			world.player.kill()
		"reveal_reach":
			overlay.mode = DebugOverlay.Mode.REACHABILITY
	_paused = qa != null and qa.visible
