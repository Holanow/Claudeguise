extends "res://Tests/TestCase.gd"


## The whole-fight acceptance checks from issues 2 and 7. Real CombatSim, real
## Registry content. Reference compositions here are re-picked whenever a
## balance-affecting fix lands; see TEAM_LOG for the history rather than
## restating it inline.

## Issue 399: preset pawns, because "these two classes fight differently" is a
## claim about class content including its authored rows. Measured with no rows
## at all, the Geysermancer and the Priest produce the same outcome and
## near-identical length on seed 14 -- reported in the PR, not tuned.
func _party_of(class_id: StringName, count: int) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in count:
		party.append(PawnFactory.make_preset_pawn(class_id, &"%s_%d" % [class_id, i], "%s %d" % [class_id, i]))
	return party


## Issue 564: what the two parties actually cast, not who won and how fast.
##
## The proxy this replaces compared outcome and fight length, and it separated
## these classes only while one of them was losing: on trunk a planned
## geysermancer x4 won 6 of 30 in this room and siege_master x4 won 30 of 30,
## so "different outcome" was really "one of these is worse". #556 made the
## Geysermancer win the same room at the same speed and the proxy collapsed
## while the classes did not -- their cast sets stayed disjoint throughout.
const PAIR_SEEDS := 8

## Every action the PARTY's own pawns fired, deduplicated and sorted. Enemy
## casts are excluded: both arms fight the same room, so counting those would
## make every pair overlap.
func _cast_set(class_id: StringName) -> Array:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var out := {}
	for seed in PAIR_SEEDS:
		var state := CombatSim.build(_party_of(class_id, 4), encounter, seed)
		CombatSim.run(state)
		for e in state.events:
			if e.kind != CG.EventKind.ACTION_FIRE:
				continue
			var u := state.unit(e.source_id)
			if u != null and u.pawn != null:
				out[e.action_id] = true
	var keys := out.keys()
	keys.sort()
	return keys


## Not strict disjointness: `channel_mana` is a shared core action two classes
## may both carry, and sharing one utility row does not make them one class.
## The claim is that each casts something the other never does.
func _only_in(a: Array, b: Array) -> Array:
	var out := []
	for id in a:
		if not b.has(id):
			out.append(id)
	return out


func _assert_pair_differs(class_a: StringName, class_b: StringName) -> void:
	var a := _cast_set(class_a)
	var b := _cast_set(class_b)
	var a_only := _only_in(a, b)
	var b_only := _only_in(b, a)
	print("classes differ: %s casts %s (%d only its own) | %s casts %s (%d only its own)" % [
		class_a, a, a_only.size(), class_b, b, b_only.size()])
	assert_false(a.is_empty(), "%s cast nothing at all; this measurement is empty" % class_a)
	assert_false(b.is_empty(), "%s cast nothing at all; this measurement is empty" % class_b)
	assert_false(a_only.is_empty(), "%s casts nothing %s does not also cast" % [class_a, class_b])
	assert_false(b_only.is_empty(), "%s casts nothing %s does not also cast" % [class_b, class_a])


## Mono-class parties, diagnostic only, same caveat this file states everywhere
## else.
func test_geysermancers_and_warriors_fight_differently() -> void:
	_assert_pair_differs(&"geysermancer", &"warrior")


## **The park this replaces was inverted, and #556 fired it.** From #490 the
## two casters were alike on 12 of 30 seeds, 16 after #544; separating their
## statlines took it to 0 of 30, so the real assertion is restored here as the
## park's own message asked.
func test_geysermancers_and_priests_fight_differently() -> void:
	_assert_pair_differs(&"geysermancer", &"priest")


func test_geysermancers_and_siege_masters_fight_differently() -> void:
	_assert_pair_differs(&"geysermancer", &"siege_master")


## The negative half, and without it the three above prove nothing: a class
## compared with itself must read as the SAME, or "each casts something the
## other does not" is a property of the instrument rather than of the classes.
func test_a_class_does_not_read_as_different_from_itself() -> void:
	for class_id in [&"geysermancer", &"priest", &"siege_master"]:
		var own := _cast_set(class_id)
		assert_false(own.is_empty(), "%s cast nothing at all" % class_id)
		assert_eq(_only_in(own, own), [],
			"%s reads as casting something it does not cast" % class_id)


## Issue 2's acceptance criterion 6 asked for a win count across twenty seeds
## that was neither 0 nor 20, which assumed combat outcomes vary with the
## seed. At the time nothing did. The fix landed as issue 7's damage-variance
## hook. The tests below are issue 7's real distribution-based replacements
## for that single-seed check.

func _win_rate(classes: Array[StringName], seeds: int) -> Dictionary:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var wins := 0
	var ticks: Array[int] = []
	var costs: Array[float] = []
	for seed in seeds:
		var party: Array[PawnData] = []
		for i in classes.size():
			party.append(PawnFactory.make_starter_pawn(classes[i], &"%s_%d_%d" % [classes[i], seed, i], String(classes[i])))
		var state := CombatSim.build(party, encounter, seed)
		var outcome := CombatSim.run(state)
		ticks.append(state.tick)
		if outcome == CombatState.Outcome.PLAYER_WIN:
			wins += 1
			var total_hp := 0.0
			var max_hp := 0.0
			for u in state.units:
				# Pawns only. `u.pawn == null` is a summon; see the ratchet note
				# above `WARDEN_MAX_HEALTH_LEFT` for what counting siege engines
				# as party health did to a whole table of thresholds.
				if u.team == CG.Team.PLAYER and u.pawn != null:
					max_hp += float(u.hp_max)
					total_hp += float(maxi(0, u.hp))
			costs.append(total_hp / max_hp * 100.0)
	ticks.sort()
	costs.sort()
	var median_cost := costs[costs.size() / 2] if not costs.is_empty() else -1.0
	return {"wins": wins, "min": ticks[0], "median": ticks[ticks.size() / 2], "max": ticks[ticks.size() - 1], "median_cost": median_cost}


func test_seed_changes_the_fight() -> void:
	# **This comment used to say geysermancer x4 "has the widest measured spread
	# of the sampled comps". It does not: abomination x4 is 108% against this
	# party's 55% (#268).** The assertion is left where
	# it is -- 55% clears a 15% floor comfortably and re-pointing a passing test
	# at a different party to chase a bigger number is not an improvement. What
	# was wrong was the sentence, so the sentence is what changed.
	var r := _win_rate([&"geysermancer", &"geysermancer", &"geysermancer", &"geysermancer"], 20)
	var spread_fraction := float(r["max"] - r["min"]) / float(max(1, r["median"]))
	print("seed sensitivity, geysermancer x4: ticks min=%d median=%d max=%d (spread %.0f%% of median)" % [r["min"], r["median"], r["max"], spread_fraction * 100.0])
	assert_true(spread_fraction >= 0.15, "tick spread should be at least 15%% of the median, was %.0f%%" % (spread_fraction * 100.0))


func test_same_seed_replays_bit_identical() -> void:
	var encounter := Registry.get_encounter(CG.DEFAULT_ENCOUNTER)
	var party_a := _party_of(&"priest", 4)
	var party_b := _party_of(&"priest", 4)
	var state_a := CombatSim.build(party_a, encounter, 777)
	var state_b := CombatSim.build(party_b, encounter, 777)
	var outcome_a := CombatSim.run(state_a)
	var outcome_b := CombatSim.run(state_b)
	assert_eq(outcome_a, outcome_b)
	assert_eq(state_a.tick, state_b.tick)
	assert_eq(state_a.events.size(), state_b.events.size(), "same seed must produce the same number of events")


## Issue 13b's cover room. #110 replaced the comparison, not the property: the
## old version compared two different rooms, which answers "are these different
## fights" and not "do the pillars do anything".
func test_cover_changes_the_fight_for_the_parties_that_close() -> void:
	var cover := Registry.get_encounter(&"floor1_cover")
	assert_not_null(cover)
	assert_true(cover.terrain.size() > 0, "floor1_cover should carry pillars")

	var bare := Encounter.new()
	bare.id = cover.id
	bare.display_name = cover.display_name
	bare.enemy_spawns = cover.enemy_spawns
	bare.party_spawns = cover.party_spawns
	bare.terrain = []

	for class_id in [&"abomination", &"warrior", &"geysermancer", &"priest", &"siege_master"]:
		var differing := 0
		for seed in 5:
			var with_pillars := CombatSim.build(_party_of(class_id, 4), cover, seed)
			CombatSim.run(with_pillars)
			var without := CombatSim.build(_party_of(class_id, 4), bare, seed)
			CombatSim.run(without)
			if with_pillars.tick != without.tick or with_pillars.outcome != without.outcome:
				differing += 1
		print("floor1_cover, %s x4: %d/5 seeds differ with the pillars against the same room without them" % [class_id, differing])
		if class_id == &"abomination" or class_id == &"warrior":
			assert_true(differing >= 4, "floor1_cover's pillars should change the fight for %s x4, which closes to melee; changed %d of 5 seeds" % [class_id, differing])


## Issue 34: `floor1_chokepoint` resolves now instead of drawing. It was pulled
## from the registry when it stalled every fight to the 3600-tick cap (13b), then
## restored once the decide-time line-of-sight check came back.
func test_the_chokepoint_room_resolves_instead_of_drawing() -> void:
	var chokepoint := Registry.get_encounter(&"floor1_chokepoint")
	assert_not_null(chokepoint)
	var draws := 0
	for seed in 10:
		var state := CombatSim.build(_party_of(&"siege_master", 4), chokepoint, seed)
		CombatSim.run(state)
		if state.outcome != CombatState.Outcome.PLAYER_WIN and state.outcome != CombatState.Outcome.ENEMY_WIN:
			draws += 1
			print("floor1_chokepoint seed %d did not resolve: %s at tick %d of %d" % [
				seed, CombatState.Outcome.keys()[state.outcome], state.tick, CG.MAX_TICKS,
			])
	assert_true(draws <= 2, "expected floor1_chokepoint to resolve most fights, got %d/10 draws" % draws)


## The known-bad input, constructed rather than borrowed from a defect (#268).
func test_the_stall_detector_can_see_a_constructed_stall() -> void:
	var enc := Encounter.new()
	enc.id = &"a_wall_across_the_room"
	enc.display_name = "a wall across the room"
	enc.enemy_spawns = [
		{"enemy_id": &"goblin", "position": Vector2(400.0, -60.0)},
		{"enemy_id": &"goblin", "position": Vector2(400.0, 60.0)},
	]
	enc.party_spawns = [Vector2(-400.0, -60.0), Vector2(-400.0, 60.0)]
	enc.terrain = [Terrain.make(Terrain.Kind.WALL, Rect2(-30.0, -CG.ARENA_HALF_HEIGHT, 60.0, CG.ARENA_HALF_HEIGHT * 2.0))]

	var state := CombatSim.build(_party_of(&"warrior", 2), enc, 0)
	CombatSim.run(state)
	print("a wall across the room: %s at tick %d" % [CombatState.Outcome.keys()[state.outcome], state.tick])

	assert_eq(state.tick, CG.MAX_TICKS,
		"the wall fixture must not resolve, and it ended at tick %d. If movement or sight changed so that a unit can now cross or shoot through a full-height wall, that is a real finding about Scripts/Combat and not a reason to weaken this test." % state.tick)
	# The whole point of the fixture, and the assertion #263 found dead: the
	# guard above reads exactly this predicate, so it has to be true here.
	assert_true(state.outcome != CombatState.Outcome.PLAYER_WIN and state.outcome != CombatState.Outcome.ENEMY_WIN,
		"a fight sitting on the tick cap must count as unresolved, and this one reported %s" % CombatState.Outcome.keys()[state.outcome])
	assert_eq(state.outcome, CombatState.Outcome.DRAW,
		"a stall reports DRAW, not UNRESOLVED -- if this ever changes, the guard above has to change with it")
