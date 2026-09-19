# QA SPEC

## 1. Status lifecycle

Every level carries exactly one status, in its `qa_status` field.

```
PROTOTYPE → IN DEVELOPMENT → QA REQUIRED → QA PASSED → CERTIFIED
                                  ↓
                              QA FAILED → (back to IN DEVELOPMENT)
```

**Only CERTIFIED levels ship.** The build must refuse to include anything
else.

| Status | Meaning |
|---|---|
| `PROTOTYPE` | A sketch. May not even parse. |
| `IN_DEVELOPMENT` | Being built. Automated validation may fail. |
| `QA_REQUIRED` | Author says it is done. Automated validation passes. Awaiting human testing. |
| `QA_FAILED` | Human testing found a blocker. |
| `QA_PASSED` | All four tests below passed. |
| `CERTIFIED` | QA_PASSED, plus signed off against the difficulty curve and the gate's arc. |

## 2. The four tests

### Test 1 — First-time player
Hand the level to someone who has not seen it.

* Do they understand what to do without being told?
* Do they find the critical path without exhaustive trial and error?
* Does anything read as scenery that is actually interactive, or the reverse?
* Where do they hesitate, and is that hesitation the intended kind?

**Fail if:** the player stalls for more than about 30 seconds with no idea
what to try, or solves it by accident without understanding why.

### Test 2 — Experienced player
Hand it to someone who knows the mechanics cold.

* Is it still interesting once the trick is known?
* Is there a faster or greedier line worth taking?
* Does the expert route cost real risk or real execution?

**Fail if:** the level is pure execution with no decision, or the expert
route is strictly better than the safe one at no cost.

### Test 3 — Adversarial test
Actively try to break it. This is the most important test and it is not
optional. Work through the list:

* Push every movable block into every corner and doorway.
* Trigger every switch in every order, including the wrong one.
* Take every object in every order; take none of them.
* Die in unusual places — mid-jump, on a ladder, on a collapsing floor, in a
  doorway, next to a checkpoint.
* Save at a dangerous location, then close and reopen the app.
* Leave a room and come back mid-puzzle.
* Stand where a door could close on you.
* Drop into every pit and every dead end.
* Walk into every wall, corner and one-tile gap looking for a collision seam.
* Let a collapsing floor collapse under a block, an enemy, and yourself.

**Fail if:** any sequence produces a softlock, a crush, a lost required
object, a checkpoint you cannot progress from, or a position the player
cannot leave.

Note what the engine already guarantees (`docs/LEVEL_RULES.md` §3). If the
adversarial test finds a softlock, that is a **bug in the engine**, not just
in the level — the engine's guarantee failed, and the fix belongs there.

### Test 4 — Automated validation
```bash
godot --headless --path . --script res://tests/run_tests.gd
```

Must be green. The `levels` suite checks every level in the tree for parse
errors, buried entities, duplicate ids, dangling requirements, reachable
checkpoints, a reachable critical path, a documented solution, and
solvability.

## 3. What the automated tests do not cover

The validator answers *is it solvable*, not *is it fair*. It deliberately
does not model:

* enemy timing and patrol phase
* hazard damage
* collapsing-floor and timed-door windows
* water currents
* light radius and darkness

Those are human-test concerns. A level that validates but demands frame-perfect
timing in Gate II is a QA failure even though every test is green.

## 4. Development QA tools

Debug builds only (`Settings.qa_tools`, which follows `OS.is_debug_build()`).

**F12 — QA menu** (`src/debug/qa_menu.gd`): reset room, restart from
checkpoint, reload level, grant all required objects, complete level, kill
player, validate now, toggle invulnerability, reveal reachable tiles.

**F11 — debug overlay** (`src/debug/debug_overlay.gd`), cycling through:

| Mode | Shows |
|---|---|
| COLLISION | tile grid, solid/hazard/climb/trigger flags, player and enemy hitboxes, the anchor point, patrol direction |
| ENTITIES | every treasure, object, door, switch and checkpoint with its id; start and exit |
| REACHABILITY | every tile the player can currently reach. Anything the level needs that is *not* shaded is a bug |
| CRITICAL PATH | the authored path, numbered and labelled |
| ALL | everything at once |

Plus a permanent readout: current state, last transition, anchor in subunits,
vertical velocity, objects held, treasure count, and whether the softlock
audit is passing.

Neither tool is reachable in a release build.

## 5. Telemetry

Track during development (spec section 45): death count, death location, death
cause, completion time, failed puzzle attempts, restart frequency, abandoned
attempts, treasure completion, critical-path failures.

**Do not automatically reduce difficulty because players die.** Classify the
death first:

| Classification | Response |
|---|---|
| Intended challenge | none |
| Poor communication | fix the level's readability, not its difficulty |
| Bad control | fix the controller |
| Unfair timing | widen the window |
| Bug | fix the bug |
| Softlock | fix the engine guarantee |
| Genuine mastery challenge | none — this is the point |

A difficulty spike is only a problem if it has no design justification.

## 6. Regression protection

Before modifying any established system (spec section 49):

1. Say why the change is necessary.
2. Identify what depends on it.
3. Make the smallest robust change.
4. Run the full test suite.
5. Re-verify every CERTIFIED level.

A CERTIFIED level that starts failing validation is a release blocker, not a
level problem.
