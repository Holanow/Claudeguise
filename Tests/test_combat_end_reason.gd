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
	marked_only.targeting = ActionTargeting.new()
	marked_only.targeting.requires_marked_target = true
	marked_only.targeting.range_units = 9000.0
	marked_only.effects = [HitEffect.new()] as Array[AbilityEffect]
	var plain := ActionDef.new()
	plain.id = &"fixture_bolt"
	plain.targeting = ActionTargeting.new()
	plain.targeting.range_units = 9000.0
	plain.effects = [HitEffect.new()] as Array[AbilityEffect]
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
		out.append(PawnFactory.make_preset_pawn(
			cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out