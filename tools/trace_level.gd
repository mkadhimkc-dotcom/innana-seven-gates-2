extends SceneTree

## Development tool: run a level headlessly against a scripted input sequence
## and print the player state every tick (spec sections 21, 22).
##
##   godot --headless --path . --script res://tools/trace_level.gd
##
## This is how a movement or puzzle bug gets diagnosed without repeatedly
## playing the room by hand: the run is deterministic, so whatever it prints
## is exactly what happens on the device.

const LEVEL: String = "res://levels/gate1/g1_l1_threshold.json"

const L: int = InputFrame.B_LEFT
const R: int = InputFrame.B_RIGHT
const U: int = InputFrame.B_UP
const D: int = InputFrame.B_DOWN
const J: int = InputFrame.B_JUMP


func _initialize() -> void:
	## Regression scenarios for the three bugs found in the first play test.
	_scenario("walk onto the stakes at x=8 - SHOULD hurt, and only there",
			[[R, 200]])
	_scenario("jump the stakes from tile 7 - should clear them untouched",
			[[R, 79], [R | J, 12], [R, 40], [0, 20]])
	_scenario("checkpoint at the ladder foot must not interrupt the walk",
			[[R, 70], [0, 5]])
	_scenario("climb to the terrace, then walk back and forth over the "
			+ "ladder hole at (6,5) - she must NOT fall through",
			[[R, 63], [U, 100], [L, 45], [R, 90], [0, 10]])
	quit(0)


func _scenario(title: String, script: Array) -> void:
	print("")
	print("=== %s ===" % title)
	var parsed: LevelLoader.ParseResult = LevelLoader.load_file(LEVEL)
	if parsed.level == null:
		print("  level failed to load: %s" % ", ".join(parsed.errors))
		return
	var w: WorldSim = WorldSim.new(parsed.level)
	var masks: PackedInt32Array = InputRouter.script_to_masks(script)

	var prev_mask: int = 0
	var last_line: String = ""
	for i: int in masks.size():
		w.tick(InputFrame.from_mask(masks[i], prev_mask))
		prev_mask = masks[i]
		var p: PlayerSim = w.player
		## Only print when something meaningful changes, or the print is
		## thousands of near-identical lines.
		var line: String = "%-16s tile=%s hp=%d" % [p.state_name(), str(p.tile()), p.health]
		if line != last_line:
			print("  t%-4d %s  anchor=(%d,%d)" % [i, line, p.pos.x, p.pos.y])
			last_line = line
		for e: Dictionary in w.drain_events():
			if str(e["type"]) in ["treasure", "object", "hazard_hit", "death",
					"level_complete", "checkpoint", "exit_opened"]:
				print("    t%-4d EVENT %s" % [i, str(e)])
	print("  final: tile=%s state=%s hp=%d"
			% [str(w.player.tile()), w.player.state_name(), w.player.health])
