# CONTROL SPEC

## 1. The contract

The game must be **fully playable on a phone with no physical controller**.
Touch is a first-class input path, not a fallback.

Every input source — touch, keyboard, gamepad, replay playback, automated
test — produces the same seven-bit button mask, and the simulation cannot tell
them apart. That is what makes replay and the determinism tests possible.

```
touch / keyboard / gamepad / replay  ──►  InputRouter  ──►  InputFrame  ──►  PlayerSim
```

## 2. The buttons

| Button | Bit | Meaning |
|---|---|---|
| LEFT | `B_LEFT` | walk left; leave a ladder sideways |
| RIGHT | `B_RIGHT` | walk right; leave a ladder sideways |
| UP | `B_UP` | climb a ladder; enter one from below |
| DOWN | `B_DOWN` | descend a ladder; step down onto one |
| JUMP | `B_JUMP` | jump. Height varies with hold length |
| ACTION | `B_ACTION` | context-sensitive: interact if there is something to interact with, otherwise swing the dagger |
| RUN | `B_RUN` | hold to run. **Never required by any level.** |

Push is not a button. Walking into a pushable block starts a push, which
makes it discoverable without instruction.

## 3. Input rules

* **Opposing directions cancel**, at the source. `LEFT+RIGHT` is a zero axis,
  not a fight. This is applied in both `InputFrame.axis_x()` and the virtual
  pad, so the simulation never sees an ambiguous frame.
* **`just_pressed` is computed per tick**, by diffing against the previous
  tick's mask — not from Godot's event queue, so it survives replay.
* **Jump buffer**: 6 ticks. Pressing jump just before landing still jumps.
* **Coyote time**: 4 ticks after walking off a ledge.
* **Variable jump height**: releasing jump while rising cuts the velocity.

These three graces are what make grid-true movement feel forgiving instead of
stiff. They are all integer-tick and deterministic.

## 4. Touch layout

`src/input/virtual_pad.gd`, drawn procedurally in the logical 256×192 space
and scaled to the device.

```
   ┌────────────────────────────────────────┐
   │                                        │
   │                                        │
   │        ▲                        ◆      │   ◆ = action
   │      ◄   ►                   ●         │   ● = jump
   │        ▼                               │
   └────────────────────────────────────────┘
      movement cluster            action cluster
```

* Movement cluster bottom-left, action cluster bottom-right. Mirrored when
  `Settings.pad_left_handed` is set.
* **Hit areas are larger than the drawn buttons** — `TOUCH_SLOP` of 6 world
  units beyond the visible radius. A thumb that lands slightly off target
  still registers.
* Multi-touch: each finger is tracked independently, so direction + jump +
  action can all be held at once.
* Dragging between buttons re-targets, so a thumb can slide from LEFT to RIGHT
  without lifting.
* Jump is the largest button, because it is pressed most and its failure is
  most punishing.

## 5. Configurable

All under `Settings`, persisted to `user://settings.cfg`:

| Setting | Default | Range |
|---|---|---|
| `touch_enabled` | true | on/off |
| `pad_scale` | 100 | 60–200 % |
| `pad_opacity` | 60 | 10–100 % |
| `pad_left_handed` | false | on/off |
| `pad_margin` | 12 | world units from the screen edge |

## 6. Keyboard and gamepad

For development, testing, and players who want them. Not required, and no
level may assume them.

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | Arrows / WASD | left stick, d-pad |
| Jump | Space | A / cross |
| Action | J | X / square |
| Run | Shift | B / circle |
| Pause | Esc | Start |
| Debug overlay | F11 | — |
| QA menu | F12 | — |

F11 and F12 exist only in debug builds.

## 7. Feel targets

| Quantity | Value | Why |
|---|---:|---|
| Walk | 16 subunits/tick | exactly one world unit per tick; 16 ticks per tile |
| Run | 24 | noticeably faster without outrunning readability |
| Climb | 16 | divides the tile exactly, so climbs land on boundaries |
| Stairs | 16 per axis | true diagonal at walking pace |
| Gravity | +4/tick | — |
| Terminal velocity | 64 | four world units per tick |
| Jump velocity | −60 | rises ~26 world units: clears one tile, never two |
| Landing recovery | 3 ticks | enough to read, too short to feel sticky |
| Push | 20 ticks per tile | deliberately slower than walking; a push is a commitment |

**A jump clears one tile of height or one tile of gap. Never two.** This is the
single most important number in the game: every level is authored against it,
and the solvability validator's jump envelope is derived from it. Changing it
invalidates every level in the project.

## 8. Alignment

Spec section 9: the player must never become partially trapped between grid
positions. The anchor snaps to the tile centre when she stops walking, enters
or leaves a ladder, or finishes a push. Climbing clamps to the top boundary of
the ladder run. Stair height is a pure function of x.

`tests/test_player_fsm.gd` soaks a long scripted input sequence and asserts
after **every tick** that the body never overlaps a solid tile and that IDLE
always leaves the anchor snapped.

## 9. Recording and replay

`InputRouter` can record the mask stream and play it back. Combined with the
deterministic simulation this gives, from one mechanism: replay, automated
puzzle validation by scripted input, regression tests, and reproducible bug
reports.

```gdscript
router.start_recording()
# ... play ...
var masks := router.stop_recording()
router.play(masks)    # reproduces the run exactly
```
