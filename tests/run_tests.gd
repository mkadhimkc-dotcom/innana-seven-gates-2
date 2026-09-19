extends SceneTree

## Headless test entry point.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Exits non-zero on any failure, so it can gate a commit or a build.

const SUITES: Array[String] = [
	"res://tests/test_core.gd",
	"res://tests/test_player_fsm.gd",
	"res://tests/test_world.gd",
	"res://tests/test_solver.gd",
	"res://tests/test_levels.gd",
]


func _initialize() -> void:
	var total_passed: int = 0
	var all_failures: PackedStringArray = PackedStringArray()
	var started: int = Time.get_ticks_msec()

	print("")
	print("INANNA: SEVEN GATES -- test run")
	print("================================")

	for path: String in SUITES:
		var script: GDScript = load(path)
		if script == null:
			all_failures.append("could not load suite %s" % path)
			continue
		var suite: TestSuite = script.new()
		suite.run()
		total_passed += suite.passed
		all_failures.append_array(suite.failures)
		var mark: String = "ok  " if suite.failures.is_empty() else "FAIL"
		print("%s %-14s %3d passed, %d failed"
				% [mark, suite.suite_name, suite.passed, suite.failures.size()])

	print("--------------------------------")
	if all_failures.is_empty():
		print("%d checks passed in %d ms" % [total_passed, Time.get_ticks_msec() - started])
	else:
		print("%d passed, %d FAILED:" % [total_passed, all_failures.size()])
		for f: String in all_failures:
			print("  - %s" % f)

	quit(0 if all_failures.is_empty() else 1)
