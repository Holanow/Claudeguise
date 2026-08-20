extends "res://Tests/TestCase.gd"


## ISSUE 249, my third of it. `outcome` says who won; `end_reason` says what
## finished it, which is the half a player cannot recover by looking at the
## screen. Before #243 there was one ending and it needed no name. There are
## now two, and on seed 0 of `floor1_warden` the second one reads "The Warden's
## Marked fades" and then Defeat -- legible only to somebody who already knows
## the rule.

const SEEDS := 40
const WARDEN := &"floor1_warden"

# --- fixtures ---------------------------------------------------------------

func _turret(id: int, team: CG.Team) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = 100
	u.hp = 100
	u.move_speed = 0.0
	return u

func _deps() -> SimDeps:
	var marked_only := ActionDef.new()
	marked_only.id = &"fixture_marked_bolt"
	marked_only.requires_marked_target = true
	marked_only.range_units = 9000.0
	var plain := ActionDef.new()
	plain.id = &"fixture_bolt"
	plain.range_units = 9000.0
	var lookup := {&"fixture_marked_bolt": marked_only, &"fixture_bolt": plain}
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName) -> ActionDef: return lookup.get(id, null)
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	return deps

func _end_reasons(state: CombatState) -> Array:
	var out: Array = []
	for e in state.events:
		if e.kind == CG.EventKind.FIGHT_END:
			out.append(e.end_reason)
	return out

func test_a_side_killed_off_ends_the_fight_with_no_survivors() -> void:
	var state := CombatState.new(0)
	var pawn := _turret(0, CG.Team.PLAYER)
	pawn.actions = [&"fixture_bolt"] as Array[StringName]
	state.units.append(pawn)
	var foe := _turret(1, CG.Team.ENEMY)
	foe.actions = [&"fixture_bolt"] as Array[StringName]
	foe.alive = false
	state.units.append(foe)
	CombatSim.step(state, _deps())
	assert_eq(_end_reasons(state), [CG.EndReason.NO_SURVIVORS] as Array,
		"the enemy has no living unit left; that is the ending the game always had")

func test_a_stranded_side_ends_the_fight_because_it_cannot_act() -> void:
	var state := CombatState.new(0)
	var stranded := _turret(0, CG.Team.PLAYER)
	stranded.actions = [&"fixture_marked_bolt"] as Array[StringName]
	state.units.append(stranded)
	var foe := _turret(1, CG.Team.ENEMY)
	foe.actions = [&"fixture_bolt"] as Array[StringName]
	state.units.append(foe)
	CombatSim.step(state, _deps())
	assert_eq(_end_reasons(state), [CG.EndReason.CANNOT_ACT] as Array,
		"both sides still have a unit standing; one of them can never act again")
	assert_true(state.unit(0).alive, "and the stranded unit is alive, which is the whole point")

## The mislabel this is guarding against: a side that was already empty must not
## be reported as stranded just because `_side_can_fight` would also say no.
func test_an_empty_side_is_never_reported_as_stranded() -> void:
	var state := CombatState.new(0)
	var stranded := _turret(0, CG.Team.PLAYER)
	stranded.actions = [&"fixture_marked_bolt"] as Array[StringName]
	state.units.append(stranded)
	var foe := _turret(1, CG.Team.ENEMY)
	foe.actions = [&"fixture_bolt"] as Array[StringName]
	foe.alive = false
	state.units.append(foe)
	CombatSim.step(state, _deps())
	assert_eq(_end_reasons(state), [CG.EndReason.NO_SURVIVORS] as Array,
		"the enemy died; the fact that the winner is also stranded does not name this ending")

# --- the real game ----------------------------------------------------------

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in Registry.all_class_ids():
		if cid == &"abomination":
			continue
		out.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

func _warden_fights() -> Array:
	var encounter := Registry.get_encounter(WARDEN)
	var out: Array = []
	for s in SEEDS:
		var state := CombatSim.build(_party(), encounter, s)
		CombatSim.run(state)
		out.append(state)
	return out

## THE ASSERTION rook asked for, and it is run against real content because a
## fixture proves only that the setter reads what I gave it.
func test_every_real_ending_carries_a_reason() -> void:
	var seen := {}
	var endings := 0
	for state in _warden_fights():
		for reason in _end_reasons(state):
			endings += 1
			seen[reason] = true
			assert_true(reason != CG.EndReason.UNSET,
				"a FIGHT_END with no reason on it is a defect in CombatSim._check_outcome")
	assert_eq(endings, SEEDS, "one ending per fight, and every fight resolved")
	assert_true(seen.has(CG.EndReason.NO_SURVIVORS), "the ordinary ending still happens")
	assert_true(seen.has(CG.EndReason.CANNOT_ACT),
		("no fight on %s ended with a side stranded, and issue 233 measured 11 of 40 "
		+ "here. If content has genuinely stopped producing that ending, say so before "
		+ "loosening this line.") % WARDEN)

## THE TRIPWIRE for the ending `CG.EndReason` cannot name. Red the day a real
## fight runs out of ticks, which is the day the enum needs a third value.
func test_no_real_fight_reaches_the_tick_cap() -> void:
	for state in _warden_fights():
		assert_true(state.tick < CG.MAX_TICKS,
			("a fight hit CG.MAX_TICKS. Its FIGHT_END carries UNSET, because a cap is "
			+ "neither NO_SURVIVORS nor CANNOT_ACT. CG.EndReason now needs a third "
			+ "value -- that is a Core change and it is rook's. See issue 249."))
