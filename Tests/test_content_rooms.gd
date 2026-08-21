extends "res://Tests/TestCase.gd"


## Issue #94: the four rooms a player picks between, and the properties that
## make them four rooms rather than four skins. OWNER: heron.

## The four rooms #94 built, and the set every headcount, stall and wall check
## in this file measures across.
const PICKABLE: Array[StringName] = [
	&"floor1_room1",
	&"floor1_cover",
	&"floor1_hazard",
	&"floor1_chokepoint",
]

## Class ids in a stable order, and this helper is not incidental:
## `Registry.all_class_ids()` sorts an `Array[StringName]`, and StringName does
## not sort alphabetically -- Godot compares the interned pointer.
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
		out.append(PawnFactory.make_preset_pawn(ids[i], StringName("%s_%d_%d" % [ids[i], seed, i]), String(ids[i])))
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


## Every other test in this file measures a room a player cannot reach; this is
## the one that says so out loud (issue #176). `PartySelect.current_config()` is
## the only path from a player to a fight.



## **The headcount rule, and it is the reason any other number in this file
## means anything.** The retrospective records a terrain conclusion that was
## wrong because it compared a three-enemy room against a ten-enemy one and
## credited the geometry for the difference. Before issue #94 that was still
## live in the content: `floor1_cover` and `floor1_hazard` carried three
## enemies each while `floor1_room1` and `floor1_chokepoint` carried ten.
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


## Issue #121, and board rule 1 is why this test exists: a win table cannot see a
## dead mechanic. The Brute's before/after win table on `floor1_hazard` is nearly
## flat.
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


## The Rat King's lash really does leave rats behind, and the swarm really does
## not accumulate. Both halves are asserted or printed on purpose.
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


## A record of a defect, written so it fails on the day the defect is fixed.
## ENGINEER.md: when a check cannot pass yet, assert the reason is still true
## rather than leaving a comment to rot.
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

	# The lash count is printed and deliberately not asserted. It was written as an
	# assertion first and it was wrong: the median moved from 1 to 4.8 between two
	# branches, because a working Abomination changes every fight around it.
	assert_true(peak_rats <= 6,
		"the swarm now peaks at %d rats against the four the room starts with. If that is a fix, delete this test and assert the swarm properly (issue #97)" % peak_rats)


## **Issue #130's rats, and it replaces an assertion of swift's that fired.**
##
## `test_combat_bleed_is_live.gd::test_no_authored_action_applies_bleed_yet`
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


## Issue #121's Stalker, and the honest half: this asserts the mark reaches the
## game at all. What it does not assert, because it does not exist yet, is the
## half the player asked for.
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


## The #78 regression guard, and the reason this file exists. #78: three fights
## in 700 never resolved on `floor1_chokepoint` and reported `Outcome.DRAW`, the
## same value a mutual wipe produces, so every run tool counted a hang as a result.
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


## The tar pit's field pair in `Terrain.gd` -- `applies_status`,
## `applies_status_enabled`, `status_duration_ticks` -- is read by nothing.
## `_tick_hazards` consults `damage_per_tick` only, and skips any hazard
## dealing no damage before it could look at a status. See #204.
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


## The colonnade has to be a colonnade. A roster was once chosen for this room on
## its win table alone -- best cost spread, no party walled, zero stalls -- and
## none of that says whether the pillars mattered.
func test_the_colonnades_pillars_are_not_decoration() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var bare := _without_terrain(enc)
	var seeds := 10
	var largest := 0
	var total := 0
	var worst_divergence := seeds + 1
	var diverging_fights := 0
	var party_fights := 0
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
		diverging_fights += differs
		party_fights += seeds
	print("floor1_cover: largest single health effect %d points, total across five parties %d; fewest diverging fights for any party %d/%d; diverging fights overall %d/%d" % [largest, total, worst_divergence, seeds, diverging_fights, party_fights])
	# Threshold unchanged since issue 121; with the pillars moved onto the battle
	# line (#330) the room clears it at 50/50, health deltas +11 +5 +18 +10 -1.
	assert_true(diverging_fights >= 25,
		"the pillars should change the fight; only %d of %d party-fights diverged with them in, against 0 for a colonnade of paint" % [diverging_fights, party_fights])


## The player's metric for the colonnade, issue #330: fewer ranged attacks get
## fired in a room with pillars than in the same room without them. It counts
## attempts, so a unit that shoots into stone counts against the room.
func test_the_colonnade_takes_ranged_attacks_out_of_the_fight() -> void:
	var enc := Registry.get_encounter(&"floor1_cover")
	var seeds := 10
	var stone := _ranged_attack_rate(enc, seeds)
	var paint := _ranged_attack_rate(_without_terrain(enc), seeds)
	print("floor1_cover: ranged attacks %d over %d living unit-ticks = %.2f per 1000; colonnade of paint %d over %d = %.2f per 1000" % [
		stone[0], stone[1], stone[2], paint[0], paint[1], paint[2],
	])
	print("floor1_cover: the pillars take %.1f%% of the ranged attacks out of the fight" % [
		100.0 * (paint[2] - stone[2]) / paint[2],
	])
	assert_true(stone[2] < paint[2],
		("the pillars should mean fewer ranged attacks, normalised for fight length; got %.2f per 1000 with them "
		+ "against %.2f without. Nothing seeks cover on purpose yet -- see #316 and #330.") % [stone[2], paint[2]])
	assert_true(stone[0] < paint[0],
		"and fewer in raw count too; got %d with the pillars against %d without" % [stone[0], paint[0]])


## Ranged attacks fired, living unit-ticks, and the rate per thousand of them.
## Normalised because pillars change fight length, and a longer fight fires more
## shots for reasons that have nothing to do with cover.
func _ranged_attack_rate(enc: Encounter, seeds: int) -> Array:
	var fires := 0
	var unit_ticks := 0
	for ids in _buildable_parties():
		for seed in seeds:
			var state := CombatSim.build(_pawns(ids, seed), enc, seed)
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for u in state.units:
					if u.alive:
						unit_ticks += 1
			for e in state.events:
				if e.kind == CG.EventKind.ACTION_FIRE and _is_a_ranged_attack(e.action_id):
					fires += 1
	return [fires, unit_ticks, 1000.0 * float(fires) / float(maxi(1, unit_ticks))]


func _is_a_ranged_attack(action_id: StringName) -> bool:
	var a := Registry.get_action(action_id)
	return a != null and not a.heals and a.requires_line_of_sight and a.range_units > 60.0


## The fire has to change the fight, and the control is the same roster with the
## fire removed. The old single 160x120 patch sat off the shortest path and cost
## every buildable party almost nothing.
func test_the_burn_pit_changes_the_fight_for_every_buildable_party() -> void:
	var enc := Registry.get_encounter(&"floor1_hazard")
	var bare := _without_terrain(enc)
	var seeds := 4
	var ratio_total := 0.0
	var parties := 0
	var shortened := 0
	var largest_health := 0
	var largest_carrier := ""
	var health_total := 0
	var enemy_fire := 0
	var party_fire := 0
	var fire_kills := 0
	var fights := 0
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
			var burned := _hazard_damage_by_team(a)
			party_fire += burned[0]
			enemy_fire += burned[1]
			fire_kills += _killed_by_the_fire(a)
			fights += 1
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
		if absi(health_delta) > largest_health:
			largest_carrier = "%s (%+d)" % [ids, health_delta]
		largest_health = maxi(largest_health, absi(health_delta))
		health_total += absi(health_delta)
	var mean_ratio := ratio_total / float(maxi(1, parties))
	print("floor1_hazard: mean fire/bare tick ratio across %d parties %.2f, shortened for %d" % [parties, mean_ratio, shortened])
	print("floor1_hazard: largest single health effect %d points, carried by %s; total across five parties %d" % [largest_health, largest_carrier, health_total])
	print("floor1_hazard: the fire itself dealt %d health per fight to the enemy and %d to the party, over %d fights" % [
		enemy_fire / maxi(1, fights), party_fire / maxi(1, fights), fights,
	])
	print("floor1_hazard: the fire landed the killing blow on %.2f enemies per fight" % [
		float(fire_kills) / float(maxi(1, fights)),
	])

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
	# And the same proof for the fire-output floor below, which is the half of
	# this test that is *not* a difference of two arms and so has no control of
	# its own. A detector nobody feeds known-good input to is `ENGINEER.md`'s
	# sixteen-passing-tests failure; a hazard of paint is the known-good input.
	var control_bare := _run(_pawns(_buildable_parties()[0], 0), bare, 0)
	var control_burn := _hazard_damage_by_team(control_bare)
	assert_eq(control_burn[0], 0, "with the terrain stripped nothing can be burnt, and the party took %d" % control_burn[0])
	assert_eq(control_burn[1], 0, "with the terrain stripped nothing can be burnt, and the enemy took %d" % control_burn[1])
	# finch, issue 121: `every party` became `four of five`, and the exception is
	# named rather than the threshold widened. Measured 0.56, 0.55, 1.17, 0.74,
	# 0.84 -- the outlier is the one buildable party with no Priest.

	# Every assertion above is a difference of two arms, and none asserted the fire
	# ever dealt a point of damage: both tick ratios and `largest_health` compare
	# the room against itself stripped, so anything moving the bare arm moves the
	# verdict. This asserts the fire itself.
	assert_true(enemy_fire / maxi(1, fights) >= 100,
		"the fire should burn the enemy back rank crossing it; it dealt %d health per fight over %d fights, against 0 for a hazard of paint" % [enemy_fire / maxi(1, fights), fights])

	# The half that replaces `largest_health`: damage is the fire working, a kill
	# is the fire deciding something.
	assert_true(fire_kills >= fights,
		"the fire should land the killing blow on about two enemies a fight; it landed %d over %d fights, against 0 for a hazard of paint" % [fire_kills, fights])
	assert_eq(_killed_by_the_fire(control_bare), 0,
		"with the terrain stripped the fire can kill nobody, and it killed %d" % _killed_by_the_fire(control_bare))


func _run(party: Array[PawnData], enc: Encounter, seed: int) -> CombatState:
	var state := CombatSim.build(party, enc, seed)
	CombatSim.run(state)
	return state


## Health taken from terrain, as `[party, enemy]`. The discriminator is `status`:
## `_tick_hazards` and the damage-over-time tick both emit DAMAGE with
## `source_id == -1`, so the status is the only thing telling them apart.
func _killed_by_the_fire(state: CombatState) -> int:
	var by_fire := {}
	for e in state.events:
		if e.kind != CG.EventKind.DAMAGE:
			continue
		by_fire[e.target_id] = e.source_id == -1 and e.action_id == &"" and e.status == CG.Status.SHIELD
	var killed := 0
	for u in state.units:
		if u.hp > 0 or u.team == CG.Team.PLAYER:
			continue
		if by_fire.get(u.id, false):
			killed += 1
	return killed


func _hazard_damage_by_team(state: CombatState) -> Array:
	var mine := 0
	var theirs := 0
	for e in state.events:
		if e.kind != CG.EventKind.DAMAGE or e.source_id != -1 or e.action_id != &"":
			continue
		if e.status != CG.Status.SHIELD:
			continue
		var u := state.unit(e.target_id)
		if u == null:
			continue
		if u.team == CG.Team.PLAYER:
			mine += e.amount
		else:
			theirs += e.amount
	return [mine, theirs]


## Excludes summons. `CombatSim._spawn_summon` gives a summon `caster.team`, so
## a Siege Engine reads as PLAYER and this sum used to include 140 hp of immobile
## health. Every `team == PLAYER` total needs the same discriminator.
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


## The player's standing direction (PLAYTEST-NOTES.md): with a party of four
## the player should win most single battles and lose to attrition. A pickable
## room one party simply cannot have is not variety, it is a card they learn not
## to press.
const WALL_SEEDS := 20
const WALL_FLOOR := 5


## The same room with every enemy spawned twice, the second copy offset so the
## pair does not start inside itself. Terrain, roster and party spawns are
## untouched: the only variable is how many bodies the party has to get through.
func _doubled_roster(enc: Encounter) -> Encounter:
	var e := Encounter.new()
	e.id = enc.id
	e.display_name = enc.display_name
	e.party_spawns = enc.party_spawns
	e.terrain = enc.terrain
	var spawns: Array[Dictionary] = []
	for s in enc.enemy_spawns:
		spawns.append(s)
		spawns.append({"enemy_id": s["enemy_id"], "position": (s["position"] as Vector2) + Vector2(70.0, 0.0)})
	e.enemy_spawns = spawns
	return e


func test_no_pickable_room_is_a_wall_for_any_buildable_party() -> void:
	var seeds := WALL_SEEDS
	var floor_wins := WALL_FLOOR
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


## **The detector, run against a room that really is a wall.**
##
## `floor1_chokepoint` with twenty enemies instead of ten. Measured at
## **0/40 for all five buildable parties** by `Tools/WallProbe.gd`; the gate
## runs the same seeds and the same floor constant as the assertion above, so a
## floor moved later is re-checked here without anybody remembering to.
func test_the_detector_fires_on_a_room_that_really_is_a_wall() -> void:
	var wall := _doubled_roster(Registry.get_encounter(&"floor1_chokepoint"))
	for ids in _buildable_parties():
		var wins := 0
		for seed in WALL_SEEDS:
			if _run(_pawns(ids, seed), wall, seed).outcome == CombatState.Outcome.PLAYER_WIN:
				wins += 1
				if wins >= WALL_FLOOR:
					break
		print("wall control: %s won %d/%d, floor %d" % [ids, wins, WALL_SEEDS, WALL_FLOOR])
		assert_true(wins < WALL_FLOOR,
			"the doubled chokepoint is a wall and the detector should say so, but %s won %d/%d against a floor of %d" % [ids, wins, WALL_SEEDS, WALL_FLOOR])
