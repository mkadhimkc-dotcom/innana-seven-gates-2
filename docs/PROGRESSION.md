# PROGRESSION

## 1. The curve

| Section | Difficulty | Levels | Introduces |
|---|---:|---:|---|
| Tutorial (G1 L1) | 1 | — | walk, jump, climb, take, open |
| Gate I — Outer Temple | 1–2 | 4 | the fundamentals, basic hazards |
| Gate II — Palace of Kings | 2–3 | 5 | movable blocks, pressure plates, stairs, multiple routes |
| Gate III — Royal Tombs | 3–4 | 5 | collapsing floors, spikes, timed doors, hidden passages |
| Gate IV — Flooded Temples | 4–5 | 5 | water, floating platforms, currents, flood control |
| Gate V — Cedar Shadow | 5–6 | 6 | enemies as a routing constraint, moving hazards |
| Gate VI — Kur | 6–8 | 6 | darkness, light sources, limited visibility |
| Gate VII — Throne of Ereshkigal | 8–10 | 5 | no new mechanics; mastery of everything |
| **Total** | | **36** | |

Level counts are targets, not contracts. Playtesting moves them.

## 2. The rule that matters most

**The first level is easy because it is the first level**, not hard because
later levels are hard. A player who bounces off Gate I never sees Gate VI.

The player should understand the fundamental game within the first twenty
minutes, without a tutorial overlay and without reading anything.

## 3. Within each gate

Every gate runs its own four-beat arc:

1. **Introduction** — the new mechanic alone, in a safe room, with nothing
   else to think about. The player cannot fail to notice it.
2. **Development** — the mechanic with a consequence attached: a hazard, a
   drop, a route decision.
3. **Combination** — the new mechanic plus one older one. Exactly one.
4. **Mastery** — the gate's real test. Combines freely from everything the
   player has learned, including from earlier gates.

Never introduce five mechanics at once. Never introduce a new mechanic in the
mastery level of a gate.

## 4. Gate by gate

### Gate I — Outer Temple  (difficulty 1–2, 4 levels)
Warm clay and sandstone, daylight through the roof. Teaches movement, jumping,
falling, ladders, treasure, keys, gates and one basic hazard. No combinations.
No timing. No enemies.

*L1 The Threshold* — walk, jump one gap, climb, take the key, open the gate.
Implemented; the reference level.

### Gate II — Palace of Kings  (2–3, 5 levels)
Gold, bronze and royal red. Movable blocks and pressure plates arrive, and
with them the first genuine puzzles: a block is both a tool and a hazard to
your own route. Staircases give diagonal traversal. The first levels with more
than one way through.

### Gate III — Royal Tombs  (3–4, 5 levels)
Tomb stone and bitumen. Floors that fall away, spikes, doors on timers, and
passages that are not visible until found. This is where risk/reward becomes a
real decision: the greedy route starts costing something.

### Gate IV — Flooded Temples  (4–5, 5 levels)
Lapis and turquoise. Water changes the movement rules; floating platforms and
currents add environmental timing the player does not control. Flood gates let
the player change the room itself.

### Gate V — Cedar Shadow  (5–6, 6 levels)
Deep green, old bronze. The architecture starts giving way to mythology.
Enemies stop being obstacles and become routing constraints: the question
becomes *when* to move, not *whether* you can.

### Gate VI — Kur  (6–8, 6 levels)
Near black. Darkness and a carried light are the only new mechanics, and that
is deliberate — the difficulty here comes from combining what the player
already knows under reduced information, not from a pile of new systems.

### Gate VII — Throne of Ereshkigal  (8–10, 5 levels)
Dark royal, gold, cold underworld light. **No new mechanics and no new
controls.** Everything at once: ladders, stairs, treasure routing, keys,
plates, blocks, hazards, water, darkness, enemy avoidance, timing. The final
level is the game's exam.

## 5. The seven surrenders

At each gate Inanna gives up one possession, and her silhouette changes. The
player should notice without being told.

| Gate | Surrendered | Visible change |
|---|---|---|
| I | Horned crown | the crown leaves her head |
| II | Jewellery | gold at her wrists goes |
| III | Lapis necklace | the blue band at her throat goes |
| IV | Breastplate | the gold band across her chest goes |
| V | Robe | the red robe becomes plain cloth |
| VI | Staff | she is unarmed but for the dagger |
| VII | Her name | — |

Implemented in `WorldRenderer._draw_player` as a `regalia` count derived from
the level's gate number.

## 6. Completion tracking

Per level: best time, deaths, treasure value, treasures found, cleared flag.
Globally: artifacts, cylinder seals, cuneiform discoveries, Codex entries,
gates cleared, NG+ cycle. Stored by `SaveGame`.

Optional collectibles encourage exploration. None of them gate progression,
and none of them require grinding.

## 7. Unlocks

* **Level select** — per gate, once that gate is cleared.
* **Codex entries** — on discovery, permanently.
* **New Game+** — on clearing Gate VII. See `docs/NG_PLUS.md`.
