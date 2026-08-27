extends "res://Tests/TestCase.gd"


## Issue 166: Channel, the ability a caster has to sit idle for.

const CHANNEL := &"channel_mana"

func _channel() -> ActionDef:
	return Registry.get_action(CHANNEL)

# ---------------------------------------------------------------------------
# the shape of the ability
# ---------------------------------------------------------------------------

func test_the_channel_costs_time_and_nothing_else() -> void:
	var a := _channel()
	assert_not_null(a, "channel_mana is not registered")
	assert_eq(a.resource_cost, 0, "a mana restore you pay mana for is not a restore")
	assert_true(a.restores_resource > 0, "Channel returns nothing, so it does nothing")
	assert_true(a.targets_self, "Channel is cast on its caster")
	assert_eq(a.range_units, 0.0, "Channel reaches nobody but the caster")
	assert_true(a.cooldown_ticks > a.wind_up_ticks,
		"a Channel that can be re-cast the moment it lands is a second resource bar, not a choice")

# ---------------------------------------------------------------------------
# who has it
# ---------------------------------------------------------------------------

## Gated on the resource, not on `CG.Method`. Three classes are MAGICAL and one
## of those (the Abomination) spends Rage, which `CombatSim` never restores this
## way; the Siege Master spends Mana and is MARTIAL. Mana is the half that
## decides whether the ability does anything at all.
func test_every_mana_caster_has_the_channel_and_nobody_else_does() -> void:
	var expected := {&"priest": true, &"geysermancer": true,
		&"siege_master": false, &"warrior": false, &"abomination": false}
	for cid in ClassLibrary.all_ids():
		var def := Registry.get_class_def(cid)
		var has: bool = def.starting_action_ids().has(CHANNEL)
		assert_eq(has, bool(expected.get(cid, false)),
			"%s %s the Channel" % [cid, "has" if has else "does not have"])

func test_the_two_classes_that_have_it_spend_mana() -> void:
	for cid in [&"priest", &"geysermancer"]:
		assert_eq(Registry.get_class_def(cid).resource_kind, CG.ResourceKind.MANA,
			"%s no longer spends Mana, so the Channel on it restores nothing" % cid)

## The plan editor is where the player picks it up, and it offers what the pawn
## has rather than a second list.
func test_the_plan_editor_offers_the_channel_to_a_starter_priest() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"priest", &"p0", "Priest")
	assert_true(Registry.actions_for_pawn(pawn).has(CHANNEL),
		"a starter Priest cannot pick the Channel out of its own action list")

# ---------------------------------------------------------------------------
# the plan row, and the two points of WIS that pay for it
# ---------------------------------------------------------------------------

## **No class's preset plans may cost more WIS than it has**, which is what the
## name says and the half that is a rule rather than a snapshot.
func test_no_class_carries_a_plan_row_it_cannot_pay_for() -> void:
	var over: Array[String] = []
	for cid in ClassLibrary.all_ids():
		var pawn := PawnFactory.make_starter_pawn(cid, cid, String(cid))
		var free_blocks := Balance.plan_block_budget(pawn) - PresetPlans.total_blocks(cid)
		if free_blocks < 0:
			over.append("%s (%d over)" % [cid, free_blocks])
	assert_eq(over, [] as Array[String],
		"A class's presets cost more blocks than its WIS pays for: %s" % [over])

## Both casters run every row in their library, the Channel included. Issue 399:
## a starter pawn ships with none, so the rows are added here the way a player
## adds them.
func test_both_casters_run_every_row_including_the_channel() -> void:
	for cid in [&"priest", &"geysermancer"]:
		var pawn := PawnFactory.make_preset_pawn(cid, cid, String(cid))
		assert_eq(PlanInterpreter.active_plan_count(pawn), pawn.plans.size(),
			"a starter %s cannot pay for its own last row" % cid)
		var last_action: ActionDef = (pawn.plans[pawn.plans.size() - 1].blocks[1] as UseActionBlock).action
		assert_eq(last_action.id if last_action != null else &"", CHANNEL,
			"the Channel is not the %s's last row, so the assertion above proves something else" % cid)

## The Robes are what pay for it, asserted rather than assumed: take them off and
## the row strands. This is the screen's own "Inert: needs %d WIS" case.
func test_taking_the_robes_off_strands_the_channel_row() -> void:
	for cid in [&"priest", &"geysermancer"]:
		var pawn := PawnFactory.make_preset_pawn(cid, cid, String(cid))
		assert_not_null(pawn.armor, "a starter %s no longer wears anything" % cid)
		pawn.armor = null
		assert_eq(PlanInterpreter.active_plan_count(pawn), pawn.plans.size() - 1,
			"the %s's Channel row is paid for by something other than its armour" % cid)

# ---------------------------------------------------------------------------
# it fires in a real fight
# ---------------------------------------------------------------------------

func test_the_channel_fires_in_a_real_encounter_and_returns_its_mana() -> void:
	var party: Array[PawnData] = [PawnFactory.make_preset_pawn(&"priest", &"p0", "Priest")]
	var state := CombatSim.build(party, Registry.get_encounter(&"floor1_room1"), 7)
	var priest := state.unit(0)
	assert_not_null(priest, "no Priest was built")
	priest.resource = 0
	## Passive regen off: the only thing allowed to move this pool is the Channel.
	var deps := SimDeps.new()
	deps.resource_regen_per_tick = func(_u) -> float: return 0.0

	var restored := -1
	var seen := 0
	for _i in 900:
		if not priest.alive:
			break
		var before := priest.resource
		CombatSim.step(state, deps)
		var fired := false
		while seen < state.events.size():
			var e: CombatEvent = state.events[seen]
			seen += 1
			if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == CHANNEL and e.source_id == 0:
				fired = true
		if fired:
			restored = priest.resource - before
			break
	assert_true(restored >= 0, "the Channel never fired in a real fight")
	assert_eq(restored, _channel().restores_resource,
		"a Channel that landed in a real fight returned %d Mana" % restored)

## The "sit idle for it" half, asserted rather than assumed: the caster does not
## move for the whole wind-up.
func test_the_caster_stands_still_for_the_whole_wind_up() -> void:
	var party: Array[PawnData] = [PawnFactory.make_preset_pawn(&"priest", &"p0", "Priest")]
	var state := CombatSim.build(party, Registry.get_encounter(&"floor1_room1"), 7)
	var priest := state.unit(0)
	priest.resource = 0
	var deps := SimDeps.new()
	deps.resource_regen_per_tick = func(_u) -> float: return 0.0
	var anchor := Vector2.ZERO
	var held := 0
	var best := 0
	var moved := 0
	for _i in 900:
		if not priest.alive:
			break
		CombatSim.step(state, deps)
		if priest.current_action == CHANNEL and priest.action_ticks_left > 0:
			if held == 0:
				anchor = priest.position
			held += 1
			if priest.position != anchor:
				moved += 1
			best = maxi(best, held)
		else:
			held = 0
	assert_eq(moved, 0, "the caster moved during a Channel, so it is not idling for it")
	## The wind-up is AGI-scaled, so the exact figure is the pawn's, not the
	## action's. Two Bolt cycles is the floor the shape test above asserts.
	var bolt := Registry.get_action(&"priest_bolt")
	assert_true(best >= bolt.wind_up_ticks + bolt.recover_ticks,
		"the longest Channel held was %d ticks, under one Bolt cycle" % best)

## A stun breaks it, which is the counterplay the wind-up buys. Asserted on a
## hand-built fight because no floor-1 enemy stuns.
func test_a_stun_during_the_wind_up_returns_no_mana() -> void:
	var party: Array[PawnData] = [PawnFactory.make_preset_pawn(&"priest", &"p0", "Priest")]
	var state := CombatSim.build(party, Registry.get_encounter(&"floor1_room1"), 7)
	var priest := state.unit(0)
	priest.resource = 0
	priest.focus_id = priest.id
	priest.intent = Intent.use_action(CHANNEL, priest.id)
	var deps := SimDeps.new()
	deps.plan_decide = func(_s, _u): return null
	deps.default_decide = func(_s, _u): return Intent.idle()
	deps.resource_regen_per_tick = func(_u) -> float: return 0.0
	CombatSim.step(state, deps)
	assert_eq(priest.current_action, CHANNEL, "the Channel never started")
	priest.statuses[CG.Status.STUN] = state.tick + 30
	for _i in _channel().wind_up_ticks + 5:
		CombatSim.step(state, deps)
	assert_eq(priest.resource, 0, "a broken Channel still paid out")
