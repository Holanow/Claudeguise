extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")

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

## The four the picker offers. `floor1_horde`, `floor1_ghoul_den` and
## `floor1_warden` stay registered and are deliberately not in this list.
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
	var seeds := 4
	var largest := 0
	var total := 0
	for ids in _buildable_parties():
		var with_hp := 0
		var bare_hp := 0
		for seed in seeds:
			with_hp += _party_hp_percent(_run(_pawns(ids, seed), enc, seed))
			bare_hp += _party_hp_percent(_run(_pawns(ids, seed), bare, seed))
		var delta := (with_hp - bare_hp) / seeds
		print("floor1_cover, %s: %d%% health with the pillars, %d%% without, delta %d" % [ids, with_hp / seeds, bare_hp / seeds, delta])
		largest = maxi(largest, absi(delta))
		total += absi(delta)
	print("floor1_cover: largest single effect %d points, total across five parties %d" % [largest, total])
	assert_true(largest >= 10, "the pillars should change at least one party's fight substantially, largest effect was %d points" % largest)
	assert_true(total >= 25, "the pillars should move the five buildable parties by %d points in total or more, moved %d" % [25, total])


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
## **This asserts on fight length, not on party health, and the first version
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
## What is true of every party is that the fire ends the fight much sooner:
## 171-244 ticks against 426-735. That is the honest invariant, it is what a
## decorative hazard would fail, and the per-party health spread is printed
## rather than asserted so the pull request can report it.
func test_the_burn_pit_changes_the_fight_for_every_buildable_party() -> void:
	var enc := Registry.get_encounter(&"floor1_hazard")
	var bare := _without_terrain(enc)
	var seeds := 4
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
		print("floor1_hazard, %s: fire %d%% health / %d ticks   bare %d%% health / %d ticks" % [
			ids, burnt_hp / seeds, burnt_ticks / seeds, bare_hp / seeds, bare_ticks / seeds,
		])
		assert_true(burnt_ticks * 4 < bare_ticks * 3, "the fire should end the fight materially sooner for %s, got %d ticks against %d" % [ids, burnt_ticks / seeds, bare_ticks / seeds])


func _run(party: Array[PawnData], enc: Encounter, seed: int) -> CombatState:
	var state := CombatSim.build(party, enc, seed)
	CombatSim.run(state)
	return state


func _party_hp_percent(state: CombatState) -> int:
	var hp := 0
	var hp_max := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER:
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
## assertion here. Measured at 8 seeds rather than 20 to keep the gate quick --
## the pull request carries the 20-seed numbers.
func test_no_pickable_room_is_a_wall_for_any_buildable_party() -> void:
	for id in PICKABLE:
		var enc := Registry.get_encounter(id)
		for ids in _buildable_parties():
			var wins := 0
			for seed in 8:
				if _run(_pawns(ids, seed), enc, seed).outcome == CombatState.Outcome.PLAYER_WIN:
					wins += 1
			print("%s: %s won %d/8" % [id, ids, wins])
			assert_true(wins >= 4, "%s should be winnable by %s, won %d/8" % [id, ids, wins])
