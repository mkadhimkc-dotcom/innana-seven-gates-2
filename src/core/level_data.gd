class_name LevelData
extends Resource

## Data-driven level definition (spec section 46).
##
## A level is data, not code. Puzzle behaviour is expressed through reusable
## systems (doors, switches, objects, hazards) rather than bespoke scripts, so
## that the solvability validator in src/validation can reason about every
## level without executing it.

## QA lifecycle (spec section 44). Only CERTIFIED may ship.
enum QA { PROTOTYPE, IN_DEVELOPMENT, QA_REQUIRED, QA_FAILED, QA_PASSED, CERTIFIED }

const QA_NAMES: Array[String] = [
	"PROTOTYPE", "IN DEVELOPMENT", "QA REQUIRED", "QA FAILED", "QA PASSED", "CERTIFIED",
]

## Characters accepted in the ASCII tile map. Levels may override or extend
## this with their own "legend" block.
const DEFAULT_LEGEND: Dictionary = {
	".": TileDB.T.EMPTY,
	"#": TileDB.T.TEMPLE_WALL,
	"B": TileDB.T.MUD_BRICK_FLOOR,
	"H": TileDB.T.LADDER,
	"/": TileDB.T.STAIR_RIGHT,
	"\\": TileDB.T.STAIR_LEFT,
	"G": TileDB.T.LOCKED_GATE,
	"O": TileDB.T.OPEN_GATE,
	"^": TileDB.T.SPIKES,
	"c": TileDB.T.COLLAPSING_FLOOR,
	"~": TileDB.T.WATER,
	"I": TileDB.T.PILLAR,
	"_": TileDB.T.PRESSURE_PLATE,
	"X": TileDB.T.MOVABLE_BLOCK,
	"?": TileDB.T.HIDDEN_PASSAGE,
	"%": TileDB.T.DARKNESS_ZONE,
}

# --- metadata -------------------------------------------------------------
@export var id: String = ""
@export var display_name: String = ""
@export var gate: int = 1
@export var index_in_gate: int = 1
@export var difficulty: int = 1
@export var palette: String = "gate1"
@export var qa_status: QA = QA.PROTOTYPE
@export var seed_value: int = 1
@export var author_notes: String = ""

# --- geometry -------------------------------------------------------------
@export var width: int = Grid.SCREEN_W
@export var height: int = Grid.SCREEN_H
## Row-major, width*height entries, each a TileDB.T value.
@export var tiles: PackedByteArray = PackedByteArray()

# --- placement ------------------------------------------------------------
@export var player_start: Vector2i = Vector2i.ZERO
@export var exit_tile: Vector2i = Vector2i.ZERO

# --- entities (arrays of plain Dictionaries, see docs/LEVEL_RULES.md) -----
@export var treasures: Array[Dictionary] = []
@export var required_objects: Array[Dictionary] = []
@export var doors: Array[Dictionary] = []
@export var switches: Array[Dictionary] = []
@export var hazards: Array[Dictionary] = []
@export var enemies: Array[Dictionary] = []
@export var checkpoints: Array[Dictionary] = []

# --- design intent --------------------------------------------------------
@export var critical_path: Array[Dictionary] = []
@export var optional_routes: Array[Dictionary] = []
@export var validation_rules: Dictionary = {}
## Prose walkthrough. Every level must document its solution (spec section 4).
@export var solution_notes: String = ""


func tile_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= width or ty >= height:
		return TileDB.T.TEMPLE_WALL   # outside the map reads as solid boundary
	return tiles[ty * width + tx]


func set_tile(tx: int, ty: int, id_value: int) -> void:
	if tx < 0 or ty < 0 or tx >= width or ty >= height:
		return
	tiles[ty * width + tx] = id_value


func in_bounds(tx: int, ty: int) -> bool:
	return tx >= 0 and ty >= 0 and tx < width and ty < height


func qa_name() -> String:
	return QA_NAMES[qa_status]


func is_shippable() -> bool:
	return qa_status == QA.CERTIFIED


func duplicate_level() -> LevelData:
	var copy: LevelData = duplicate(true) as LevelData
	copy.tiles = tiles.duplicate()
	return copy
