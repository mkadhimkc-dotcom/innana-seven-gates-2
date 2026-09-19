# ART BIBLE

## 1. The single rule

Everything must read as **ancient Mesopotamia** — Sumerian, Akkadian,
Babylonian. Not Egyptian. Not generic fantasy dungeon. Not European medieval.

The three failure modes to watch for:

| Wrong | Why it creeps in | Instead |
|---|---|---|
| Egyptian | sand, gold, tombs, "ancient" shorthand | mud brick not limestone; ziggurat not pyramid; horned crown not nemes; cuneiform not hieroglyphs; lapis blue not turquoise |
| Fantasy dungeon | grey stone, torches, iron portcullis | mud brick and bitumen; reed-oil braziers; barred gates of bronze |
| Medieval European | arches, castles, knights | trilithon doorways, flat roofs, guardians as statues not soldiers |

## 2. Reference vocabulary

Build from what a Sumerian builder actually had:

* **Mud brick**, laid in offset courses. The single most important texture in
  the game. Warm, slightly irregular, sun-dried.
* **Bitumen** — the black mortar and waterproofing. Our shadow colour.
* **Reed** — mats, bundled columns, reed-mat wall courses.
* **Bronze** — fittings, braziers, guardian bodies.
* **Gold** — regalia, gates, treasure.
* **Lapis lazuli** — the sacred blue. Necklaces, inlay, supernatural light.
* **Carnelian** — the red-orange of beads and Inanna's robe.
* **Shell/bone** — inlay white, the palest value in the palette.
* **Cuneiform** — wedge marks on tablets. Never a readable alphabet.
* **Cylinder seals** — the rolled relief band. Our "this is interactive" mark.
* **Ziggurat terracing**, **trilithon doorways** (two jambs, one lintel),
  **temple reliefs**, **astronomical symbols**.
* **Inanna's eight-pointed star** — her sign, and ours. It marks legendary
  treasure and the treasure counter.

## 3. Colour

Defined in `src/render/palette.gd`. Shared anchors across all gates:

| Name | Hex | Use |
|---|---|---|
| BITUMEN | `#0b090e` | deepest shadow, outlines |
| LAPIS | `#1d3f8f` | sacred blue |
| LAPIS_LIGHT | `#3a68c4` | supernatural light, spirits |
| GOLD | `#e0ab48` | regalia, gates, valuable treasure |
| GOLD_DEEP | `#a6761f` | gold in shadow |
| BRONZE | `#8c6239` | fittings, guardians |
| CARNELIAN | `#a4392c` | Inanna's robe, danger accents |
| SHELL | `#e8ddc4` | inlay white, UI text |

Per gate (spec section 26):

| Gate | Identity |
|---|---|
| I — Outer Temple | warm clay and sandstone, daylight |
| II — Palace of Kings | gold, bronze, royal red |
| III — Royal Tombs | dark stone, bitumen, dry bone |
| IV — Flooded Temples | lapis, turquoise, reflection |
| V — Cedar Shadow | deep green, old bronze |
| VI — Kur | near-black, blue supernatural light only |
| VII — Throne of Ereshkigal | dark royal purple, gold, cold underworld glow |

Each gate is its own room in one building. A player dropped into any screen
should know which gate they are in from colour alone — and should still
recognise it as the same world.

## 4. Inanna

An original interpretation, not a recreation of anyone else's protagonist.

* **Silhouette**: compact, upright, unmistakable at 16 pixels. Dark hair
  falling behind her, a long robe, a level gaze.
* **Read at a glance**: the horned crown (the mark of a Mesopotamian deity) is
  her strongest silhouette feature — which is exactly why losing it at Gate I
  registers.
* **Palette**: shell skin, carnelian robe, gold regalia, lapis necklace,
  bitumen hair.

### The seven surrenders

Her appearance gets plainer as she descends. Implemented as a `regalia` count
in `WorldRenderer._draw_player`, derived from the level's gate.

| After gate | Lost | Silhouette change |
|---|---|---|
| I | horned crown | the crown is gone from her head |
| II | jewellery | gold at the wrists |
| III | lapis necklace | the blue band at her throat |
| IV | breastplate | the gold band across her chest |
| V | robe | red robe becomes plain cloth |
| VI | staff | unarmed but for the dagger |
| VII | her name | — |

The player should notice without exposition.

## 5. Tiles

16×16. Every tile must communicate its behaviour before its material.

| Tile | Visual language |
|---|---|
| TEMPLE_WALL | flat, unlit, a single highlight course on top. Reads as "never" |
| MUD_BRICK_FLOOR | two offset brick courses, lit top edge, dark bottom |
| COLLAPSING_FLOOR | brick plus cracks; visibly trembles once triggered |
| LADDER | two rails, three rungs, lighter than the wall behind |
| STAIR_L / STAIR_R | four stepped blocks, each with a lit tread |
| LOCKED_GATE | trilithon doorway, **barred**. Reads as "not yet" |
| OPEN_GATE | same doorway, bars gone, slow warm pulse in the opening |
| SPIKES | upturned reed stakes set into the floor |
| WATER | translucent, one moving ripple line |
| PILLAR | inset column with capital and base |
| PRESSURE_PLATE | raised slab that visibly sinks when pressed |
| MOVABLE_BLOCK | masonry **plus a carved cylinder-seal band** — the band is what says "you can move this" |
| DARKNESS_ZONE | near-opaque field of the gate's darkest value |

## 6. Actors

* **Guardian** — broad, low, helmeted, clearly not human. Carnelian eyes face
  the direction of travel so the player can read the turn coming.
* **Statue** — shell-white when awake, dim grey when dormant. The colour
  change *is* the tell.
* **Spirit** — a lapis glow with a shell core, pulsing. Ignores geometry, and
  looks like it should.
* **Shade** — a guardian silhouette in the gate's darkest value.

## 7. Treasure

| Tier | Form | Colour |
|---|---|---|
| Common | clay tablet with two cuneiform strokes | `#b9a57e` |
| Valuable | cylinder seal seen end-on, shell cap | `#e0ab48` |
| Legendary | Inanna's eight-pointed star | `#6fc6e8` |

All treasure bobs on a slow sine driven by the animation counter, so it
separates from the background without flashing.

## 8. Current implementation, and what replaces it

Everything is drawn procedurally in `src/render/world_renderer.gd`. That is
deliberate: the project has a complete and coherent visual identity with no
binary assets, which keeps the engine work unblocked.

Sprite sheets replace the draw functions **one at a time**. Each sheet must
match the silhouette, palette and read-at-a-glance behaviour described above.
Nothing in the simulation changes when they land — the renderer is the only
layer that knows what anything looks like.

## 9. Constraints

* Logical resolution 256×192. Integer scaling wherever practical.
* Nearest-neighbour filtering, MSAA off.
* Readability beats realism, always. If a tile is prettier but less legible,
  it is worse.
* No effect may be driven by `randf()`. Animation phase comes from counters,
  so it can never desync a replay.
