# INANNA: SEVEN GATES

A Mesopotamian single-screen puzzle-platformer for iOS and Android.
Godot 4.x, GDScript, deterministic grid-based tile engine.

Inanna descends toward the Underworld. At each of seven gates she surrenders
one of her possessions.

## Status

**Phase 1 complete — core engine.** See `docs/` for the design and technical
source of truth.

| System | State |
|---|---|
| Deterministic 60Hz fixed-point simulation | built |
| Tile registry and collision | built |
| Player FSM (18 states, explicit transitions) | built |
| Ladders, stairs, gravity, jumping, pushing | built |
| Data-driven level format + loader | built |
| Solvability validator | built |
| Anti-deadlock enforcement | built |
| Checkpoints, save/resume | built |
| Enemies (4 kinds, deterministic) | built |
| Procedural renderer, HUD, virtual pad | built |
| Debug overlay + QA menu | built |
| Headless test suite | built |
| Screenshot + crop tools for art review | built |
| Gate I level 1 | playable |
| Gates I–VII content | not started |
| Audio | not started |
| Sprite art | procedural placeholder |

## Running

Requires Godot 4.3 or newer.

Open the project folder in Godot and press F5, or:

```bash
godot --path .
```

## Play it in a browser

Live: **https://mkadhimkc-dotcom.github.io/innana-seven-gates-2/**

That is the `gh-pages` branch, which holds nothing but the exported build.
To rebuild and republish:

```bash
godot --headless --path . --export-release "Web" "build/web/index.html"
```

Then replace the contents of `gh-pages` with `build/web/`, keeping the
`.nojekyll` file. Test it locally first — `python -m http.server 8080
--directory build/web` — because an export that fails only shows up in a
browser.

Three things about the web build that are easy to get wrong:

* **The export is single-threaded** (`variant/thread_support=false`).
  Multi-threaded Godot web builds need SharedArrayBuffer, which requires
  cross-origin isolation headers that GitHub Pages cannot send. Single-threaded
  has been the Godot default since 4.3 for exactly this reason.
* **Web requires the Compatibility renderer / WebGL 2.0.** This project already
  uses `gl_compatibility`, so nothing needed changing.
* **`rendering/textures/vram_compression/import_etc2_astc` must be on**, or the
  export is refused with a blank error message. It is needed for the iOS and
  Android targets anyway.

`export_presets.cfg` is committed deliberately so the build is reproducible.

## Tests

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

Exits non-zero on failure. Suites: `core`, `player`, `world`, `solver`,
`levels`. The `levels` suite validates every level file in the tree, so no
level can enter the project unvalidated.

## Controls

| Action | Touch | Keyboard |
|---|---|---|
| Move | left cluster | Arrows / WASD |
| Jump | large right button | Space |
| Action / attack | small right button | J |
| Run | — | Shift |
| Pause | — | Esc |
| Debug overlay | — | F11 (debug builds) |
| QA menu | — | F12 (debug builds) |

Walking into a movable block pushes it. Full detail in
`docs/CONTROL_SPEC.md`.

## Layout

```
src/core/        grid maths, tiles, level data, loader, RNG, settings, save
src/world/       collision map, world simulation, enemies
src/player/      player FSM and movement
src/validation/  solvability validator
src/render/      palette, procedural renderer
src/input/       input router, virtual pad
src/debug/       debug overlay, QA menu
src/main/        game loop, HUD, main scene
levels/gate1/    level files (JSON)
tests/           headless test suites
tools/           dev tools: level tracer, screenshot cropper
docs/            design and technical source of truth
```

## Documentation

| File | Covers |
|---|---|
| `docs/GAME_DESIGN.md` | premise, loop, verbs, treasure, combat, what this is not |
| `docs/TECH_ARCHITECTURE.md` | layering, determinism, coordinates, FSM, anti-deadlock |
| `docs/LEVEL_RULES.md` | level file format, hard rules, the anti-deadlock contract |
| `docs/PROGRESSION.md` | the seven gates, difficulty curve, the seven surrenders |
| `docs/QA_SPEC.md` | status lifecycle, the four tests, QA tools, telemetry |
| `docs/NG_PLUS.md` | New Game+ modifiers and constraints |
| `docs/ART_BIBLE.md` | visual identity, palette, tiles, actors |
| `docs/AUDIO_BIBLE.md` | instrumentation, music per gate, SFX, mix rules |
| `docs/CONTROL_SPEC.md` | input contract, touch layout, feel targets |

When implementation changes, update the relevant document. These files are the
source of truth.

## Two numbers that matter

* **A tile is 16×16 world units.** A standard screen is 16×12 tiles.
* **A jump clears one tile of height, or one tile of gap. Never two.** Every
  level is authored against this, and the validator's jump envelope is derived
  from it. Changing it invalidates every level in the project.

## Originality

This game takes its *design philosophy* from classic single-screen
treasure-hunting platformers: simple controls, readable rooms, keys and locked
passages, ladders, movable objects, risk/reward exploration. Everything
expressive is original to this project — character, story, art, levels,
mechanics, enemies, items, UI, audio, puzzle layouts and progression. No maps,
sprites, characters, animations, sounds, level layouts, UI or names are
reproduced from any existing game.
