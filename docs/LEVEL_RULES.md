# LEVEL RULES

The level file format, the design rules a level must obey, and the
anti-deadlock contract.

## 1. File format

Levels are JSON under `levels/gate<N>/`. The loader is
`src/core/level_loader.gd`; parse errors are collected and reported, never
thrown, because QA wants the whole list.

```json
{
  "id": "g1_l1_threshold",
  "name": "The Threshold",
  "gate": 1,
  "index": 1,
  "difficulty": 1,
  "palette": "gate1",
  "seed": 1985,
  "qa_status": "IN_DEVELOPMENT",
  "notes": "designer intent, free text",
  "map": ["################", "..."],
  "legend": { "X": 13 },
  "player_start": [2, 10],
  "exit": [14, 1],
  "treasures": [...],
  "required_objects": [...],
  "doors": [...],
  "switches": [...],
  "hazards": [...],
  "enemies": [...],
  "checkpoints": [...],
  "critical_path": [...],
  "optional_routes": [...],
  "validation_rules": {...},
  "solution": "prose walkthrough, required"
}
```

### The map

One string per row, one character per tile. Row 0 is the top. Default legend:

| Char | Tile | Char | Tile |
|---|---|---|---|
| `.` | EMPTY | `^` | SPIKES |
| `#` | TEMPLE_WALL | `c` | COLLAPSING_FLOOR |
| `B` | MUD_BRICK_FLOOR | `~` | WATER |
| `H` | LADDER | `I` | PILLAR |
| `/` | STAIR_RIGHT | `_` | PRESSURE_PLATE |
| `\` | STAIR_LEFT | `X` | MOVABLE_BLOCK |
| `G` | LOCKED_GATE | `?` | HIDDEN_PASSAGE |
| `O` | OPEN_GATE | `%` | DARKNESS_ZONE |

A level may add or override characters with its own `"legend"` block.

Out-of-bounds always reads as `TEMPLE_WALL`, so a level does not strictly need
a border — but author one anyway, because it makes the room legible.

### Entity rows

Every row in `treasures`, `required_objects`, `doors`, `switches`, `hazards`,
`enemies` and `checkpoints` needs a `"pos": [x, y]`. `"id"` is auto-generated
if omitted, but name them: ids appear in telemetry and in QA reports.

* **treasures** — `tier` is `common` | `valuable` | `legendary`, `value` is an
  integer, `required: true` marks it as mandatory (rare; prefer optional).
* **required_objects** — `kind` is `key` | `seal` | `ritual`. These are what
  `exit_requires` and door `requires` name.
* **doors** — `requires: [object ids]`. A door with requirements opens on
  contact when the player holds them all.
* **switches** — `type` is `lever` (needs the action button) or `plate`
  (stood on). `mode` is `toggle` | `once` | `hold`. `targets` lists door ids.
* **checkpoints** — position only. Validated before acceptance.

### validation_rules

* `exit_requires: [object ids]` — the gate stays sealed until all are held.
* `exit_requires_all_treasure: true` — every treasure must be collected.

## 2. Hard rules

These are checked automatically by `tests/test_levels.gd`. A level that breaks
one cannot enter the project.

1. The level **parses cleanly** — no unknown legend characters, no ragged rows.
2. `player_start` and `exit` are **inside the map**, are **different tiles**,
   and the start tile is neither solid nor a hazard.
3. Nothing is **buried in solid rock**. Every treasure, object, checkpoint and
   switch sits in a non-solid tile.
4. Ids are **unique within their table**.
5. Every `exit_requires` entry and every switch `target` **names something the
   level actually contains**.
6. The level **passes `Solver.validate_level`**.
7. Every **checkpoint is reachable**.
8. Every **critical path step is reachable** (the final exit step excepted,
   since it is sealed until its condition is met).
9. The level **documents its solution** in the `solution` field.

## 3. The anti-deadlock contract

Spec section 17 is non-negotiable: the player must never be able to make a
level permanently unwinnable. The engine enforces most of it, but level design
has to hold up its end.

### What the engine guarantees

| Failure mode | Guarantee |
|---|---|
| Required key pushed into a corner | Objects are picked up permanently and cannot be dropped |
| Object dropped into an inaccessible pit | Same |
| Movable block seals the only route | Every push is validated before it commits; a sealing push is refused |
| Block overwrites a ladder or gate | A block only enters genuinely `EMPTY` terrain |
| Required resource consumed permanently | No consumable is required by default; opt in with `consumes_key` and the solver accounts for it |
| Door closes with player on the wrong side | A `hold` switch never closes a door onto the player's tile |
| Route destroyed by a collapse | Collapsing floors rebuild after `COLLAPSE_RESPAWN` ticks |
| Checkpoint saves an impossible state | Checkpoints are validated before acceptance |
| Anything else | A softlock audit runs every 45 ticks and triggers recovery |

### What the designer must still do

* **Do not require an optional route.** If a treasure is needed to open the
  exit, mark it `"required": true` so the validator knows.
* **Do not build a one-way drop into a dead end.** The solver will catch it,
  but catching it at commit time is worse than not authoring it.
* **Do not rely on a switch to close a required route.** The solver's fixpoint
  is monotone: it assumes switches only ever open things. A level that needs a
  closing switch must say so in `validation_rules` and be hand-reviewed.
* **Give every puzzle a recovery.** Room reset, object reset or a checkpoint
  within reach. Never make a puzzle mistake cost a full level restart.

## 4. The solver's movement model

The validator under-approximates on purpose. If it says a tile is reachable,
the controller can genuinely get there.

* **Walk** to an adjacent non-solid tile that is supported, a ladder, or a
  stair.
* **Fall** through empty space to the first supporting tile.
* **Climb** ladders up and down.
* **Stairs** connect diagonally.
* **Jump**, only from a standing position, to `(±1, -1)`, `(±2, 0)` or
  `(±2, +1)`. That is: **one tile up, or one tile of gap across** — never two
  of either. Derived from the controller's actual numbers (`JUMP_V = -60`
  against `GRAVITY = 4` rises 26 world units), kept deliberately short.

What it does **not** model: enemy timing, hazard damage, collapsing-floor
timing, water currents, or light. Those are playtest concerns, not solvability
concerns. A level that is solvable but unfairly timed is a QA failure, not a
validator failure.

## 4b. Stairs and ladders

**Use a ladder for vertical movement. Put stairs only where nothing has to
walk past them — the edge of a room.**

This is not style, it is geometry. A stair tile's walking surface runs
diagonally from the top of the tile at one edge to the *bottom* of it at the
other. Put a stair tile inside a walkway row and its surface drops a full tile
below that walkway exactly where the two meet: the player falls into the
notch, and everything on the far side of it is walled off behind a one-tile
step.

Gate I level 2 was authored that way first and was unplayable because of it.

* **A ladder through a floor** is the safe pattern, and the one level 1 uses:
  make the ladder's topmost tile *be* the floor tile it passes through. It is
  then standable, so the walkway stays continuous and the player can walk over
  it, and pressing DOWN still enters the ladder.
* **A staircase** needs a clear run of tiles with a floor at each end and
  nothing expected to walk along the rows it occupies.

## 5. Authoring a level

1. Sketch the room as ASCII. Keep the whole puzzle on one 16×12 screen until
   there is a reason not to.
2. Place start, exit, and the one mechanic the level is about.
3. Write the `critical_path` **before** placing optional treasure. If the
   critical path is not interesting on its own, the treasure will not save it.
4. Place optional treasure on routes that cost risk or execution, never on the
   critical path.
5. Write the `solution` field in prose. If it is hard to write, the level is
   unclear.
6. Run the tests. Fix what they say.
7. Set `qa_status` honestly. Only `CERTIFIED` ships (see `docs/QA_SPEC.md`).

## 6. Worked example

`levels/gate1/g1_l1_threshold.json` is the reference. It teaches walk, jump,
climb, treasure, key and gate — one at a time, nothing combined, nothing
timed, and the gate is visible from the start position before the player knows
how to open it.
