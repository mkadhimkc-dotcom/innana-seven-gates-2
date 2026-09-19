# TECH ARCHITECTURE

Source of truth for how the engine is built. Update this file whenever the
implementation changes.

## 1. Layering

The project is split so that the simulation never depends on the presentation,
and neither depends on the other's timing.

```
                   InputRouter  ──►  InputFrame
                                          │
  LevelData ──► WorldSim ──► PlayerSim ───┘
       │            │   └──► EnemySim
       │            └──► CollisionMap
       │
       └──► Solver  (offline validation + runtime anti-deadlock)

  WorldRenderer / Hud / DebugOverlay  ──►  read WorldSim, never write it
```

| Layer | Files | May depend on |
|---|---|---|
| Core | `src/core/` | nothing but Godot |
| Simulation | `src/world/`, `src/player/` | core |
| Validation | `src/validation/` | core |
| Presentation | `src/render/`, `src/main/`, `src/debug/`, `src/input/` | everything |

There are **no cycles between `class_name` scripts**. `PlayerSim` never
references `WorldSim`; it reaches outward only through the four `Callable`
hooks on `PlayerHooks`. This is both an architectural rule and a practical
one, because Godot resolves cyclic `class_name` dependencies badly.

## 2. Determinism

Spec section 6 requires that a recorded input sequence reproduce the same
state. The mechanisms:

* **Integer everything.** Positions, velocities and timers are `int`. There is
  no float in any file under `src/core`, `src/world` or `src/player`.
* **Fixed point.** `Grid.SUB = 16` subunits per world unit; a tile is 256
  subunits. Positions are `Vector2i` anchored bottom-centre.
* **Fixed tick.** The simulation advances only from `_physics_process`, which
  Godot pins to `physics_ticks_per_second = 60`. No gameplay code reads a
  delta.
* **Speeds divide the tile.** `WALK_SPEED`, `CLIMB_SPEED` and `STAIR_SPEED`
  are all 16 subunits/tick, so vertical and horizontal travel land exactly on
  tile boundaries instead of drifting past them. `RUN_SPEED` is 24 and relies
  on the snap-on-stop rule instead.
* **Own RNG.** `DetRng` is a xorshift32. Godot's `RandomNumberGenerator` is
  not guaranteed stable across engine versions, so it is not used for
  anything that affects gameplay.
* **Deterministic "randomness" in presentation.** Screen shake and animation
  phase are derived from counters, never from `randf()`, so they cannot
  desync a replay.

`WorldSim.state_hash()` fingerprints the whole world; `tests/test_world.gd`
runs two worlds in lockstep against one input script and asserts they never
diverge.

### Floor division

GDScript's `/` truncates toward zero, which makes tile lookups asymmetric
across the origin and breaks collision on the left and top edges. All
subunit-to-tile conversion goes through `Grid.fdiv` / `Grid.fmod_i`, which
floor properly. `tests/test_core.gd` pins this.

## 3. Coordinates

* Tile size 16 world units; standard screen 16×12 tiles = 256×192 world units.
* Player body 12×14 world units, anchored **bottom-centre**.
* Because the body is 14 units tall inside a 16 unit tile, a player standing
  with her feet on a tile boundary fits **entirely within one row**. A
  one-tile crawl space is genuinely passable, and both `CollisionMap` and
  `Solver` agree on that.
* The renderer converts to pixels once, at the edge, via `Grid.to_px`.

## 4. Tiles

`TileDB` is a **registry**, not a `match` statement. A tile is an id plus a
bitmask of capabilities (`F_SOLID`, `F_SUPPORT`, `F_CLIMB`, `F_STAIR_L/R`,
`F_HAZARD`, `F_PUSHABLE`, …). Movement, collision, rendering and validation
all read flags. Adding a tile type is one `TileDB.register()` call; ids 64+
are reserved for gate-specific tiles.

Ids 0–15 are fixed by the spec and **must never be renumbered**, because level
files store them by value.

### Conditional tiles are materialised

A conditional tile (locked gate, collapsing floor, hidden passage) is not
resolved at query time. When a gate opens, the tile in `CollisionMap`
genuinely *becomes* `OPEN_GATE`; when a floor collapses it genuinely becomes
`EMPTY`. Collision therefore never consults puzzle state, queries stay cheap,
and the solver can reason about a static grid.

## 5. Player FSM

`PlayerSim` holds 18 states and an explicit `TRANSITIONS` table. `_set_state`
asserts against that table, so an illegal transition fails loudly in a debug
build. `_force_state` bypasses it and exists only for spawn and snapshot
restore, which reconstruct the player rather than driving her.

Movement is deliberate rather than simulated: no friction, no acceleration
curve, no sliding. A direction press moves at a fixed rate and releasing it
stops on the same tick.

**Alignment rule.** Stopping, entering or leaving a ladder, and finishing a
push all snap the anchor to the tile centre. Climbing clamps to the top
boundary of the ladder run, which leaves the player's feet level with the
floor the ladder serves so she can simply walk off sideways. Stair height is a
pure function of x, so she can never be wedged on a staircase.

## 6. Anti-deadlock

See `docs/LEVEL_RULES.md` for the design rules. Mechanically:

1. **Pushes are validated before they commit.** `WorldSim._can_push` clones
   the map, applies the push (including the block's fall), and runs the
   solver. If the result is unsolvable the push is refused and the UI says
   so. A block can only be pushed into genuinely `EMPTY` terrain, so a push
   can never overwrite a ladder, gate or treasure tile.
2. **Required objects cannot be dropped.** Picking one up is permanent. That
   single rule removes the whole "key lost in a pit" family of softlocks.
3. **Collapsed floors rebuild.** A collapse never destroys a route
   permanently, and a rebuild is deferred if the player is standing in the
   tile.
4. **Checkpoints are validated before acceptance.** An unwinnable state is
   never written.
5. **A periodic audit** re-validates every 45 ticks and triggers recovery if
   anything slipped through.

## 7. Save and resume

`SaveGame` (autoload) holds durable progression plus one resume point, written
on every checkpoint and completion. Snapshots are flattened for JSON on the
way out (`PackedByteArray` → array, `Vector2i` keys → `"x,y"`) and rebuilt by
`SaveGame.from_saveable` on the way in.

## 8. Rendering

`WorldRenderer` is procedural vector drawing at logical resolution, so the
project has a complete visual identity with no binary art dependencies. It
interpolates between the last two ticks using
`Engine.get_physics_interpolation_fraction()`, so motion is smooth on displays
that are not exactly 60Hz while the simulation stays locked.

Sprite sheets will replace the per-tile and per-actor draw functions one at a
time. The silhouettes and palette they must match are in `docs/ART_BIBLE.md`.

## 9. Testing

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

Exits non-zero on failure. Suites: `core`, `player`, `world`, `solver`,
`levels`. The `levels` suite walks the whole `levels/` tree, so a level cannot
enter the project without parsing, validating and documenting its solution.

## 10. Conventions

* Static typing everywhere; `untyped_declaration` is on as a warning.
* Tabs for indentation (Godot standard).
* `class_name` for anything referenced across files; autoloads only for
  `Settings` and `SaveGame`.
* Comments explain *why*. The what is in the code.
