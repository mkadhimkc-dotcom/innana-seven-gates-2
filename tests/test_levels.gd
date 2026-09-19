extends TestSuite

## Every shipped level file must parse, must validate, and must document its
## own solution (spec sections 4, 20, 44).
##
## This is the automated half of the QA gate. It runs over the whole levels/
## tree, so a level cannot be added to the project without being checked.

const LEVELS_ROOT: String = "res://levels"


func run() -> void:
	suite_name = "levels"
	var files: PackedStringArray = _find_levels(LEVELS_ROOT)
	test("level tree")
	check(files.size() > 0, "found at least one level file under %s" % LEVELS_ROOT)

	for path: String in files:
		_check_level(path)

	_check_campaign(files)


func _find_levels(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = "%s/%s" % [root, entry]
		if dir.current_is_dir():
			out.append_array(_find_levels(full))
		elif entry.ends_with(".json"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _check_level(path: String) -> void:
	var name: String = path.get_file()
	test(name)

	var parsed: LevelLoader.ParseResult = LevelLoader.load_file(path)
	check(parsed.errors.is_empty(), "parses cleanly: %s" % ", ".join(parsed.errors))
	if parsed.level == null:
		return
	var lv: LevelData = parsed.level

	check(not lv.id.is_empty(), "has an id")
	check(lv.gate >= 1 and lv.gate <= 7, "gate is 1-7 (got %d)" % lv.gate)
	check(lv.width > 0 and lv.height > 0, "has geometry")
	check(not lv.solution_notes.is_empty(),
			"documents its solution path (spec section 4)")

	## Placement sanity.
	check(lv.in_bounds(lv.player_start.x, lv.player_start.y), "start is inside the map")
	check(lv.in_bounds(lv.exit_tile.x, lv.exit_tile.y), "exit is inside the map")
	check_ne(lv.player_start, lv.exit_tile, "start and exit are different tiles")

	var start_tile: int = lv.tile_at(lv.player_start.x, lv.player_start.y)
	check(not TileDB.has(start_tile, TileDB.F_SOLID),
			"start tile is not solid (got %s)" % TileDB.name_of(start_tile))
	check(not TileDB.has(start_tile, TileDB.F_HAZARD), "start tile is not a hazard")

	## Nothing may be placed inside solid rock, or it can never be collected.
	for row_name: String in ["treasures", "required_objects", "checkpoints",
			"switches", "enemies"]:
		for e: Dictionary in (lv.get(row_name) as Array):
			var p: Vector2i = e["pos"]
			check(lv.in_bounds(p.x, p.y), "%s %s is inside the map"
					% [row_name, str(e["id"])])
			check(not TileDB.has(lv.tile_at(p.x, p.y), TileDB.F_SOLID),
					"%s %s is not buried in a solid tile" % [row_name, str(e["id"])])

	## Ids must be unique within a table, or the puzzle layer cannot address
	## them and the validator silently double-counts.
	for row_name2: String in ["treasures", "required_objects", "doors",
			"switches", "checkpoints"]:
		var seen: Dictionary = {}
		var dupes: PackedStringArray = PackedStringArray()
		for e: Dictionary in (lv.get(row_name2) as Array):
			var eid: String = str(e["id"])
			if seen.has(eid):
				dupes.append(eid)
			seen[eid] = true
		check(dupes.is_empty(), "%s ids are unique (dupes: %s)"
				% [row_name2, ", ".join(dupes)])

	## Every requirement must name something that exists.
	var object_ids: Dictionary = {}
	for o: Dictionary in lv.required_objects:
		object_ids[str(o["id"])] = true
	for req: Variant in lv.validation_rules.get("exit_requires", []):
		check(object_ids.has(str(req)),
				"exit requires \"%s\", which the level actually contains" % str(req))

	var door_ids: Dictionary = {}
	for d: Dictionary in lv.doors:
		door_ids[str(d["id"])] = true
	for s: Dictionary in lv.switches:
		for t: Variant in s.get("targets", []):
			check(door_ids.has(str(t)), "switch %s targets an existing door \"%s\""
					% [str(s["id"]), str(t)])

	## The main event.
	var rep: Solver.Report = Solver.validate_level(lv)
	check(rep.solvable, "passes solvability validation: %s" % rep.summary())
	check(rep.unreachable_checkpoints.is_empty(),
			"every checkpoint is reachable (%s)" % ", ".join(rep.unreachable_checkpoints))

	## The authored critical path must agree with the validator.
	if lv.critical_path.size() > 0:
		var reach: Dictionary = Solver.reachable_tiles(
				CollisionMap.from_level(lv), lv.player_start)
		var unreachable: PackedStringArray = PackedStringArray()
		for step: Dictionary in lv.critical_path:
			if not step.has("pos"):
				continue
			var p: Vector2i = LevelLoader._to_vec(step["pos"], Vector2i.ZERO)
			## The final step is usually the sealed exit, which only opens
			## once its condition is met, so it is checked by the solver above.
			if p == lv.exit_tile:
				continue
			if not reach.has(p):
				unreachable.append("%s%s" % [str(step.get("label", "")), str(p)])
		check(unreachable.is_empty(), "critical path steps are reachable: %s"
				% ", ".join(unreachable))

	## Shipping gate (spec section 44).
	if lv.qa_status == LevelData.QA.CERTIFIED:
		check(rep.solvable, "a CERTIFIED level must validate")
		check(lv.critical_path.size() > 0, "a CERTIFIED level documents its critical path")


## The campaign must actually chain, or a finished level is a dead end. This
## is not hypothetical: before Campaign existed, completing a level printed a
## line and the game sat there with the start level hardcoded.
func _check_campaign(files: PackedStringArray) -> void:
	Campaign.refresh()
	var order: PackedStringArray = Campaign.levels()

	test("campaign")
	check_eq(order.size(), files.size(), "every level file is in the campaign")
	check(not Campaign.first().is_empty(), "there is a first level")

	## Sorted by the level's own gate and index, and every step leads onward
	## except the last.
	var ascending: bool = true
	var dead_ends: PackedStringArray = PackedStringArray()
	var prev_key: int = -1
	for i: int in order.size():
		var parsed: LevelLoader.ParseResult = LevelLoader.load_file(order[i])
		if parsed.level == null:
			continue
		var key: int = parsed.level.gate * 1000 + parsed.level.index_in_gate
		if key <= prev_key:
			ascending = false
		prev_key = key
		var nxt: String = Campaign.next_after(order[i])
		if i < order.size() - 1 and nxt.is_empty():
			dead_ends.append(order[i].get_file())
	check(ascending, "ordered by gate then index")
	check(dead_ends.is_empty(), "no level dead-ends mid-campaign: %s"
			% ", ".join(dead_ends))
	check(Campaign.next_after(order[order.size() - 1]).is_empty(),
			"the last level ends the campaign rather than looping")
