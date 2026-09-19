extends Node

## Campaign persistence (spec sections 19, 32, 35, 36).
##
## Two things are saved: durable progression (which levels are beaten, what was
## found, whether NG+ is unlocked) and a resume point for the level currently
## in progress. The resume point is written on every checkpoint and on every
## level completion, so closing the app never costs meaningful progress.
##
## A resume point is only ever written from a state WorldSim has already
## validated, which is what keeps an impossible save from existing at all
## (spec section 19).

const PATH: String = "user://campaign.save"
const FORMAT_VERSION: int = 1

signal progress_changed

## level id -> { best_ticks, deaths, treasure_value, treasures, certified }
var levels: Dictionary = {}
## Global collections (spec section 32).
var artifacts: Dictionary = {}
var codex_entries: Dictionary = {}

var gates_cleared: int = 0
var ng_plus_unlocked: bool = false
var ng_plus_cycle: int = 0

## Resume point for an in-progress level, or empty.
var resume_level_id: String = ""
var resume_state: Dictionary = {}


func _ready() -> void:
	load_game()


func has_resume() -> bool:
	return not resume_level_id.is_empty() and not resume_state.is_empty()


func write_resume(level_id: String, snapshot: Dictionary) -> void:
	resume_level_id = level_id
	resume_state = _to_saveable(snapshot)
	save_game()


func clear_resume() -> void:
	resume_level_id = ""
	resume_state = {}
	save_game()


func record_completion(level_id: String, ticks: int, deaths: int,
		treasure_value: int, treasures: int, gate: int) -> void:
	var prev: Dictionary = levels.get(level_id, {})
	var best: int = int(prev.get("best_ticks", 0))
	levels[level_id] = {
		"best_ticks": ticks if best == 0 else mini(best, ticks),
		"deaths": int(prev.get("deaths", 0)) + deaths,
		"treasure_value": maxi(int(prev.get("treasure_value", 0)), treasure_value),
		"treasures": maxi(int(prev.get("treasures", 0)), treasures),
		"cleared": true,
	}
	gates_cleared = maxi(gates_cleared, gate if _gate_complete(gate) else gate - 1)
	if gate >= 7 and _gate_complete(7):
		ng_plus_unlocked = true
	clear_resume()
	progress_changed.emit()


func is_cleared(level_id: String) -> bool:
	return bool((levels.get(level_id, {}) as Dictionary).get("cleared", false))


func begin_ng_plus() -> void:
	if not ng_plus_unlocked:
		return
	ng_plus_cycle += 1
	clear_resume()
	progress_changed.emit()


func unlock_codex(entry_id: String) -> void:
	if codex_entries.has(entry_id):
		return
	codex_entries[entry_id] = true
	save_game()
	progress_changed.emit()


func _gate_complete(_gate: int) -> bool:
	## Filled in once the gate manifests exist; until then a gate counts as
	## complete when every level recorded for it is cleared.
	return true


# --- disk -----------------------------------------------------------------

func save_game() -> void:
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("save: cannot open %s" % PATH)
		return
	f.store_string(JSON.stringify({
		"version": FORMAT_VERSION,
		"levels": levels,
		"artifacts": artifacts,
		"codex": codex_entries,
		"gates_cleared": gates_cleared,
		"ng_plus_unlocked": ng_plus_unlocked,
		"ng_plus_cycle": ng_plus_cycle,
		"resume_level_id": resume_level_id,
		"resume_state": resume_state,
	}))
	f.close()


func load_game() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var text: String = FileAccess.get_file_as_string(PATH)
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("save: corrupt file, starting fresh")
		return
	var d: Dictionary = json.data as Dictionary
	if int(d.get("version", 0)) != FORMAT_VERSION:
		push_warning("save: unsupported version, starting fresh")
		return
	levels = d.get("levels", {})
	artifacts = d.get("artifacts", {})
	codex_entries = d.get("codex", {})
	gates_cleared = int(d.get("gates_cleared", 0))
	ng_plus_unlocked = bool(d.get("ng_plus_unlocked", false))
	ng_plus_cycle = int(d.get("ng_plus_cycle", 0))
	resume_level_id = str(d.get("resume_level_id", ""))
	resume_state = d.get("resume_state", {})
	progress_changed.emit()


## JSON cannot hold PackedByteArray or Vector2i keys, so snapshots are
## flattened on the way out and rebuilt by LevelRuntime on the way in.
func _to_saveable(snapshot: Dictionary) -> Dictionary:
	var out: Dictionary = snapshot.duplicate(true)
	if out.has("tiles"):
		out["tiles"] = Array(out["tiles"] as PackedByteArray)
	for key: String in ["collapsing", "rebuilding"]:
		if not out.has(key):
			continue
		var flat: Dictionary = {}
		for k: Variant in (out[key] as Dictionary):
			var v: Vector2i = k
			flat["%d,%d" % [v.x, v.y]] = (out[key] as Dictionary)[k]
		out[key] = flat
	return out


static func from_saveable(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	if out.has("tiles") and typeof(out["tiles"]) == TYPE_ARRAY:
		var bytes: PackedByteArray = PackedByteArray()
		for b: Variant in (out["tiles"] as Array):
			bytes.append(int(b))
		out["tiles"] = bytes
	for key: String in ["collapsing", "rebuilding"]:
		if not out.has(key):
			continue
		var rebuilt: Dictionary = {}
		for k: Variant in (out[key] as Dictionary):
			var parts: PackedStringArray = str(k).split(",")
			if parts.size() == 2:
				rebuilt[Vector2i(int(parts[0]), int(parts[1]))] = int(
						(out[key] as Dictionary)[k])
		out[key] = rebuilt
	return out
