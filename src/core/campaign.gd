class_name Campaign
extends RefCounted

## The order levels are played in (spec sections 23, 30).
##
## Built by scanning levels/ and sorting by (gate, index) rather than by a
## hand-maintained manifest, so adding a level file is the only step needed to
## put it in the campaign. The sort is on the level's own declared gate and
## index, not on filename, because filenames drift.
##
## Until this existed, finishing a level printed "Gate passed" and the game
## sat there: START_LEVEL was hardcoded and there was no route from one level
## to the next.

const ROOT: String = "res://levels"

## Ordered level file paths.
static var _order: PackedStringArray = PackedStringArray()
static var _built: bool = false


static func _build() -> void:
	if _built:
		return
	_built = true
	var rows: Array[Dictionary] = []
	for path: String in _scan(ROOT):
		var parsed: LevelLoader.ParseResult = LevelLoader.load_file(path)
		if parsed.level == null:
			push_error("campaign: cannot read %s" % path)
			continue
		rows.append({
			"path": path,
			"gate": parsed.level.gate,
			"index": parsed.level.index_in_gate,
			"id": parsed.level.id,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["gate"]) != int(b["gate"]):
			return int(a["gate"]) < int(b["gate"])
		return int(a["index"]) < int(b["index"]))
	_order = PackedStringArray()
	for r: Dictionary in rows:
		_order.append(str(r["path"]))


## Forces a rescan. Only needed by tests and the QA menu.
static func refresh() -> void:
	_built = false
	_build()


static func levels() -> PackedStringArray:
	_build()
	return _order


static func first() -> String:
	_build()
	return _order[0] if _order.size() > 0 else ""


## The path after this one, or "" when the campaign is finished.
static func next_after(path: String) -> String:
	_build()
	var i: int = _order.find(path)
	if i < 0 or i + 1 >= _order.size():
		return ""
	return _order[i + 1]


static func position_of(path: String) -> int:
	_build()
	return _order.find(path)


## Every .json under levels/, recursively. Directory order is not relied on:
## the caller sorts by the level's own gate and index.
static func _scan(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		push_error("campaign: cannot open %s" % root)
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full: String = "%s/%s" % [root, entry]
			if dir.current_is_dir():
				out.append_array(_scan(full))
			elif entry.ends_with(".json"):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
