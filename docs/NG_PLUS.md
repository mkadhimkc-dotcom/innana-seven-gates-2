# NEW GAME+

Unlocked on clearing Gate VII.

## 1. The principle

NG+ is **not** a difficulty multiplier. Nothing gets more health, nothing
deals more damage, nothing takes longer to kill. The player has mastered these
rooms; NG+ makes the rooms behave slightly differently so that mastery has to
be re-earned rather than re-executed.

The target for the first NG+ level is roughly **10% harder in perceived
difficulty** than its normal counterpart. That explicitly does not mean:

```
enemy_hp * 1.10          # no
damage_taken * 1.10      # no
timer * 0.90             # no, not on its own
```

It means adjusting patrol timing, hazard timing, treasure placement, route
complexity, visibility, hazard count, timing windows and optional-route
complexity — so the room reads familiar but does not play from memory.

## 2. Modifiers

Apply **1–3 per level**, never more. Each is deterministic from the level seed
plus the NG+ cycle, so a given cycle always produces the same rooms.

### Restless Guardians
Patrol phase, start position and reversal points change. The guardian is the
same guardian; its rhythm is not.

### Fading Light
Light sources burn for less time. Gate VI only, and never below the time
needed to cross the room by the critical path plus a margin.

### Unstable Stone
Collapsing floors have altered delay and respawn timing. Never short enough to
make a required crossing impossible.

### Hidden Treasure
Some treasure moves to different valid positions. Required treasure never
moves. Legendary treasure may move to a harder route but never to an
unreachable one.

### Sealed Passage
A previously available route is closed and a different one opened. The
replacement must be reachable with the same verbs — this is a re-route, not a
new mechanic.

### Ancient Curse
Additional hazards appear at authored candidate positions. Candidates are
declared per level so the generator cannot put spikes in the landing zone of a
mandatory jump.

## 3. Hard constraints

1. **Every NG+ level must remain solvable.** Modifiers are applied, then the
   level is re-validated with `Solver.validate_level`. If it fails, the
   modifier set is rejected and the next candidate set is tried, using the
   same deterministic seed stream.
2. **No modifier may introduce a new mechanic.** NG+ never teaches; it varies.
3. **No modifier may change the control scheme.**
4. **The critical path must stay reachable** with the verbs the original level
   taught.
5. **Required objects must stay obtainable**, and checkpoints must stay valid.
6. **Nothing uncertified ships.** A modified level is generated content and
   goes through the same gate as any other generated content
   (`docs/QA_SPEC.md`).

## 4. The curve across cycles

Difficulty rises gradually with `SaveGame.ng_plus_cycle`:

| Cycle | Modifiers per level | Character |
|---:|---:|---|
| 1 | 1–2 | rhythms shift; layouts mostly intact |
| 2 | 2 | re-routes begin; treasure moves |
| 3 | 2–3 | hazard density rises; windows tighten |
| 4+ | 3 | full variation, still inside every constraint above |

The rise is asymptotic. There is no cycle at which the game becomes
unsolvable or stops being fair, and the constraints in §3 hold at every cycle.

## 5. What NG+ does not change

* The story and the seven surrenders.
* The control scheme.
* Enemy behaviour rules (a guardian is still a guardian).
* Anything that would invalidate the player's learned intuitions about how
  the game works.

## 6. Implementation notes

Modifiers operate on `LevelData` before `WorldSim` is constructed, producing a
new `LevelData`. That keeps the simulation identical between normal play and
NG+ — there is no NG+ branch inside the tick — and it means an NG+ level can
be validated, snapshotted and replayed exactly like a handcrafted one.

`DetRng.fork(cycle)` seeds the modifier selection, so cycle N of a given
level is reproducible on every device.
