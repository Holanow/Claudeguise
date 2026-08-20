extends "res://Tests/TestCase.gd"


## Issue 87, the content half: does the Geysermancer's cleanse reach a real
## fight, and does it strip anything when it gets there?

## **Fixture headroom, and why both constants below moved (heron found this,
## finch measured and fixed it).** `test_..._stripping_harm_from_an_ally`'s
## `on_ally` count drifted **6 -> 2 -> 3 -> 1** across four builds with nobody
const SEEDS := 24
const ENCOUNTER := &"floor1_rat_king"

## The margin `test_the_ally_cleanse_fixture_still_has_headroom` guards. Set well
## below the measured count (69 at issue 223) so ordinary content tuning does not
## trip it, and well above 0 so the slide is caught long before the assertion it
## protects. **Not raised to match the new headroom**: the floor asks "is this
## fixture still measuring anything", which is the same question at 10 as at 69.
const MIN_ALLY_CLEANSES := 4

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in Registry.all_class_ids():
		if cid == &"abomination":
			continue
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

## Every STATUS_EXPIRED naming a caster and an action -- the shape only a
## cleanse produces. A status running out on its own carries source_id -1 and no
## action id (swift's signature note, and `CombatSim._tick_statuses`).
func _cleanse_events(state: CombatState) -> Array:
	var out := []
	for e in state.events:
		if e.kind == CG.EventKind.STATUS_EXPIRED and e.source_id != -1 and e.action_id == &"geyser_cleanse":
			out.append(e)
	return out

func _run(fight_seed: int) -> CombatState:
	var deps := SimDeps.new()
	var state := CombatSim.build(_party(), Registry.get_encounter(ENCOUNTER), fight_seed, deps)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state, deps)
	return state


## **This assertion used to name POISON, and issue 121 is the change that made
## that wrong.** It read `assert_eq(e.status, CG.Status.POISON)` with the reason
## *"POISON is the only harmful status anything applies to a player unit today"*,
func test_a_real_fight_shows_a_geysermancer_stripping_harm_from_an_ally() -> void:
	var strips := 0
	var on_an_ally := 0
	var by_status := {}
	for s in SEEDS:
		var state := _run(s)
		for e in _cleanse_events(state):
			strips += 1
			by_status[e.status] = int(by_status.get(e.status, 0)) + 1
			assert_eq(e.action_id, &"geyser_cleanse",
				"the only action in the game that strips a status is the Geysermancer's")
			assert_true(CG.is_harmful(e.status),
				"Scour stripped %s, which CG.is_harmful says is not a harmful status. A cleanse that removes a buff is the ability doing the opposite of its job." % _status_name(e.status))
			var caster := state.unit(e.source_id)
			assert_eq(caster.pawn.pawn_class.id, &"geysermancer")
			var target := state.unit(e.target_id)
			assert_eq(target.team, CG.Team.PLAYER, "a cleanse must never land on an enemy")
			if e.target_id != e.source_id:
				on_an_ally += 1
	assert_true(strips > 0, "the cleanse stripped nothing in %d real fights" % SEEDS)
	assert_true(on_an_ally > 0, "the cleanse only ever scrubbed its own caster; the ability is for the party")
	# **The supply, said plainly, because it is what the fixture rests on.** Every
	# other assertion in this file is worthless if nothing in the room ever
	# afflicts a pawn -- such a room passes every "never strips a buff" check by
	var harmful := 0
	for k in by_status.keys():
		if CG.is_harmful(k):
			harmful += int(by_status[k])
	assert_true(harmful > 0,
		("nothing harmful was stripped in %d fights of %s, so this fixture's affliction supply has gone. "
		+ "Re-measure with Tools/CleanseFixture.gd and re-point ENCOUNTER, and do NOT edit a "
		+ "room's roster to feed this test. Stripped instead: %s") % [SEEDS, ENCOUNTER, _describe(by_status)])

func _status_name(status: CG.Status) -> String:
	return String(CG.Status.keys()[status]).capitalize()

func _describe(by_status: Dictionary) -> String:
	if by_status.is_empty():
		return "nothing at all"
	var parts: Array[String] = []
	for k in by_status.keys():
		parts.append("%s x%d" % [_status_name(k), int(by_status[k])])
	return ", ".join(parts)


## **The margin, not the cliff.** This is the test that should have existed
## before `on_ally` slid 6 -> 2 -> 3 -> 1 with nobody noticing.
func test_the_ally_cleanse_fixture_still_has_headroom() -> void:
	var on_an_ally := 0
	for s in SEEDS:
		var state := _run(s)
		for e in _cleanse_events(state):
			if e.target_id != e.source_id:
				on_an_ally += 1
	assert_true(on_an_ally >= MIN_ALLY_CLEANSES,
		("ally cleanses have fallen to %d over %d seeds of %s (floor %d). The fixture is "
		+ "about to stop measuring anything. DO NOT RAISE SEEDS: this count is driven by "
		+ "GEOMETRY, not by sampling -- the cleanse reaches 200 units and a spread-out party "
		+ "puts the afflicted ally out of reach, so a starved room reads the same number at "
		+ "every seed count (floor1_cover measured 2 at 6, 12, 24 and 48; floor1_room1 now "
		+ "reads 0 at all four). Repoint ENCOUNTER at a room that bunches the party around a "
		+ "continuous source of harm, and re-measure with Tools/CleanseFixture.gd -- its "
		+ "harmful column is this file's supply assertion. Do NOT edit a room's roster to "
		+ "feed this test.")
		% [on_an_ally, SEEDS, ENCOUNTER, MIN_ALLY_CLEANSES])


## The negative half, and the one the whole design turns on: **does the
## condition actually gate the cast, or does it fire blind?**
func test_the_cleanse_does_not_fire_blind() -> void:
	var casts := 0
	var strips := 0
	for s in SEEDS:
		var state := _run(s)
		strips += _cleanse_events(state).size()
		for e in state.events:
			if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"geyser_cleanse":
				casts += 1
	assert_true(casts > 0, "fixture is meaningless if the cleanse never fired at all")
	assert_true(strips * 2 >= casts,
		"%d casts stripped only %d statuses; the condition is not gating the cast" % [casts, strips])


## Determinism, the project's own hard rule. The cleanse consults no rng --
## neither the plan ops (nearest, over `state.living` order) nor the strip
## itself (sorted keys) -- so one seed must produce the same cleanses twice.
func test_the_cleanse_is_deterministic_on_one_seed() -> void:
	var first := _cleanse_events(_run(0))
	var second := _cleanse_events(_run(0))
	assert_eq(first.size(), second.size())
	for i in first.size():
		assert_eq(first[i].tick, second[i].tick)
		assert_eq(first[i].source_id, second[i].source_id)
		assert_eq(first[i].target_id, second[i].target_id)
		assert_eq(first[i].status, second[i].status)


## "and the log says so" is the issue's own acceptance wording, so it is
## checked against `CombatLogView.line_for_event` -- the function the battle
## screen actually renders -- rather than against a sentence composed here,
## which would only ever agree with itself.
func test_the_combat_log_reports_the_cleanse() -> void:
	var log_view := CombatLogView.new()
	var saw_the_cast := false
	var saw_the_strip := false
	for s in SEEDS:
		var state := _run(s)
		for e in state.events:
			var line: String = log_view.line_for_event(state, e)
			if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"geyser_cleanse":
				assert_true(line.contains("Scour"), "the cast should name the ability, got '%s'" % line)
				saw_the_cast = true
			elif e.kind == CG.EventKind.STATUS_EXPIRED and e.source_id != -1:
				# Issue 121: the status the event actually carries, not the word
				# "Poison". This hardcoded the one status that existed when it was
				# written, so heron's Stalker made it report `warrior's Marked
				# fades` as a defect -- a correct line, failing a test that was
				# checking the content rather than the log.
				assert_true(line.contains(_status_name(e.status)),
					"the strip should name the status it removed (%s), got '%s'" % [_status_name(e.status), line])
				saw_the_strip = true
	log_view.free()
	assert_true(saw_the_cast and saw_the_strip)

## **The poison-specific claim, moved here from the fight above in issue 160 and
## made deterministic on the way.**
func test_scour_strips_poison_specifically() -> void:
	var party: Array[PawnData] = [
		PawnFactory.make_starter_pawn(&"geysermancer", &"g0", "Geysermancer"),
		PawnFactory.make_starter_pawn(&"priest", &"p0", "Priest"),
	]
	var deps := SimDeps.new()
	var state := CombatSim.build(party, Registry.get_encounter(ENCOUNTER), 0, deps)
	var ally: CombatUnit = null
	var caster: CombatUnit = null
	for u in state.units:
		if u.pawn == null:
			continue
		if u.pawn.pawn_class.id == &"geysermancer":
			caster = u
		else:
			ally = u
	assert_not_null(caster)
	assert_not_null(ally)
	# Inside the cleanse's 200-unit reach, and afflicted.
	ally.position = caster.position + Vector2(50.0, 0.0)
	ally.statuses[CG.Status.POISON] = state.tick + 300
	var stripped := 0
	for i in 240:
		CombatSim.step(state, deps)
		for e in _cleanse_events(state):
			if e.status == CG.Status.POISON and e.target_id == ally.id:
				stripped += 1
		if stripped > 0:
			break
	assert_true(stripped > 0,
		"a Geysermancer standing 50 units from a poisoned ally never scoured the poison off it")
