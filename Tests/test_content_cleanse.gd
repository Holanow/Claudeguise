extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const CombatLogView := preload("res://Scripts/UI/CombatLogView.gd")

## Issue 87, the content half: does the Geysermancer's cleanse reach a real
## fight, and does it strip anything when it gets there?
##
## Deliberately a whole-fight test and not a unit one. `Tests/test_combat_
## cleanse.gd` (swift's) already proves the mechanism strips what it is handed;
## `Tests/test_plans_interpreter.gd` proves the two new plan ops pick the right
## unit. Neither of those can fail if the action is never chosen, and being
## never chosen is exactly what happened to `geyser_scald` for the whole of its
## existence and to a *free* probe cleanse in all 210 of swift's fights. So the
## check that matters here runs the real Registry, the real preset plans and the
## real CombatSim, and asserts a strip actually happened.
##
## The party is built in `Registry.all_class_ids()` order minus the Abomination,
## which is what `Tools/SampleFights.gd` and `PartySelect` both do. Order is
## load-bearing for outcomes (see `test_content_encounter.gd`'s own header on
## spawn order), so it is stated rather than assumed -- but this test asserts
## across six seeds rather than on one fight, so it does not depend on any
## single fight going a particular way.

## **Fixture headroom, and why both constants below moved (heron found this,
## finch measured and fixed it).** `test_..._stripping_poison_from_an_ally`'s
## `on_ally` count drifted **6 -> 2 -> 3 -> 1** across four builds with nobody
## touching this file, and on merged trunk it sat at **1** against an assertion
## needing more than zero. One more content change in any direction and it goes
## red for somebody who has no idea why.
##
## **The rare event is not poison.** That was the obvious reading and it is
## wrong: `floor1_cover` poisons player pawns **113 times** across six fights.
## The rare event is *the Geysermancer cleansing somebody other than itself*.
## Measured per encounter with `Tools/CleanseFixture.gd`, `on_ally` as a
## fraction of all strips:
##
##     floor1_chokepoint   0 of 28   (0%)   -- 249 poisonings, never once an ally
##     floor1_cover        4 of 38   (11%)
##     floor1_room1       16 of 44   (36%)
##
## It is geometry. The cleanse reaches 200 units, and in the walled rooms the
## party is spread far enough that the afflicted ally is usually out of reach, so
## the Geysermancer scours itself instead. `floor1_chokepoint` is the proof: the
## most poison of any room and not one ally cleanse at any seed count.
##
## So `ENCOUNTER` is `floor1_room1` (best rate, and the room heron's four-room
## work did not touch) and `SEEDS` is 12, which measures **9** ally cleanses
## rather than 1. **Deliberately not fixed by bending the `floor1_cover` roster
## to feed this fixture** -- heron argued against that and rook agreed: that
## roster came from four measured variants, and pointing content at a test's
## needs stops the room being the thing that was measured.
##
## **The real defect was that nothing watched the margin.** `> 0` gives no
## warning as it slides 6 -> 2 -> 3 -> 1; it is silent until the day it is a
## failure. `test_the_ally_cleanse_fixture_still_has_headroom` below asserts the
## margin itself, so the slide is what goes red, with instructions, rather than
## the cliff.
##
## **The detector did its job, and this is the second move. Issue 129 (the basic
## attack comes from the weapon, and every starter pawn is armed) took
## `floor1_room1` from 9 ally cleanses to 3** -- still above zero, so the
## assertion it guards was still green and would have told nobody. The headroom
## test is what went red, which is the whole reason it exists.
##
## Re-measured with `Tools/CleanseFixture.gd` on the issue-129 branch, `on_ally`:
##
##                        6 seeds  12 seeds  24 seeds
##     floor1_chokepoint      0        2         4
##     floor1_cover           4        6        10
##     floor1_room1           2        3         7
##     (the other four rooms field no poison source at all: 0 everywhere)
##
## **The geometry finding above still holds and the ranking has swapped anyway.**
## Room1 still cleanses allies at the best *rate*, but an armed party kills the
## cultist far sooner, so there is much less poison to strip: 65 poisonings over
## 12 seeds where `floor1_cover` has 211. Supply, not reach, is now the binding
## constraint in the room that used to be the roomy one.
##
## So `ENCOUNTER` is `floor1_cover` and `SEEDS` is 24, measuring **10** -- the
## margin this fixture had when the detector was written, restored rather than
## approximated. It costs twice the fights this file used to run, and that is the
## price of a fixture that is not about to rot again.
##
## **Fourth movement, and the detector fired again: `floor1_cover` collapsed
## 10 -> 2 under issue 132's taunt compulsion.** Re-measured all seven rooms
## with `Tools/CleanseFixture.gd` on swift's branch, `on_ally` at 24 seeds:
##
##     floor1_room1        7      floor1_chokepoint   3
##     floor1_cover        2      the other four      0 (no poison source)
##
## **The geometry finding is what moved, and in the direction it predicts.** A
## compelled pawn walks to its taunter, so the party bunches differently, and
## `floor1_cover` -- which had the most poison in the game at 498 poisonings --
## now puts the afflicted ally out of the cleanse's 200 units almost every time.
## Supply went *up* and ally cleanses went *down*, which is the same dissociation
## this header has recorded twice.
##
## `floor1_room1` measured 7 both before and after the compulsion, so it is the
## stable one as well as the best one. Back to it, seeds unchanged at 24.
##
## **Said plainly: the margin is now 3 over a floor of 4, and no room in the game
## does better.** This fixture has moved four times in a fortnight and every move
## has been a real content change rather than carelessness. It is running out of
## room, and the underlying reason is the one I reported on #91 -- Scour is a weak
## ability whose supply nobody is designing for. If it moves a fifth time the
## question is whether the ability wants a source of its own, not where to point
## the test next.
##
## **Fifth movement, issue 121, and back to `floor1_cover`.** Burn made fights in
## `floor1_room1` short enough that its poison supply collapsed -- 57 poisonings
## across 24 seeds against `floor1_cover`'s 399 -- and ally cleanses there went to
## **0**. Cover measures **20**, the widest margin this fixture has ever had.
##
## **The ping-pong is the finding, and I am naming it rather than moving the
## fixture a sixth time in silence.** Room1 and cover have now swapped places
## twice, each time because a real mechanic landed: the taunt compulsion bunched
## parties and starved cover, then burn shortened fights and starved room1. The
## fixture is not fragile because it was chosen badly. It is fragile because
## **Scour's supply is nobody's design** -- the #91 finding, unaddressed, showing
## up as test maintenance. A sixth move should be a decision about the ability.
##
## **And the instrument had drifted with it.** `Tools/CleanseFixture.gd` counted
## "STATUS_EXPIRED carrying a source", which stopped meaning "a cleanse" the
## moment `geyser_blast` began consuming BURN through the same event. It reported
## room1 at 66 ally cleanses where this test sees 0. Fixed in the same commit;
## I nearly picked a fixture off the wrong number.
const SEEDS := 24
const ENCOUNTER := &"floor1_cover"

## The margin `test_the_ally_cleanse_fixture_still_has_headroom` guards. Set well
## below the measured 10 so ordinary content tuning does not trip it, and well
## above 0 so the slide is caught long before the assertion it protects.
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
## Issue 121: **`action_id` as well as a caster, and the narrowing is load-bearing
## rather than tidying.** "STATUS_EXPIRED carrying a source" used to mean exactly
## one thing, because a cleanse was the only way a status ended early. Blast now
## *consumes* a burn and emits the same shape deliberately -- swift's
## `_consume_status` mirrors `_cleanse_harmful` so a log can tell "Blast ate the
## burn" from "the burn ran out". So this file started counting the combo as
## cleanses and asserting a Geysermancer had scoured an enemy.
##
## The fix is to say which action, not to loosen the assertions that caught it.
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
## which was true when it was written and was a statement about the whole game
## rather than about this ability. heron's Stalker marks a pawn, so a Scour now
## legitimately strips MARKED and the fixture called it a defect.
##
## **The third movement of this fixture, and the first that is a design change
## rather than drift.** The first two were content quietly sliding the `ON_ALLY`
## count (6 -> 2 -> 3 -> 1, then 9 -> 3) and the answer was to re-point the
## fixture. This one is not drift: the game now has more than one harmful status
## on purpose, which is issue 121's entire point, and no fixture change makes the
## old assertion true again.
##
## So it asserts the ability's real contract -- **a cleanse strips something
## harmful and never strips a buff** -- which no amount of new content can
## falsify. Supply is asserted separately below, because "there was something to
## strip" is the thing this fixture actually depends on and it deserves to be
## said out loud rather than to hide inside an equality on a status id.
func test_a_real_fight_shows_a_geysermancer_stripping_poison_from_an_ally() -> void:
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
	# afflicts a pawn -- four of the seven encounters field no poison source at
	# all and would pass every "never strips a buff" check by stripping nothing.
	# The old POISON equality was guarding this by accident; now it is guarded on
	# purpose, and it names the room rather than the whole game.
	assert_true(int(by_status.get(CG.Status.POISON, 0)) > 0,
		("no POISON was stripped in %d fights of %s, so this fixture's affliction supply has gone. "
		+ "It is not enough that SOMETHING was stripped: this room was chosen for its poison. "
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
##
## `assert_true(on_an_ally > 0)` above is the property the ability is *for*, and
## it is worth asserting, but it is silent for the entire journey toward failing:
## it reads identically at 6 and at 1, and only speaks on the build that reaches
## 0 -- by which point the person it fails for is whoever touched content next
## and has no idea this fixture depends on room geometry.
##
## So this asserts the headroom itself. When it fires, the fixture is still
## green and the fix is cheap; the message says what to do rather than leaving
## the next person to rediscover the geometry finding.
##
## **It is deliberately not a tighter version of the same assertion.** It fails
## *earlier*, on a number that is still passing, which is the only kind of guard
## that turns a slow drift into a loud event.
func test_the_ally_cleanse_fixture_still_has_headroom() -> void:
	var on_an_ally := 0
	for s in SEEDS:
		var state := _run(s)
		for e in _cleanse_events(state):
			if e.target_id != e.source_id:
				on_an_ally += 1
	assert_true(on_an_ally >= MIN_ALLY_CLEANSES,
		("ally cleanses have fallen to %d over %d seeds of %s (floor %d). The fixture is "
		+ "about to stop measuring anything. This count is driven by GEOMETRY, not by poison "
		+ "supply -- the cleanse reaches 200 units and a spread-out party puts the afflicted "
		+ "ally out of reach, which is why floor1_chokepoint scores 0 of 28 despite 249 "
		+ "poisonings. Raise SEEDS, or repoint ENCOUNTER at a tighter room and re-measure "
		+ "with Tools/CleanseFixture.gd. Do NOT edit a room's roster to feed this test.")
		% [on_an_ally, SEEDS, ENCOUNTER, MIN_ALLY_CLEANSES])


## The negative half, and the one the whole design turns on: **does the
## condition actually gate the cast, or does it fire blind?**
##
## The cost of this ability is the caster's time, not its Mana, so the number
## that decides whether it was worth a card is casts-per-strip. swift measured
## the failing version directly: `always` as the condition, 4055 casts for 8
## strips, and Blast fell 593->101 and Scald 676->32 in the same fights. That is
## what a blind cleanse looks like, and a test asserting "the Geysermancer still
## mostly attacks" would not have caught it in every room -- these rooms resolve
## in a few hundred ticks and a Geysermancer only gets a couple of dozen casts
## in one, so a *ratio* against attacks is dominated by how long the room lasts
## rather than by whether the ability is well built.
##
## Casts-per-strip is not: it is a property of the condition alone. Measured
## across swift's full 210-fight sample this ships at 55 casts for 51 strips.
## The bound below is loose (a cast may still whiff honestly -- the ally can be
## cured by the status expiring naturally, die, or walk out of 200 units during
## the 8-tick wind-up) but nowhere near loose enough to survive `always`.
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
