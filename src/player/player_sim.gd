class_name PlayerSim
extends RefCounted

## Inanna's finite state machine and movement (spec sections 9, 10, 12).
##
## All arithmetic is integer, in fixed-point subunits, driven from an
## InputFrame. Given the same level, the same start state and the same input
## sequence, this produces byte-identical results on every device.
##
## Movement is deliberate and readable rather than physically simulated: there
## is no friction, no acceleration curve and no sliding. A direction press
## moves at a fixed rate; releasing it stops on the same tick.

enum S {
	IDLE,
	WALKING,
	RUNNING,
	JUMPING,
	FALLING,
	LANDING,
	CLIMBING,
	DESCENDING,
	STAIR_ASCENDING,
	STAIR_DESCENDING,
	PUSHING,
	ATTACKING,
	HURT,
	DYING,
	DEAD,
	INTERACTING,
	LEVEL_COMPLETE,
}

const STATE_NAMES: Array[String] = [
	"IDLE", "WALKING", "RUNNING", "JUMPING", "FALLING", "LANDING",
	"CLIMBING", "DESCENDING", "STAIR_ASCENDING", "STAIR_DESCENDING",
	"PUSHING", "ATTACKING", "HURT", "DYING", "DEAD", "INTERACTING",
	"LEVEL_COMPLETE",
]

# --- tuning (subunits per tick unless noted) ------------------------------
const WALK_SPEED: int = 16          # 1 world unit/tick -> 16 ticks per tile
const RUN_SPEED: int = 24
## Climb and stair speeds must divide TILE_SUB exactly, so vertical travel
## lands on tile boundaries rather than drifting past them.
const CLIMB_SPEED: int = 16
const STAIR_SPEED: int = 16
## Gravity and jump velocity are tuned together against one rule: a jump
## must clear ONE tile of height or ONE tile of gap, and never two.
## -54 against 3 rises 28.7 world units (under the 32 that would reach a
## two-tile ledge) and stays airborne 35 ticks, which carries her 2.2
## tiles sideways at walking speed. The earlier -60 against 4 only
## carried 1.8 tiles, so clearing a one-tile gap meant jumping from the
## very edge of the departure tile - far too exacting for Gate I.
const GRAVITY: int = 3
const TERMINAL_V: int = 64
const JUMP_V: int = -54
const JUMP_CUT_V: int = -16         # variable jump height on early release
const LANDING_TICKS: int = 3
const PUSH_TICKS: int = 20          # deliberately slower than walking
const ATTACK_TICKS: int = 12
const INTERACT_TICKS: int = 8
const HURT_TICKS: int = 20
const INVULN_TICKS: int = 90
const DYING_TICKS: int = 48
const COYOTE_TICKS: int = 4         # grace after walking off a ledge
const JUMP_BUFFER_TICKS: int = 6    # grace for pressing jump just before landing
const MAX_HEALTH: int = 3
const FALL_DAMAGE_SUB: int = Grid.TILE_SUB * 5   # survivable fall height

## Explicit transition table (spec section 10). Any transition not listed
## here is a bug, and is caught by tests/test_player_fsm.gd.
const TRANSITIONS: Dictionary = {
	S.IDLE: [S.WALKING, S.RUNNING, S.JUMPING, S.FALLING, S.CLIMBING, S.DESCENDING,
		S.STAIR_ASCENDING, S.STAIR_DESCENDING, S.PUSHING, S.ATTACKING,
		S.INTERACTING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.WALKING: [S.IDLE, S.RUNNING, S.JUMPING, S.FALLING, S.CLIMBING, S.DESCENDING,
		S.STAIR_ASCENDING, S.STAIR_DESCENDING, S.PUSHING, S.ATTACKING,
		S.INTERACTING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.RUNNING: [S.IDLE, S.WALKING, S.JUMPING, S.FALLING, S.STAIR_ASCENDING,
		S.STAIR_DESCENDING, S.ATTACKING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.JUMPING: [S.FALLING, S.CLIMBING, S.DESCENDING, S.LANDING, S.HURT, S.DYING,
		S.LEVEL_COMPLETE],
	S.FALLING: [S.LANDING, S.IDLE, S.CLIMBING, S.DESCENDING, S.STAIR_ASCENDING,
		S.STAIR_DESCENDING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.LANDING: [S.IDLE, S.WALKING, S.RUNNING, S.JUMPING, S.FALLING, S.PUSHING,
		S.ATTACKING, S.INTERACTING, S.STAIR_ASCENDING, S.STAIR_DESCENDING,
		S.CLIMBING, S.DESCENDING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.CLIMBING: [S.IDLE, S.DESCENDING, S.FALLING, S.JUMPING, S.WALKING,
		S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.DESCENDING: [S.IDLE, S.CLIMBING, S.FALLING, S.JUMPING, S.WALKING,
		S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.STAIR_ASCENDING: [S.IDLE, S.WALKING, S.RUNNING, S.STAIR_DESCENDING,
		S.FALLING, S.LANDING, S.JUMPING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.STAIR_DESCENDING: [S.IDLE, S.WALKING, S.RUNNING, S.STAIR_ASCENDING,
		S.FALLING, S.LANDING, S.JUMPING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.PUSHING: [S.IDLE, S.WALKING, S.FALLING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.ATTACKING: [S.IDLE, S.FALLING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.INTERACTING: [S.IDLE, S.FALLING, S.HURT, S.DYING, S.LEVEL_COMPLETE],
	S.HURT: [S.IDLE, S.LANDING, S.FALLING, S.DYING, S.LEVEL_COMPLETE],
	S.DYING: [S.DEAD],
	S.DEAD: [S.IDLE],
	S.LEVEL_COMPLETE: [S.IDLE],
}

# --- state ----------------------------------------------------------------
var pos: Vector2i = Vector2i.ZERO    ## bottom-centre anchor, subunits
var vel_y: int = 0
var facing: int = 1
var state: int = S.IDLE
var state_ticks: int = 0
var health: int = MAX_HEALTH
var invuln: int = 0
var coyote: int = 0
var jump_buffer: int = 0
var fall_start_y: int = 0
var push_dir: int = 0
var push_tile: Vector2i = Vector2i.ZERO
var attack_hit: bool = false
var interact_tile: Vector2i = Vector2i.ZERO

var map: CollisionMap = null
var hooks: PlayerHooks = null

## Diagnostics only. Never read by gameplay logic.
var last_transition: String = ""


func _init(collision_map: CollisionMap = null, player_hooks: PlayerHooks = null) -> void:
	map = collision_map
	hooks = player_hooks if player_hooks != null else PlayerHooks.new()


func spawn_at_tile(t: Vector2i) -> void:
	## Spawns standing on the floor of the given tile, horizontally centred.
	pos = Vector2i(Grid.tile_center(t.x), Grid.tile_origin(t.y + 1))
	vel_y = 0
	facing = 1
	health = MAX_HEALTH
	invuln = 0
	coyote = 0
	jump_buffer = 0
	push_dir = 0
	_force_state(S.IDLE)


func state_name() -> String:
	return STATE_NAMES[state]


func tile() -> Vector2i:
	return Vector2i(Grid.to_tile(pos.x), Grid.to_tile(pos.y - 1))


func is_alive() -> bool:
	return state != S.DEAD and state != S.DYING


## Busy states ignore movement input; the world uses this to suppress the
## virtual pad and to know when a scripted state owns the player.
func is_locked() -> bool:
	return state in [S.DYING, S.DEAD, S.LEVEL_COMPLETE, S.HURT]


# --- transition plumbing --------------------------------------------------

func can_transition(to: int) -> bool:
	if to == state:
		return true
	var allowed: Variant = TRANSITIONS.get(state)
	if allowed == null:
		return false
	return (allowed as Array).has(to)


func _set_state(to: int) -> void:
	if to == state:
		return
	assert(can_transition(to),
			"illegal transition %s -> %s" % [STATE_NAMES[state], STATE_NAMES[to]])
	last_transition = "%s->%s" % [STATE_NAMES[state], STATE_NAMES[to]]
	state = to
	state_ticks = 0


## Bypasses the table. Only for spawn and checkpoint restore, which are
## reconstructing the player rather than driving it.
func _force_state(to: int) -> void:
	state = to
	state_ticks = 0


# --- main tick ------------------------------------------------------------

func tick(inp: InputFrame) -> void:
	state_ticks += 1
	if invuln > 0:
		invuln -= 1
	if jump_buffer > 0:
		jump_buffer -= 1
	if inp.just_pressed(InputFrame.B_JUMP):
		jump_buffer = JUMP_BUFFER_TICKS

	match state:
		S.IDLE, S.WALKING, S.RUNNING:
			_tick_grounded(inp)
		S.JUMPING:
			_tick_airborne(inp, true)
		S.FALLING:
			_tick_airborne(inp, false)
		S.LANDING:
			_tick_landing(inp)
		S.CLIMBING, S.DESCENDING:
			_tick_ladder(inp)
		S.STAIR_ASCENDING, S.STAIR_DESCENDING:
			_tick_stairs(inp)
		S.PUSHING:
			_tick_pushing(inp)
		S.ATTACKING:
			_tick_attacking(inp)
		S.INTERACTING:
			_tick_timed_return(INTERACT_TICKS)
		S.HURT:
			_tick_hurt(inp)
		S.DYING:
			if state_ticks >= DYING_TICKS:
				_set_state(S.DEAD)
		S.DEAD, S.LEVEL_COMPLETE:
			pass


# --- grounded -------------------------------------------------------------

func _tick_grounded(inp: InputFrame) -> void:
	if _try_leave_ground_for_ladder(inp):
		return
	if not map.on_ground(pos.x, pos.y):
		if _try_enter_stair_from_ground():
			return
		coyote = COYOTE_TICKS
		_begin_fall()
		return
	coyote = COYOTE_TICKS

	if jump_buffer > 0:
		_begin_jump()
		return
	if inp.just_pressed(InputFrame.B_ACTION):
		if _try_interact():
			return
		_begin_attack()
		return

	var ax: int = inp.axis_x()
	if ax == 0:
		## Alignment rule (spec section 9): stopping snaps to the grid so the
		## player can never end a move straddling two tiles.
		pos.x = Grid.snap_to_center(pos.x)
		_set_state(S.IDLE)
		return

	facing = ax
	var running: bool = inp.is_held(InputFrame.B_RUN)
	var speed: int = RUN_SPEED if running else WALK_SPEED

	if _try_enter_stair_horizontal(ax):
		return

	var moved: int = _move_x(pos.x, pos.y, ax * speed)
	if moved == 0:
		## Blocked. A pushable tile ahead turns this into a push instead.
		if _try_begin_push(ax):
			return
		pos.x = Grid.snap_to_center(pos.x)
		_set_state(S.IDLE)
		return
	pos.x += moved
	_set_state(S.RUNNING if running else S.WALKING)


func _try_leave_ground_for_ladder(inp: InputFrame) -> bool:
	var ay: int = inp.axis_y()
	if ay < 0 and map.climb_at_anchor(pos.x, pos.y):
		_enter_ladder(S.CLIMBING)
		return true
	if ay > 0 and map.climb_below(pos.x, pos.y):
		_enter_ladder(S.DESCENDING)
		return true
	return false


func _enter_ladder(to: int) -> void:
	pos.x = Grid.snap_to_center(pos.x)   # alignment rule
	vel_y = 0
	_set_state(to)


# --- stairs ---------------------------------------------------------------

## Surface height of a stair tile at a given horizontal anchor, in subunits.
## Purely a function of x, so the player can never become wedged on a stair.
func stair_surface_y(tx: int, ty: int, ax: int) -> int:
	var local_x: int = Grid.fmod_i(ax, Grid.TILE_SUB)
	var dir: int = map.stair_dir(tx, ty)
	if dir > 0:
		return Grid.tile_origin(ty + 1) - local_x
	if dir < 0:
		return Grid.tile_origin(ty) + local_x
	return Grid.tile_origin(ty + 1)


func _stair_tile_under(ax: int, ay: int) -> Vector2i:
	## The stair the anchor is standing on, or (-1,-1).
	var tx: int = Grid.to_tile(ax)
	for ty: int in [Grid.to_tile(ay - 1), Grid.to_tile(ay)]:
		if map.is_stair(tx, ty):
			return Vector2i(tx, ty)
	return Vector2i(-1, -1)


func _try_enter_stair_from_ground() -> bool:
	var st: Vector2i = _stair_tile_under(pos.x, pos.y)
	if st.x < 0:
		return false
	pos.y = stair_surface_y(st.x, st.y, pos.x)
	_set_state(S.STAIR_DESCENDING)
	return true


## Stepping from flat ground onto the foot of a staircase.
##
## This has to actually move her onto the stair tile and onto its surface. An
## earlier version only switched state, which left her standing one subunit
## short of the stair: the stair tick then found no stair beneath her, handed
## control straight back, and she juddered in place forever.
func _try_enter_stair_horizontal(ax: int) -> bool:
	var nx: int = pos.x + ax * STAIR_SPEED
	var tx_ahead: int = Grid.to_tile(nx)
	if tx_ahead == Grid.to_tile(pos.x):
		return false   # still inside the current tile; nothing to step onto
	var ty_feet: int = Grid.to_tile(pos.y - 1)
	for ty: int in [ty_feet, ty_feet + 1, ty_feet - 1]:
		var dir: int = map.stair_dir(tx_ahead, ty)
		if dir == 0:
			continue
		var ny: int = stair_surface_y(tx_ahead, ty, nx)
		if map.body_blocked(nx, ny):
			continue
		pos.x = nx
		pos.y = ny
		_set_state(S.STAIR_ASCENDING if dir == ax else S.STAIR_DESCENDING)
		return true
	return false


func _tick_stairs(inp: InputFrame) -> void:
	if jump_buffer > 0:
		_begin_jump()
		return
	var ax: int = inp.axis_x()
	if ax == 0:
		_set_state(S.IDLE)
		return
	facing = ax

	var st: Vector2i = _stair_tile_under(pos.x, pos.y)
	if st.x < 0:
		## Walked off the end of the staircase.
		_settle_after_stairs()
		return

	var dir: int = map.stair_dir(st.x, st.y)
	var nx: int = pos.x + ax * STAIR_SPEED
	var next_tx: int = Grid.to_tile(nx)
	var ny: int = 0
	if map.is_stair(next_tx, st.y):
		ny = stair_surface_y(next_tx, st.y, nx)
	else:
		## Crossing a tile boundary: look for the continuation one step up or
		## down, otherwise leave the staircase.
		var step_y: int = st.y - 1 if ax == dir else st.y + 1
		if map.is_stair(next_tx, step_y):
			ny = stair_surface_y(next_tx, step_y, nx)
		else:
			pos.x = nx
			pos.y = Grid.tile_origin(st.y) if ax == dir else Grid.tile_origin(st.y + 1)
			_settle_after_stairs()
			return

	if map.body_blocked(nx, ny):
		pos.x = Grid.snap_to_center(pos.x)
		_set_state(S.IDLE)
		return

	pos.x = nx
	pos.y = ny
	_set_state(S.STAIR_ASCENDING if ax == dir else S.STAIR_DESCENDING)


func _settle_after_stairs() -> void:
	if map.on_ground(pos.x, pos.y):
		_set_state(S.IDLE)
	else:
		_begin_fall()


# --- air ------------------------------------------------------------------

func _begin_jump() -> void:
	jump_buffer = 0
	coyote = 0
	vel_y = JUMP_V
	fall_start_y = pos.y
	_set_state(S.JUMPING)


func _begin_fall() -> void:
	if vel_y < 0:
		vel_y = 0
	fall_start_y = pos.y
	_set_state(S.FALLING)


func _tick_airborne(inp: InputFrame, rising: bool) -> void:
	if coyote > 0:
		coyote -= 1
	## Coyote time: a jump pressed just after walking off a ledge still
	## jumps. Without this the grid makes leaving a platform feel like a
	## trapdoor, because the tile boundary is exact and the player is not.
	if not rising and coyote > 0 and jump_buffer > 0:
		_begin_jump()
		return
	## Grabbing a ladder mid-air is how most vertical routes are entered.
	if inp.axis_y() != 0 and map.climb_at_anchor(pos.x, pos.y):
		_enter_ladder(S.CLIMBING if inp.axis_y() < 0 else S.DESCENDING)
		return

	if rising and not inp.is_held(InputFrame.B_JUMP) and vel_y < JUMP_CUT_V:
		vel_y = JUMP_CUT_V   # variable jump height

	var ax: int = inp.axis_x()
	if ax != 0:
		facing = ax
		pos.x += _move_x(pos.x, pos.y, ax * WALK_SPEED)

	vel_y = mini(vel_y + GRAVITY, TERMINAL_V)
	if rising and vel_y >= 0:
		fall_start_y = pos.y
		_set_state(S.FALLING)
	_move_y(vel_y)


func _tick_landing(inp: InputFrame) -> void:
	if state_ticks >= LANDING_TICKS:
		_set_state(S.IDLE)
		_tick_grounded(inp)


# --- ladders --------------------------------------------------------------

func _tick_ladder(inp: InputFrame) -> void:
	if jump_buffer > 0:
		_begin_jump()
		return

	var ax: int = inp.axis_x()
	if ax != 0:
		## Stepping off sideways. Only permitted onto something that is not
		## solid, otherwise the input is ignored rather than wedging her.
		facing = ax
		var nx: int = pos.x + ax * WALK_SPEED
		if not map.body_blocked(nx, pos.y):
			pos.x = nx
			## The step-off completes only once her ANCHOR is over the new
			## tile, and then snaps to that tile. Testing the body edges
			## instead would finish the step while she is still over the
			## ladder column, and snapping to the nearest centre would pull
			## her back onto the ladder, where there is no floor to stand on.
			var anchor_tx: int = Grid.to_tile(pos.x)
			if map.is_support(anchor_tx, Grid.to_tile(pos.y)):
				pos.x = Grid.tile_center(anchor_tx)
				_set_state(S.IDLE)
				return
			if _ladder_row() < 0:
				_begin_fall()
				return

	var ay: int = inp.axis_y()
	if ay == 0:
		return   # hanging still on the ladder

	if ay < 0:
		_climb_up()
	else:
		_climb_down()


## The row of the ladder tile the anchor is currently riding, or -1.
## The feet tile is preferred, but when she is resting exactly on the top
## boundary of a ladder the feet tile is the empty space above it, so the
## tile the anchor sits on counts too.
func _ladder_row() -> int:
	var tx: int = Grid.to_tile(pos.x)
	var feet: int = Grid.to_tile(pos.y - 1)
	if map.is_climb(tx, feet):
		return feet
	var under: int = Grid.to_tile(pos.y)
	if map.is_climb(tx, under):
		return under
	return -1


func _climb_up() -> void:
	var row: int = _ladder_row()
	if row < 0:
		_begin_fall()
		return
	## Find the top of this contiguous ladder run and refuse to climb past it.
	## Resting on that boundary leaves her feet level with the floor the
	## ladder serves, so she can simply walk off sideways.
	var tx: int = Grid.to_tile(pos.x)
	var top_row: int = row
	while map.is_climb(tx, top_row - 1):
		top_row -= 1
	var ny: int = maxi(pos.y - CLIMB_SPEED, Grid.tile_origin(top_row))
	if ny == pos.y or map.body_blocked(pos.x, ny):
		return
	pos.y = ny
	_set_state(S.CLIMBING)


func _climb_down() -> void:
	var ny: int = pos.y + CLIMB_SPEED
	if map.body_blocked(pos.x, ny):
		pos.y = Grid.snap_to_boundary(ny)
		_set_state(S.IDLE)
		return
	## Stepping off the bottom of the ladder onto the floor it stands on.
	for probe: int in range(pos.y + 1, ny + 1):
		if Grid.fmod_i(probe, Grid.TILE_SUB) == 0 and map.on_ground(pos.x, probe):
			pos.y = probe
			_set_state(S.IDLE)
			return
	pos.y = ny
	if _ladder_row() < 0:
		_begin_fall()
		return
	_set_state(S.DESCENDING)


# --- pushing --------------------------------------------------------------

func _try_begin_push(dir: int) -> bool:
	var ty: int = Grid.to_tile(pos.y - 1)
	var tx: int = Grid.to_tile(pos.x) + dir
	var target: Vector2i = Vector2i(tx, ty)
	if not TileDB.has(map.at(tx, ty), TileDB.F_PUSHABLE):
		return false
	if not hooks.can_push(target, dir):
		return false
	push_dir = dir
	push_tile = target
	_set_state(S.PUSHING)
	return true


func _tick_pushing(inp: InputFrame) -> void:
	if inp.axis_x() != push_dir:
		push_dir = 0
		pos.x = Grid.snap_to_center(pos.x)
		_set_state(S.IDLE)
		return
	if state_ticks < PUSH_TICKS:
		return
	hooks.do_push(push_tile, push_dir)
	pos.x += push_dir * Grid.TILE_SUB
	pos.x = Grid.snap_to_center(pos.x)
	push_dir = 0
	_set_state(S.IDLE)


# --- action ---------------------------------------------------------------

func _try_interact() -> bool:
	var t: Vector2i = tile()
	if hooks.try_interact(t, facing):
		interact_tile = t
		_set_state(S.INTERACTING)
		return true
	var ahead: Vector2i = t + Vector2i(facing, 0)
	if hooks.try_interact(ahead, facing):
		interact_tile = ahead
		_set_state(S.INTERACTING)
		return true
	return false


func _begin_attack() -> void:
	attack_hit = false
	_set_state(S.ATTACKING)


func _tick_attacking(_inp: InputFrame) -> void:
	if state_ticks == 1:
		attack_hit = hooks.try_attack(tile() + Vector2i(facing, 0), facing)
	if state_ticks >= ATTACK_TICKS:
		_set_state(S.IDLE)


func _tick_timed_return(ticks: int) -> void:
	if state_ticks >= ticks:
		_set_state(S.IDLE)


func _tick_hurt(_inp: InputFrame) -> void:
	vel_y = mini(vel_y + GRAVITY, TERMINAL_V)
	_move_y(vel_y)
	if state == S.HURT and state_ticks >= HURT_TICKS:
		_set_state(S.IDLE)


# --- damage ---------------------------------------------------------------

## Returns true if the damage was actually applied.
func apply_damage(amount: int, from_dir: int = 0) -> bool:
	if invuln > 0 or not is_alive() or state == S.LEVEL_COMPLETE:
		return false
	health -= amount
	invuln = INVULN_TICKS
	if health <= 0:
		health = 0
		_set_state(S.DYING)
		return true
	if from_dir != 0:
		facing = -from_dir
	_set_state(S.HURT)
	return true


func kill() -> void:
	if state == S.DYING or state == S.DEAD:
		return
	health = 0
	invuln = 0
	_set_state(S.DYING)


func complete_level() -> void:
	if can_transition(S.LEVEL_COMPLETE):
		_set_state(S.LEVEL_COMPLETE)


# --- swept movement -------------------------------------------------------

## Horizontal sweep. Returns how far the body may actually travel, stopping
## flush against the blocking tile rather than overlapping it.
func _move_x(ax: int, ay: int, delta: int) -> int:
	if delta == 0:
		return 0
	if not map.body_blocked(ax + delta, ay):
		return delta
	var step: int = 1 if delta > 0 else -1
	var travelled: int = 0
	while travelled != delta:
		if map.body_blocked(ax + travelled + step, ay):
			break
		travelled += step
	return travelled


## Vertical sweep, with landing and ceiling resolution.
func _move_y(delta: int) -> void:
	if delta == 0:
		return
	var step: int = 1 if delta > 0 else -1
	var travelled: int = 0
	while travelled != delta:
		var ny: int = pos.y + travelled + step
		if map.body_blocked(pos.x, ny):
			break
		if step > 0:
			## Landing: the feet crossing a tile boundary onto a support tile.
			if Grid.fmod_i(ny, Grid.TILE_SUB) == 0 and map.on_ground(pos.x, ny):
				pos.y = ny
				_land()
				return
			## Falling onto a staircase lands on its diagonal surface.
			var st: Vector2i = Vector2i(Grid.to_tile(pos.x), Grid.to_tile(ny))
			if map.is_stair(st.x, st.y):
				var surf: int = stair_surface_y(st.x, st.y, pos.x)
				if ny >= surf:
					pos.y = surf
					_land()
					return
		travelled += step
	pos.y += travelled
	if travelled == delta:
		return
	if step < 0:
		vel_y = 0        # bonked a ceiling
	else:
		_land()


func _land() -> void:
	var fell: int = pos.y - fall_start_y
	vel_y = 0
	coyote = COYOTE_TICKS
	if state == S.HURT:
		return
	if fell > FALL_DAMAGE_SUB and apply_damage(1, 0):
		return
	if can_transition(S.LANDING):
		_set_state(S.LANDING)
	elif can_transition(S.IDLE):
		_set_state(S.IDLE)


# --- snapshot (checkpoints, puzzle reset, replay) -------------------------

func snapshot() -> Dictionary:
	return {
		"pos_x": pos.x, "pos_y": pos.y, "vel_y": vel_y, "facing": facing,
		"state": state, "state_ticks": state_ticks, "health": health,
		"invuln": invuln, "coyote": coyote, "jump_buffer": jump_buffer,
		"fall_start_y": fall_start_y, "push_dir": push_dir,
	}


func restore(s: Dictionary) -> void:
	pos = Vector2i(int(s["pos_x"]), int(s["pos_y"]))
	vel_y = int(s["vel_y"])
	facing = int(s["facing"])
	health = int(s["health"])
	invuln = int(s["invuln"])
	coyote = int(s["coyote"])
	jump_buffer = int(s["jump_buffer"])
	fall_start_y = int(s["fall_start_y"])
	push_dir = int(s["push_dir"])
	_force_state(int(s["state"]))
	state_ticks = int(s["state_ticks"])
