extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const PartySelect := preload("res://Scripts/UI/PartySelect.gd")

## Issue #94: the four rooms a player picks between, and the properties that
## make them four rooms rather than four skins. OWNER: heron.
##
## New file rather than more methods in `test_content_encounter.gd`, which is
## already 500 lines of another session's balance history and is a conflict
## site while several sessions are live.
##
## Every check here is a run-it-and-see, not a structural read of the room
## definition, except the two that guard the headcount rule -- and those exist
## precisely because they cannot be run: "these four rooms are comparable to
## each other" is a property of the authoring, not of any one fight.

## The four rooms #94 built. `floor1_horde`, `floor1_ghoul_den` and
## `floor1_warden` stay registered and are deliberately not in this list.
##
## **This comment used to say "the four the picker offers" and there is no
## picker.** Issue #176. `PartySelect.current_config()` hardcodes
## `CG.DEFAULT_ENCOUNTER`, so a player fights `floor1_room1` and only ever
## `floor1_room1`; the other three, and every specialty enemy and piece of
## terrain in them, cannot be reached through the game at all. The name of
## this constant is now a statement of intent rather than of fact, and
## `test_only_one_pickable_room_can_actually_be_reached` below is what will
## tell whoever fixes it that this file needs re-reading.
const PICKABLE: Array[StringName] = [
	&"floor1_room1",
	&"floor1_cover",
	&"floor1_hazard",
	&"floor1_chokepoint",
]

## **Class ids in a stable order, and this helper is not incidental.**
##
## `Registry.all_class_ids()` ends with `ids.sort()` on an `Array[StringName]`,
## and **StringName does not sort alphabetically**: Godot compares the interned
## pointer, so the order depends on which StringNames the process happened to
## create first. Reproduced directly -- a script that mentions `&"warrior"`
## before loading the registry gets a different order out of the same call:
##
##     plain run:          [abomination, siege_master, geysermancer, priest, warrior]
##     after warming up:   [siege_master, geysermancer, abomination, priest, warrior]
##
## That matters here because `CombatSim.build` hands `party[i]` the spawn point
## `party_spawns[i]`, so the order decides **which class stands where**. The
## same seed and the same four classes are a different fight in a different
## process. It cost me a real half hour: a pillar layout measured stall-free
## over 100 fights standalone stalled inside the gate, and the party had simply
## been dealt out to different spawn points.
##
## Sorting the `String` forms is lexicographic and process-independent, so
## every number in this file means the same thing wherever it runs. Reported to
## rook -- `Scripts/Content/Registry.gd` is not mine and this file works around
## it rather than fixing it.
func _class_ids_in_a_stable_order() -> Array[StringName]:
	var names := PackedStringArray()
	for id in Registry.all_class_ids():
		names.append(String(id))
	names.sort()
	var out: Array[StringName] = []
	for n in names:
		out.append(StringName(n))
	return out


## The five parties `PartySelect` can actually build: one card per class,
## four slots, five classes, so the leave-one-out combinations and nothing
## else. `siege_master x4` is not a party and no balance claim here is read
## off one.
func _buildable_parties() -> Array:
	var class_ids := _class_ids_in_a_stable_order()
	var out := []
	for skip in class_ids.size():
		var party: Array[StringName] = []
		for i in class_ids.size():
			if i != skip:
				party.append(class_ids[i])
		out.append(party)
	return out


func _pawns(ids: Array, seed: int) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(ids[i], StringName("%s_%d_%d" % [ids[i], seed, i]), String(ids[i])))
	return out


## The same room with its terrain removed and everything else identical. The
## control for every layout claim in this file.
func _without_terrain(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.enemy_spawns = enc.enemy_spawns
	e.party_spawns = enc.party_spawns
	e.terrain = []
	return e


## **EVERY OTHER TEST IN THIS FILE MEASURES A ROOM A PLAYER CANNOT REACH, and
## this is the one that says so out loud. Issue #176.**
##
## `PartySelect.current_config()` is the only path from a player to a fight and
## it hardcodes `CG.DEFAULT_ENCOUNTER`. There is no room picker anywhere in
## `Scripts/UI` or `Scenes`, so `floor1_cover`, `floor1_hazard` and
## `floor1_chokepoint` -- the Stalker, the Rats and BLEED, the Brute and the
## game's only STUN source, and the tar pit that is the game's only terrain
## `test_only_one_pickable_room_can_actually_be_reached` WAS HERE AND IS DELETED,
## which is what it asked for rather than being loosened.
##
## It asserted the defect -- three of four pickable rooms unreachable -- and was
## built to go red the day a picker landed. Issue #176 landed it, and the
## verification it demanded was done through the controls rather than through
## `current_config()` in isolation: `Tools/RoomPickerShot.gd` drives the real
## picker on the real screen into a real fight for each of the four rooms and
## compares the built `CombatState`'s terrain count and enemy count against the
## room that was chosen. All four pass.
##
## **One correction to the record, because the test would not in fact have gone
## red on its own.** It built a bare `PartySelect` and read `current_config()`,
## and a bare screen has no picker, so it would have kept reporting three
## unreachable rooms while a player could reach all four -- passing forever,
## measuring nothing, exactly the failure mode announcement rule 2 describes. It
## still did its job: it is the reason this file was re-read at all. The guard
## that replaces it is `test_every_registered_room_is_either_offered_or_explicitly_not`
## in `Tests/test_ui_room_picker.gd`, which fails on a room nobody classified
## rather than on a count somebody has to remember to update.



## **The headcount rule, and it is the reason any other number in this file
## means anything.** The retrospective records a terrain conclusion that was
## wrong because it compared a three-enemy room against a ten-enemy one and
## credited the geometry for the difference. Before issue #94 that was still
## live in the content: `floor1_cover` and `floor1_hazard` carried three
## enemies each while `floor1_room1` and `floor1_chokepoint` carried ten.
##
## This is a structural check because the property is structural. It cannot be
## run: no single fight can tell you whether two rooms are comparable.
func test_all_four_pickable_rooms_field_the_same_number_of_enemies() -> void:
	var counts := {}
	for id in PICKABLE:
		var enc := Registry.get_encounter(id)
		assert_not_null(enc, "%s should be registered -- the picker offers it" % id)
		if enc == null:
			continue
		counts[id] = enc.enemy_spawns.size()
	print("pickable room headcounts: %s" % counts)
	for id in counts:
		assert_eq(counts[id], 10, "%s should field ten enemies like the other three" % id)


## Names that promise a layout and deliver an empty terrain list are how this
## project ended up with a finished terrain system nothing reached. Issue #94's
## own words: `floor1_room1`, the room the player actually plays, had an empty
## terrain list while `floor1_cover` and `floor1_hazard` were authored and
## unreachable.
func test_each_room_carries_the_terrain_its_name_promises() -> void:
	var room1 := Registry.get_encounter(&"floor1_room1")
	assert_true(room1.terrain.is_empty(), "floor1_room1 is the open-ground baseline and should stay bare")

	var cover := Registry.get_encounter(&"floor1_cover")
	assert_true(_kinds(cover).has(Terrain.Kind.PILLAR), "floor1_cover should carry pillars")

	var hazard := Registry.get_encounter(&"floor1_hazard")
	assert_true(_kinds(hazard).has(Terrain.Kind.HAZARD), "floor1_hazard should carry a hazard")

	## PIT, not WALL, and the distinction is the whole fix for #78 -- see the
	## chokepoint's own comment in floor1_encounters.gd. A WALL here would
	## reintroduce the deadlock, so this asserts the absence as well as the
	## presence.
	var choke := Registry.get_encounter(&"floor1_chokepoint")
	assert_true(_kinds(choke).has(Terrain.Kind.PIT), "floor1_chokepoint should be cut with pits")
	assert_false(_kinds(choke).has(Terrain.Kind.WALL), "a WALL in floor1_chokepoint deadlocks the fight -- see #78")


func _kinds(enc: Encounter) -> Array:
	var out := []
	for f in enc.terrain:
		out.append(f.kind)
	return out


## **Issue #121, and board rule 1 is the whole reason this test exists: a win
## table cannot see a dead mechanic.**
##
## The Brute's before/after win table on `floor1_hazard` is nearly flat, and if
## that were all I had looked at I would have concluded the stun was doing
## nothing. Read from `state.events` instead, it fires 50 times in 60 fights
## and cancels a committed wind-up 8 times. Both numbers are the deliverable of
## this enemy: it is the first STUN source in the game, and `INTERRUPTED` is
## the mechanism swift shipped when the player overturned issue 10.
##
## **Counted from `state.events`, not from `unit.statuses`, per board rule 2.**
## A status set snapshotted after `run()` says only what happened to survive to
## the last tick, and an 8-tick stun on a fight that ends 200 ticks later never
## survives anything. `STATUS_APPLIED` is emitted at the moment it lands.
##
## The thresholds have margin on purpose, per board rule 4: `> 0` on an
## emergent count reads identically at 17 and at 1 and only ever speaks on the
## build that hits zero, which is whoever touched content next rather than
## whoever caused the drift. Measured 17 stuns and 2-3 interrupts per 20
## fights; the floors are 8 and 1.
##
## **The interrupt floor of 1 is a cliff and I am naming it rather than
## dressing it up.** An interrupt needs the slam to land on a pawn during a
## wind-up, which is a narrow window, and there is no larger sample available
## that does not cost the gate real time. If it drifts to 1 it will fail on the
## next unrelated change; that is worse than a false green here, because a
## silent zero means the mechanism that justifies this enemy stopped working.
func test_the_brutes_slam_stuns_and_interrupts_on_the_hazard_room() -> void:
	var enc := Registry.get_encounter(&"floor1_hazard")
	var has_brute := false
	for spawn in enc.enemy_spawns:
		if spawn.get("enemy_id", &"") == &"brute":
			has_brute = true
	assert_true(has_brute, "floor1_hazard should field the Brute -- this test measures nothing without it")

	var stuns := 0
	var interrupts := 0
	var fights := 0
	for ids in _buildable_parties():
		for seed in 4:
			var state := _run(_pawns(ids, seed), enc, seed)
			fights += 1
			for e in state.events:
				if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.STUN and e.action_id == &"brute_slam":
					stuns += 1
				if e.kind == CG.EventKind.INTERRUPTED:
					interrupts += 1
	print("floor1_hazard over %d fights: brute_slam stunned %d times, INTERRUPTED %d casts" % [fights, stuns, interrupts])
	assert_true(stuns >= 8, "the Brute's stun should land repeatedly across %d fights, landed %d" % [fights, stuns])
	assert_true(interrupts >= 1, "a stun that never cancels a cast is issue 10's behaviour again; got %d interrupts in %d fights" % [interrupts, fights])


## **The Rat King's lash really does leave rats behind, and the swarm really
## does not accumulate. Both halves are asserted or printed on purpose.**
##
## README: *"Big collection of rats joined at the tail. Ranged attacker, all
## attacks leave behind rats which are close range melee attackers."* The first
## clause is the one this checks, because a summoner that summons nothing is
## the exact shape of dead mechanic announcement rule 1 exists for and a win
## table cannot see it.
##
## **Counted by watching `state.units` grow, not from an event, because there
## is no event.** `CombatSim._spawn_summon` appends a unit and emits nothing at
## all -- no `EventKind` for a summon exists. So a mid-fight spawn is invisible
## to the combat log and to anything else reading the stream; wren draws the
## body (#75) so a player sees a rat appear, but nothing says where it came
## from. Reported, not mine to fix.
##
## **The peak is printed and deliberately not asserted, and it is the finding.**
## The swarm never exceeds the four rats the room starts with, in any party, on
## any seed.
##
## **THE CAUSE THIS COMMENT USED TO GIVE WAS WRONG.** It said "a 20 hp rat dies
## faster than the king's 42-tick lash cycle replaces it", i.e. a balance
## statement about the rat. Measured per tick with `Tools/SwarmProbe.gd`: the
## median rat lives 60-96 ticks and **the lash fires a median of once per
## fight**, in fights of ~250 ticks that afford six cycles. The rats are not
## dying too fast; the king is barely ever allowed to lash. The mechanism is in
## `test_the_rat_king_is_almost_never_allowed_to_lash` below.
func test_the_rat_king_leaves_rats_behind() -> void:
	var enc := Registry.get_encounter(&"floor1_rat_king")
	assert_not_null(enc, "floor1_rat_king should be registered")
	var kings := 0
	var start_rats := 0
	for spawn in enc.enemy_spawns:
		if spawn.get("enemy_id", &"") == &"rat_king":
			kings += 1
		if spawn.get("enemy_id", &"") == &"rat":
			start_rats += 1
	assert_eq(kings, 1, "the nest should field one Rat King")

	var shed := 0
	var peak := 0
	var fights := 0
	for ids in _buildable_parties():
		for seed in 3:
			var party := _pawns(ids, seed)
			var state := CombatSim.build(party, enc, seed)
			var start_units := state.units.size()
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				var live := 0
				for u in state.units:
					if u.enemy_id == &"rat" and u.alive:
						live += 1
				peak = maxi(peak, live)
			shed += state.units.size() - start_units
			fights += 1
	print("floor1_rat_king over %d fights: %d rats shed by the lash, most alive at once %d (the room starts with %d)" % [fights, shed, peak, start_rats])
	assert_true(shed >= 10, "every attack should leave a rat behind; the lash shed %d rats across %d fights" % [shed, fights])


## **A RECORD OF A DEFECT, WRITTEN SO IT FAILS ON THE DAY THE DEFECT IS FIXED.**
##
## `ENGINEER.md`: when a check cannot pass yet, assert that the reason is still
## true rather than leaving a comment to rot. The reason here is that the Rat
## King's one mechanic almost never runs, and the day somebody fixes it this
## test goes red and points at the paragraph that says what to do about it.
##
## **What is broken.** `DefaultBehavior.decide` lets a ranged unit fire only
## between `range * KITE_RANGE_FRACTION` (0.6) and `range * RANGED_COMMIT_FRACTION`
## (0.85). For the lash's 200 range that is the 50 units from 120 to 170.
## Closer than 120 the unit retreats; further than 170 it approaches. Measured
## over 12 seeds x 5 buildable parties with `Tools/SwarmProbe.gd`, the king
## spends **3-6% of its life inside that band**, 32-52% backing away and 43-59%
## walking forward, and it moves on essentially every tick it is alive.
##
## **Why the king and not every ranged enemy.** `goblin_arrow` has the same 200
## range and fires 5.72 times per 100 ticks against the lash's 0.10. The
## difference is move_speed: an Archer at 3.2 re-establishes the band after a
## pawn closes on it, and the King at 1.2, the slowest unit in the game, never
## does. So this is an interaction between the kite band and the slow end of the
## bestiary, not a blanket ranged defect, and a test that asserted "ranged
## enemies cannot fire" would be measuring something false.
##
## **It is a defect and not a balance number**, which is why it is recorded
## while the rest of this file avoids tuning: a miniboss whose defining
## mechanic runs once per fight is a mechanism that does nothing, and no value
## in `floor1_enemies.gd` reaches it -- the band is a fraction of whatever range
## is written, so widening the range widens the band with it. CLAUDE.md's
## pawn-behaviour principle and issue #97 both name the automatic kiting branch
## as the thing to remove.
##
## **When it fails:** delete this test, and put the real assertion in its place
## -- that the lash fires several times per fight and the swarm exceeds its
## starting four.
func test_the_rat_king_is_almost_never_allowed_to_lash() -> void:
	var enc := Registry.get_encounter(&"floor1_rat_king")
	assert_not_null(enc, "floor1_rat_king should be registered")

	var fires := 0
	var fights := 0
	var alive_ticks := 0
	var in_band := 0
	var peak_rats := 0
	for ids in _buildable_parties():
		for seed in 3:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed)
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				var king: CombatUnit = null
				for u in state.units:
					if u.enemy_id == &"rat_king":
						king = u
				if king == null or not king.alive:
					break
				var gap := INF
				for u in state.units:
					if u.team == CG.Team.PLAYER and u.alive:
						gap = minf(gap, king.position.distance_to(u.position))
				if gap == INF:
					break
				alive_ticks += 1
				if gap >= 120.0 and gap <= 170.0:
					in_band += 1
				var live := 0
				for u in state.units:
					if u.enemy_id == &"rat" and u.alive:
						live += 1
				peak_rats = maxi(peak_rats, live)
				CombatSim.step(state)
			for e in state.events:
				if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"rat_king_lash":
					fires += 1
			fights += 1

	var band_percent := 100.0 * float(in_band) / float(maxi(1, alive_ticks))
	var per_fight := float(fires) / float(maxi(1, fights))
	print("floor1_rat_king: the lash fired %.2f times per fight over %d fights; the king was inside its 120-170 firing band for %.1f%% of the ticks it was alive; most rats alive at once %d" % [per_fight, fights, band_percent, peak_rats])

	# **THE LASH COUNT IS PRINTED AND DELIBERATELY NOT ASSERTED, and I wrote it
	# as an assertion first and it was wrong.** On `main` at 3846fa6 the lash
	# fires a median of 1 time per fight; on swift's `issue-164/starting-resource`
	# at 08d131e it fires 4.8, because a working Abomination makes every fight
	# roughly twice as long and the king lives 338-509 ticks instead of 214-372.
	# A floor on that number would have gone red on swift's merge and named
	# swift, which is board rule 4 exactly and the third time this file has
	# nearly shipped it.
	#
	# **More lashes did not make a swarm, which is the point.** Same branch,
	# same probe: rats alive at once still peaks at 4, mean 1.10-1.39, and the
	# room holds no rats at all for 33-49% of its length. Rats arrive faster and
	# die just as fast, so the population is unchanged.
	#
	# **The band is printed too, and asserting it would repeat the mistake I
	# just described.** It reads 5.5% on trunk and 15.0% on swift's branch: a
	# `< 20%` ceiling would sit five points off a number that moved ten in one
	# merge, which is a cliff by this file's own definition, and it would fire on
	# whoever next lengthens a fight rather than on anybody who fixed anything.
	# The band is the explanation and it belongs in this comment and in the
	# printout; it is not the invariant.
	#
	# **One assertion, on the symptom that has not moved at all.** The swarm
	# peaks at 4 on trunk and 5 on swift's against the four the room starts
	# with, on every party and every seed, across two branches whose fight
	# lengths differ by a factor of two. That is the thing a fix has to change
	# and the thing nothing else touches.
	assert_true(peak_rats <= 6,
		"the swarm now peaks at %d rats against the four the room starts with. If that is a fix, delete this test and assert the swarm properly (issue #97)" % peak_rats)


## **Issue #130's rats, and it replaces an assertion of swift's that fired.**
##
## `test_combat_bleed_is_live.gd::test_no_authored_action_applies_bleed_yet`
## asserted that nothing in the game applied BLEED and said the day it failed
## was the day to re-measure. `rat_bite` failed it. That file builds arenas by
## hand and cannot run a room, so the replacement lives here: real fights, real
## rats, counted out of `state.events`.
##
## **Stacks, not applications, is the whole point of the check.** A bleed that
## refreshed instead of stacking would emit exactly the same number of
## `STATUS_APPLIED` events and be a completely different mechanic, so counting
## applications would pass against the thing #130 exists to rule out. The stack
## count rides on `STATUS_APPLIED.amount`, and what this asserts is that a
## single pawn is seen carrying **several at once**.
##
## Measured floors, not aspirational ones: the peak stack on one pawn across
## these fights is in the doc of the pull request, and the floor here is 3 --
## enough that a refresh-only mechanic cannot reach it, with margin, per board
## rule 4.
func test_the_rats_bleed_stacks_on_a_real_pawn() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var rats := 0
	for spawn in enc.enemy_spawns:
		if spawn.get("enemy_id", &"") == &"rat":
			rats += 1
	assert_eq(rats, 2, "floor1_cover should field the two rats this test measures")

	var peak := 0
	var applications := 0
	var fights := 0
	for ids in _buildable_parties():
		for seed in 4:
			var state := _run(_pawns(ids, seed), enc, seed)
			fights += 1
			for e in state.events:
				if e.kind == CG.EventKind.STATUS_APPLIED and e.action_id == &"rat_bite":
					applications += 1
					peak = maxi(peak, e.amount)
	print("floor1_cover over %d fights: rat_bite landed %d times, peak stack on one pawn %d" % [fights, applications, peak])
	assert_true(applications >= 20, "the rats should bite repeatedly across %d fights, landed %d" % [fights, applications])
	assert_true(peak >= 3, "BLEED should stack rather than refresh; the most any pawn carried at once was %d" % peak)


## **Issue #121's Stalker, and the honest half of it.**
##
## What is asserted is that the mark reaches the game at all. What is *not*
## asserted, because it does not exist yet, is the half the player asked for:
## *"it just causes ranged enemies to focus their fire on a specific target."*
## `DefaultBehavior` has a marked-only **restriction** and no marked
## **preference**, so the three cultists and three archers standing beside this
## thing still shoot whoever is nearest. That tie-break is one filter in a file
## I do not own.
##
## **The mark is not inert in the meantime, and I checked rather than assumed
## it either way.** MARKED subtracts `Balance.MARKED_VULNERABILITY_BONUS` from
## the target's damage reduction, which strips a pawn's CON-derived natural
## armour. Measured with a temporary edit disabling only this action's status,
## same room, same seeds, 12 seeds x 5 buildable parties: four of the five
## parties finish worse with the mark than without it, by 3, 4, 11 and 12
## points of health, and one is unchanged. That control is not in the gate --
## it needs an edit to content to run -- so this asserts the reachable half and
## the number lives in the pull request.
##
## The floor is 25 against a measured 46 in 20 fights. It was 229 before the
## mark got a cooldown -- eleven applications per fight and eleven log lines
## from one 30hp enemy -- and why that was worth fixing is written beside the
## cooldown in `floor1_enemies.gd`.
func test_the_stalkers_mark_lands_on_the_colonnade() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var marks := 0
	var fights := 0
	for ids in _buildable_parties():
		for seed in 4:
			var state := _run(_pawns(ids, seed), enc, seed)
			fights += 1
			for e in state.events:
				if e.kind == CG.EventKind.STATUS_APPLIED and e.action_id == &"stalker_mark":
					marks += 1
	print("floor1_cover over %d fights: stalker_mark landed %d times" % [fights, marks])
	assert_true(marks >= 25, "the Stalker's mark should land throughout the fight, landed %d in %d fights" % [marks, fights])


## **The #78 regression guard, and the reason this file exists.**
##
## #78: three fights in 700 never resolved on `floor1_chokepoint` and reported
## as `Outcome.DRAW`, the same value a mutual wipe produces, so every run tool
## counted them as ordinary losses. Measured per-party rather than pooled
## across every encounter, it was much worse than three in 700: the party
## without a Warrior drew 7 of 20.
##
## Traced rather than guessed. `CombatSim._resolve_move` slides one axis at a
## time with no pathfinder; two units on opposite sides of a wall each slide
## toward the other's y, converge, and at that moment the y-step is zero-length
## while the x-step is into the wall. Both freeze for the rest of the fight.
## The walls are pits now: a pit blocks movement and not sight, so a jammed
## fight still resolves through damage.
##
## This asserts the outcome, not the mechanism, so it stays true if the
## movement code is ever given a real pathfinder.
##
## **It covers all four rooms, not just the chokepoint, because building these
## four turned up a second stall from a completely different cause.** The
## colonnade's first pillar layout hung four fights in twenty with nothing
## blocking anything: `DefaultBehavior` approaches when line of sight is
## blocked and retreats when a ranged unit is too close, neither branch has
## hysteresis, and a unit resting on a pillar's edge alternates between them
## forever in a two-tick cycle without firing. Two stalls, two causes, one
## symptom -- so the guard belongs on the symptom and on every room.
func test_no_pickable_room_stalls_for_any_buildable_party() -> void:
	var draws := 0
	var fights := 0
	for id in PICKABLE:
		var enc := Registry.get_encounter(id)
		for ids in _buildable_parties():
			for seed in 6:
				var state := CombatSim.build(_pawns(ids, seed), enc, seed)
				CombatSim.run(state)
				fights += 1
				if state.outcome != CombatState.Outcome.PLAYER_WIN and state.outcome != CombatState.Outcome.ENEMY_WIN:
					draws += 1
					print("%s STALL: party %s seed %d ended unresolved at tick %d" % [id, ids, seed, state.tick])
	print("pickable rooms: %d unresolved of %d fights across all five buildable parties" % [draws, fights])
	assert_eq(draws, 0, "a pickable room must not stall -- see #78 and this test's own comment")


## The negative half, and the one almost nobody writes: the pits have to be
## the reason. The same roster with the terrain stripped is `floor1_room1`
## exactly, and it also resolves -- so a passing test above would say nothing
## about the pits if the stall were never there to begin with. What this
## asserts is that the two rooms are genuinely different fights, which is the
## claim "the chokepoint is a different room from the open one" rests on.
func test_the_chokepoints_terrain_is_not_decoration() -> void:
	var enc := Registry.get_encounter(&"floor1_chokepoint")
	var bare := _without_terrain(enc)
	var ids: Array = _buildable_parties()[0]
	var differs := false
	for seed in 5:
		var with_pits := CombatSim.build(_pawns(ids, seed), enc, seed)
		CombatSim.run(with_pits)
		var without := CombatSim.build(_pawns(ids, seed), bare, seed)
		CombatSim.run(without)
		print("chokepoint seed %d: pits ticks=%d outcome=%d  vs  bare ticks=%d outcome=%d" % [
			seed, with_pits.tick, with_pits.outcome, without.tick, without.outcome,
		])
		if with_pits.tick != without.tick or with_pits.outcome != without.outcome:
			differs = true
	assert_true(differs, "the pits should change the fight, or they are decoration")


## **Issue #121 item 7, the tar pit, and this test is red until swift wires
## `CombatSim._tick_hazards`.**
##
## The field pair landed in `Scripts/Core/Terrain.gd` -- `applies_status`,
## `applies_status_enabled`, `status_duration_ticks` -- and **nothing reads
## it**. `_tick_hazards` loops `Terrain.hazards_at` and consults
## `damage_per_tick` and nothing else, so a feature whose whole effect is a
## status does nothing at all. Worse for this feature in particular: the
## loop's first line is `if hazard.damage_per_tick <= 0: continue`, so a tar
## pit that deals no damage is skipped before anything could look at its
## status.
##
## This asserts the outcome rather than the field, which is the difference
## between "content set a flag" and "a pawn was slowed". Counted out of
## `state.events`: a terrain status arrives as `STATUS_APPLIED` with no action
## id, the same shape hazard damage already uses, so it is distinguishable
## from a status an ability applied without needing a second mechanism.
##
## **Left red on purpose rather than deleted or skipped.** A skip reads as a
## pass in the summary line, and the point of writing it now is that whoever
## next opens `_tick_hazards` is told what is waiting on it.
func test_the_chokepoints_tar_pit_slows_whoever_crosses_the_bridge() -> void:
	var enc := Registry.get_encounter(&"floor1_chokepoint")
	var tar := 0
	for f in enc.terrain:
		if f.kind == Terrain.Kind.HAZARD and f.applies_status_enabled and f.applies_status == CG.Status.SLOWED:
			tar += 1
	assert_eq(tar, 1, "floor1_chokepoint should carry one tar pit -- this test measures nothing without it")

	var slows := 0
	var fights := 0
	for ids in _buildable_parties():
		for seed in 4:
			var state := _run(_pawns(ids, seed), enc, seed)
			fights += 1
			for e in state.events:
				if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.SLOWED and e.action_id == &"":
					slows += 1
	print("floor1_chokepoint over %d fights: the tar pit slowed something %d times" % [fights, slows])
	assert_true(slows >= 20, "the tar pit lies across the only land bridge, so every unit should cross it; slowed %d times in %d fights" % [slows, fights])


## **The colonnade has to be a colonnade, and this is the check that nearly
## did not get written.**
##
## A roster was chosen for this room on its win table alone -- best cost
## spread of four candidates, no party walled, zero stalls -- and it was one
## commit from shipping before the with-and-without column got measured. Its
## pillars did **nothing**: bit-identical tick counts on 20 of 20 seeds for
## every party. Enough goblins rushed the party that the fight resolved near
## the party spawns, a long way from the colonnade, and a pillar behind the
## fighting is scenery.
##
## That is this project's single most repeated failure -- a finished mechanic
## with nothing reaching it -- arriving inside the very issue filed to close
## it, and a win table cannot see it by construction. `test_content_encounter`
## has a check with this test's intent in its name, but it compares
## `floor1_room1` against `floor1_cover`: two different rooms, so it answers
## "are these rooms different" rather than "do the pillars do anything", and
## it would have passed against a colonnade made of paint.
##
## Measured direction, and it is the opposite of the room's original premise:
## the pillars **help the party**. Sight is worth more to whoever is closing
## than to whoever is standing still.
##
## ---
##
## **The assertion counted parties and it should never have.** It required
## three of the five buildable parties to move by five points or more, and
## swift's taunt compulsion (#132) took it to two without a pillar moving.
## swift left it red rather than editing my number, which was right, and rook
## asked me to re-measure rather than re-baseline. Re-measured on the trunk at
## `2606190` and on swift's branch at `96d9d37`, same seeds, same rooms:
##
##     party              trunk   with the compulsion
##     no_abomination         5                     2
##     no_geysermancer       11                     4
##     no_priest             17                    16
##     no_siege_master       22                    22
##     no_warrior             1                     4
##     parties over 5         4                     2
##     largest effect        22                    22
##     total of all five     56                    48
##
## **The pillars did not get weaker. Two borderline parties crossed a line.**
## The largest effect is identical at 22, the party that carries it is
## unmoved, and the total fell by 8 points out of 56. What actually happened is
## that `no_abomination` sat at **exactly 5** against a `>= 5` test and
## `no_geysermancer` at 11, and the compulsion pushed both under.
##
## That is board rule 4 arriving in the one place I did not look for it. I have
## twice written that an `> 0` assertion on an emergent count is a cliff-edge
## detector. **A count-of-parties-over-a-threshold is two cliffs stacked**: a
## per-party one at 5 points, and a population one at three of five. A party
## resting on the first tips the second, and the failure then names whoever
## touched behaviour next rather than anything about the pillars.
##
## **A smaller correction to what I first wrote here, and I am leaving it
## visible because it nearly became the finding.** My first reading of these
## two columns was that the three parties carrying both the Priest and the
## Siege Master were the three that went small, which would have been a clean
## mechanism -- the Siege Engine is the one unit with `spawn_taunt_radius` and
## a compulsion would drag the fight onto it. The trunk column kills it:
## `no_warrior` carries both and was already at 1 before the compulsion, and it
## went **up**, not down. Two parties moved and the rest did not. There is no
## clean split here, and I checked before posting it to swift rather than
## after.
##
## So the assertion is now on **size**, which is what "not decoration" means,
## and on two numbers rather than one so neither is a cliff:
##
##   - the largest single effect, floor 10 against a measured 22 on both
##   - the total across all five, floor 25 against a measured 56 and 48
##
## Both are **zero** against a colonnade of paint, which is the case this test
## exists for and the case it nearly failed to catch. Both pass with wide
## margin before *and* after the compulsion, so this lands on the trunk on its
## own rather than riding in swift's branch -- it does not encode a claim about
## which behaviour is live.
func test_the_colonnades_pillars_are_not_decoration() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var bare := _without_terrain(enc)
	var seeds := 10
	var largest := 0
	var total := 0
	var worst_divergence := seeds + 1
	for ids in _buildable_parties():
		var with_hp := 0
		var bare_hp := 0
		var differs := 0
		for seed in seeds:
			var a := _run(_pawns(ids, seed), enc, seed)
			var b := _run(_pawns(ids, seed), bare, seed)
			with_hp += _party_hp_percent(a)
			bare_hp += _party_hp_percent(b)
			if a.tick != b.tick or a.outcome != b.outcome:
				differs += 1
		var delta := (with_hp - bare_hp) / seeds
		print("floor1_cover, %s: %d%% health with the pillars, %d%% without, delta %d, fights that diverged %d/%d" % [
			ids, with_hp / seeds, bare_hp / seeds, delta, differs, seeds,
		])
		largest = maxi(largest, absi(delta))
		total += absi(delta)
		worst_divergence = mini(worst_divergence, differs)
	print("floor1_cover: largest single health effect %d points, total across five parties %d; fewest diverging fights for any party %d/%d" % [largest, total, worst_divergence, seeds])
	# **finch, issue 121: 10 -> 8 and 25 -> 18, re-baselined not tuned.** BURN and
	# the Blast combo changed how a Geysermancer spends its Mana and which enemy
	# it aims at, and every room in the game moved with it. Measured here: deltas
	# 0, +8, -8, +4, +2, largest 8, total 22.
	#
	# **The aggregate is the weaker half of this test and it is worth saying so
	# rather than quietly lowering it.** Announcement rule 1 -- a win table cannot
	# see a dead mechanic -- is answered by the per-seed check above, which finds
	# `abomination x4` and `warrior x4` differing on 5 of 5 seeds with the pillars
	# against without. That is direct evidence the pillars do something, and it did
	# not move. These two thresholds only ever measured how *much*.
	#
	# **This will be re-taken after #174 lands.** Rage starting at zero moves every
	# party that carries an Abomination or a Warrior, which is four of these five
	# rows.
	# **THE OLD ASSERTIONS WERE `largest >= 8` AND `total >= 18` AT FOUR SEEDS,
	# AND THEY WERE MEASURING NOISE. Here is the evidence, because the numbers
	# below are the whole argument for changing what this test asserts.**
	#
	# Party health here stopped counting summoned Siege Engines on 2026-08-15
	# (see `_party_hp_percent`), which took this pair from 12/23 to 8/19 against
	# floors of 8 and 18 -- exactly on the first floor. So I measured the effect
	# against sample size, health excluding summons, `Tools/PillarDelta.gd`:
	#
	#     seeds   largest   total   per-party deltas
	#         4         8      19   +5, +2, +0, +8, -4
	#         8         8      17   +8, +0, -2, +7, +0
	#        12         5      15   +5, +0, -5, +4, -1
	#        20         6       8   +0, +0, -2, +6, +0
	#        40         5       8   -2, +0, +0, +5, +1
	#
	# **The effect shrinks toward nothing as the sample grows.** At 40 seeds the
	# colonnade moves ending party health by 5 points at worst and 8 in total,
	# with three of five parties at zero or one. The 12 and 23 this test was
	# baselined on were mostly sampling noise sitting on top of summon
	# inflation, and raising the seed count -- the obvious fix -- makes this
	# assertion fail.
	#
	# **That does not mean the pillars are decoration.** Ending health was always
	# the weaker proxy and this header has said so since #121: *"the aggregate is
	# the weaker half of this test"*. It is now measurably the wrong half. The
	# strong evidence the header keeps citing -- parties diverging seed by seed
	# with the pillars in -- **was only ever in a comment and was never
	# asserted**, which is announcement rule 2 wearing a different hat: the claim
	# nobody could check was the one carrying the weight.
	#
	# **It was not hypothetical: with the summon fix in, `total` came out at 16
	# against the floor of 18 on swift's #175**, a branch that does not touch
	# this room, this roster or these pillars. The landmine fired on exactly the
	# person the rule says it would.
	#
	# **So the assertion changes to the thing that actually detects decoration,
	# and the magnitude becomes a printout.** Lowering 18 to fit 16 would be a
	# widening of a number I have just shown is noise, and it would leave the
	# test asserting a quantity it cannot measure.
	#
	# **Divergence is the right claim and this file already had the pattern.**
	# `test_the_chokepoints_terrain_is_not_decoration` asserts that ticks or
	# outcome differ with the terrain in, which is a yes/no per fight and so has
	# no magnitude to be noisy. Measured over 10 seeds, both on `main` at
	# `75df176` and on #165, identically:
	#
	#     party              fights that diverge
	#     no_abomination                   10/10
	#     no_geysermancer                   9/10
	#     no_priest                         9/10
	#     no_siege_master                  10/10
	#     no_warrior                        8/10
	#
	# Against a colonnade of paint every one of those is **0/10**, bit-for-bit,
	# which is the case that nearly shipped on #94 and the case this test exists
	# for. The floor is 5 of 10 against a measured worst of 8.
	#
	# **This is strictly stronger than what it replaces**, not a retreat: the
	# old pair could be satisfied by noise and could be broken by noise, and
	# this cannot be either. The health spread stays in the printout because it
	# is still the interesting number for a pull request to report -- it is just
	# not a thing to assert at any sample size this gate can afford.
	assert_true(worst_divergence >= 5,
		"the pillars should change the fight for every buildable party; the least affected diverged in only %d of %d fights" % [worst_divergence, seeds])


## **The fire has to change the fight, and the control is the same roster with
## the fire removed.**
##
## The old burn pit's single 160x120 patch sat off the shortest path and cost
## every buildable party almost nothing -- 77-96% health remaining, which is
## indistinguishable from a room with no hazard in it. Measuring the rebuilt
## room against `floor1_room1` would prove nothing, because the roster differs
## too. Measured against its own roster with the terrain stripped, the only
## variable left is the fire.
##
## **THIS ASSERTED ON FIGHT LENGTH UNTIL 2026-08-15 AND NOW ASSERTS ON HEALTH.
## The reason is at the bottom of the function, with both tables.** Short
## version: after hazard avoidance (#163) and a working Abomination (#172) the
## fire no longer ends fights sooner -- three of five parties now fight longer
## in it -- while the health effect it moved onto is larger and steadier than
## the length effect ever was. Everything below this paragraph is the history of
## the length claim, kept because it is the record of what was true before.
##
## **This asserted on fight length, not on party health, and the first version
## of it was wrong in a way worth recording.** I wrote "the burn pit should
## cost the party at least 10 points of health" and it failed, and the reason
## it failed is the room working: *fire burns both sides*. The enemy back rank
## has to cross it to reach a party that stands off, so two of the five
## buildable parties finish a burning room **healthier** than the same roster
## on bare ground, and three finish 13-34 points worse. Averaging that to a
## single party-tax number destroys exactly the information the room exists to
## produce, and tuning until the average went one way would have been tuning
## away the point.
##
## What is true of every party is that the fire ends the fight much sooner.
## That is the honest invariant, it is what a decorative hazard would fail, and
## the per-party health spread is printed rather than asserted so the pull
## request can report it.
##
## ---
##
## **The invariant survived hazard avoidance (#163). The threshold did not.**
##
## swift's #178 teaches movement to step around fire, and it turned this red
## for one party at 401 ticks against 521 -- a ratio of 0.77 against a `* 4 <
## * 3` test, which is 0.75. Measured on both sides, same seeds, same room:
##
##     party              trunk   with avoidance
##     no_abomination      0.35            0.73
##     no_geysermancer     0.56            0.75
##     no_priest           0.43            0.77
##     no_siege_master     0.41            0.55
##     no_warrior          0.49            0.56
##     mean                0.45            0.67
##
## **The fire still ends every fight sooner. It just ends it less sooner**, as
## it must: a hazard units step around changes the fight less than one they
## walk into, and swift said so before I measured it. Nothing here is a
## regression and nothing needs tuning.
##
## So the assertion moves off the cliff and onto the effect, exactly as
## `test_the_colonnades_pillars_are_not_decoration` did two days ago when a
## party sat at exactly 5 against a `>= 5` test. **This is the same mistake in
## a second file by the same author.** A hard per-party ratio is a cliff, and
## a member near the line tips it on somebody else's commit.
##
##   - per party, the ratio must be under 0.95, against a measured worst of
##     0.77 and a paint hazard's 1.00
##   - across the five, the mean must be under 0.85, measured 0.45 and 0.67
##
## Both pass before and after avoidance, so this lands on the trunk on its own
## and takes #178 green rather than riding in it. Both are 1.00 against a
## hazard of paint.
##
## **THE HEALTH STORY IS THE FINDING, AND IT IS BIG. Reported, not acted on.**
## Health with the fire against the same roster on bare ground:
##
##     party              trunk        with avoidance
##     no_abomination      +1            +8
##     no_geysermancer    -11           +23
##     no_priest           -1            +9
##     no_siege_master    -21           +37
##     no_warrior         +26           +34
##
## **Avoidance flipped the sign for every party.** Two of five used to finish a
## burning room healthier than a bare one; now five of five do, by 8 to 37
## points. The room's own cost model was units crossing fire, and the side that
## crossed it most was the party -- it advances, and the enemy back rank stands
## still. Stop the party walking into fire and the fire's cost lands on almost
## nobody: `no_siege_master` goes from 14% health to 72%, `no_geysermancer`
## from 51% to 85%.
##
## That is a large easing of one of the four rooms and **it is exactly the kind
## of movement the balance freeze exists to keep un-tuned.** It is also why
## health is still not asserted here: it was inconsistent in sign before and
## consistent now, and a sign that has already flipped once is not an
## invariant.
##
## **I was asked whether the lanes now want reshaping, and my answer is not
## yet, for a reason that is not caution.** Nobody can reach this room. Issue
## #176 -- `PartySelect` hardcodes `CG.DEFAULT_ENCOUNTER` and there is no
## picker, so `floor1_hazard` has never been seen by a player or by me in a
## running game. Reshaping geometry to make a skip tempting, while blind, to
## move numbers that #172's rage ruling will move again, is churn with three
## unknowns in it. The lanes are also **usable for the first time**: before
## #163 nothing routed around fire, so two authored 50-unit gaps were content
## the game could not use. The room just got better at being what it was
## designed to be. Look at it first.
func test_the_burn_pit_changes_the_fight_for_every_buildable_party() -> void:
	var enc := Registry.get_encounter(&"floor1_hazard")
	var bare := _without_terrain(enc)
	var seeds := 4
	var ratio_total := 0.0
	var parties := 0
	var shortened := 0
	var largest_health := 0
	var health_total := 0
	for ids in _buildable_parties():
		var burnt_hp := 0
		var bare_hp := 0
		var burnt_ticks := 0
		var bare_ticks := 0
		for seed in seeds:
			var a := _run(_pawns(ids, seed), enc, seed)
			var b := _run(_pawns(ids, seed), bare, seed)
			burnt_hp += _party_hp_percent(a)
			bare_hp += _party_hp_percent(b)
			burnt_ticks += a.tick
			bare_ticks += b.tick
		var ratio := float(burnt_ticks) / float(maxi(1, bare_ticks))
		ratio_total += ratio
		parties += 1
		print("floor1_hazard, %s: fire %d%% health / %d ticks   bare %d%% health / %d ticks   ratio %.2f, health delta %+d" % [
			ids, burnt_hp / seeds, burnt_ticks / seeds, bare_hp / seeds, bare_ticks / seeds,
			ratio, (burnt_hp - bare_hp) / seeds,
		])
		if ratio < 0.95:
			shortened += 1
		var health_delta := (burnt_hp - bare_hp) / seeds
		largest_health = maxi(largest_health, absi(health_delta))
		health_total += absi(health_delta)
	var mean_ratio := ratio_total / float(maxi(1, parties))
	print("floor1_hazard: mean fire/bare tick ratio across %d parties %.2f, shortened for %d" % [parties, mean_ratio, shortened])
	print("floor1_hazard: largest single health effect %d points, total across five parties %d" % [largest_health, health_total])

	# **THE DETECTOR, PROVED NOT INERT.** The header has claimed since #178 that
	# a hazard of paint scores 1.00 and zero, and nothing ever asserted it. A
	# floor on an emergent number that cannot reach zero is not a check, and a
	# detector nobody feeds known-good input to is the sixteen-passing-tests
	# failure in `ENGINEER.md`. The room measured against itself is the exact
	# no-difference case, and the simulation is deterministic, so this is not an
	# approximation.
	var control_a := _run(_pawns(_buildable_parties()[0], 0), enc, 0)
	var control_b := _run(_pawns(_buildable_parties()[0], 0), enc, 0)
	assert_eq(_party_hp_percent(control_a), _party_hp_percent(control_b),
		"with no difference between the arms this test must measure no health effect at all")
	assert_eq(control_a.tick, control_b.tick,
		"with no difference between the arms this test must measure no length effect at all")
	# **finch, issue 121: "every party" became "four of five", and the exception is
	# named rather than the threshold widened.** Measured: 0.56, 0.55, **1.17**,
	# 0.74, 0.84. The outlier is `abomination, geysermancer, siege_master, warrior`
	# -- the one buildable party with **no Priest** -- which now spends 17 more
	# points of health and 72 more ticks in the fire than in the bare room.
	#
	# That is a mechanism, not noise: fire is chip damage over time, and the party
	# with no heal is the one that cannot pay it off, so the fight drags and the
	# fire gets longer to work. **Widening `ratio < 0.95` until 1.17 fits would
	# have made the per-party claim vacuous** -- it would no longer say the fire
	# ends fights sooner at all. heron's own header already refuses to assert
	# health here for the same reason: "a sign that has already flipped once is not
	# an invariant". The tick sign has now flipped for one row, so the per-row
	# claim is counted instead of demanded, and the mean still carries the
	# direction.
	#
	# **This will be re-taken after #174 lands** -- rage from zero moves every row
	# here that carries an Abomination, which is four of five.
	# **THE CLAIM HAS CHANGED, AND THAT IS THE FINDING. It is not a third
	# widening.** rook asked whether the length assertion is still the right
	# claim after swift's rage-on-being-hit fix. Measured on both sides, same
	# seeds, same room, `main` at 3846fa6 against `issue-164/starting-resource`
	# at 08d131e:
	#
	#     party              trunk   with a working Abomination
	#     no_abomination      0.84         0.85
	#     no_geysermancer     0.74         1.01
	#     no_priest           1.17         1.08
	#     no_siege_master     0.55         1.13
	#     no_warrior          0.56         0.56
	#     mean                0.77         0.93
	#     shortened              4            2
	#
	# **The fire no longer ends fights sooner and I am not going to pretend it
	# does.** Three of five rows are now at or above 1.00. Widening `mean < 0.85`
	# to fit 0.93 would be the fifth widening this project has recorded against
	# zero narrowings (#144) and it would assert something false: a room where
	# three parties fight *longer* in the fire is not a room where the fire
	# shortens fights.
	#
	# **The effect did not go away, it moved to the other axis, and there it is
	# larger and more consistent than the length effect ever was.** Health with
	# the fire against the same roster on bare ground:
	#
	#     party              trunk   with a working Abomination
	#     no_abomination        +3          +20
	#     no_geysermancer      +22           +0
	#     no_priest            -17          +12
	#     no_siege_master      +38          +20
	#     no_warrior           +37          +38
	#     largest                38           38
	#     total                 117           90
	#
	# The mechanism is the one this header already recorded at #163: the party
	# routes around fire and the enemy back rank has to cross it, so the fire's
	# cost lands on the side that walks into it. A working Abomination closes
	# faster, so the party spends longer alive and less of that time burning --
	# every row is now at or above zero.
	#
	# **So the assertion moves onto size, exactly as
	# `test_the_colonnades_pillars_are_not_decoration` did**, and for the same
	# reason: `no_geysermancer` sits at **exactly +0**, and a per-party
	# direction test would be a cliff with a party resting on it, which is board
	# rule 4 for the third time in this file. Two numbers, neither a cliff:
	#
	#   - the largest single health effect, floor 20 against 38 on both sides
	#   - the total across the five, floor 55 against 117 and 90
	#
	# Both are **zero** against a hazard of paint, which the control above now
	# asserts rather than claiming. Both pass before and after swift's change,
	# so this lands on the trunk on its own and takes #172 green rather than
	# riding in it.
	#
	# **The length numbers are still measured and printed and no longer
	# asserted.** They are the record of a claim that was true for two months
	# and is not true now; deleting them would delete the evidence that it
	# changed. If a later build makes the fire shorten fights again, that is
	# visible in this output and somebody can put the assertion back.
	assert_true(largest_health >= 20,
		"the fire should change at least one party's fight substantially, largest health effect was %d points" % largest_health)
	assert_true(health_total >= 55,
		"the fire should move the five buildable parties by %d points of health in total or more, moved %d" % [55, health_total])


func _run(party: Array[PawnData], enc: Encounter, seed: int) -> CombatState:
	var state := CombatSim.build(party, enc, seed)
	CombatSim.run(state)
	return state


## **THIS COUNTED SUMMONED SIEGE ENGINES AS PARTY UNTIL 2026-08-15, and finch
## found the same bug inflating the Warden table before I found it here.**
##
## `CombatSim._spawn_summon` builds a summon with `caster.team`, so a Siege
## Engine is `Team.PLAYER` and this function was adding 140 hp of immobile
## construct to a four-pawn party of roughly 400. Measured on `main` at
## `75df176`, health at the end of a fight computed both ways:
##
##     room                party              all   pawns   delta
##     floor1_cover        no_abomination     49%     25%     +24
##     floor1_hazard       no_geysermancer    52%     31%     +21
##     floor1_chokepoint   no_warrior         40%     19%     +21
##     floor1_room1        no_warrior         49%     22%     +27
##     any room            no_siege_master     --      --      +0
##
## **The `no_siege_master` row is the control and it is exactly zero in every
## room**, which is the mechanism confirming itself: the one buildable party
## with no Siege Master is the one party with no summon, and it is the only row
## that does not move.
##
## `enemy_id` is the discriminator because a summon carries one and a real pawn
## never does -- the same generic signal `DefaultBehavior` already reads, rather
## than naming the Siege Engine.
##
## **What this does to the two assertions that use it, and my first answer was
## wrong in one of the two.** I wrote that both would gain margin because the
## inflation was damping the differences. That holds for the burn pit, whose
## largest/total go **25/64 to 35/90** against floors of 20 and 55. It is the
## opposite for the colonnade, which went **12/23 to 8/19** against floors of 8
## and 18 -- landing exactly on the first floor, and under the second on swift's
## #175. Measured, not reasoned, and corrected here rather than left as the
## confident version.
##
## That is what sent me to measure the colonnade against sample size, and the
## answer is in that test: its health aggregate was noise at any sample this
## gate can afford, so it now asserts per-fight divergence instead. **No floor
## was lowered to fit anything.**
func _party_hp_percent(state: CombatState) -> int:
	var hp := 0
	var hp_max := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.enemy_id != &"":
			continue
		hp += maxi(0, u.hp)
		hp_max += u.hp_max
	if hp_max <= 0:
		return 0
	return int(round(100.0 * float(hp) / float(hp_max)))


## The player's standing direction, from PLAYTEST-NOTES.md and quoted in
## `Tools/SampleFights.gd`: *"With a party of 4 I should be winning most single
## battles and my losses should come from attrition."* A pickable room that one
## party simply cannot have is not variety, it is a card the player has learnt
## not to press.
##
## **This is a floor, not a target, and it is deliberately not a band.** A room
## that suits one party and not another is the point of having four of them;
## the spread belongs in the pull request's table, not flattened into an
## assertion here.
##
## ---
##
## **THE OLD SHAPE WAS `wins >= 4 of 8`, AND IT WAS A COIN-FLIP DETECTOR DRAWN
## THROUGH THE MIDDLE OF A COIN FLIP. I wrote it; it was flaky on the trunk
## before anybody's branch touched it.**
##
## It went red on swift's #175 for `floor1_chokepoint` x `no_geysermancer` at
## 3/8, which reads as a room that stopped being winnable. It is not. Measured
## at **100 seeds** on `main` at `75df176` and on `main` + #165:
##
##     party              main   with #165
##     no_abomination     100%         99%
##     no_geysermancer     54%         47%
##     no_priest           97%         98%
##     no_siege_master     98%         98%
##     no_warrior         100%        100%
##
## **That cell is a coin flip in both arms**, and the 7-point gap between them
## is 1.4 standard deviations at n=100 -- not a movement anybody should act on.
## The 3/8 the gate reported is an eight-seed sample of a 50% cell.
##
## **So the old assertion was failing about one run in three on the trunk, and
## had been for as long as that cell sat near 50%.** At p=0.54 and n=8,
## `wins >= 4` fails roughly 32% of the time. It passed the runs it was looked
## at on. This is board rule 4 in its purest form and the author is me: a
## threshold drawn at exactly the value the population sits at cannot do
## anything but flip, and when it flips it names whoever pushed last.
##
## **What the test is named for is a WALL, and 50% was never a wall.** The
## measured distribution has an enormous gap in it -- one cell at 47-54% and
## every other cell in the game at 97-100% -- so there is no number between 10%
## and 40% that noise can reach from either side. The floor is 25%:
##
##   - against the coin flip at 47%, `wins >= 5 of 20` fails about 0.06% of runs
##   - against a genuine wall at 5%, it fails essentially always
##
## **This is a change of claim, not a widening.** The claim is now the one the
## function name always made -- no room is unwinnable for a party -- and the
## claim it replaces was "no room is worse than even for a party", which the
## project does not believe: `test_some_composition_is_a_genuine_coin_flip`
## asserts the opposite, that a coin flip somewhere is a thing worth having.
## **Nothing about the rooms changed to make this necessary.** The trunk numbers
## and the #165 numbers both pass it and both passed the old one on a good day.
##
## Seeds go 8 to 20, which is what makes the floor mean anything: 8 seeds cannot
## distinguish a 47% cell from a 25% one at all.
##
## **The coin flip itself is reported and not tuned.** `no_geysermancer` on the
## chokepoint is the one party that finds that room hard, it is the only such
## cell in the game, and per the header above that is what four rooms are for.
func test_no_pickable_room_is_a_wall_for_any_buildable_party() -> void:
	var seeds := 20
	var floor_wins := 5
	var worst := seeds + 1
	var worst_cell := ""
	for id in PICKABLE:
		var enc := Registry.get_encounter(id)
		for ids in _buildable_parties():
			var wins := 0
			for seed in seeds:
				if _run(_pawns(ids, seed), enc, seed).outcome == CombatState.Outcome.PLAYER_WIN:
					wins += 1
			print("%s: %s won %d/%d" % [id, ids, wins, seeds])
			if wins < worst:
				worst = wins
				worst_cell = "%s x %s" % [id, ids]
			assert_true(wins >= floor_wins,
				"%s should not be a wall for %s: won %d/%d, floor %d" % [id, ids, wins, seeds, floor_wins])
	print("no_pickable_room_is_a_wall: worst cell %s at %d/%d, floor %d" % [worst_cell, worst, seeds, floor_wins])
