extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const Projectile := preload("res://Scripts/Core/Projectile.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")

## The simulation. Owns every mutation of a CombatUnit and every event emitted.
##
## OWNER: wren. Files under Scripts/Combat/ are wren's. Nobody else edits them.
##
## The contract the rest of the project is built against:
##
##   var state := CombatSim.build(party, encounter, seed)
##   while state.outcome == CombatState.Outcome.UNRESOLVED:
##       CombatSim.step(state)
##
## `step` advances exactly one tick and must be pure with respect to everything
## outside `state`. Same seed plus same inputs, same fight, every time.
##
## `deps` is optional on every entry point and defaults to the real content
## system (SimDeps.new() wires to Balance and Registry). Tests pass their own
## SimDeps and never touch Balance, Registry or a single registered class,
## action or enemy.

## Layout-only fallback spacing for party members past the encounter's spawn
## list. Not a combat number: nothing here affects hp, damage or speed.
const _FALLBACK_SPAWN_SPACING := 32.0

## Builds the starting state: places both sides, derives hp and resources
## through `deps`, and emits FIGHT_START.
static func build(party: Array[PawnData], encounter: Encounter, fight_seed: int, deps: SimDeps = null) -> CombatState:
	if deps == null:
		deps = SimDeps.new()
	var state := CombatState.new(fight_seed)
	state.terrain = encounter.terrain
	var next_id := 0

	for i in party.size():
		var unit := _build_player_unit(next_id, party[i], party_spawn_position(encounter, i), deps)
		state.units.append(unit)
		next_id += 1

	for spawn in encounter.enemy_spawns:
		var enemy_id: StringName = spawn.get("enemy_id", &"")
		var pos: Vector2 = spawn.get("position", Vector2.ZERO)
		var enemy_def: EnemyDef = deps.enemy_lookup.call(enemy_id)
		var unit := _build_enemy_unit(next_id, enemy_def, enemy_id, pos)
		state.units.append(unit)
		next_id += 1

	state.emit(_event(CG.EventKind.FIGHT_START, 0, -1, -1, &""))
	return state

## Advances one tick. Order within a tick is itself a contract, because
## changing it changes every fight: decide intents for all units from the state
## as it was at the start of the tick, then resolve them in unit id order, then
## tick statuses and cooldowns, then check the outcome.
static func step(state: CombatState, deps: SimDeps = null) -> void:
	if state.outcome != CombatState.Outcome.UNRESOLVED:
		return
	if deps == null:
		deps = SimDeps.new()
	state.tick += 1
	_decide_phase(state, deps)
	_resolve_phase(state, deps)
	_tick_phase(state, deps)
	_tick_projectiles(state, deps)
	_check_outcome(state, deps)

## Runs to completion. Used by tests and by the headless balance checks; the
## battle view calls step() itself so it can draw between ticks.
static func run(state: CombatState, deps: SimDeps = null) -> CombatState.Outcome:
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		step(state, deps)
	return state.outcome

# ---------------------------------------------------------------------------
# build() helpers
# ---------------------------------------------------------------------------

## Public since issue 145, on finch's `default_attack_action` precedent: the
## deploy screen has to open showing where each pawn *would* have started, and a
## screen that reimplemented the overflow rule would drift from the fight it is
## meant to be previewing. One rule, asked rather than copied.
static func party_spawn_position(encounter: Encounter, index: int) -> Vector2:
	if index < encounter.party_spawns.size():
		return encounter.party_spawns[index]
	var base := Vector2.ZERO
	if not encounter.party_spawns.is_empty():
		base = encounter.party_spawns[encounter.party_spawns.size() - 1]
	var overflow := index - encounter.party_spawns.size() + 1
	return base + Vector2(float(overflow) * _FALLBACK_SPAWN_SPACING, 0.0)

static func _build_player_unit(id: int, pawn: PawnData, pos: Vector2, deps: SimDeps) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.display_name = pawn.display_name
	u.pawn = pawn
	u.position = pos
	u.hp_max = int(deps.max_hp.call(pawn))
	u.hp = u.hp_max
	u.resource_max = int(deps.max_resource.call(pawn))
	u.resource_kind = pawn.pawn_class.resource_kind if pawn.pawn_class != null else CG.ResourceKind.ENERGY
	## Issue 164. Mana opens full, Rage and Energy at zero -- a caster that cannot
	## cast on tick one is not playing the first half of the fight, and a Rage
	## class that opens full never has to earn its finisher.
	##
	## Set after `resource_kind` on purpose: it is the input. This was
	## `u.resource = u.resource_max` immediately after `resource_max`, so moving
	## the assignment down is load-bearing rather than tidying.
	##
	## THE ENEMY BRANCH DELIBERATELY DOES NOT CHANGE. rook's ruling: the player's
	## paragraph is about mana classes, and changing `_build_enemy_unit` because
	## it is the same line would be an unasked balance change while balance is
	## frozen.
	u.resource = int(deps.starting_resource.call(u.resource_kind, u.resource_max))
	u.move_speed = float(deps.move_speed.call(pawn))
	u.actions = _collect_player_actions(pawn)
	return u

static func _collect_player_actions(pawn: PawnData) -> Array[StringName]:
	var out: Array[StringName] = []
	if pawn.pawn_class != null:
		for a in pawn.pawn_class.starting_actions:
			if not out.has(a):
				out.append(a)
	for e in pawn.equipment():
		for a in e.granted_actions:
			if not out.has(a):
				out.append(a)
	return out

static func _build_enemy_unit(id: int, enemy_def: EnemyDef, enemy_id: StringName, pos: Vector2, team: CG.Team = CG.Team.ENEMY) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.enemy_id = enemy_id
	u.position = pos
	if enemy_def == null:
		push_error("CombatSim.build: unknown enemy id '%s'" % enemy_id)
		u.display_name = String(enemy_id)
		u.hp_max = 1
		u.hp = 1
		return u
	u.display_name = enemy_def.display_name
	u.radius = enemy_def.radius
	u.hp_max = enemy_def.hp_max
	u.hp = u.hp_max
	u.resource_max = enemy_def.resource_max
	u.resource = u.resource_max
	u.resource_kind = enemy_def.resource_kind
	u.move_speed = enemy_def.move_speed
	u.actions = enemy_def.actions.duplicate()
	## EnemyDef.spawn_taunt_radius's own doc comment: a non-pawn unit's action
	## list only ever runs one fixed action, so it cannot rotate between
	## "taunt" and "attack" the way a plan-driven pawn can -- a summoned siege
	## engine that needs to draw fire gets TAUNTING applied here, at spawn,
	## rather than through an action it would then never be able to also
	## attack with. CG.MAX_TICKS as the expiry is "outlives the fight" -- a
	## fight cannot run longer than that tick, so this never has to be
	## refreshed or read as having expired mid-fight. Shared by both call
	## sites of _build_enemy_unit (an ordinary encounter spawn in build() and
	## a mid-fight _spawn_summon), on purpose: content decides via the
	## EnemyDef, not via which path built the unit.
	if enemy_def.spawn_taunt_radius > 0.0:
		u.statuses[CG.Status.TAUNTING] = CG.MAX_TICKS
		u.taunt_radius = enemy_def.spawn_taunt_radius
	return u

# ---------------------------------------------------------------------------
# decide
# ---------------------------------------------------------------------------

static func _decide_phase(state: CombatState, deps: SimDeps) -> void:
	for unit in state.units:
		if not unit.alive:
			continue
		## Checked BEFORE the busy guard, which is the whole of the #121 change.
		## It used to sit after it, so a unit already mid-wind-up was never
		## reached and its action fired on schedule.
		if unit.has_status(CG.Status.STUN):
			_interrupt_on_stun(state, unit)
			continue
		if unit.intent != null or unit.is_busy():
			continue
		## THE COMPULSION, and it sits here rather than in the decision layer
		## for one reason: it has to beat a stated plan. See `_compelling_taunter`.
		var taunter := _compelling_taunter(state, unit)
		if taunter != null:
			unit.intent = _compelled_intent(unit, taunter, deps)
			_reaffirm_sustain(state, unit, unit.intent)
			continue
		var intent: Intent = null
		if unit.pawn != null:
			intent = deps.plan_decide.call(state, unit)
		if intent == null:
			intent = deps.default_decide.call(state, unit)
		unit.intent = intent
		_reaffirm_sustain(state, unit, intent)

## A stunned unit neither decides nor acts, and as of #121 it does not finish
## what it had already started either.
##
## ISSUE 10'S DECISION, OVERTURNED BY THE PLAYER. Kept here rather than deleted,
## because the reasoning behind the original call is still worth knowing and the
## costs it named are the costs we now pay.
##
## What it used to say, and it was deliberate: stun did NOT cancel an action
## already committed before it landed. A unit mid-wind-up when stunned still
## fired on schedule -- `is_busy()` kept it out of this loop entirely, so the
## status only ever mattered for a unit that was free to decide. The argument
## was that a wind-up safe once committed is the simpler thing to teach ("land
## the stun before the swing starts, not during it"), and that cancelling one
## costs a resource-refund policy, a decision about whether the original target
## still matters, and a way for content to reason about "was this interrupted".
##
## The player's ruling, in their words: *"Stun should very much interrupt actions
## in progress"*. Which is the ordinary meaning of the word, and a stun that
## cannot interrupt a cast is a much weaker thing than a player expects when a
## boss lands one. heron measured the old behaviour live before anybody argued
## about it -- stunned mid-wind-up, the action still fired -- which is what
## turned this from a reading of the code into a question worth putting to the
## player.
##
## The three costs the old comment named, now answered, and the player answered
## all three rather than us:
##
##   1. **The wind-up is lost, not resumed.** Resuming is nearly invisible to
##      somebody watching, and "broadly follow what happened and why" is the
##      finish line this project is measured against.
##   2. **The resource is NOT refunded.** `RESOURCE_SPENT` fired at commit and
##      nothing reverses it. A twenty-Mana cast producing nothing is harsh on
##      purpose: that is what makes landing a stun on a caster worth doing.
##   3. **The original target stops mattering**, because there is no longer an
##      action to aim. `focus_id` is left alone -- it is where the unit is
##      looking, not a pending commitment, and it is overwritten by whatever the
##      unit commits to next.
##
## Cooldown needs no refund and could not have one: `_fire_action` sets it, and
## an interrupted action never fires, so it was never on cooldown.
##
## RECOVERY IS DELIBERATELY NOT CANCELLED. Only `action_ticks_left`, the wind-up,
## is thrown away. Cancelling recovery would *help* the stunned unit -- it would
## come out of the stun free to act instead of finishing what it owed -- and an
## interrupt that rewards its victim is not an interrupt.
##
## ISSUE 61 is unchanged and its reasoning still stands on its own: a stun breaks
## a sustained action, because a channel is a decision renewed every tick and a
## unit that neither decides nor acts is by definition not renewing one. That was
## true when a wind-up survived and it is true now.
##
## Emits INTERRUPTED once, on the tick the action is taken away, and never again
## for the same stun -- the second tick of a stun finds nothing left to cancel.
## `amount` is the ticks of wind-up already invested and thereby thrown away,
## which is not recoverable after the fact for the same reason
## `CombatUnit.action_ticks_total` had to exist at all: HASTE scales the real
## count at commit, so the number on the ActionDef is not it.
static func _interrupt_on_stun(state: CombatState, unit: CombatUnit) -> void:
	unit.intent = null
	if unit.action_ticks_left > 0:
		var e := _event(CG.EventKind.INTERRUPTED, state.tick, unit.id, -1, unit.current_action)
		e.amount = maxi(0, unit.action_ticks_total - unit.action_ticks_left)
		state.emit(e)
		unit.current_action = &""
		unit.action_ticks_left = 0
		unit.action_ticks_total = 0
	_end_sustain(state, unit)

# ---------------------------------------------------------------------------
# taunt as a compulsion (issues 58, 121, 132)
# ---------------------------------------------------------------------------
#
# The player: *"Taunted pawns should be forced to move into range and use their
# default attack on the enemy that taunted them."*
#
# WHY THIS IS IN THE SIMULATION AND NOT IN THE DECISION LAYER. Taunt already
# influenced targeting, in `DefaultBehavior._choose_target`, under an earlier
# ruling of rook's: *taunt overrides the default fallback, never a stated plan*.
# That is enforced by construction, because `DefaultBehavior` never runs when a
# plan fired -- and it is exactly why the Brute's roar was decorative. **Every
# player pawn has a plan.** A taunt that only moves unplanned units taunts
# nobody the player controls, in the one situation the ability exists for.
#
# rook's ruling was made before the player stated theirs and has been withdrawn
# in favour of it. A compulsion that must beat a plan cannot live in the thing
# that only runs when no plan fired, so it lives here, next to STUN -- which is
# the same shape already: a status that overrides whatever the decision layer
# would have said. One rule covers planned pawns and unplanned enemies rather
# than two that can disagree.
#
# THIS IS NOT A HIDDEN RULE, which is the CLAUDE.md principle it has to answer
# to. A compelled unit carries a TAUNTED badge for exactly as long as it is
# compelled, and a STATUS_APPLIED event names who taunted it and when. The pawn
# is visibly not following its plan, and the reason is on the pawn. That is the
# difference between a compulsion and the automatic kiting branch this project
# deleted: one is a legible status a player can counter, the other was an
# unwritten rule nobody could see or change.

## Who this unit is compelled by, or null.
##
## The taunter's id is kept in `status_magnitude[TAUNTED]`, which is the
## "a status remembers something" mechanism from #130 doing a second job rather
## than a second mechanism being built beside it.
##
## A DEAD TAUNTER FREES ITS VICTIMS IMMEDIATELY, and says so with a
## STATUS_EXPIRED rather than leaving a badge on a pawn that is no longer
## compelled. Killing the Brute is the other counter to its roar, and a player
## who cannot see that it worked has not been given the counter.
static func _compelling_taunter(state: CombatState, unit: CombatUnit) -> CombatUnit:
	if not unit.has_status(CG.Status.TAUNTED):
		return null
	var taunter := state.unit(int(unit.status_magnitude.get(CG.Status.TAUNTED, -1.0)))
	if taunter != null and taunter.alive:
		return taunter
	_remove_status(unit, CG.Status.TAUNTED)
	var e := _event(CG.EventKind.STATUS_EXPIRED, state.tick, -1, unit.id, &"")
	e.status = CG.Status.TAUNTED
	state.emit(e)
	return null

## Move into range, then use the default attack on the taunter. Exactly the
## player's sentence, and nothing else -- a compelled unit is not made to stop
## healing itself or to walk into a pit, it is made to pick one target.
##
## `deps.default_attack_action` is `DefaultBehavior.default_attack_action`, which
## is public for precisely this reason: its own doc comment records that a
## *copy* of "which attack does this unit fall back to" has already gone stale
## twice on this project, and that one shared definition is the fix. This is now
## its third caller and it does not get a fourth copy of the rule.
##
## Which SIDE (melee or ranged) is decided here by whether the melee option can
## actually reach, which is a simpler rule than `_choose_attack_action`'s commit
## fraction and is stated rather than borrowed. A unit with one attack -- every
## unit in the game but The Warden -- takes the same branch either way.
##
## A unit with no attack at all is still dragged into range. It has been taunted;
## it just has nothing to answer with.
static func _compelled_intent(unit: CombatUnit, taunter: CombatUnit, deps: SimDeps) -> Intent:
	var defs: Array[ActionDef] = []
	for id in unit.actions:
		var a: ActionDef = deps.action_lookup.call(id)
		if a != null:
			defs.append(a)
	var dist := unit.position.distance_to(taunter.position)
	var melee: ActionDef = deps.default_attack_action.call(defs, false)
	var ranged: ActionDef = deps.default_attack_action.call(defs, true)
	var chosen: ActionDef = melee
	if melee == null or dist > melee.range_units:
		chosen = ranged if ranged != null else melee
	## Issue 155: both carry `Intent.COMPELLED` so the log can say the pawn was
	## dragged rather than letting a compulsion look like the fallback deciding.
	if chosen == null or dist > chosen.range_units:
		return Intent.move_to(taunter.position, Intent.COMPELLED)
	return Intent.use_action(chosen.id, taunter.id, Intent.COMPELLED)

## Puts TAUNTED on everyone the taunt reaches, at the moment it is applied.
##
## A ONE-SHOT BROADCAST, not a membership test re-run every tick. That is what
## makes the player's two other rulings true at once: the status carries a real
## duration, so nothing is locked permanently, and **a cleanse actually frees the
## pawn** instead of being overwritten again on the following tick. A
## per-tick-membership taunt (the shape `_tick_hazards` uses for standing in
## fire) would make cleansing it pointless, which would contradict the ruling
## that cleansing is the counter.
##
## ENEMIES MUST NOT DOUBLE-TAUNT, per the player, and it is enforced here as a
## property of the mechanism rather than as cleverness in enemy targeting: a unit
## already compelled by a **living** taunter is skipped, so a second roar cannot
## steal it and cannot refresh it. Two Brutes therefore split a party instead of
## piling onto one pawn, without either of them having to know the other exists.
## (The other half -- an enemy not *wasting* the cast in the first place -- is a
## decision, and lives in `Scripts/Plans`.)
##
## `state.living` order is `state.units` order, so two runs from one seed taunt
## the same units in the same order. Nothing random is consulted.
static func _broadcast_taunt(state: CombatState, taunter: CombatUnit, ticks: int) -> void:
	if taunter.taunt_radius <= 0.0 or ticks <= 0:
		return
	for victim in state.living(_enemy_team(taunter.team)):
		if taunter.position.distance_to(victim.position) > taunter.taunt_radius:
			continue
		if _compelling_taunter(state, victim) != null:
			continue
		victim.statuses[CG.Status.TAUNTED] = state.tick + ticks
		victim.status_magnitude[CG.Status.TAUNTED] = float(taunter.id)
		var e := _event(CG.EventKind.STATUS_APPLIED, state.tick, taunter.id, victim.id, &"")
		e.status = CG.Status.TAUNTED
		state.emit(e)

# ---------------------------------------------------------------------------
# resolve
# ---------------------------------------------------------------------------

static func _resolve_phase(state: CombatState, deps: SimDeps) -> void:
	for unit in state.units:
		if not unit.alive:
			continue
		var intent := unit.intent
		if intent == null:
			continue
		unit.intent = null
		match intent.kind:
			CG.IntentKind.MOVE_TO:
				_resolve_move(state, unit, intent, deps)
			CG.IntentKind.USE_ACTION:
				_resolve_use_action(state, unit, intent, deps)
			_:
				_resolve_idle(state, unit, deps)

## Issue 132: THE FIRST THING IN THIS SIMULATION THAT TRADES TIME FOR RESOURCE.
##
## A unit that spends its tick doing nothing recovers resource faster than one
## that spends it moving or fighting. Everything else in this game gives
## resource back on a clock (`_tick_regen`) or for landing a hit
## (`_on_hit_landed`); nothing has ever made *standing still* a choice worth
## making, so "wait for mana" has not been a thing a plan could express.
##
## Applied here, in the IDLE branch of `_resolve_phase`, rather than in
## `_tick_phase` beside `_tick_regen`. That is deliberate and it is the reason
## no `CombatUnit` field was needed: by the time `_tick_phase` runs, the intent
## has already been consumed and cleared, so "did this unit idle" is a fact that
## only exists at this exact point. Recording it on the unit to read one phase
## later would be a second copy of something the intent already says.
##
## It stacks with `_tick_regen` rather than replacing it: an idling unit gets
## the ordinary tick of regeneration in `_tick_phase` and this on top. So the
## seam is a *multiplier on the ordinary rate*, and the number it means is
## "how many times faster does waiting refill you".
##
## INERT BY DEFAULT AND PROVABLY SO. `SimDeps.idle_resource_regen_scale`
## defaults to 1.0, which makes `extra` exactly 0.0, which returns before
## `_stochastic_round` is reached and therefore **before `state.rng` is
## touched**. That last part is what keeps every existing measurement valid:
## consuming one more random number per idle tick would reshuffle the rng stream
## and change every fight in the game, which is a far bigger change than the
## feature. Checked by test, not reasoned about.
##
## RAGE is skipped, structurally, the same way `_tick_regen` skips it and for
## the same reason: Rage is earned by landing hits. A berserker filling up by
## standing still would undo the whole point of the resource, and enforcing that
## here rather than trusting the rate function means a content mistake cannot
## reintroduce it.
##
## NO EVENT IS EMITTED, deliberately. This fires on most ticks of most fights
## for any waiting unit, which is exactly the volume argument that puts
## RESOURCE_SPENT on the log's silent list. The resource bar already shows the
## number moving. If it turns out a player cannot tell "my pawn is waiting on
## purpose" from "my pawn is stuck", the fix is one event kind and I would
## rather add it against a measured complaint than flood the log in advance.
static func _resolve_idle(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	if unit.resource_kind == CG.ResourceKind.RAGE:
		return
	if unit.resource >= unit.resource_max:
		return
	var scale: float = deps.idle_resource_regen_scale.call(unit)
	if scale <= 1.0:
		return
	var base: float = deps.resource_regen_per_tick.call(unit)
	var gained := _stochastic_round(state, base * (scale - 1.0))
	if gained > 0:
		unit.resource = clampi(unit.resource + gained, 0, unit.resource_max)

## No pathfinding: a unit that cannot take its full step tries sliding along
## one axis at a time, and stays put only if neither axis is clear either.
## Enough for a room built from a few rectangles, per issue 13a's own scope;
## a unit that genuinely cannot route around an obstacle is a finding to
## report, not a pathfinder to build.
static func _resolve_move(state: CombatState, unit: CombatUnit, intent: Intent, deps: SimDeps) -> void:
	var before := unit.position
	var to_dest := intent.destination - unit.position
	var dist := to_dest.length()
	var speed := _effective_move_speed(unit, deps)
	var step: Vector2
	if dist <= speed or dist <= 0.0001:
		step = to_dest
	else:
		step = to_dest.normalized() * speed

	var direct := _sweep(state, unit, step)
	if direct != unit.position:
		unit.position = _avoid_hazard(state, unit, to_dest, speed, direct)
		_update_facing_from_movement(unit, before)
		return

	# The direct step made no progress at all (blocked immediately, not just
	# short of the full distance). Try sliding along one axis instead of
	# freezing.
	#
	# Issue 30: this used to slide with Vector2(step.x, 0.0) / Vector2(0.0,
	# step.y) -- the x/y *component* of the diagonal step, not a full step on
	# that axis. Near a corner where one axis is fully blocked, the unit's
	# remaining distance is dominated by the blocked axis, so the angle to
	# the target keeps flattening as the open axis closes in -- and the open
	# axis's component of a fixed-length diagonal shrinks with that angle.
	# The result was a real, measured, unit ever more slowly and never
	# hitting zero within any fixed number of ticks: an asymptote a 3600-tick
	# fight cap can't tell from frozen. Each axis now gets its own full
	# move_speed (capped at how far it actually has left to go on that axis
	# alone), so slide progress no longer depends on the angle of a step it
	# isn't taking.
	var slide_x := _sweep(state, unit, Vector2(_axis_step(to_dest.x, speed), 0.0))
	var slide_y := _sweep(state, unit, Vector2(0.0, _axis_step(to_dest.y, speed)))
	var moved_x := slide_x != unit.position
	var moved_y := slide_y != unit.position

	if moved_x and moved_y:
		unit.position = slide_x if absf(step.x) >= absf(step.y) else slide_y
	elif moved_x:
		unit.position = slide_x
	elif moved_y:
		unit.position = slide_y
	# else: fully blocked in every direction this tick. Stay put.
	_update_facing_from_movement(unit, before)

## Issue 163: a step that would end in fire gives way to a clear one, when a
## clear one exists that still makes progress.
##
## `_sweep` has always refused to LAND a unit inside a wall. It never had an
## opinion about a hazard, because a hazard does not block -- so a unit walked
## the straight line into fire and stood in it. heron measured the cost: 20hp
## units dead on tick 48 and tick 68 of EVERY seed in `floor1_hazard`, and the
## room's two authored safe lanes were content nothing in the game could use.
##
## THIS IS NOT PATHFINDING and does not become it. It considers exactly the two
## axis slides `_resolve_move` already computes for the wall case, and it walks
## into the fire when neither is better. A unit boxed in by a hazard burns, which
## is the honest outcome for a room authored that way.
##
## THE ANTI-OSCILLATION RULE IS THE LOAD-BEARING PART, and it is here because
## this project has already paid for the alternative: heron found a two-tick
## limit cycle in `DefaultBehavior` where an approach branch and a kite branch
## had no hysteresis between them, and a fight hung for 2400 ticks firing not one
## shot. **A detour is only taken if it strictly reduces the distance to the
## destination.** Progress is therefore monotonic and a unit cannot trade places
## between two steps forever.
##
## A unit ALREADY standing in a hazard is not helped by this and should not be:
## every candidate is measured for where it lands, so a burning unit takes
## whichever step gets it out, and the straight line out is usually it.
##
## NO EVENT. The cause is drawn on the floor -- a unit curving around a lit
## hazard explains itself in a way a retreat does not -- and this would fire on
## most ticks of most crossings, which is the flood argument that keeps
## RESOURCE_SPENT off the log. Posted on the board rather than decided quietly;
## one event kind if the ruling goes the other way.
static func _avoid_hazard(state: CombatState, unit: CombatUnit, to_dest: Vector2, speed: float, direct: Vector2) -> Vector2:
	if state.terrain.is_empty() or not _hazard_harms(state, direct):
		return direct
	var goal := unit.position + to_dest
	if to_dest.length() <= 0.0001:
		return direct
	var step_direction := to_dest.normalized()
	var best := direct
	var best_gap := goal.distance_to(unit.position)
	## The candidates are the step turned 45 degrees each way, then the two axis
	## slides `_resolve_move` already computes for the wall case.
	##
	## The turned steps are the ones that do the work, and the axis slides alone
	## could not: `_axis_step` returns zero on an axis with nothing left to close,
	## so a unit walking due east at a fire dead ahead is offered no lateral
	## candidate at all. Measured -- it stood in the fire for 8 ticks and took 40
	## damage with this function already in place.
	##
	## 45 rather than 90 because a right-angle sidestep makes no progress toward
	## the destination and is therefore refused by the monotonic rule below, which
	## is exactly the rule that keeps this from oscillating. A 45-degree turn
	## still closes on the goal (by cos 45 of the step) while clearing the
	## obstacle sideways, so skirting and progress are the same movement rather
	## than two that have to alternate.
	var turn := step_direction.rotated(PI / 4.0) * speed
	var turn_back := step_direction.rotated(-PI / 4.0) * speed
	for candidate in [
		_sweep(state, unit, turn),
		_sweep(state, unit, turn_back),
		_sweep(state, unit, Vector2(_axis_step(to_dest.x, speed), 0.0)),
		_sweep(state, unit, Vector2(0.0, _axis_step(to_dest.y, speed))),
	]:
		if candidate == unit.position or _hazard_harms(state, candidate):
			continue
		var gap := goal.distance_to(candidate)
		if gap < best_gap:
			best_gap = gap
			best = candidate
	return best

## Whether standing at `p` costs a unit anything. Damage or a status -- a tar pit
## deals no damage at all and is still somewhere a unit should rather not stand,
## so both count, and a decorative hazard authored with neither is correctly
## ignored.
static func _hazard_harms(state: CombatState, p: Vector2) -> bool:
	for hazard in Terrain.hazards_at(state.terrain, p):
		if hazard.damage_per_tick > 0:
			return true
		if hazard.applies_status_enabled and hazard.status_duration_ticks > 0:
			return true
	return false

## `CombatUnit.facing` only changes when a unit actually displaces this tick --
## a blocked or idle unit keeps whatever it last faced rather than snapping to
## zero, so SHIELDING's front-arc check still has something meaningful to read
## while a unit is stalled at a wall or fully boxed in.
static func _update_facing_from_movement(unit: CombatUnit, before: Vector2) -> void:
	if unit.position != before:
		unit.facing = (unit.position - before).normalized()

## Set at the moment a unit commits to USE_ACTION, alongside focus_id, so it
## persists through the wind-up the same way focus_id already does -- a unit
## keeps facing what it is fighting for the whole time it is committed to
## hitting it, not just the instant it decided to. Left unchanged if the
## target id does not resolve to a living unit (nothing to face) or the unit
## is already standing exactly on top of it (no direction to derive).
static func _update_facing_toward(state: CombatState, unit: CombatUnit, target_id: int) -> void:
	var target := state.unit(target_id)
	if target == null:
		return
	var dir := target.position - unit.position
	if dir.length() > 0.0001:
		unit.facing = dir.normalized()

## A single axis's full step: move_speed toward `remaining`, capped so it
## does not overshoot the destination on that axis alone. Zero if there is
## nothing left to close on this axis.
static func _axis_step(remaining: float, move_speed: float) -> float:
	return clampf(remaining, -move_speed, move_speed)

## Issue 14: SLOWED scales movement the same way HASTE already scales action
## ticks -- deps.slowed_speed_scale is a SimDeps seam, not a hardcoded
## multiplier, so content owns the number. Read fresh every time a move
## resolves rather than cached on the unit, so applying or removing SLOWED
## mid-fight changes the very next step rather than reaching back into one
## already computed.
##
## Deliberately the only place `unit.move_speed` gets touched for movement.
## `unit.move_speed` itself is set once in build() from deps.move_speed and
## never mutated -- SLOWED is a per-tick read-time multiplier, not a write to
## the unit, which is what lets it expire cleanly with nothing to restore.
static func _effective_move_speed(unit: CombatUnit, deps: SimDeps) -> float:
	if not unit.has_status(CG.Status.SLOWED):
		return unit.move_speed
	var scale: float = deps.slowed_speed_scale.call(unit)
	return maxf(0.0, unit.move_speed * scale)

## Walks `step` in small increments and returns the furthest point actually
## reached before hitting something solid -- `unit.position` unchanged if
## even the first increment is blocked. This is what stops a unit faster
## than a wall is thick from tunneling straight through it:
## `Terrain.point_is_blocked` alone only checks the landing point, and a
## single large jump can clear a thin wall without either endpoint ever
## registering as inside it. Doubles as "stop at the wall" for a head-on
## approach with no clear slide axis, which is the "stop" half of "slide
## along it or stop" -- no pathfinding, just don't pass through.
const _MOVE_SWEEP_STEP := 4.0

static func _sweep(state: CombatState, unit: CombatUnit, step: Vector2) -> Vector2:
	var length := step.length()
	if length <= 0.0001:
		return unit.position
	var direction := step / length
	var travelled := 0.0
	var last_good := unit.position
	while travelled < length:
		travelled = minf(travelled + _MOVE_SWEEP_STEP, length)
		var candidate := _clamp_to_arena(unit.position + direction * travelled)
		if Terrain.point_is_blocked(state.terrain, candidate, unit.radius):
			break
		last_good = candidate
	return last_good

## Nothing previously compared a unit's position to the arena bounds, so a
## unit told to walk past the edge just kept going -- issue 16 measured
## survivors twenty arena widths off the map after a full fight. Clamped
## here, in the simulation, not in the view: the view drawing a unit at the
## edge while the simulation thinks it is elsewhere would be worse than the
## bug it replaces. A destination outside the arena still moves the unit
## partway (whatever move_speed allows) and lands it on the boundary rather
## than refusing to move at all.
static func _clamp_to_arena(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, -CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_WIDTH),
		clampf(p.y, -CG.ARENA_HALF_HEIGHT, CG.ARENA_HALF_HEIGHT)
	)

## HASTE scales wind-up and recovery ticks by deps.haste_tick_scale, floored
## at 1 tick so a hasted unit can never act instantaneously. Read at the
## moment ticks are computed (commit for wind-up, landing for recovery), not
## cached, so HASTE applied or removed mid-action changes the *next*
## computation rather than reaching back into one already in flight.
static func _apply_haste(unit: CombatUnit, deps: SimDeps, ticks: int) -> int:
	if ticks <= 0 or not unit.has_status(CG.Status.HASTE):
		return ticks
	var scale: float = deps.haste_tick_scale.call(unit)
	return maxi(1, int(round(float(ticks) * scale)))

static func _resolve_use_action(state: CombatState, unit: CombatUnit, intent: Intent, deps: SimDeps) -> void:
	var action: ActionDef = deps.action_lookup.call(intent.action_id)
	if action == null:
		push_error("CombatSim: unit %d tried unknown action '%s'" % [unit.id, intent.action_id])
		return

	## Issue 61: the plan choosing a sustained action the unit is *already*
	## holding is the re-affirmation that keeps the channel alive, and it must
	## not also re-commit. Without this the unit would pay `resource_cost`,
	## restart its wind-up and refresh its cooldown on every single tick of the
	## channel, which would make holding an action strictly more expensive than
	## firing it and would mean it never actually ticked.
	##
	## Checked before the affordability and cooldown gates below on purpose: a
	## cooldown on a sustained action must not be able to interrupt one already
	## running. (Content should not put a cooldown on one at all --
	## `PlanInterpreter.can_afford` would refuse to re-choose it and the channel
	## would end itself on the next free tick. `Tests/test_combat_sustain.gd`
	## asserts no authored action does.)
	if action.sustain_cost_per_tick > 0 and unit.sustaining == action.id:
		return

	if unit.resource < action.resource_cost:
		return
	if unit.cooldowns.has(action.id) and state.tick < int(unit.cooldowns[action.id]):
		return

	## The seam's only reuse of an existing CombatUnit field: focus_id becomes
	## the in-flight action's target for the duration of the wind-up, which is
	## what lets range be measured again when the effect lands rather than at
	## commit. PlanInterpreter is free to set it ahead of an ACTION block; this
	## overwrites it with where the action actually aims, which is the same
	## value except when a targeting block aimed this one action elsewhere.
	unit.focus_id = intent.target_id
	_update_facing_toward(state, unit, intent.target_id)
	unit.current_action = action.id
	unit.action_ticks_left = _apply_haste(unit, deps, int(deps.wind_up_ticks.call(unit, action)))
	unit.action_ticks_total = unit.action_ticks_left

	if action.resource_cost > 0:
		unit.resource -= action.resource_cost
		var spent := _event(CG.EventKind.RESOURCE_SPENT, state.tick, unit.id, -1, action.id)
		spent.amount = action.resource_cost
		state.emit(spent)

	## Issue 155: the one place the decision layer's answer survives its own tick.
	## The intent is cleared by `_resolve_phase` immediately after this call, so
	## if the reason does not ride out on this event it is gone.
	var started := _event(CG.EventKind.ACTION_START, state.tick, unit.id, intent.target_id, action.id)
	started.source_plan = intent.source_plan
	state.emit(started)

	if unit.action_ticks_left <= 0:
		_fire_action(state, unit, action, deps)

# ---------------------------------------------------------------------------
# tick: wind-ups, recovery, statuses
# ---------------------------------------------------------------------------

static func _tick_phase(state: CombatState, deps: SimDeps) -> void:
	for unit in state.units:
		if not unit.alive:
			## Issue 61: a channel does not outlive its caster. Deaths land in
			## several places -- an attack in `_resolve_phase`, a DOT or a hazard
			## or somebody else's aura later in this same loop -- so this is
			## checked at the one point every dead unit passes through on every
			## tick, rather than beside each of them.
			if unit.sustaining != &"":
				_end_sustain(state, unit)
			continue
		if unit.action_ticks_left > 0:
			unit.action_ticks_left -= 1
			if unit.action_ticks_left == 0 and unit.alive:
				var action: ActionDef = deps.action_lookup.call(unit.current_action)
				if action != null:
					_fire_action(state, unit, action, deps)
				else:
					unit.current_action = &""
		elif unit.recover_ticks_left > 0:
			unit.recover_ticks_left -= 1
			if unit.recover_ticks_left == 0:
				unit.current_action = &""
		_tick_regen(state, unit, deps)
		_tick_sustain(state, unit, deps)
		_tick_dot_statuses(state, unit, deps)
		_tick_statuses(state, unit, deps)
		_tick_hazards(state, unit)
		## Anything above can kill this unit -- its own aura cannot, but a DOT,
		## a hazard, or a death that resolved earlier in this tick can. Checked
		## again here so the channel's end event lands on the tick the caster
		## died rather than one tick later, which is what the top-of-loop check
		## alone would give.
		if not unit.alive and unit.sustaining != &"":
			_end_sustain(state, unit)

## Mana and Energy refill over time; Rage does not — CombatSim enforces that
## itself rather than trusting the rate function, so a rate that forgets to
## special-case Rage still cannot make it climb. Fractional rates are rounded
## stochastically against state.rng rather than dropped, so "0.3 per tick"
## still averages out over a fight instead of always rounding to 0 (and stays
## reproducible for the same seed).
static func _tick_regen(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	if unit.resource_kind == CG.ResourceKind.RAGE:
		return
	var gained := _stochastic_round(state, deps.resource_regen_per_tick.call(unit))
	if gained > 0:
		unit.resource = clampi(unit.resource + gained, 0, unit.resource_max)

static func _stochastic_round(state: CombatState, value: float) -> int:
	if value <= 0.0:
		return 0
	var whole := int(floor(value))
	var frac := value - float(whole)
	if frac > 0.0 and state.rng.randf() < frac:
		whole += 1
	return whole

## Keys are sorted before iterating because a Dictionary's key order is insertion
## order -- the order the statuses happened to land in during a fight.
##
## A STACKING STATUS DOES NOT DROP NINE STACKS AT ONCE. On expiry it loses one
## and re-arms for `deps.status_stack_decay_ticks`, so a bleed reads down 3, 2,
## 1, gone rather than vanishing in a single frame the tick its source dies.
## That decay window is content's number, and it defaults to 0 -- which means
## the whole status comes off at once, exactly the refresh behaviour every
## status had before this existed. So this is inert until finch sets it, like
## everything else here.
##
## A dropped stack emits nothing. The status has not expired, and the badge count
## is drawn live off `status_magnitude`, so the player sees it fall without a log
## line per step -- which at nine stacks would be nine lines saying the same
## thing gets smaller.
static func _tick_statuses(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	if unit.statuses.is_empty():
		return
	var expired: Array = unit.statuses.keys()
	expired.sort()
	for status in expired:
		if state.tick >= int(unit.statuses[status]):
			if _decay_one_stack(state, unit, status, deps):
				continue
			## `_remove_status` also resets the two fields that shadow a status:
			## TAUNTING's radius, so nothing downstream reads a stale reach off a
			## unit that is no longer taunting, and SUSTAINING's action id.
			##
			## SUSTAINING is applied with a CG.MAX_TICKS expiry, so in a real
			## fight it is only ever removed by `_end_sustain`. It is handled
			## there for the same reason: the two pieces of state must not be
			## able to diverge. This deliberately does not emit SUSTAIN_END --
			## nothing in a fight can reach that case, and a second end event for
			## one channel would be worse than none.
			_remove_status(unit, status)
			var e := _event(CG.EventKind.STATUS_EXPIRED, state.tick, -1, unit.id, &"")
			e.status = status
			state.emit(e)

## True when one stack came off and the status survives, so the caller leaves it
## alone. False for everything else, which is every status that does not stack
## and the last stack of one that does.
static func _decay_one_stack(state: CombatState, unit: CombatUnit, status: CG.Status, deps: SimDeps) -> bool:
	if not _STACKING_STATUSES.has(status):
		return false
	var remaining := float(unit.status_magnitude.get(status, 0.0)) - 1.0
	if remaining < 1.0:
		return false
	var window: int = int(deps.status_stack_decay_ticks.call(status))
	if window <= 0:
		return false
	unit.status_magnitude[status] = remaining
	unit.statuses[status] = state.tick + window
	return true

## BURN and POISON deal their damage every tick they are active, with a
## DAMAGE event per hit so the log and floaters see it -- the same
## membership-driven shape as hazard damage, and for the same reason: no
## event, no visible cause, and CombatEvent exists specifically to prevent
## that. Fires before _tick_statuses checks expiry, so the tick a status
## expires on still deals its damage; the tick after, it does not, matching
## the hazard "stops the tick after it leaves" behaviour.
## BLEED appended, never inserted: this is iterated in order and two statuses
## killing a unit on the same tick must resolve in a fixed one.
const _DOT_STATUSES := {
	CG.Status.BURN: CG.DamageType.FIRE,
	CG.Status.POISON: CG.DamageType.PROFANE,
	CG.Status.BLEED: CG.DamageType.PHYSICAL,
}

## THREE STATUSES, THREE SCALING RULES, one expression:
##
##     per_tick = base(unit, status) + per_magnitude(unit, status) * magnitude
##
##   - POISON scales off the target's max health. Base only; it stores no
##     magnitude, so the second term is zero and it is untouched.
##   - BURN scales off the hit that applied it. Content moves its number from
##     the base to the per-magnitude side and burn punishes being hit hard.
##   - BLEED scales off repetition. Per-magnitude times the stack count, ticking
##     on a slower interval, so it punishes being hit often.
##
## Both new seams default to inert (`0.0` and `1`), so until content wires a
## number this is arithmetically the identical expression it was before: BURN
## and POISON take their base and nothing else, and BLEED, which nothing
## applies, does nothing. That matters more than usual here -- `_stochastic_round`
## draws from `state.rng`, so a rate that moved at all would reshuffle the shared
## stream and change every fight in the game rather than only the burning ones.
##
## The interval gate is `state.tick % interval`, on the fight's own clock rather
## than a per-unit counter. Two units bleeding tick together, which reads as one
## rhythm on screen instead of an arrhythmia, and there is no per-unit state to
## keep in step with the status.
static func _tick_dot_statuses(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	for status in _DOT_STATUSES:
		if not unit.has_status(status):
			continue
		var interval: int = maxi(1, int(deps.status_tick_interval.call(status)))
		if state.tick % interval != 0:
			continue
		var rate: float = deps.status_damage_per_tick.call(unit, status)
		var magnitude := float(unit.status_magnitude.get(status, 0.0))
		if magnitude > 0.0:
			rate += float(deps.status_damage_per_magnitude.call(unit, status)) * magnitude
		var amount := _stochastic_round(state, rate)
		if amount <= 0:
			continue
		var before := unit.hp
		unit.hp = maxi(0, unit.hp - amount)
		var applied := before - unit.hp
		var e := _event(CG.EventKind.DAMAGE, state.tick, -1, unit.id, &"")
		e.amount = applied
		e.damage_type = _DOT_STATUSES[status]
		e.status = status
		state.emit(e)
		if unit.hp <= 0 and unit.alive:
			unit.alive = false
			state.emit(_event(CG.EventKind.DEATH, state.tick, -1, unit.id, &""))
			return

## A tar pit: terrain that applies a status rather than dealing damage.
##
## Called BEFORE the `damage_per_tick <= 0` early-out above, and that ordering is
## the entire fix. A feature whose whole effect is a status has no damage, so it
## was skipped before anything ever looked at `applies_status` -- heron measured
## the pit slowing something 0 times in 20 fights.
##
## THE EXPIRY IS REFRESHED EVERY TICK THE UNIT IS INSIDE, so walking out is what
## ends it, not a clock that started when it walked in. That is the same
## membership-per-tick shape the damage loop above already uses, and it is what
## makes a pit read as a place rather than as a trap that fires once.
##
## THE EVENT FIRES ON ENTRY ONLY, and only on entry. A refresh is silent. Per
## tick would be 45 log lines for one unit crossing one pit, which is the
## `stalker_mark` flood again -- and a player does not need to be told forty-five
## times that a rat is still in the tar. The badge is what says "still slowed";
## the event says "became slowed".
##
## Deliberately does not use `_apply_status`: that one reads an `ActionDef` and
## carries the stacking and hit-scaling rules, none of which a patch of ground
## has. A pit refreshes, it does not stack, and nothing about it is a hit.
static func _apply_hazard_status(state: CombatState, unit: CombatUnit, hazard) -> void:
	if not hazard.applies_status_enabled or hazard.status_duration_ticks <= 0:
		return
	var status: CG.Status = hazard.applies_status
	var entering := not unit.has_status(status)
	unit.statuses[status] = state.tick + hazard.status_duration_ticks
	if entering:
		var e := _event(CG.EventKind.STATUS_APPLIED, state.tick, -1, unit.id, &"")
		e.status = status
		state.emit(e)

## A unit standing in a HAZARD takes its damage every tick it is inside, with
## an event per hit so the log and floaters see it, and stops the tick after
## it leaves -- membership is just re-checked each tick, no decay to track.
static func _tick_hazards(state: CombatState, unit: CombatUnit) -> void:
	if state.terrain.is_empty():
		return
	for hazard in Terrain.hazards_at(state.terrain, unit.position):
		_apply_hazard_status(state, unit, hazard)
		if hazard.damage_per_tick <= 0:
			continue
		var before := unit.hp
		unit.hp = maxi(0, unit.hp - hazard.damage_per_tick)
		var applied := before - unit.hp
		var e := _event(CG.EventKind.DAMAGE, state.tick, -1, unit.id, &"")
		e.amount = applied
		e.damage_type = hazard.damage_type
		state.emit(e)
		if unit.hp <= 0 and unit.alive:
			unit.alive = false
			state.emit(_event(CG.EventKind.DEATH, state.tick, -1, unit.id, &""))
			return

# ---------------------------------------------------------------------------
# firing an action, applying its effect
# ---------------------------------------------------------------------------

static func _fire_action(state: CombatState, unit: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	state.emit(_event(CG.EventKind.ACTION_FIRE, state.tick, unit.id, unit.focus_id, action.id))

	if action.summons_unit_id != &"":
		_spawn_summon(state, unit, action, deps)

	## Issue 61: a sustained action lands nothing at the moment it fires. Firing
	## is ignition; the first tick of upkeep is the first tick of effect, and it
	## arrives on this same tick because `_tick_sustain` runs later in
	## `_tick_phase` than the branch that called this.
	##
	## It deliberately skips `_resolve_targets` rather than running it and
	## ignoring the result. A channel is aimed at an area around its caster, so
	## it has no focused target to be in range of -- running the ordinary path
	## would emit a MISS on every ignition, which is a lie in the combat log and
	## exactly the kind of wrong-but-plausible record issue 98 is about.
	if action.sustain_cost_per_tick > 0:
		_begin_sustain(state, unit, action)
	else:
		var targets := _resolve_targets(state, unit, action)
		if targets.is_empty():
			state.emit(_event(CG.EventKind.MISS, state.tick, unit.id, unit.focus_id, action.id))
		elif action.projectile_speed > 0.0:
			## Issue 18: range and line-of-sight are still checked right here, at
			## the moment the wind-up completes, exactly as an instant action --
			## an out-of-range or blocked target still MISSes immediately above,
			## nothing launches. The only change for a target that IS resolved:
			## the effect does not land yet. `_spawn_projectile` aims at
			## `targets[0]` (the primary) only; splash, if any, is regathered
			## around the target's live position at impact, not fire time -- see
			## `_splash_targets`'s own doc comment.
			_spawn_projectile(state, unit, targets[0], action, deps)
		else:
			for target in targets:
				_apply_action_effect(state, unit, target, action, deps)
			_on_hit_landed(state, unit, action, deps)

	unit.current_action = action.id
	unit.action_ticks_left = 0
	unit.action_ticks_total = 0
	unit.recover_ticks_left = _apply_haste(unit, deps, int(deps.recover_ticks.call(unit, action)))
	if action.cooldown_ticks > 0:
		unit.cooldowns[action.id] = state.tick + action.cooldown_ticks
	if unit.recover_ticks_left <= 0:
		unit.current_action = &""

## Everything a source gains from a hit that actually connected: Rage, and issue
## 165's `ActionDef.restores_resource`.
##
## Rage gains only from a landed hit, not from committing or from a miss: a
## Rage pawn swinging at nothing (out of range at landing) must not fill, per
## issue 4's own acceptance criterion for it. Issue 18 split this out of
## `_fire_action` because "landed" now happens at two different moments: the
## same tick as firing for an instant action, or a later tick at projectile
## impact -- `_advance_projectile` calls this too, once it resolves a hit.
##
## **THAT SPLIT IS WHY `restores_resource` IS WIRED HERE AND NOWHERE ELSE, and it
## is the trap issue 165 was filed around.** Both actions carrying the field
## today -- `priest_bolt` and `geyser_spout` -- are projectiles, so a version
## wired into `_fire_action` would look right, pass a hand-written test, and
## return nothing in a real fight. Every caller of this function is a connection
## and none of the MISS paths call it, which is what makes "does not pay out on a
## miss" a property of where the code sits rather than a condition it has to
## check.
##
## `action` is threaded in for the same reason: this used to need only the
## source, and the restore is per action.
##
## The restore is a flat int, so no stochastic rounding -- unlike Rage, which is
## a rate. It is clamped at `resource_max` the same way, and it is not restricted
## by resource kind: a Rage class that ever carries the field gains Rage from it,
## which is a content decision rather than one for this file.
static func _on_hit_landed(state: CombatState, source: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	if action != null and action.restores_resource > 0:
		source.resource = clampi(source.resource + action.restores_resource, 0, source.resource_max)
	if source.resource_kind != CG.ResourceKind.RAGE:
		return
	var gained := _stochastic_round(state, deps.rage_gain_on_attack.call(source))
	if gained > 0:
		source.resource = clampi(source.resource + gained, 0, source.resource_max)

## Issue 174: Rage also fills from being HIT, not only from hitting.
##
## `_on_hit_landed` pays the attacker and nothing has ever paid the victim, so a
## Rage class opening at 0 (issue 164) had exactly one way to earn its first
## ability: land hits with a free basic attack while being focused. Measured, it
## did not get there -- the Abomination died in 19 of 20 fights and peak Rage
## fell 82 -> 29.
##
## **The gap is the opening, not the ceiling**, which is why this is the fix
## rather than a higher starting pool or a stronger Claw. A starting pool
## contradicts the player's ruling outright, and a stronger Claw makes the ramp
## survivable by making it pointless. Filling from damage taken preserves the
## ramp and gives it a second source that a 12-CON class which closes and holds
## is uniquely placed to use -- the Abomination earns rage by doing its job.
##
## Only on damage that actually landed, and only on a survivor: a killing blow
## pays nothing, the same way `_on_hit_landed` refuses to pay for a miss.
##
## Placed inside the damage branch rather than beside `_apply_action_effect`'s
## exit, so a heal can never reach it and neither can a status application.
## DOTs and hazards deliberately do not pay: a burn ticking on a corpse-to-be is
## not somebody hitting you, and paying per tick would make standing in fire the
## cheapest way to fill a Rage bar in the game.
static func _on_damage_taken(state: CombatState, target: CombatUnit, applied: int, deps: SimDeps) -> void:
	if applied <= 0 or not target.alive:
		return
	if target.resource_kind != CG.ResourceKind.RAGE:
		return
	var gained := _stochastic_round(state, deps.rage_gain_on_damage_taken.call(target, applied))
	if gained > 0:
		target.resource = clampi(target.resource + gained, 0, target.resource_max)

## Issue 12: the one place `state.units` grows after `build()`. Appends only --
## never inserts, never reorders -- so a new unit's id is `state.units.size()`
## at the moment it is appended, which is exactly the index `state.unit(id)`
## expects. Every existing id keeps pointing at the same unit forever, same as
## before this existed.
##
## Runs unconditionally when the action fires, independent of whether
## `_resolve_targets` finds anything: a build action is not an attack, and
## content is free to give it no target at all (or a self-target) without the
## summon becoming contingent on a hit.
##
## Deterministic by construction: no rng, no wall-clock, nothing but the
## caster's own state and `deps.enemy_lookup`, which is a pure content lookup.
## Same seed, same decisions, same casters resolve in the same tick in the
## same order (CombatState's own ordering rule -- iterate `units`, never a
## Dictionary), so two runs from the same seed spawn identically. Unknown
## `EnemyDef` ids are handled by `_build_enemy_unit` itself, the same way an
## unknown enemy spawn in `build()` already is.
##
## Spawned on the caster's team, at the caster's exact position ("at or near"
## per issue 12) -- units do not collide with each other, only with terrain, so
## sharing a point is not a stuck state.
##
## A unit appended here can be visited later in the same tick's `_resolve_phase`
## or `_tick_phase` loop, because both iterate `state.units` directly and Array
## iteration in GDScript re-reads size() each step. That is harmless rather
## than avoided: a unit that did not exist during `_decide_phase` has
## `intent == null` and `action_ticks_left == 0` / `recover_ticks_left == 0`, so
## every branch that would touch it this tick is a no-op. It gets its first
## real decision on the following tick, same as any unit built in `build()`
## would if `_decide_phase` had not already run for tick 1.
static func _spawn_summon(state: CombatState, caster: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	var enemy_def: EnemyDef = deps.enemy_lookup.call(action.summons_unit_id)
	var new_id := state.units.size()
	var summon := _build_enemy_unit(new_id, enemy_def, action.summons_unit_id, caster.position, caster.team)
	state.units.append(summon)
	## Issue 193. Emitted after the append, so `state.unit(target_id)` already
	## resolves for anything reading the event on this tick.
	state.emit(_event(CG.EventKind.SUMMONED, state.tick, caster.id, new_id, action.id))

## Range and line of sight are both measured here, at the moment the effect
## lands, against the target the action committed to -- same reasoning for
## both: a target that walked out of range, or behind a wall, during the
## wind-up is a miss (issue 28), and one that steps back into range or out
## from behind cover is a hit. ACTION_FIRE is still emitted either way (the
## log shows the attempt) but nothing else follows for a miss.
static func _resolve_targets(state: CombatState, unit: CombatUnit, action: ActionDef) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	var primary := state.unit(unit.focus_id)
	if primary == null or not primary.alive:
		return out
	if unit.position.distance_to(primary.position) > action.range_units:
		return out
	if action.requires_line_of_sight and Terrain.line_is_blocked(state.terrain, unit.position, primary.position):
		return out
	return _splash_targets(state, primary, action)

## Issue 18: pulled out of `_resolve_targets` so a projectile's impact can
## gather splash around the target's *live* position at the tick it lands,
## not around whatever the primary's position was at fire time. An explosion
## should land where the shot lands.
static func _splash_targets(state: CombatState, primary: CombatUnit, action: ActionDef) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	if action.splash_radius <= 0.0:
		out.append(primary)
		return out
	for other in state.living(primary.team):
		if other.position.distance_to(primary.position) <= action.splash_radius:
			out.append(other)
	return out

static func _apply_action_effect(state: CombatState, unit: CombatUnit, target: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	if not target.alive:
		return

	## Resolved BEFORE the damage is computed, so the bonus lands inside the one
	## DAMAGE event rather than beside it as a second number. A player reading
	## "Blast consumes Burn" and then a single large figure can follow the combo;
	## two damage lines for one hit is the same fact told twice and read as two.
	var bonus := _consume_status(state, unit, target, action)

	## How hard this hit landed, after mitigation, or 0 for a heal. Read below by
	## `_apply_status` for a status whose magnitude is the hit that applied it.
	var dealt := 0

	if action.heals:
		var amount := maxi(0, int(round(deps.attack_power.call(unit, action, state.rng) + bonus)))
		var before := target.hp
		target.hp = mini(target.hp_max, target.hp + amount)
		var applied := target.hp - before
		if applied > 0:
			var e := _event(CG.EventKind.HEAL, state.tick, unit.id, target.id, action.id)
			e.amount = applied
			e.damage_type = action.damage_type
			state.emit(e)
	else:
		var raw: float = deps.attack_power.call(unit, action, state.rng) + bonus
		var reduction: float = clampf(deps.damage_reduction.call(target), 0.0, 1.0)
		var mitigated := maxi(0, int(round(raw * (1.0 - reduction))))
		var before := target.hp
		target.hp = maxi(0, target.hp - mitigated)
		var applied := before - target.hp
		dealt = mitigated
		var e := _event(CG.EventKind.DAMAGE, state.tick, unit.id, target.id, action.id)
		e.amount = applied
		e.amount_before_mitigation = int(round(raw))
		e.damage_type = action.damage_type
		state.emit(e)
		_on_damage_taken(state, target, applied, deps)

	if action.applies_status_enabled:
		_apply_status(state, unit, target, action, dealt)

	if target.hp <= 0 and target.alive:
		target.alive = false
		state.emit(_event(CG.EventKind.DEATH, state.tick, unit.id, target.id, action.id))

	if action.pull_distance > 0.0 and target.alive:
		_apply_pull(state, unit, target, action.pull_distance)

	if action.cleanses_harmful and target.alive:
		_cleanse_harmful(state, unit, target, action)

# ---------------------------------------------------------------------------
# a status that remembers something (issues 121 and 130)
# ---------------------------------------------------------------------------
#
# A STATUS USED TO BE A DURATION AND NOTHING ELSE. `CombatUnit.statuses` maps a
# status to the tick it ends and there has never been anywhere to put a
# per-application payload, which is why nothing in this game stacks and why every
# damage-over-time status scaled off the same thing.
#
# Two of the player's rulings need the same missing piece, so they are one
# mechanism and not two:
#
#   "Bleed should differentiate itself from poison in that it does damage less
#    often but stacks infinitely."
#   "BURN damage per tick should be relative to the hit that applied it."
#
# `CombatUnit.status_magnitude` is that piece. What the number MEANS is decided
# per status, by exactly one of the two tables below, and the sim owns only how
# it is written and how it decays. Every number it turns into is content's,
# through SimDeps, so there is no tuning value in this file.

## Statuses that accumulate instead of refreshing: applying one again adds a
## stack rather than replacing what was there.
##
## BLEED and nothing else, per #130, which names BLEED and is silent about the
## rest. A table here rather than a flag on `ActionDef` on purpose: whether a
## status stacks is a property of the status, and a field would let two actions
## applying BLEED disagree about it, which is a knob nobody asked to turn.
const _STACKING_STATUSES := {
	CG.Status.BLEED: true,
}

## Statuses whose magnitude is the damage of the hit that applied them.
##
## BURN, per the player's ruling. The stored number is the **mitigated** damage
## -- what the hit actually dealt, which is the figure in the floater and the
## log, so "it burns as hard as it hit" is something a player can check on
## screen. Armour therefore matters twice, and that is the intended reading: a
## well-armoured target takes a small hit and consequently a small burn.
##
## `mitigated` rather than the `applied` figure the event carries, because
## `applied` is clamped by the target's remaining health -- a killing blow
## would otherwise store a number that describes how nearly dead the target
## already was rather than how hard it was hit.
const _HIT_SCALED_STATUSES := {
	CG.Status.BURN: true,
}

## Writes the status, its expiry and its magnitude in one place, so the three
## cannot be set inconsistently by two call sites.
##
## RE-APPLICATION, and this is the decision with a wrong answer a player would
## notice and be unable to explain:
##
##   - **Stacking statuses add one and refresh the expiry.** That is the whole
##     of "stacks infinitely".
##   - **Hit-scaled statuses take the MAX and refresh the expiry.** Not
##     overwrite. Overwriting downward means a second, weaker fire attack makes
##     the player's burn *worse*, which is an outcome nobody could explain from
##     watching. It is worse still now that a consume's payoff scales off the
##     same number: a weak follow-up would silently devalue a combo the player
##     had already planned around. The duration always refreshes, so a light hit
##     still keeps a strong burn alive -- it just cannot dilute it.
##   - **Everything else behaves exactly as before**, a plain refresh.
##
## `STATUS_APPLIED.amount` carries the resulting magnitude, which is unset on
## that kind today, so a log line can say "Bleed (3)" or "Burn (18)" without a
## new field and without reaching into the unit.
static func _apply_status(state: CombatState, caster: CombatUnit, target: CombatUnit, action: ActionDef, dealt: int) -> void:
	var status: CG.Status = action.applies_status
	var carried := float(target.status_magnitude.get(status, 0.0))
	if _STACKING_STATUSES.has(status):
		target.status_magnitude[status] = carried + 1.0
	elif _HIT_SCALED_STATUSES.has(status):
		target.status_magnitude[status] = maxf(carried, float(dealt))

	target.statuses[status] = state.tick + action.status_duration_ticks
	## TAUNTING's reach is stored on the taunting unit itself rather than
	## re-derived from its action list each tick -- ActionDef.taunt_radius's
	## own doc comment. Reapplying (a refresh) overwrites it the same way
	## reapplying any other status already overwrites its expiry tick.
	if status == CG.Status.TAUNTING:
		target.taunt_radius = action.taunt_radius
		## The taunt lands on its victims here, in the same breath as the status
		## that makes this unit a taunter, so the two cannot get out of step.
		## `status_duration_ticks` is shared deliberately: the roar's advertised
		## duration and how long anyone is actually held by it are the same
		## number, and a player reading "for 3 seconds" on the action should not
		## have to learn that it means something else.
		_broadcast_taunt(state, target, action.status_duration_ticks)

	var se := _event(CG.EventKind.STATUS_APPLIED, state.tick, caster.id, target.id, action.id)
	se.status = status
	se.amount = int(target.status_magnitude.get(status, 0.0))
	state.emit(se)

## Strips `action.consumes_status` off the target and returns the bonus power it
## paid, or 0.0 when the action consumes nothing or the target is not carrying
## it. Every action in the game today takes the second branch.
##
## The bonus is `consumed_power_scale` times the status's OWN stored magnitude,
## which is the player's rule and is about every consume rather than about
## Blast: *"this will be the norm for burn consume effects"*. A burn from a big
## hit ticks harder and is worth more to eat, off one stored number read at both
## ends.
##
## A stacking status is consumed whole -- every stack, for the total magnitude.
## Eating one stack of nine would need a second decision about which stack and
## leave the player with a badge that barely moved.
##
## Emits STATUS_EXPIRED carrying the caster and the consuming action, exactly as
## `_cleanse_harmful` does and for the same reason: that pair is the only thing
## separating "Blast ate the burn" from "the burn ran out", and it is emitted
## before the DAMAGE event so a log reads in cause-then-effect order.
static func _consume_status(state: CombatState, caster: CombatUnit, target: CombatUnit, action: ActionDef) -> float:
	if not action.consumes_status_enabled:
		return 0.0
	var status: CG.Status = action.consumes_status
	if not target.has_status(status):
		return 0.0
	var magnitude := float(target.status_magnitude.get(status, 0.0))
	_remove_status(target, status)
	var e := _event(CG.EventKind.STATUS_EXPIRED, state.tick, caster.id, target.id, action.id)
	e.status = status
	state.emit(e)
	return action.consumed_power_scale * magnitude

## The one place a status comes off a unit. Every erasure goes through here so
## `statuses`, `status_magnitude` and the two fields that shadow a status
## (`taunt_radius`, `sustaining`) cannot be left disagreeing -- which is exactly
## how a stale taunt radius or a phantom stack would survive a cleanse.
##
## Emits nothing: the three callers each say something different about why the
## status went (expiry, cleanse, consume) and the event belongs to them.
static func _remove_status(unit: CombatUnit, status: CG.Status) -> void:
	unit.statuses.erase(status)
	unit.status_magnitude.erase(status)
	if status == CG.Status.TAUNTING:
		unit.taunt_radius = 0.0
	elif status == CG.Status.SUSTAINING:
		unit.sustaining = &""
		unit.sustain_started_tick = -1

## Issue 87: strips every harmful status from `target`, one STATUS_EXPIRED per
## status removed.
##
## `CG.is_harmful` is the only thing consulted for which statuses those are.
## Not a second list here: the status badges (Scripts/Art/StatusIcons.gd) and
## the combat log (Scripts/UI/CombatLogView.gd) already call the same function,
## so what a cleanse strips and what the player sees disappear cannot disagree.
## A status added to CG.Status without being classified there is treated as
## harmless and survives a cleanse, which is the safe direction that function's
## own doc comment argues for.
##
## Placed beside `_apply_pull` at the end of `_apply_action_effect`, and
## guarded the same way, for the same two reasons: it runs after this action's
## own damage and death resolution, so a cleanse never fires on a corpse, and
## an action that sets neither field behaves exactly as it did before.
##
## Removal goes through `_remove_status`, which takes the magnitude with it.
## That was not always necessary: every harmful status used to be a pure
## read-while-present flag -- SLOWED a multiplier read in
## `_effective_move_speed`, STUN a check in `_decide_phase`, MARKED a read in
## Balance, BURN/POISON membership tests in `_tick_dot_statuses` -- and the only
## status carrying anything extra (TAUNTING, via taunt_radius) was harmless and
## therefore never reached here.
##
## **BLEED and BURN broke that**: both are harmful and both now carry a
## magnitude, so a cleanse that erased only the expiry would leave nine stacks
## of bleed sitting on a unit that no longer has bleed, waiting to be revived at
## full strength by the next application. One removal path is what stops that
## from ever being a question again.
##
## Keys are sorted before iterating, exactly as `_tick_statuses` does: a
## Dictionary's key order is insertion order, so two fights from one seed
## would otherwise emit the same removals in an order that depends on which
## enemy afflicted the unit first. Nothing random is consulted at all.
##
## The event carries the caster and the action, where an expiry from
## `_tick_statuses` carries source_id -1 and no action id. That is the only
## signal separating "the Geysermancer scrubbed the poison off" from "the
## poison ran out", and it is there for the log to use; CombatLogView does not
## read it yet and rendering it is wren's call, not mine.
static func _cleanse_harmful(state: CombatState, caster: CombatUnit, target: CombatUnit, action: ActionDef) -> void:
	if target.statuses.is_empty():
		return
	var present: Array = target.statuses.keys()
	present.sort()
	for status in present:
		if not CG.is_harmful(status):
			continue
		_remove_status(target, status)
		var e := _event(CG.EventKind.STATUS_EXPIRED, state.tick, caster.id, target.id, action.id)
		e.status = status
		state.emit(e)

## Issue 14: drags `target` toward `caster` by up to `distance`, world units.
## Guarded by the caller on `target.alive` -- checked *after* this same
## effect's own damage/death resolution above, so a pull on a killing blow
## never fires on a corpse.
##
## Reuses `_sweep`, the same increment-and-stop walk ordinary movement already
## uses against `Terrain.point_is_blocked`, rather than a straight-line
## teleport: a pull that can shove a unit through a wall is exactly the "lands
## inside terrain" failure issue 14 names, and `_sweep` already refuses to
## land past the first blocked increment. A pull that meets a wall stops at
## the wall instead of failing outright -- dragged as far as the wall allows,
## which reads better than a hook that does nothing because the last few units
## of it were blocked.
static func _apply_pull(state: CombatState, caster: CombatUnit, target: CombatUnit, distance: float) -> void:
	var to_caster := caster.position - target.position
	var dist := to_caster.length()
	if dist <= 0.0001:
		return # already on top of the caster; nothing to drag
	var travel := minf(distance, dist)
	var step := to_caster.normalized() * travel
	target.position = _sweep(state, target, step)

# ---------------------------------------------------------------------------
# sustained actions (issue 61)
# ---------------------------------------------------------------------------
#
# THE FIRST THING IN THIS SIMULATION THAT IS NOT A POINT IN TIME.
#
# Every other action resolves as wind-up, fire, recover -- three moments. A
# sustained action fires once and is then *held*: it deals its effect and
# charges `sustain_cost_per_tick` on every tick, and it keeps doing so for
# exactly as long as the pawn's decision layer keeps choosing it.
#
# WHAT ENDS IT, and this is the design decision rather than an implementation
# detail. Four things, and the first one is the important one:
#
#   1. The plan stops choosing it. A holding unit is NOT busy, so
#      `_decide_phase` asks the decision layer every tick exactly as it always
#      has. An intent of USE_ACTION naming the same action re-affirms the
#      channel; anything else ends it (`_reaffirm_sustain`).
#   2. Resource below the per-tick cost (`_tick_sustain`).
#   3. STUN (`_decide_phase`).
#   4. Death (`_tick_phase`, both ends of the loop body).
#
# (1) was chosen over an autonomous toggle the pawn switches off by itself, and
# the reason is CLAUDE.md's binding principle: *pawns should never do anything
# the player cannot see in the plans of action.* A channel that outlives the
# plan that started it is a pawn burning its own resource for reasons written
# nowhere the player can read, which is that failure exactly. Re-affirmation
# also means the plan's CONDITION is the off switch -- already authored, already
# visible on the inspect screen, already editable.
#
# It costs nothing to implement, because the seam was already there: the sim has
# always asked for an intent whenever a unit is free, and a held action leaves
# the unit free.
#
# ON DURATION, the fifth PlanBlock kind, whose ops are `[&"once"]` and which
# stores no per-plan progress anywhere. A sustained action is the first thing
# that could have given it a meaning and I decided against it deliberately
# rather than leaving it inert by accident: **this mechanism makes CONDITION do
# DURATION's job.** The channel's lifetime *is* the plan's condition,
# re-evaluated every tick. A DURATION block saying "for N ticks" beside it would
# be a second, competing governor of the same lifetime, and a plan whose
# condition drops at tick 20 with a duration of 60 has no correct answer. If
# DURATION is ever to mean something it is scheduling -- "keep re-firing this
# plan for N ticks before yielding to a later one" -- which is a concept
# `PlanInterpreter` has never had, lives in a file this session does not own,
# and is not what issue 61 asks for.
#
# The unit is free to move while holding: movement is not a competing action,
# and the player asked for an aura rather than a root. In practice a plan that
# stops firing hands the tick to `DefaultBehavior`, which usually moves, and the
# channel ends there -- through (1), for a reason the player can read.

## Begins the channel. Both pieces of state are written here and nowhere else,
## which is what keeps `CombatUnit.sustaining` and `CG.Status.SUSTAINING` from
## being able to disagree.
##
## The status carries a CG.MAX_TICKS expiry -- "outlives the fight", the same
## thing `_build_enemy_unit` does for a spawn-time TAUNTING, and for the same
## reason: this status is ended by a rule, not by a clock, so it must never
## expire on its own.
static func _begin_sustain(state: CombatState, unit: CombatUnit, action: ActionDef) -> void:
	unit.sustaining = action.id
	unit.sustain_started_tick = state.tick
	unit.statuses[CG.Status.SUSTAINING] = CG.MAX_TICKS
	state.emit(_event(CG.EventKind.SUSTAIN_START, state.tick, unit.id, -1, action.id))

## Ends it, from any of the four causes. Safe to call on a unit holding nothing,
## which is why every caller is a plain unguarded call.
##
## Erasing the status here does NOT emit STATUS_EXPIRED, where `_tick_statuses`
## and `_cleanse_harmful` both do. SUSTAIN_END is that event, carrying strictly
## more information (which action, how long); two events for one ending would
## put the same fact in a log twice and let a reader count a channel as having
## stopped twice.
static func _end_sustain(state: CombatState, unit: CombatUnit) -> void:
	if unit.sustaining == &"":
		return
	var e := _event(CG.EventKind.SUSTAIN_END, state.tick, unit.id, -1, unit.sustaining)
	e.amount = maxi(0, state.tick - unit.sustain_started_tick)
	state.emit(e)
	unit.sustaining = &""
	unit.sustain_started_tick = -1
	unit.statuses.erase(CG.Status.SUSTAINING)

## Cause (1). Called from `_decide_phase` with whatever the decision layer just
## returned, on every tick the unit was free to decide.
##
## A unit that is busy is never asked, so it is never checked here, and its
## channel survives its own recovery ticks. That is deliberate: recovery is the
## unit finishing the thing it was told to do, not the unit changing its mind.
static func _reaffirm_sustain(state: CombatState, unit: CombatUnit, intent: Intent) -> void:
	if unit.sustaining == &"":
		return
	if intent != null and intent.kind == CG.IntentKind.USE_ACTION and intent.action_id == unit.sustaining:
		return
	_end_sustain(state, unit)

## One tick of upkeep: charge, then deal.
##
## The same membership-per-tick shape `_tick_hazards` already uses for standing
## in fire, pointed at the caster instead of at a fixed patch of ground. That
## was the model issue 61 named and it is the right one -- there is no duration
## to decay, no list of affected units to maintain, nothing to clean up when
## somebody walks out. Position is re-read every tick and that is the whole
## bookkeeping.
##
## ON THE TICK THE RESOURCE RUNS OUT: it stops cleanly and there is no partial
## tick. Nothing is charged and nothing is dealt. The alternative -- spend what
## is left and deal a fraction of the effect -- makes the last tick of every
## channel a different tick from all the others for no gain a player could
## read.
##
## DETERMINISM: `state.living()` is `state.units` order, which is fixed for a
## seed, and the only randomness reached is `state.rng` through
## `deps.attack_power`, consumed in that same fixed order. No wall clock, no
## Dictionary iteration.
##
## This can kill a unit that `_tick_phase` has not reached yet in the loop that
## called it, which is the same thing an attack in `_resolve_phase` has always
## been able to do -- that unit is simply skipped for the rest of this tick.
static func _tick_sustain(state: CombatState, unit: CombatUnit, deps: SimDeps) -> void:
	if unit.sustaining == &"":
		return
	var action: ActionDef = deps.action_lookup.call(unit.sustaining)
	if action == null or action.sustain_cost_per_tick <= 0:
		_end_sustain(state, unit)
		return
	if unit.resource < action.sustain_cost_per_tick:
		_end_sustain(state, unit)
		return

	unit.resource -= action.sustain_cost_per_tick
	var spent := _event(CG.EventKind.RESOURCE_SPENT, state.tick, unit.id, -1, action.id)
	spent.amount = action.sustain_cost_per_tick
	state.emit(spent)

	for target in _sustain_targets(state, unit, action):
		_apply_action_effect(state, unit, target, action, deps)

## Everyone inside the channel's radius this tick.
##
## `action.heals` picks the side, the same field that already decides whether
## `_apply_action_effect` adds or subtracts hp -- so a sustained heal aura is a
## card content can author with no further work here, which is what issue 61
## means by "a new category, not a new number". A damage aura reads the enemy
## team and therefore can never catch the caster's own party.
##
## `requires_line_of_sight` is honoured per target, so a pillar between the
## Abomination and a goblin spares the goblin. An aura that burns through a wall
## would be the same defect `Terrain.line_is_blocked` was built to fix for
## shots.
##
## A zero radius returns nothing rather than falling back to the focused target.
## A channel with a cost and no reach is content authored wrong, and it should
## look wrong -- silently retargeting it would hide the mistake.
static func _sustain_targets(state: CombatState, unit: CombatUnit, action: ActionDef) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	if action.sustain_radius <= 0.0:
		return out
	var side := unit.team if action.heals else _enemy_team(unit.team)
	for other in state.living(side):
		if unit.position.distance_to(other.position) > action.sustain_radius:
			continue
		if action.requires_line_of_sight and Terrain.line_is_blocked(state.terrain, unit.position, other.position):
			continue
		out.append(other)
	return out

static func _enemy_team(team: CG.Team) -> CG.Team:
	return CG.Team.ENEMY if team == CG.Team.PLAYER else CG.Team.PLAYER

# ---------------------------------------------------------------------------
# projectiles
# ---------------------------------------------------------------------------

## Issue 18: launched instead of resolving instantly when `action.projectile_speed
## > 0.0`. `aim_point` is the target's position at this exact moment and is
## never recomputed -- no homing, which is what lets a target walk out of the
## way (it isn't there when the shot arrives) as well as walk into one early
## (`_advance_projectile`'s own hit check, below). `recover_ticks` and any
## RAGE-on-commit bookkeeping already happened in `_fire_action` before this
## is called and do not wait for impact; only the projectile's own effect
## (`_apply_action_effect`) and its RAGE-on-landed-hit gain (`_on_hit_landed`)
## are deferred to `_advance_projectile`.
static func _spawn_projectile(state: CombatState, caster: CombatUnit, target: CombatUnit, action: ActionDef, deps: SimDeps) -> void:
	var p := Projectile.new()
	p.id = state.projectiles.size()
	p.source_id = caster.id
	p.target_id = target.id
	p.action_id = action.id
	p.origin = caster.position
	p.aim_point = target.position
	p.position = caster.position
	p.speed = action.projectile_speed
	p.spawn_tick = state.tick
	state.projectiles.append(p)

## Advances every unresolved projectile by one tick and resolves the ones
## that arrive. Runs after `_tick_phase` and before `_check_outcome`, so a hit
## that would end the fight this tick still lands before the outcome is
## decided -- the same ordering guarantee every other effect in a tick
## already gets.
##
## Scans from `state.next_unresolved_projectile` rather than 0: resolved
## entries stay in the array in place (same "dead units stay in place"
## convention `state.units` already uses -- nothing iterating mid-tick should
## see the array reshuffle), and a long, hasted fight can accumulate
## thousands of them. Correctness never depends on the cursor: the scan below
## still covers cursor..end in full every tick, so a fast projectile launched
## after a slower one is still found and resolved even though it isn't at the
## front. The cursor only buys speed, on the assumption that resolution is
## *roughly* in launch order -- if that assumption turns out false in
## practice, this degrades toward scanning the same already-resolved prefix
## repeatedly, not toward missing anything.
static func _tick_projectiles(state: CombatState, deps: SimDeps) -> void:
	var i := state.next_unresolved_projectile
	while i < state.projectiles.size():
		var p: Projectile = state.projectiles[i]
		if not p.resolved:
			_advance_projectile(state, p, deps)
		i += 1
	while state.next_unresolved_projectile < state.projectiles.size() \
			and state.projectiles[state.next_unresolved_projectile].resolved:
		state.next_unresolved_projectile += 1

## Moves `p` up to `p.speed` toward its frozen `aim_point`, then resolves it
## if either condition is met this tick:
##
## 1. Its target is still alive and `p`'s new position is within the
##    target's own `radius` of the target's *current* position -- reusing
##    the field the movement code already treats as a unit's physical size
##    rather than inventing a second "how close counts as a hit" number.
##    This is what lets a target walk into an incoming shot early.
## 2. It has reached `aim_point` without (1) firing -- resolves as an
##    ordinary MISS, the same event an out-of-range shot already gets today.
##    This is what lets a target walk out of the way: nothing is at the aim
##    point anymore.
##
## A target that died before impact simply never satisfies (1) again (`state.unit`
## still resolves the id -- ids are stable forever -- but `.alive` is false),
## so it falls through to (2), an ordinary miss, with no cancellation path to
## build. A dead source needs nothing special at all: everything this needs
## (`source_id`, `target_id`, `action_id`, `aim_point`) was captured at launch.
##
## `requires_line_of_sight` is re-checked every tick against the live
## predicate (`Terrain.line_is_blocked`, projectile's current position to the
## target's current position) rather than once at fire time, so a pillar
## sliding into the path blocks that tick's hit-check with no special case.
static func _advance_projectile(state: CombatState, p: Projectile, deps: SimDeps) -> void:
	var travelled_from := p.position
	var to_aim := p.aim_point - p.position
	var remaining := to_aim.length()
	if p.speed >= remaining or remaining <= 0.0001:
		p.position = p.aim_point
	else:
		p.position = p.position + to_aim.normalized() * p.speed

	var action: ActionDef = deps.action_lookup.call(p.action_id)
	var target := state.unit(p.target_id)
	var source := state.unit(p.source_id)
	if action != null and target != null and source != null:
		## SHIELDING checked before the intended target, every tick the shot
		## is in flight -- a shielder standing between the shooter and the
		## target intercepts it wherever the shot currently is, not only once
		## it would have reached the original target. Checked even if `target`
		## has already died: the guard reacts to a hostile shot crossing its
		## front regardless of what the shot was originally aimed at.
		var shielder := _find_shielder(state, target.team, source.team, travelled_from, p.position)
		if shielder != null:
			p.resolved = true
			state.emit(_event(CG.EventKind.BLOCKED, state.tick, p.source_id, shielder.id, p.action_id))
			for t in _splash_targets(state, shielder, action):
				_apply_action_effect(state, source, t, action, deps)
			_on_hit_landed(state, source, action, deps)
			return

		if target.alive:
			var in_range := p.position.distance_to(target.position) <= target.radius
			var blocked := action.requires_line_of_sight \
				and Terrain.line_is_blocked(state.terrain, p.position, target.position)
			if in_range and not blocked:
				p.resolved = true
				for t in _splash_targets(state, target, action):
					_apply_action_effect(state, source, t, action, deps)
				_on_hit_landed(state, source, action, deps)
				return

	if p.position == p.aim_point:
		p.resolved = true
		state.emit(_event(CG.EventKind.MISS, state.tick, p.source_id, p.target_id, p.action_id))

## How wide the shield is: how close a hostile shot's path has to pass to a
## SHIELDING unit's front for that unit to take it instead.
##
## 40 units, which is melee range -- `warrior_strike` and `warrior_execute`
## both have `range_units = 40.0`, and that is what "melee" means in this
## content. It is the player's own original wording for this ability: "block
## ranged attacks that enter its melee range from the direction it's facing."
##
## It was `candidate.radius`, 22 units, the shielder's own body. That cannot
## do what `warrior_block`'s description promises ("stops a travelling shot
## aimed at an ally standing behind it") because two units cannot overlap, so
## an ally standing behind is at least 44 units away -- twice the old window.
## The shield covered a bubble on the Warrior, and the ally was only ever
## protected when the shot happened to fly close past the Warrior anyway.
##
## Reusing `radius` was the same instinct as reusing it for the ordinary hit
## check, and it was wrong for the same reason a hit check is right: a hit
## asks "did this touch a body", a shield asks "did this come through the
## space I am guarding". Those are different questions and 40 is the answer to
## the second one, stated rather than borrowed.
##
## It does not follow content: if melee range moves, this does not move with
## it. Deliberate -- a simulation constant that silently tracked an action's
## range would make this ability change when an unrelated action was tuned.
const SHIELD_WIDTH := 40.0

## A shot crossing a SHIELDING unit's front is stopped by it, per
## CG.Status.SHIELDING's own doc comment -- this is the projectile-based
## design that comment named as the point of building #18 first, replacing
## the geometric-line-check fallback it also named (never built, since
## projectiles landed before this did).
##
## Tested against the **segment the shot travelled this tick**, `from` -> `to`,
## not against where it happens to have landed at the end of it. A shot moves
## `speed` units per tick (65 for every real ranged action today) and the
## window is 40 wide, so a point test lets a shot teleport straight through a
## raised shield without ever being sampled inside it. That is not a rare edge:
## it is most shots, and it is a large part of why this ability appeared to do
## nothing. A segment test has no such hole at any speed, which also means the
## measurement stops depending on the tick rate.
##
## The front arc is now two sign tests instead of one, and the second is new:
##
##   1. the shot **started this tick in front**: `facing.dot(from - pos) > 0`
##   2. the shot is **moving into the shield**: `facing.dot(to - from) < 0`
##
## Together that is the player's own wording for the ability -- "ranged attacks
## that enter its melee range from the direction it's facing". Test 1 alone was
## what this had, and it cannot tell approach from departure, because it reads
## where the shot is and never which way it is going. The old comment on the
## facing test in Tests/test_combat_taunt_and_shield.gd says so outright: a
## shielder on the shot's line is "briefly in front of the shot during the
## approach and briefly behind it during departure, for *either* facing". So a
## shot that had already flown past a guard could be caught on its way out, and
## widening the window from 22 to 40 would have made that more common, not less.
## Test 2 removes it: a shield stops what comes at its face.
##
## Neither test can be asked of the closest point on the segment. For a shot
## passing straight through a shielder that point is the shielder's own
## position, which dots to zero from every facing.
##
## `attacking_team == defending_team` returns null immediately, so a shield
## never blocks a friendly heal or buff aimed at an ally standing behind it --
## SHIELDING stops incoming fire, not outgoing support.
##
## First qualifying shielder in `state.living(defending_team)` order wins,
## same "iterate units, never a Dictionary" determinism rule every other
## tie-break in this file already follows.
static func _find_shielder(state: CombatState, defending_team: CG.Team, attacking_team: CG.Team, from: Vector2, to: Vector2) -> CombatUnit:
	if attacking_team == defending_team:
		return null
	for candidate in state.living(defending_team):
		if not candidate.has_status(CG.Status.SHIELDING):
			continue
		if candidate.facing == Vector2.ZERO:
			continue # "no facing yet" per CombatUnit.facing's own doc comment: blocks nothing
		var closest := Geometry2D.get_closest_point_to_segment(candidate.position, from, to)
		if closest.distance_to(candidate.position) > SHIELD_WIDTH:
			continue
		## Vector2.normalized() on a zero-length vector returns ZERO rather
		## than dividing by zero, so a shot starting its tick exactly on the
		## shielder's own position dots to 0 and correctly falls through to
		## "not in front" rather than special-casing "can't be behind me if
		## it's exactly on me" -- a shot dead-centre on a shielder facing away
		## is still approaching from the shielder's back, not its front.
		var to_shot := (from - candidate.position).normalized()
		if candidate.facing.dot(to_shot) <= 0.0:
			continue
		if candidate.facing.dot(to - from) < 0.0:
			return candidate
	return null

# ---------------------------------------------------------------------------
# outcome
# ---------------------------------------------------------------------------

static func _check_outcome(state: CombatState, deps: SimDeps = null) -> void:
	if deps == null:
		deps = SimDeps.new()
	var player_alive := not state.living(CG.Team.PLAYER).is_empty()
	var enemy_alive := not state.living(CG.Team.ENEMY).is_empty()
	# Issue 233. Only asked while both sides still have somebody standing: a
	# side with nothing left alive has already lost by the rule above, and
	# asking whether its corpses can act would turn a win into a draw. That is
	# not hypothetical -- it is what the first version of this did, and
	# `test_an_empty_side_still_loses_immediately` caught it.
	# Issue 249. The reason is decided here rather than derived later because
	# here is the only place that still knows it: after the tick, "the last
	# enemy died" and "the last enemy became furniture" both look like a side
	# that cannot fight. Taken before `_side_can_fight` can overwrite either
	# flag, so a side that was already empty is never reported as stranded.
	var reason := CG.EndReason.NO_SURVIVORS
	if player_alive and enemy_alive:
		player_alive = _side_can_fight(state, CG.Team.PLAYER, deps)
		enemy_alive = _side_can_fight(state, CG.Team.ENEMY, deps)
		if not player_alive or not enemy_alive:
			reason = CG.EndReason.CANNOT_ACT

	var outcome := CombatState.Outcome.UNRESOLVED
	if player_alive and not enemy_alive:
		outcome = CombatState.Outcome.PLAYER_WIN
	elif enemy_alive and not player_alive:
		outcome = CombatState.Outcome.ENEMY_WIN
	elif not player_alive and not enemy_alive:
		outcome = CombatState.Outcome.DRAW
	elif state.tick >= CG.MAX_TICKS:
		outcome = CombatState.Outcome.DRAW
		# THE ONE ENDING `CG.EndReason` HAS NO NAME FOR, AND I AM NOT INVENTING
		# ONE: the enum is Core and Core is rook's. Both sides are alive and
		# able, and the fight stopped because it ran out of ticks, which is
		# neither NO_SURVIVORS nor CANNOT_ACT.
		#
		# Reachable in code, and **not reached in practice**: 1600 fights over
		# every encounter x party x 40 seeds produced 1587 PLAYER_WIN, 13
		# ENEMY_WIN and zero draws of any kind (`Tools/OutcomeTable.gd`).
		#
		# This is deliberately left as UNSET rather than mapped onto a reason
		# that would be a lie. `Tests/test_combat_end_reason.gd` holds both
		# halves of it: every ending the game actually produces carries a
		# reason, and the tick cap is still unreachable. The second goes red
		# the day a fight hits the cap, which is the day the enum needs a
		# third value -- rather than a comment quietly certifying an absence.
		reason = CG.EndReason.UNSET

	if outcome != CombatState.Outcome.UNRESOLVED:
		state.outcome = outcome
		# finch's #219 finding, and the fifth way a channel can end: the fight
		# stops while it is still lit. The other four all run `_end_sustain`;
		# this one dropped the event, so a log could show a channel starting
		# and never stopping, and anything counting SUSTAIN_START against
		# SUSTAIN_END would come out short by at most one per fight.
		#
		# Before FIGHT_END, in unit order: the channel stopped because the
		# fight did, so it reads that way round, and no dictionary is iterated
		# to decide it.
		for unit in state.units:
			if unit.alive and unit.sustaining != &"":
				_end_sustain(state, unit)
		var end_event := _event(CG.EventKind.FIGHT_END, state.tick, -1, -1, &"")
		end_event.end_reason = reason
		state.emit(end_event)

## Issue 233. A side is beaten when it has no living unit left **or** when
## every unit it has left can never act again for the rest of the fight.
##
## The second half exists because of one measured event, not a hypothetical.
## `floor1_warden` with the four-class party: 22 of 40 seeds outlive the whole
## party because two Siege Engines are still standing. Eleven of those are wins
## the engines land within 4 seconds. **The other eleven are 25.9-second
## defeats, of which 21.8 to 25.9 seconds contain nothing the player's side
## does at all** -- measured event by event with `Tools/TailAnatomy.gd`, and
## watched on screen with `Tools/TailWatch.gd`, where the arena is visually
## frozen and the combat log's last line is twelve seconds old.
##
## The cause is not a slow tail, which is why "speed the tail up" is not the
## fix. `siege_engine_bolt` is `requires_marked_target`, the engines have
## `move_speed` 0, and the only unit in the game that applies MARKED is the
## Siege Master. The tick their mark fades, two engines become furniture with
## no action they can ever satisfy, and the Warden spends 25 seconds
## demolishing them. **The fight is decided; only the announcement is late.**
##
## It is deliberately not "end the fight when the last pawn dies": that throws
## away the eleven wins the engines earn, and they earn them in under four
## seconds.
## Issue 218, and rook's ruling: **a fight where every pawn is dead is not a
## victory.** The simulation's result does not change -- the enemies are gone,
## so `outcome` is PLAYER_WIN and stays PLAYER_WIN -- but the screen must not
## call it one. This is the question the banner asks to tell the two endings
## apart.
##
## Public because the answer belongs here rather than in the view: it is a
## property of the fight, and a second implementation of "which of these units
## was a pawn" in `BattleView` would drift from this one. 11 of 40 seeds on
## `floor1_warden` end this way (issue 233), so it is not a corner case.
##
## **No new field was needed and I did not add one.** `state.units` keeps dead
## units in place with `alive == false` for the whole fight, and a pawn is the
## one player-team unit with `pawn != null` -- `build()` sets `.pawn` for party
## members and leaves `enemy_id` empty, while a summon is built from an EnemyDef
## and carries one. So "the party existed and every one of them is dead" is
## readable off `CombatState` at any tick, including after the fight ends.
##
## The party-existed half is not decoration: a fight with no pawns at all (the
## level editor's test fight can build one) would otherwise report every win as
## pawnless and the banner would read Defeat on it.
static func party_was_wiped(state: CombatState) -> bool:
	var pawns := 0
	for unit in state.units:
		if unit.team != CG.Team.PLAYER or unit.pawn == null:
			continue
		pawns += 1
		if unit.alive:
			return false
	return pawns > 0

## The ending rook ruled on: the party is gone, and the summons they left behind
## finished the enemies off afterwards.
static func is_pawnless_win(state: CombatState) -> bool:
	return state.outcome == CombatState.Outcome.PLAYER_WIN and party_was_wiped(state)

static func _side_can_fight(state: CombatState, team: CG.Team, deps: SimDeps) -> bool:
	var living := state.living(team)
	if living.is_empty():
		return false
	for unit in living:
		if _unit_can_fight(state, unit, deps):
			return true
	return false

## Narrow on purpose. The only permanent gate in the game is
## `requires_marked_target`: a cooldown ticks down, a resource regenerates and a
## target walks back into range, so none of those may end a fight. A mark is the
## one precondition a unit cannot restore for itself, and only a living ally
## that applies MARKED can restore it.
##
## Anything not covered by that reasoning returns true, so this cannot end a
## fight the old rule would have kept running for any other reason.
static func _unit_can_fight(state: CombatState, unit: CombatUnit, deps: SimDeps) -> bool:
	if unit.move_speed > 0.0:
		return true
	# Mid wind-up, mid channel, or a shot still in the air: the fight is not
	# over while a unit's last decision is still resolving. Ending it here
	# would cancel a bolt that may be about to win.
	if unit.current_action != &"" or unit.sustaining != &"":
		return true
	for p in state.projectiles:
		if not p.resolved and p.source_id == unit.id:
			return true
	var marked_only := false
	for id in unit.actions:
		var a: ActionDef = deps.action_lookup.call(id)
		if a == null:
			continue
		if not a.requires_marked_target:
			return true
		marked_only = true
	if not marked_only:
		return true
	for foe in state.living(_enemy_team(unit.team)):
		if foe.has_status(CG.Status.MARKED):
			return true
	for ally in state.living(unit.team):
		for id in ally.actions:
			var a: ActionDef = deps.action_lookup.call(id)
			if a != null and a.applies_status_enabled and a.applies_status == CG.Status.MARKED:
				return true
	return false

# ---------------------------------------------------------------------------

static func _event(kind: CG.EventKind, tick: int, source_id: int, target_id: int, action_id: StringName) -> CombatEvent:
	var e := CombatEvent.make(kind, tick)
	e.source_id = source_id
	e.target_id = target_id
	e.action_id = action_id
	return e
