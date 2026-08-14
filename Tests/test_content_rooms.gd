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
## the pillars **help the party**, three of five buildable parties finishing
## 12 to 18 points healthier with them than without. Sight is worth more to
## whoever is closing than to whoever is standing still. Asserted loosely --
## three of five, five points -- because the size of the effect is a tuning
## number and its existence is the invariant.
func test_the_colonnades_pillars_are_not_decoration() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var bare := _without_terrain(enc)
	var seeds := 4
	var helped := 0
	for ids in _buildable_parties():
		var with_hp := 0
		var bare_hp := 0
		for seed in seeds:
			with_hp += _party_hp_percent(_run(_pawns(ids, seed), enc, seed))
			bare_hp += _party_hp_percent(_run(_pawns(ids, seed), bare, seed))
		var delta := (with_hp - bare_hp) / seeds
		print("floor1_cover, %s: %d%% health with the pillars, %d%% without, delta %d" % [ids, with_hp / seeds, bare_hp / seeds, delta])
		if absi(delta) >= 5:
			helped += 1
	assert_true(helped >= 3, "the pillars should change the outcome for at least three of the five buildable parties, changed %d" % helped)


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
