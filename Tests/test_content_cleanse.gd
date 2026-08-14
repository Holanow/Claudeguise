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

const SEEDS := 6
const ENCOUNTER := &"floor1_cover"

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
		if e.kind == CG.EventKind.STATUS_EXPIRED and e.source_id != -1:
			out.append(e)
	return out

func _run(fight_seed: int) -> CombatState:
	var deps := SimDeps.new()
	var state := CombatSim.build(_party(), Registry.get_encounter(ENCOUNTER), fight_seed, deps)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state, deps)
	return state


func test_a_real_fight_shows_a_geysermancer_stripping_poison_from_an_ally() -> void:
	var strips := 0
	var on_an_ally := 0
	for s in SEEDS:
		var state := _run(s)
		for e in _cleanse_events(state):
			strips += 1
			assert_eq(e.action_id, &"geyser_cleanse",
				"the only action in the game that strips a status is the Geysermancer's")
			assert_eq(e.status, CG.Status.POISON,
				"POISON is the only harmful status anything applies to a player unit today -- issue 90")
			var caster := state.unit(e.source_id)
			assert_eq(caster.pawn.pawn_class.id, &"geysermancer")
			var target := state.unit(e.target_id)
			assert_eq(target.team, CG.Team.PLAYER, "a cleanse must never land on an enemy")
			if e.target_id != e.source_id:
				on_an_ally += 1
	assert_true(strips > 0, "the cleanse stripped nothing in %d real fights" % SEEDS)
	assert_true(on_an_ally > 0, "the cleanse only ever scrubbed its own caster; the ability is for the party")


## The negative half, and the one the whole design turns on: **does the
## condition actually gate the cast, or does it fire blind?**
##
## The cost of this ability is the caster's time, not its Mana, so the number
## that decides whether it was worth a card is casts-per-strip. swift measured
## the failing version directly: `always` as the condition, 4055 casts for 8
## strips, and Blast fell 593->101 and Scald 676->32 in the same fights. That is
## what a blind cleanse looks like, and a test asserting "the Geysermancer still
## mostly attacks" would not have caught it in every room -- `floor1_cover`
## resolves in ~236 ticks and a Geysermancer only gets a couple of dozen casts
## there in total, so a *ratio* against attacks is dominated by how long the
## room lasts rather than by whether the ability is well built.
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
				assert_true(line.contains("Poison"), "the strip should name the status, got '%s'" % line)
				saw_the_strip = true
	log_view.free()
	assert_true(saw_the_cast and saw_the_strip)
