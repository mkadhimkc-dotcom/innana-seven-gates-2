# GAME DESIGN

## 1. What this is

**INANNA: SEVEN GATES** is a single-screen Mesopotamian puzzle-platformer for
phones. The player descends through seven gates toward the Underworld,
surrendering a possession at each one.

It sits in the tradition of classic single-screen treasure-hunting
platformers: simple controls, a room you can read at a glance, keys and
locked passages, ladders, movable objects, and a risk/reward pull between the
safe route and the greedy one. Everything expressive — character, story, art,
levels, puzzles, enemies, items, UI, audio — is original to this project.

## 2. The premise

Inanna, queen of heaven, goes down to Kur. At each of seven gates the
gatekeeper demands she give up one thing: her crown, her jewellery, her
necklace, her breastplate, her robe, her staff, and at last her name. She
arrives at the throne of Ereshkigal with nothing.

The myth is the frame. The game is a treasure hunt through the architecture
of that descent, and the player feels the myth through what is taken from
them, not through exposition.

## 3. The loop

**SEE → WONDER → EXPLORE → DISCOVER → SOLVE → RISK → REWARD → PROGRESS**

Within five seconds of a room appearing, the player should be able to answer:

1. Where am I?
2. What can I reach?
3. What can I obviously *not* reach yet?
4. What in here looks like it does something?
5. What am I trying to do?

The room answers all five by its layout. Nothing important is off-screen and
nothing important is explained in text. Experimentation should be rewarded;
blind trial and error should never be necessary.

## 4. Core verbs

| Verb | Learned in | Notes |
|---|---|---|
| Walk / run | Gate I | Run is optional throughout; no level requires it |
| Jump | Gate I | Clears one tile of height or one tile of gap. Never two. |
| Climb | Gate I | Ladders override gravity |
| Take | Gate I | Treasure and required objects; objects are permanent |
| Open | Gate I | Gates seal until their condition is met, and show it |
| Push | Gate II | Blocks. A push that would seal the level is refused |
| Stand on | Gate II | Pressure plates |
| Stairs | Gate II | Diagonal traversal |
| Endure | Gate III | Spikes, collapsing floors, timed doors |
| Swim / ride | Gate IV | Water, floating platforms, flood controls |
| Avoid | Gate V | Enemies become a real routing constraint |
| Carry light | Gate VI | Darkness, limited visibility |

Combat exists and is deliberately thin (see §7).

## 5. Readability rules

* **The exit is always visible from the start**, even when sealed. A sealed
  gate is drawn barred; an open one glows. The player always knows where they
  are going before they know how to get there.
* **Interactive things do not look like scenery.** A movable block carries a
  carved cylinder-seal band; ordinary masonry does not. A lit brazier means a
  checkpoint claimed; a dark one means a checkpoint waiting.
* **Danger telegraphs.** A collapsing floor cracks and visibly trembles before
  it goes. A guardian's eyes face the way it is about to walk.
* **Refusals explain themselves.** If a block will not move because moving it
  would seal the level, the game says "It will not move" rather than silently
  ignoring the input.

## 6. Treasure

Three tiers, and treasure is never merely currency.

* **Common** — clay tablets, bronze fittings, small vessels, beads. Scattered
  on and near the critical path. Teaches the player to look.
* **Valuable** — gold ornaments, cylinder seals, lapis work, royal artifacts,
  ceremonial weapons. Costs a detour, a risk, or a piece of execution.
* **Legendary** — tied to the mythological descent, one or two per gate,
  marked with Inanna's eight-pointed star. Always on an expert route, never
  required.

Treasure drives the replay loop, feeds the Codex, and gives the expert route
its reason to exist.

## 7. Combat

Combat answers exactly one question: *can I safely get past this?*

Not: can I build an optimised combat character. There are no skill trees, no
loot rarity, no damage numbers, no stat grinding and no combos. Inanna carries
a dagger. A swing kills a guardian in the tile ahead of her. Most encounters
are better solved by routing and timing than by swinging.

Enemies are readable and fully predictable, so a patient player can always
plan around them:

* **Guardian** — walks a floor, reverses at walls and ledges.
* **Statue** — still until the player crosses its row within four tiles.
* **Spirit** — drifts a fixed waypoint loop, ignores geometry.
* **Shade** — a guardian that will follow the player down a ladder.

## 8. Failure and recovery

Death costs time, not progress. The player returns to the last validated
checkpoint holding everything they had collected. A puzzle mistake never
costs a full level restart — the room, the puzzle, or the object resets.

The game will not let the player make a level unwinnable. That is a hard
engineering guarantee, not a design aspiration; see
`docs/LEVEL_RULES.md` §3.

## 9. Progression

Seven gates, roughly 36 levels, and a difficulty curve that starts genuinely
easy. Each gate introduces its mechanic in isolation, develops it, combines it
with what came before, then tests mastery. Details in
`docs/PROGRESSION.md`.

After Gate VII, New Game+ (see `docs/NG_PLUS.md`).

## 10. What this game is not

* Not a physics platformer. Movement is deliberate and grid-true.
* Not an action game. Combat is a traversal problem.
* Not an RPG. No stats, no levelling, no builds.
* Not a text adventure. The Codex is optional and the game is fully playable
  without reading a word of it.
* Not a roguelike. Procedural variation supplements handcrafted design; it
  never replaces it, and no generated level ships uncertified.
