extends "res://Tests/TestCase.gd"


## Issue 830. The Warden's chain was named for a pull it did not have, and its
## one plan row was named "Axe up close, chain toss at range" while aiming
## every action at whoever stood nearest.

const _SEED := 8300

func _warden(id: int, pos: Vector2) -> CombatUnit:
	return CombatSim._build_enemy_unit(id, EnemyLibrary.get_enemy(&"the_warden"), &"the_warden", pos)

func _victim(id: int, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.hp_max = 5000
	u.hp = 5000
	u.position = pos
	u.radius = 12.0
	u.move_speed = 0.0
	return u

## Three victims strung out in front of the Warden. Nobody but the Warden
## decides: the pawns stand still, so the only movement in the fixture is
## whatever the Warden's own abilities cause.
func _arena(warden_walks: bool = true) -> CombatState:
	var state := CombatState.new(_SEED)
	state.units.append(_victim(0, Vector2(60.0, 0.0)))
	state.units.append(_victim(1, Vector2(150.0, 0.0)))
	state.units.append(_victim(2, Vector2(250.0, 0.0)))
	var warden := _warden(3, Vector2.ZERO)
	if not warden_walks:
		warden.move_speed = 0.0
	state.units.append(warden)
	return state

## A Warden pinned where it stands. Its grab reaches 70 units and the nearest
## pawn is at 60, so a walking Warden hurls somebody before the chain is ever
## the row that fires; nailing it down leaves the chain as the only thing that
## can move anyone, which is what these tests are measuring.
func _chain_only() -> CombatState:
	var state := _arena(false)
	state.unit(0).position = Vector2(120.0, 0.0)
	return state

func _deps() -> SimDeps:
	var deps := SimDeps.new()
	deps.plan_decide = func(s: CombatState, u: CombatUnit) -> Intent:
		return PlanInterpreter.decide(s, u)
	deps.default_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
		return Intent.idle() if u.team == CG.Team.PLAYER else DefaultBehavior.decide(_s, u)
	return deps

func _run(state: CombatState, deps: SimDeps, ticks: int) -> void:
	for _i in ticks:
		CombatSim.step(state, deps)

# ---------------------------------------------------------------------------
# the action itself
# ---------------------------------------------------------------------------

## The bug this issue exists to fix. Asserting the effect is merely present is
## what let a chain named "Chain Toss" ship for weeks hitting and never hauling,
## so this also asserts the distance is a real one.
func test_the_chain_carries_a_pull() -> void:
	var chain := ActionLibrary.get_action(&"warden_chain_toss")
	assert_ne(chain, null, "the Warden has a chain")
	var pull := chain.pull_effect()
	assert_ne(pull, null, "and it pulls, which is the whole of its name")
	assert_true(pull.distance > 0.0, "a pull of zero units is not a pull")

## Without a cooldown the chain row outcompetes the axe row on every free tick
## and the Warden never swings. This is the gate that makes two rows behave
## like two rows.
func test_the_chain_is_on_a_cooldown() -> void:
	assert_true(ActionLibrary.get_action(&"warden_chain_toss").cooldown_ticks > 0,
		"a chain with no cooldown is a permanent lock and the axe never fires")

# ---------------------------------------------------------------------------
# the plan
# ---------------------------------------------------------------------------

func test_the_warden_has_a_row_aimed_at_the_farthest_enemy() -> void:
	var rows := EnemyLibrary.get_enemy(&"the_warden").plans
	assert_true(rows.size() >= 2, "the chain and the axe are two different rows")
	var farthest_rows := 0
	for row in rows:
		for b in row.blocks:
			if b is TargetFarthestEnemyBlock:
				farthest_rows += 1
	assert_eq(farthest_rows, 1, "exactly one row reaches past the front line")

## Every row must be named for what it does. The row this replaced was called
## "Axe up close, chain toss at range" and did neither half.
func test_every_warden_row_names_the_action_it_fires() -> void:
	for row in EnemyLibrary.get_enemy(&"the_warden").plans:
		var used: Array[StringName] = []
		for b in row.blocks:
			if b is UseActionBlock and (b as UseActionBlock).action != null:
				used.append((b as UseActionBlock).action.id)
		assert_eq(used.size(), 1, "row '%s' fires exactly one named action" % row.id)

# ---------------------------------------------------------------------------
# and it pulls the FARTHEST one, in a stepped fight
# ---------------------------------------------------------------------------

## The load-bearing test. A chain that pulls the nearest pawn changes nothing
## about the fight; pulling the back line is the whole point.
func test_the_chain_hauls_the_farthest_pawn_and_leaves_the_nearest_where_it_stood() -> void:
	var state := _chain_only()
	var near := state.unit(0)
	var mid := state.unit(1)
	var far := state.unit(2)
	var near_at := near.position
	var mid_at := mid.position
	var far_at := far.position

	_run(state, _deps(), 60)

	## Every pawn's own `move_speed` is 0 and the Warden is pinned, so the chain
	## is the only thing in this fixture that can move anybody. The haul drags
	## the back pawn straight through the other two, which shoulders them a
	## couple of units aside; that is a body being dragged past, not a chain
	## landing on them, and the two are an order of magnitude apart.
	var hauled := far_at.x - far.position.x
	assert_true(hauled > 100.0,
		"the farthest pawn was hauled %.1f units toward the Warden" % hauled)
	assert_true(near.position.distance_to(near_at) < 10.0,
		"the nearest pawn was brushed past, not chained: %s -> %s" % [near_at, near.position])
	assert_true(mid.position.distance_to(mid_at) < 10.0,
		"and neither was the one in the middle: %s -> %s" % [mid_at, mid.position])

## The pull is authorised by the stun, per `_tick_pull`. A haul that does not
## stun is one the victim walks straight back out of.
func test_the_chained_pawn_is_stunned_for_the_haul() -> void:
	var state := _chain_only()
	var far := state.unit(2)
	var stunned_at := -1
	for i in 60:
		CombatSim.step(state, _deps())
		if far.has_status(CG.Status.STUN) and stunned_at == -1:
			stunned_at = i
	assert_true(stunned_at >= 0, "the farthest pawn was stunned by the chain")
	assert_false(state.unit(0).has_status(CG.Status.STUN), "and the nearest was not")

## The event stream says so too, so a player watching the log sees the chain
## land on the back rank rather than on whoever they were already watching.
func test_the_chain_event_names_the_farthest_pawn_as_its_target() -> void:
	var state := _chain_only()
	_run(state, _deps(), 60)
	var landed := 0
	for e in state.events:
		if e.action_id != &"warden_chain_toss":
			continue
		if e.kind != CG.EventKind.DAMAGE:
			continue
		landed += 1
		assert_eq(e.target_id, 2, "the chain landed on the farthest pawn")
	assert_true(landed > 0, "the chain landed at all")

## And the axe still happens. Two rows that both fire is the difference between
## a second row and a row that eats the first one's ticks.
func test_the_axe_still_swings_once_the_chain_is_on_cooldown() -> void:
	var state := _arena()
	_run(state, _deps(), 400)
	var axed := false
	for e in state.events:
		if e.action_id == &"warden_axe" and e.kind == CG.EventKind.DAMAGE:
			axed = true
	assert_true(axed, "the Warden closes and swings between chains")

# ---------------------------------------------------------------------------
# the throw
# ---------------------------------------------------------------------------

## A knot of three pawns off to one side and a loner within grabbing reach.
## The loner is the nearest, so it is what gets picked up; the knot is where
## the landing should be aimed, and there is exactly one right answer.
func _throw_arena() -> CombatState:
	var state := CombatState.new(_SEED)
	state.units.append(_victim(0, Vector2(60.0, 0.0)))
	state.units.append(_victim(1, Vector2(210.0, -20.0)))
	state.units.append(_victim(2, Vector2(230.0, 20.0)))
	state.units.append(_victim(3, Vector2(250.0, 0.0)))
	var warden := _warden(4, Vector2.ZERO)
	warden.move_speed = 0.0
	state.units.append(warden)
	return state

func _throw_ticks(state: CombatState) -> int:
	for i in 400:
		CombatSim.step(state, _deps())
		if state.unit(0).has_status(CG.Status.AIRBORNE):
			return i
	return -1

func test_the_warden_grabs_the_nearest_pawn_and_it_goes_airborne() -> void:
	var state := _throw_arena()
	assert_true(_throw_ticks(state) >= 0, "the nearest pawn was thrown")
	assert_false(state.unit(3).has_status(CG.Status.AIRBORNE),
		"and the far one was not: the grab reaches 70 units")

## The interesting half. Every other targeting in the game picks a unit; this
## picks a spot, and the spot is the one that catches the most pawns.
func test_the_throw_lands_on_the_knot_rather_than_beside_it() -> void:
	var state := _throw_arena()
	var thrown := state.unit(0)
	assert_true(_throw_ticks(state) >= 0, "somebody was thrown")
	_run(state, _deps(), CombatSim.THROW_TICKS + 2)

	var knot := (state.unit(1).position + state.unit(2).position + state.unit(3).position) / 3.0
	assert_true(thrown.position.distance_to(knot) < 120.0,
		"landed at %s, and the knot is around %s" % [thrown.position, knot])
	assert_true(thrown.position.x > 150.0, "it travelled, rather than being dropped")

## The player's words: *"the grabbed pawn is damaged twice"*. Once by the grab
## and once by the area it lands in, and both are named in the event stream so
## a player reading the log can see two hits rather than one big one.
func test_the_thrown_pawn_is_damaged_twice_by_two_named_actions() -> void:
	var state := _throw_arena()
	assert_true(_throw_ticks(state) >= 0, "somebody was thrown")
	_run(state, _deps(), CombatSim.THROW_TICKS + 2)

	var by_action: Dictionary = {}
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE and e.target_id == 0 and e.amount > 0:
			by_action[e.action_id] = int(by_action.get(e.action_id, 0)) + 1
	assert_true(by_action.has(&"warden_throw"), "hurt by the grab: %s" % [by_action])
	assert_true(by_action.has(&"warden_throw_impact"), "and by the landing: %s" % [by_action])

## The area, not just the passenger. A throw that only hurts the thrown pawn is
## a worse single-target attack, not an area attack.
func test_the_landing_hits_the_pawns_it_was_aimed_at() -> void:
	var state := _throw_arena()
	assert_true(_throw_ticks(state) >= 0, "somebody was thrown")
	_run(state, _deps(), CombatSim.THROW_TICKS + 2)

	var caught: Array[int] = []
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE and e.action_id == &"warden_throw_impact" \
				and e.amount > 0 and not caught.has(e.target_id):
			caught.append(e.target_id)
	assert_true(caught.size() >= 3, "the landing caught %d pawns: %s" % [caught.size(), caught])

## The whole of what AIRBORNE means: no moving of its own volition, no acting.
## Asserted against a pawn that would otherwise be walking and swinging, so
## this fails if the gate is ever taken out of `_decide_phase`.
func test_an_airborne_pawn_neither_acts_nor_walks_of_its_own_volition() -> void:
	var state := _throw_arena()
	var thrown := state.unit(0)
	thrown.move_speed = 8.0
	assert_true(_throw_ticks(state) >= 0, "somebody was thrown")

	var wanted: Array[Vector2] = []
	for _i in CombatSim.THROW_TICKS - 1:
		CombatSim.step(state, _deps())
		if not thrown.has_status(CG.Status.AIRBORNE):
			break
		assert_eq(thrown.intent, null, "an airborne pawn states no intent of its own")
		assert_eq(thrown.current_action, &"", "and starts no action")
		wanted.append(thrown.position)
	assert_true(wanted.size() >= 3, "it stayed in the air long enough to check")
	assert_ne(wanted[0], wanted[wanted.size() - 1],
		"it still travelled -- the throw moves it, its own legs do not")

## AIRBORNE ends when the flight does, so the two can never drift apart.
func test_airborne_lasts_exactly_the_flight_and_no_longer() -> void:
	var state := _throw_arena()
	var thrown := state.unit(0)
	assert_true(_throw_ticks(state) >= 0, "somebody was thrown")
	var airborne_ticks := 1
	for _i in CombatSim.THROW_TICKS * 3:
		CombatSim.step(state, _deps())
		if not thrown.has_status(CG.Status.AIRBORNE):
			break
		airborne_ticks += 1
	assert_eq(airborne_ticks, CombatSim.THROW_TICKS,
		"AIRBORNE and the flight are one constant")
	assert_eq(thrown.throw_ticks_left, 0, "and the flight is over")

## AIRBORNE is its own enum member rather than an alias for STUN, because the
## player's reason for it is *"other abilities in the future will check if
## airborne"*. A plan asks with the block it already has.
func test_a_plan_can_tell_airborne_apart_from_stunned() -> void:
	var state := _throw_arena()
	var thrown := state.unit(0)
	assert_true(_throw_ticks(state) >= 0, "somebody was thrown")

	var asks_airborne := EnemyHasStatusBlock.new()
	asks_airborne.status = CG.Status.AIRBORNE
	var asks_stun := EnemyHasStatusBlock.new()
	asks_stun.status = CG.Status.STUN
	var asker := state.unit(4)
	asker.focus_id = thrown.id

	assert_true(thrown.has_status(CG.Status.AIRBORNE), "it is in the air")
	assert_false(thrown.has_status(CG.Status.STUN), "and it is not stunned")
	assert_true(asks_airborne.holds(state, asker), "a plan can see the throw")
	assert_false(asks_stun.holds(state, asker), "and does not confuse it with a stun")
	assert_true(CG.is_harmful(CG.Status.AIRBORNE), "and knows it is a bad thing")

## A cleanse mid-flight drops the pawn where it is, and the landing never goes
## off. The same bargain `_tick_pull` already makes, and it is why AIRBORNE is
## harmful rather than a bare flag.
func test_a_cleanse_mid_flight_drops_the_pawn_and_cancels_the_landing() -> void:
	var state := _throw_arena()
	var thrown := state.unit(0)
	assert_true(_throw_ticks(state) >= 0, "somebody was thrown")
	_run(state, _deps(), 2)
	var dropped_at := thrown.position

	thrown.statuses.erase(CG.Status.AIRBORNE)
	var before := state.events.size()
	_run(state, _deps(), CombatSim.THROW_TICKS + 4)

	assert_eq(thrown.throw_ticks_left, 0, "the flight was cancelled")
	for i in range(before, state.events.size()):
		assert_ne(state.events[i].action_id, &"warden_throw_impact",
			"a cancelled flight has no landing")
	assert_true(dropped_at.distance_to(thrown.position) < 60.0, "it fell where it was")

## Nobody left to aim at is the one case the search cannot answer, and it must
## not throw the pawn to the origin or off the map.
func test_a_lone_pawn_is_thrown_no_further_than_where_it_stands() -> void:
	var state := CombatState.new(_SEED)
	state.units.append(_victim(0, Vector2(60.0, 0.0)))
	var warden := _warden(1, Vector2.ZERO)
	warden.move_speed = 0.0
	state.units.append(warden)

	var thrown := state.unit(0)
	var stood := thrown.position
	for _i in 400:
		CombatSim.step(state, _deps())
		if thrown.has_status(CG.Status.AIRBORNE):
			break
	_run(state, _deps(), CombatSim.THROW_TICKS + 2)
	assert_true(thrown.position.distance_to(stood) < 1.0,
		"thrown from %s to %s with nobody to aim at" % [stood, thrown.position])

# ---------------------------------------------------------------------------
# the axe combo, #836
# ---------------------------------------------------------------------------

func test_the_axe_is_a_three_beat_combo() -> void:
	var axe := ActionLibrary.get_action(&"warden_axe")
	assert_eq(axe.beats.size(), 3, "three parts, like Crescent")
	var last := -1
	for b in axe.beats:
		assert_true(b.delay_ticks > last, "beats are in ascending delay order")
		last = b.delay_ticks
	assert_eq(axe.beats[0].delay_ticks, 0, "the first part lands on the wind-up")

## Crescent's opener carries a `StepEffect` that moves the caster away. The
## Warden does not retreat: at `move_speed` 1.4 a jumpback costs him far more
## than it costs a Sellsword, and #830 already measured his own abilities
## working against him.
func test_no_beat_steps_the_warden_backwards() -> void:
	for b in ActionLibrary.get_action(&"warden_axe").beats:
		for fx in b.effects:
			assert_false(fx is StepEffect, "the Warden's combo has no jumpback")

## Each part swings a little further than the last, so a target drifting away
## between beats is still caught. This is the thing that keeps the connect rate
## at 100%, so it is asserted rather than left to the .tres.
func test_each_beat_reaches_at_least_as_far_as_the_one_before() -> void:
	var axe := ActionLibrary.get_action(&"warden_axe")
	var reach := 0.0
	for b in axe.beats:
		var r: float = b.targeting.range_units if b.targeting != null else axe.range_units
		assert_true(r >= reach, "beat reach never shrinks: %.1f after %.1f" % [r, reach])
		reach = r

func test_every_beat_can_open_a_bleed() -> void:
	var axe := ActionLibrary.get_action(&"warden_axe")
	var with_bleed := 0
	for b in axe.beats:
		for fx in b.effects:
			if fx is StatusEffect and (fx as StatusEffect).status == CG.Status.BLEED:
				with_bleed += 1
				assert_true((fx as StatusEffect).chance > 0.0 and (fx as StatusEffect).chance < 1.0,
					"a bleed CHANCE, not a certainty")
	assert_eq(with_bleed, axe.beats.size(), "all three parts can bleed")

## BLEED stacks (`bleed.tres`, `stacks = true`), so three landed beats build
## three stacks rather than refreshing one. That is what makes the number of
## beats that connected readable on the target.
func test_bleed_stacks_so_the_combo_builds_rather_than_refreshes() -> void:
	assert_true(StatusLibrary.of(CG.Status.BLEED).stacks,
		"the combo's bleed is only interesting because BLEED stacks")

# ---------------------------------------------------------------------------
# StatusEffect.chance, the one new mechanism
# ---------------------------------------------------------------------------

## The load-bearing property. An UNCONDITIONAL draw would advance `state.rng`
## for every status in the game and change every fight ever recorded, so the
## draw must happen only for an effect authored below 1.0.
func test_a_certain_status_draws_no_rng_at_all() -> void:
	var a := CombatState.new(_SEED)
	var b := CombatState.new(_SEED)
	var certain := StatusEffect.new()
	assert_eq(certain.chance, 1.0, "1.0 is the default, so nothing authored before #836 moved")
	assert_true(CombatSim._status_chance_holds(a, certain), "a certain status always lands")
	assert_eq(a.rng.randf(), b.rng.randf(),
		"the stream is where it was: asking about a certain status must not draw")

func test_a_chance_status_draws_exactly_once() -> void:
	var a := CombatState.new(_SEED)
	var b := CombatState.new(_SEED)
	var risky := StatusEffect.new()
	risky.chance = 0.5
	CombatSim._status_chance_holds(a, risky)
	b.rng.randf()
	assert_eq(a.rng.randf(), b.rng.randf(), "one draw, not two and not none")

## A chance of 0 never lands and a chance of 1 always does, checked over enough
## draws that a stuck comparison cannot pass by luck.
func test_the_extremes_hold() -> void:
	var state := CombatState.new(_SEED)
	var never := StatusEffect.new()
	never.chance = 0.0
	var always := StatusEffect.new()
	for _i in 50:
		assert_false(CombatSim._status_chance_holds(state, never), "0.0 never lands")
		assert_true(CombatSim._status_chance_holds(state, always), "1.0 always lands")

## The negative: a chance in the middle must actually be a coin, not a constant
## dressed as one. Both outcomes have to appear.
func test_a_middling_chance_produces_both_outcomes() -> void:
	var state := CombatState.new(_SEED)
	var risky := StatusEffect.new()
	risky.chance = 0.5
	var landed := 0
	for _i in 200:
		if CombatSim._status_chance_holds(state, risky):
			landed += 1
	assert_true(landed > 40 and landed < 160,
		"200 draws at 0.5 landed %d times, which is not a coin" % landed)

## And it is deterministic, which is the whole contract the draw has to keep.
func test_one_seed_rolls_the_same_bleeds_twice() -> void:
	var risky := StatusEffect.new()
	risky.chance = 0.35
	var first: Array[bool] = []
	var second: Array[bool] = []
	var a := CombatState.new(_SEED)
	var b := CombatState.new(_SEED)
	for _i in 60:
		first.append(CombatSim._status_chance_holds(a, risky))
		second.append(CombatSim._status_chance_holds(b, risky))
	assert_eq(first, second, "same seed, same rolls")
