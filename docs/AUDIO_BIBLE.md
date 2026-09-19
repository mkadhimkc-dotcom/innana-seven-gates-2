# AUDIO BIBLE

All audio is original to this project. Nothing is reproduced or sampled from
any existing game.

## 1. Identity

The sound of a building made of mud brick, reed and bronze, going downward.

**Instrumentation** — drawn from what the reference culture actually had, or
from plausible reconstructions:

* **Lyre / harp** — the Lyres of Ur are the anchor instrument. Plucked, dry,
  slightly detuned.
* **Reed pipe** — single and double, breathy, for melody in the upper gates.
* **Frame drum and clay drum** — the pulse. Hand-struck, never a kit.
* **Bronze** — struck bowls, small cymbals, ritual bells. Used sparingly, and
  always meaning something.
* **Voice** — wordless, low, no language. Arrives at Gate V and deepens.

**What to avoid**: orchestral strings, synth pads that read as sci-fi, Middle
Eastern pop scales used as shorthand, anything that sounds like a temple in a
fantasy film.

## 2. Music per gate

| Gate | Character |
|---|---|
| I — Outer Temple | lyre and pipe, open and warm, almost pastoral. Daylight. |
| II — Palace of Kings | adds frame drum and bronze. Ceremonial, measured. |
| III — Royal Tombs | pipe drops out. Lyre alone, sparse, long silences. |
| IV — Flooded Temples | resonance and delay; the room itself is an instrument |
| V — Cedar Shadow | wordless voice enters. Drums go irregular. |
| VI — Kur | almost no music. Drone, breath, distant bronze. The player's own footsteps carry the scene. |
| VII — Throne of Ereshkigal | everything, low and slow. Voice and bronze dominant. |

Music thins as she descends, exactly as her possessions do. By Gate VI the
absence is the point: silence is a resource the earlier gates spend so that
Kur can be quiet.

## 3. Ambience

Per environment, looping, low in the mix:

* **Temple** — air movement in a large stone room, distant settling.
* **Palace** — the same, warmer, with faint bronze resonance.
* **Tomb** — dead air. Almost anechoic. Dust.
* **Flooded** — water movement, drips with long tails, muffled reverb.
* **Cedar** — wind in foliage, wood creak, distant animal.
* **Kur** — a sub-bass drone and nothing else.

Acoustic treatment differs per gate: the outer temple is bright and reflective,
the tombs are dead, the flooded temples have long tails, Kur has an unnaturally
long and slightly wrong reverb.

## 4. Sound effects

Every effect answers "what is this made of?" and "did my input register?"

### Player
| Event | Sound |
|---|---|
| Footstep | brick grit, two-variant alternation, pitch-varied per gate |
| Jump | cloth and breath, no cartoon boing |
| Land | a soft brick thud; heavier above the fall-damage threshold |
| Ladder rung | wood knock, one per rung crossed |
| Stair step | shorter, harder than a footstep |
| Push (start) | stone grinding on stone, sustained |
| Push (refused) | a dead, dull stop — the sound of something that will not move |
| Dagger swing | a short bronze whisper |
| Hurt | breath, one carnelian-bright bronze strike |
| Death | the lyre's lowest string, stopped |

### World
| Event | Sound |
|---|---|
| Treasure (common) | clay on clay |
| Treasure (valuable) | a single bronze tone |
| Treasure (legendary) | a lyre chord, held |
| Key / object taken | bronze click with a small resonance |
| Gate unsealing | bolts withdrawing, then stone moving |
| Gate entered | the chord that ends the level |
| Switch / lever | a mechanical bronze clack |
| Pressure plate | stone sinking, and a second sound when it releases |
| Collapsing floor (warning) | grit falling, rising in rate |
| Collapsing floor (goes) | brick failure and debris |
| Collapsing floor (rebuilt) | a low reverse of the same, quieter |
| Spike contact | a short, unpleasant, non-musical hit |
| Water enter / exit | body-sized, muffled |
| Checkpoint lit | a small warm flame catch, then a held bronze tone |
| Softlock recovery | a reversed stone movement — the room putting itself back |

### Enemies
| Enemy | Sound |
|---|---|
| Guardian | bronze footfall on a fixed rhythm; the rhythm *is* the tell |
| Statue waking | stone cracking, once |
| Spirit | a continuous detuned tone, panned to its position |
| Shade | guardian footfall, dampened and lower |

## 5. Mix rules

1. **Gameplay-critical sound is never buried.** A guardian's footfall must be
   audible over the music at every music setting, because the player is
   expected to route by it.
2. **The player's own actions are the loudest thing.** Input confirmation
   outranks atmosphere.
3. **Nothing repeats identically.** Footsteps and impacts alternate variants
   and vary pitch slightly — but *deterministically*, driven by the tick
   counter, never `randf()`. The simulation must stay reproducible.
4. **Silence is used on purpose.** Kur is quiet because five gates of sound
   earned it.
5. **Headphones and phone speaker both work.** Check the mix on a phone
   speaker; the sub-bass drone in Gate VI must not simply vanish.

## 6. Technical

* Music: Ogg Vorbis, looping, per gate, with a short cross-fade on level
  change within the same gate.
* SFX: short Ogg or WAV, normalised, pre-trimmed.
* Two buses: `music` and `sfx`, each driven by `Settings.music_volume` and
  `Settings.sfx_volume` (0–100 integers, so they survive a config round trip
  without float formatting noise).
* Audio is triggered from `WorldSim` **events**, drained once per tick by the
  presentation layer — never from inside the simulation, which must stay
  free of side effects.
* Mobile budget: keep the resident SFX set small and stream music. Loading has
  to stay fast (spec section 40).
