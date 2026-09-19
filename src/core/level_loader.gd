class_name LevelLoader
extends RefCounted

## Parses the on-disk JSON level format into LevelData.
##
## Parse errors are collected rather than thrown: the QA tooling wants the full
## list of what is wrong with a level file, not just the first problem.

class ParseResult extends RefCounted:
	var level: LevelData = null
	var errors: PackedStringArray = PackedStringArray()

	func ok() -> bool:
		return level != null and errors.is_empty()


static func load_file(path: String) -> ParseResult:
	var res: ParseResult = ParseResult.new()
	if not FileAccess.file_exists(path):
		res.errors.append("level file not found: %s" % path)
		return res
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		res.errors.append("level file empty: %s" % path)
		return res
	return parse(text, path)


static func parse(text: String, source: String = "<memory>") -> ParseResult:
	var res: ParseResult = ParseResult.new()
	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		res.errors.append("%s: JSON parse error line %d: %s"
				% [source, json.get_error_line(), json.get_error_message()])
		return res
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		res.errors.append("%s: top level must be an object" % source)
		return res
	return _build(root as Dictionary, source)


static func _build(d: Dictionary, source: String) -> ParseResult:
	var res: ParseResult = ParseResult.new()
	var lv: LevelData = LevelData.new()

	lv.id = _str(d, "id", "")
	if lv.id.is_empty():
		res.errors.append("%s: missing \"id\"" % source)
	lv.display_name = _str(d, "name", lv.id)
	lv.gate = _int(d, "gate", 1)
	lv.index_in_gate = _int(d, "index", 1)
	lv.difficulty = _int(d, "difficulty", 1)
	lv.palette = _str(d, "palette", "gate%d" % lv.gate)
	lv.seed_value = _int(d, "seed", 1)
	lv.author_notes = _str(d, "notes", "")
	lv.solution_notes = _str(d, "solution", "")

	var qa_text: String = _str(d, "qa_status", "PROTOTYPE").to_upper().replace("_", " ")
	var qa_i: int = LevelData.QA_NAMES.find(qa_text)
	if qa_i < 0:
		res.errors.append("%s: unknown qa_status \"%s\"" % [source, qa_text])
		qa_i = 0
	lv.qa_status = qa_i as LevelData.QA

	# --- tile map ---------------------------------------------------------
	var legend: Dictionary = LevelData.DEFAULT_LEGEND.duplicate()
	if d.has("legend") and typeof(d["legend"]) == TYPE_DICTIONARY:
		for k: Variant in (d["legend"] as Dictionary):
			legend[str(k)] = int((d["legend"] as Dictionary)[k])

	if not d.has("map") or typeof(d["map"]) != TYPE_ARRAY:
		res.errors.append("%s: missing \"map\" array of row strings" % source)
		res.level = lv
		return res

	var rows: Array = d["map"] as Array
	lv.height = rows.size()
	lv.width = 0
	for r: Variant in rows:
		lv.width = maxi(lv.width, str(r).length())
	if lv.height == 0 or lv.width == 0:
		res.errors.append("%s: \"map\" is empty" % source)
		res.level = lv
		return res

	lv.tiles = PackedByteArray()
	lv.tiles.resize(lv.width * lv.height)
	for y: int in lv.height:
		var row: String = str(rows[y])
		if row.length() != lv.width:
			res.errors.append("%s: map row %d is %d chars, expected %d"
					% [source, y, row.length(), lv.width])
		for x: int in lv.width:
			var ch: String = row.substr(x, 1) if x < row.length() else "."
			if not legend.has(ch):
				res.errors.append("%s: map (%d,%d) unknown legend char \"%s\""
						% [source, x, y, ch])
				lv.tiles[y * lv.width + x] = TileDB.T.EMPTY
			else:
				lv.tiles[y * lv.width + x] = int(legend[ch])

	# --- placement --------------------------------------------------------
	lv.player_start = _vec(d, "player_start", Vector2i.ZERO)
	lv.exit_tile = _vec(d, "exit", Vector2i.ZERO)

	# --- entity tables ----------------------------------------------------
	lv.treasures = _entities(d, "treasures", res, source)
	lv.required_objects = _entities(d, "required_objects", res, source)
	lv.doors = _entities(d, "doors", res, source)
	lv.switches = _entities(d, "switches", res, source)
	lv.hazards = _entities(d, "hazards", res, source)
	lv.enemies = _entities(d, "enemies", res, source)
	lv.checkpoints = _entities(d, "checkpoints", res, source)

	lv.critical_path = _plain_dicts(d, "critical_path")
	lv.optional_routes = _plain_dicts(d, "optional_routes")
	if d.has("validation_rules") and typeof(d["validation_rules"]) == TYPE_DICTIONARY:
		lv.validation_rules = d["validation_rules"] as Dictionary

	res.level = lv
	return res


## Entity rows get their "pos" normalised to Vector2i and an auto id if the
## author omitted one, so downstream systems never have to special-case that.
static func _entities(d: Dictionary, key: String, res: ParseResult,
		source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not d.has(key):
		return out
	if typeof(d[key]) != TYPE_ARRAY:
		res.errors.append("%s: \"%s\" must be an array" % [source, key])
		return out
	var i: int = 0
	for raw: Variant in (d[key] as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			res.errors.append("%s: %s[%d] must be an object" % [source, key, i])
			i += 1
			continue
		var e: Dictionary = (raw as Dictionary).duplicate(true)
		if not e.has("id"):
			e["id"] = "%s_%d" % [key.trim_suffix("s"), i]
		e["id"] = str(e["id"])
		if e.has("pos"):
			e["pos"] = _to_vec(e["pos"], Vector2i.ZERO)
		else:
			res.errors.append("%s: %s[%s] missing \"pos\"" % [source, key, e["id"]])
			e["pos"] = Vector2i.ZERO
		out.append(e)
		i += 1
	return out


static func _plain_dicts(d: Dictionary, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not d.has(key) or typeof(d[key]) != TYPE_ARRAY:
		return out
	for raw: Variant in (d[key] as Array):
		if typeof(raw) == TYPE_DICTIONARY:
			out.append((raw as Dictionary).duplicate(true))
	return out


static func _str(d: Dictionary, key: String, def: String) -> String:
	return str(d[key]) if d.has(key) else def


static func _int(d: Dictionary, key: String, def: int) -> int:
	return int(d[key]) if d.has(key) else def


static func _vec(d: Dictionary, key: String, def: Vector2i) -> Vector2i:
	return _to_vec(d[key], def) if d.has(key) else def


static func _to_vec(v: Variant, def: Vector2i) -> Vector2i:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2i(int((v as Array)[0]), int((v as Array)[1]))
	if typeof(v) == TYPE_DICTIONARY:
		var dv: Dictionary = v as Dictionary
		return Vector2i(int(dv.get("x", def.x)), int(dv.get("y", def.y)))
	return def
