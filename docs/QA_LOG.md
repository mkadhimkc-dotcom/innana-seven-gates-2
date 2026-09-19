# QA LOG

Per-level record of QA passes, findings and status. The process itself is in
`docs/QA_SPEC.md`; this file is the evidence.

---

## g1_l1_threshold — "The Threshold"

**Status: QA_REQUIRED** — automated validation passes, adversarial pass done,
awaiting human testing.

| §43 Test | Result |
|---|---|
| 1. First-time player | **not done** — requires a human |
| 2. Experienced player | **not done** — requires a human |
| 3. Adversarial | **passed** — see below |
| 4. Automated validation | **passed** — 270 checks |

It cannot go to QA_PASSED until Tests 1 and 2 are run, and cannot be
CERTIFIED until it is also signed off against the difficulty curve and the
Gate I arc. Nothing automated can substitute for either.

### Test 3 — adversarial

Implemented as `tests/test_adversarial.gd`, so it is repeatable rather than a
one-off session. Three seeded fuzz runs of 24,000 ticks each drive the real
level with held random input, checking after **every tick** that:

* she is never inside a solid tile;
* she is never outside the map while alive;
* the softlock audit never fires — not "recovers cleanly", *never fires*,
  because a recovery means the level genuinely did become unwinnable;
* the FSM never takes an illegal transition;
* the level never completes without its required object;
* a sealed gate is never passable.

Plus targeted cases: death and recovery preserving collected items, the
restored position being safe and still winnable, and the terrace edge.

### Findings

**1. Two illegal FSM transitions.** `RUNNING → CLIMBING` (39 occurrences) and
`FALLING → JUMPING` (1). The first meant running at a ladder and pressing UP
was an illegal transition — `RUNNING` shares `_tick_grounded` with `IDLE` and
`WALKING` but its transition list omitted the ladder, push and interact
states. The second was coyote time, added without extending `FALLING`'s list.
Both fixed. Neither was reachable by the hand-written tests; the fuzzer found
both in about thirteen seconds.

**2. The adversarial suite was itself broken.** It claimed the `assert` in
`_set_state` would abort the run on an illegal transition. It does not — it
prints and continues — so a genuinely broken transition table reported green.
`PlayerSim.illegal_transitions` now counts them and the suite fails on any.

**3. A trap on the critical path, in the tutorial level.** The upper ladder at
column 10 was the *last* tile of the terrace, so overshooting it by a single
tile dropped the player six tiles to the floor below. The fall damage
threshold is five, so imprecision cost a third of their health — in the first
level of the game, while they are still learning to walk and climb. The
terrace now continues to column 12, giving two tiles of margin. Fall damage
itself was left alone; it is a system the later gates need.

**4. A test that proved nothing while reporting green.** The first version of
the terrace-fall check walked her *left*, into the boundary wall, so she never
fell at all. Corrected to use the open edge. Worth recording because a test
that cannot fail is worse than no test — it buys false confidence.

### Still to do — Tests 1 and 2

Run these yourself; they take about fifteen minutes.

**Test 1, first-time player.** Hand it to someone who has not seen it and say
nothing at all. Watch, do not coach.

* Do they walk right, or stand still? If they stand still, the room is not
  inviting movement.
* Do they notice the stakes before stepping on them?
* Do they work out that the stakes can be jumped, or do they tank the damage?
* Do they find the key at the far right, or turn back early?
* Do they connect "gate is barred" with "I need something"?
* Do they find the first ladder without being told?
* **Where do they hesitate for more than about ten seconds?** That is the
  finding, whatever it is.

Fail if they stall with no idea what to try, or finish without understanding
why.

**Test 2, experienced player.** Give it to someone who knows the mechanics.

* Is it still worth playing once the trick is known?
* Is the optional treasure at (2,4) worth the detour, or is it free?
* Is there a faster line?

Fail if it is pure execution with no decision, or the greedy route costs
nothing.

### Second pass — after play testing

**5. The jump was not consistent, and the player was right.** Reported as
"sometimes long, sometimes short". Measured with `tools/jump_profile.gd`:
distance ranged from **0.63 tiles to 2.19 tiles** purely on how long the
button was held, and a one-tile gap needs 2.0 — so anything under a 200ms
hold simply failed. The cause was variable jump height. It has been removed:
every jump is now 2.19 tiles, tap or hold. Levels are authored against a
guarantee, and a guarantee that depends on button-hold duration is not one.

**6. The level had no enemy.** Gate I now has a temple guardian patrolling
the terrace. It is contained by the boundary wall and the terrace ledge, so
it can never reach the ground floor or camp the spawn — asserted over 6,000
ticks. It stands between the player and the upper ladder, so it must be
timed past or killed with the dagger, and the player can always retreat down
the first ladder. Deliberately slower than the default speed: this is the
level that teaches what an enemy is.

Open question for human testing: the first ladder surfaces inside the
guardian's patrol, so the player can emerge next to it. The whole room is one
screen, so it can be watched from the floor below and timed — that is the
intended skill — but whether it reads that way to a new player is exactly
what Test 1 is for.

### Notes for the sign-off

Difficulty is authored as 1. The level introduces walk, jump, climb, treasure,
key and gate — six things, but strictly one at a time and in that order, with
nothing combined and nothing timed, which is what Gate I asks for (§23).

The one genuine hazard is a single tile of stakes with a one-tile gap. The
jump clears it from the tile before with room to spare, and the current tuning
was widened specifically so it does not demand an edge-of-tile take-off.
