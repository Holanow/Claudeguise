extends "res://Tests/TestCase.gd"


## ISSUE 492. The Geysermancer's two water spells leave pools, and water and
## fire annihilate the ground they share. Terrain is dynamic from here on, which
## is the whole of the engineering: `state.terrain` was the room as authored and
## never changed once.

const FIRE := Rect2(-100.0, -100.0, 200.0, 200.0)

func _fire(rect: Rect2 = FIRE) -> Terrain.Feature:
	return Terrain.hazard(rect, 2, CG.DamageType.FIRE)

func _pool_action(half_width: float) -> ActionDef:
	var a := ActionDef.new()
	a.id = &"fixture_pool"
	a.range_units = 9000.0
	a.leaves_pool_radius = half_width
	return a

## A caster, a victim it can always reach, and whatever terrain the test wants.
func _arena(terrain: Array, action: ActionDef) -> Array:
	var state := CombatState.new(0)
	var caster := _unit(0, CG.Team.PLAYER, Vector2(-400.0, 0.0))
	caster.actions = [action.id] as Array[StringName]
	state.units.append(caster)
	var foe := _unit(1, CG.Team.ENEMY, Vector2.ZERO)
	state.units.append(foe)
	state.grid.stamp_features(terrain)
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName) -> ActionDef: return action if id == action.id else null
	deps.plan_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return null
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return [state, caster, foe, deps]

func _unit(id: int, team: CG.Team, at: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp = 500
	u.hp_max = 500
	u.position = at
	return u

## Fires the action for real rather than calling the pool helper, so the test
## exercises the path the game uses.
func _cast(bundle: Array) -> void:
	var state: CombatState = bundle[0]
	var caster: CombatUnit = bundle[1]
	caster.focus_id = bundle[2].id
	caster.intent = Intent.use_action(&"fixture_pool", bundle[2].id)
	CombatSim.step(state, bundle[3])

## Issue 625: cells, not features. A pool is the ground it covers and there is
## no longer any such thing as two features of the same kind on one spot.
func _of_kind(state: CombatState, kind: Terrain.Kind) -> Array:
	return state.grid.cells_of_kind(kind)

## Issue 625: ground covered, counted in cells. A cell is wet once, so this is
## the union by construction rather than by a containment check.
func _area(cells: Array) -> float:
	return float(cells.size()) * TerrainGrid.CELL * TerrainGrid.CELL

func _stamps(state: CombatState) -> Array:
	return _of_kind(state, Terrain.Kind.WATER)

func _wet(state: CombatState, p: Vector2) -> bool:
	var cell = state.grid.cell_at(p)
	return cell != null and cell.kind == Terrain.Kind.WATER

# --- the geometry -----------------------------------------------------------

## Issue 625 deleted `Terrain.subtract` and the six tests that covered it: a
## cell is one kind of ground, so there is no rectangle left to cut.

## Issue 496: Scald is the FIRE spell, so a pool under it puts out the burn it
## just applied. It is on the free WATER basic attack instead.
func test_exactly_two_actions_leave_a_pool_and_neither_is_the_fire_spell() -> void:
	var with_pool: Array[StringName] = []
	for id in Registry.all_action_ids():
		if Registry.get_action(id).leaves_pool_radius > 0.0:
			with_pool.append(id)
	with_pool.sort_custom(func(a, b): return String(a) < String(b))
	assert_eq(with_pool, [&"geyser_blast", &"geyser_spout"] as Array[StringName],
		"the pool belongs to the two WATER actions and to nothing else")
	assert_eq(Registry.get_action(&"geyser_scald").damage_type, CG.DamageType.FIRE,
		"if Scald has stopped being the fire spell this test is asserting nothing")

func test_the_pool_is_on_the_action_a_pawn_nobody_configured_will_cast() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"geysermancer", &"g", "G")
	var actions: Array[ActionDef] = []
	for id in Registry.actions_for_pawn(pawn):
		actions.append(Registry.get_action(id))
	var attack := DefaultBehavior.default_attack_action(actions, true)
	assert_eq(attack.id, &"geyser_spout", "the cheapest ranged attack is what a starter casts")
	assert_true(attack.leaves_pool_radius > 0.0,
		"a feature only a plan-editing player can reach does not reach a default game")

# --- the rule, through the simulation ---------------------------------------

func test_a_spell_with_no_pool_radius_leaves_no_terrain() -> void:
	var bundle := _arena([], _pool_action(0.0))
	_cast(bundle)
	assert_eq(bundle[0].grid.count(), 0,
		"every action in the game but two leaves nothing, and this is the control")

func test_a_pool_appears_where_the_effect_landed() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast(bundle)
	var pools := _of_kind(bundle[0], Terrain.Kind.WATER)
	## 4 x 4: a 50-wide stamp on the origin holds the centres of cells -2..1.
	assert_eq(pools.size(), 16, "the 16 cells whose centres the stamp covered")
	assert_true(_wet(bundle[0], Vector2.ZERO), "centred on the target it hit")
	assert_false(_wet(bundle[0], Vector2(60.0, 0.0)), "and no further")

func test_a_pool_does_nothing_on_its_own() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast(bundle)
	var pool = bundle[0].grid.cell_at(Vector2.ZERO)
	assert_eq(pool.damage_per_tick, 0, "no damage")
	assert_false(pool.applies_status_enabled, "no status")
	assert_false(pool.blocks_movement(), "and it does not block a foot")
	assert_false(pool.blocks_sight(), "or a line of sight")
	assert_eq(bundle[0].grid.hazards_at(Vector2.ZERO).size(), 0,
		"a pool is not a hazard, so nothing standing in it takes a tick of anything")

## **The player's ruling, and the expensive half of it: the whole hazard is not
## erased.** A pool inside a fire punches a hole and the fire comes back as the
## four parts around it.
func test_a_pool_inside_a_fire_punches_a_hole_rather_than_erasing_it() -> void:
	var bundle := _arena([_fire()], _pool_action(25.0))
	_cast(bundle)
	var fires := _of_kind(bundle[0], Terrain.Kind.HAZARD)
	## 196 authored cells (14 x 14) less the pool's 16. Issue 625: the hole is
	## cells rather than four rectangles, and it is the same hole.
	assert_eq(fires.size(), 196 - 16, "fire minus the pool is a hole in it, not nothing")
	assert_almost_eq(_area(fires), float(196 - 16) * 225.0, 0.001,
		"exactly the shared ground came off and no more")
	assert_true(bundle[0].grid.hazards_at(Vector2(90.0, 0.0)).size() > 0,
		"ground the pool never touched is still on fire")
	assert_eq(bundle[0].grid.hazards_at(Vector2.ZERO).size(), 0,
		"and the ground it did touch is not")

## The other half of "pools do not survive cancelation": the pool loses the same
## ground the fire does.
func test_a_pool_fully_inside_a_fire_is_spent_entirely() -> void:
	var bundle := _arena([_fire()], _pool_action(25.0))
	_cast(bundle)
	assert_eq(_of_kind(bundle[0], Terrain.Kind.WATER).size(), 0,
		"all of it was used putting the fire out, so none of it is left")

func test_a_pool_over_an_edge_keeps_only_the_half_that_missed() -> void:
	var bundle := _arena([_fire(Rect2(0.0, -100.0, 200.0, 200.0))], _pool_action(25.0))
	_cast(bundle)
	var pools := _of_kind(bundle[0], Terrain.Kind.WATER)
	assert_eq(pools.size(), 8,
		"half the pool overlapped the fire and went with it; half remains")
	var fires := _of_kind(bundle[0], Terrain.Kind.HAZARD)
	assert_eq(fires.size(), 196 - 8, "and the fire lost exactly the same ground")

func test_water_only_cancels_fire_and_leaves_other_hazards_alone() -> void:
	var tar := Terrain.hazard(FIRE, 0, CG.DamageType.EARTH)
	var bundle := _arena([tar], _pool_action(25.0))
	_cast(bundle)
	assert_eq(_of_kind(bundle[0], Terrain.Kind.HAZARD).size(), 196 - 16, "a tar pit is not on fire")
	assert_eq(_of_kind(bundle[0], Terrain.Kind.WATER).size(), 16, "so nothing was spent putting it out")

func test_a_pool_across_two_fires_is_cut_by_both() -> void:
	var bundle := _arena([
		_fire(Rect2(-200.0, -100.0, 190.0, 200.0)),
		_fire(Rect2(10.0, -100.0, 190.0, 200.0)),
	], _pool_action(25.0))
	_cast(bundle)
	## Issue 625, and it is a real consequence rather than a rounding detail:
	## the 20-wide gap here is wider than a cell and STILL does not survive,
	## because it straddles cells -1 and 0 and each fire touches one of them.
	assert_eq(_of_kind(bundle[0], Terrain.Kind.WATER).size(), 0,
		"a gap neither fire leaves a whole cell of is no gap at all")

## The same rule where the gap does hold a whole free cell: cells -1 and 0 span
## -15..15, and fires stopping at -15 and starting at 15 touch neither.
func test_a_gap_wide_enough_to_hold_a_whole_cell_stays_wet() -> void:
	var bundle := _arena([
		_fire(Rect2(-200.0, -100.0, 185.0, 200.0)),
		_fire(Rect2(15.0, -100.0, 185.0, 200.0)),
	], _pool_action(25.0))
	_cast(bundle)
	assert_eq(_of_kind(bundle[0], Terrain.Kind.WATER).size(), 8,
		"the two free columns of the pool, four cells each, are still water")

## A split fire is still the fire it was split from.
func test_the_parts_of_a_split_hazard_keep_what_made_it_dangerous() -> void:
	var bundle := _arena([_fire()], _pool_action(25.0))
	_cast(bundle)
	for c in _of_kind(bundle[0], Terrain.Kind.HAZARD):
		var f = bundle[0].grid.at(c)
		assert_eq(f.damage_per_tick, 2, "a cell that stopped hurting is a bug, not a hole")
		assert_eq(f.damage_type, CG.DamageType.FIRE)

# --- the view may not learn about this by reading state ----------------------

func _terrain_events(state: CombatState) -> Array:
	var out: Array = []
	for e in state.events:
		if e.kind == CG.EventKind.TERRAIN_ADDED or e.kind == CG.EventKind.TERRAIN_REMOVED:
			out.append(e)
	return out

func test_every_change_to_the_terrain_is_in_the_event_stream() -> void:
	var bundle := _arena([_fire()], _pool_action(25.0))
	_cast(bundle)
	var events := _terrain_events(bundle[0])
	assert_true(events.size() > 0, "a pool nobody was told about is a pool the view cannot draw")
	## Issue 625: an event carries the rectangle bounding the cells it changed,
	## so the test is that the stream covers every cell the simulation holds --
	## not that replaying rectangles reconstructs the floor, which stopped being
	## how the floor is stored.
	var announced: Array[Rect2] = []
	for e in events:
		if e.kind == CG.EventKind.TERRAIN_ADDED:
			announced.append(e.terrain_rect)
	for c in _of_kind(bundle[0], Terrain.Kind.WATER):
		var covered := false
		for r in announced:
			if r.has_point(TerrainGrid.rect_of(c).get_center()):
				covered = true
		assert_true(covered, "the stream never mentioned the water at %s" % c)

func test_the_events_say_which_spell_did_it_and_why() -> void:
	var bundle := _arena([_fire()], _pool_action(25.0))
	_cast(bundle)
	var doused := 0
	for e in _terrain_events(bundle[0]):
		assert_eq(e.source_id, 0, "the caster is named, or the log cannot say who")
		assert_eq(e.action_id, &"fixture_pool", "and so is the spell")
		if e.kind == CG.EventKind.TERRAIN_REMOVED:
			doused += 1
			assert_eq(e.terrain_change, CG.TerrainChange.DOUSED)
	assert_eq(doused, 1, "one fire went out, so the log has exactly one line to write")

func test_a_pool_that_touches_nothing_is_reported_as_cast() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast(bundle)
	var events := _terrain_events(bundle[0])
	assert_eq(events.size(), 1)
	assert_eq(events[0].kind, CG.EventKind.TERRAIN_ADDED)
	assert_eq(events[0].terrain_change, CG.TerrainChange.CAST)
	assert_eq(events[0].terrain_kind, Terrain.Kind.WATER)

## **`BattleView` hands `state.terrain` to `ArenaFloor` once, at fight start.**
## Reassigning the array instead of refilling it leaves the arena drawing the
## room as authored for the rest of the fight, which is how the first version of
## this shipped: the log said a pool had been left and the floor never changed.
func test_a_reference_taken_before_the_cast_still_sees_the_terrain() -> void:
	var bundle := _arena([_fire()], _pool_action(25.0))
	var held: TerrainGrid = bundle[0].grid
	var before := held.count()
	_cast(bundle)
	assert_eq(held, bundle[0].grid,
		"the view holds this grid and must not be left looking at a stale copy")
	## The pool lands wholly inside the fire, so #496's ruling spends all of it
	## and what the view must see change is the hole, not a puddle.
	assert_true(held.count() < before, "and it must have actually changed")

## **The room is not a scratchpad.** `build()` shared the encounter's own array,
## which was harmless while terrain never changed: pools were written back into
## the room definition and the next fight in the same process started in the last
## one's puddles. It cost 6.8x on the heaviest test before anyone noticed.
func test_a_fight_does_not_leave_its_pools_in_the_room() -> void:
	var encounter := Registry.get_encounter(&"floor1_hazard")
	var authored: int = encounter.terrain.size()
	for _run in 3:
		var party: Array[PawnData] = []
		for cid in [&"geysermancer", &"warrior"]:
			party.append(PawnFactory.make_preset_pawn(
				cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
		var state := CombatSim.build(party, encounter, 1)
		CombatSim.run(state)
		assert_eq(encounter.terrain.size(), authored,
			"the room grew to %d features; a fight must not edit the encounter"
				% encounter.terrain.size())

# --- determinism ------------------------------------------------------------

func _digest(state: CombatState) -> String:
	var parts: Array[String] = []
	for c in state.grid.sorted_cells():
		parts.append("%d:%s" % [state.grid.at(c).kind, c])
	for u in state.units:
		parts.append("%d:%d:%s" % [u.id, u.hp, u.position])
	return "|".join(parts)

## Terrain is now state, so the same seed has to produce the same terrain, not
## merely the same units.
func test_the_same_fight_produces_the_same_terrain_twice() -> void:
	var first := ""
	for run in 2:
		var bundle := _arena([
			_fire(Rect2(-200.0, -100.0, 190.0, 200.0)),
			_fire(Rect2(10.0, -100.0, 190.0, 200.0)),
		], _pool_action(25.0))
		_cast(bundle)
		_cast(bundle)
		if run == 0:
			first = _digest(bundle[0])
		else:
			assert_eq(_digest(bundle[0]), first, "two runs of one fight disagreed about the floor")


# --- issue 554: pools fuse into one painted region ---------------------------

## Casts at the same spot twice. The player: *"the pools just fuse into one,
## think painting the floor"*.
func _cast_at(bundle: Array, where: Vector2) -> void:
	bundle[2].position = where
	_cast(bundle)


func test_two_overlapping_casts_leave_one_pool_not_two() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast_at(bundle, Vector2.ZERO)
	_cast_at(bundle, Vector2(20.0, 0.0))
	assert_eq(_of_kind(bundle[0], Terrain.Kind.WATER).size(), 5 * 4,
		"two overlapping casts fuse: five columns of four, not sixteen plus twelve")


## Property one, and the whole reason a union of bounding boxes was rejected:
## the stored region must wet ONLY ground a cast actually painted. Two 50x50
## stamps offset diagonally share no corner, and a union rect would wet both.
func test_a_fused_pool_never_wets_ground_no_cast_painted() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast_at(bundle, Vector2.ZERO)
	_cast_at(bundle, Vector2(40.0, 40.0))
	var state: CombatState = bundle[0]
	assert_true(_wet(state, Vector2.ZERO), "the first stamp's centre must be wet")
	assert_true(_wet(state, Vector2(40.0, 40.0)), "the second stamp's centre must be wet")
	# (-20, 40) is inside the bounding box of the two stamps and inside neither.
	assert_false(_wet(state, Vector2(-20.0, 40.0)),
		"a corner no cast painted must stay dry; this is what a union rect would have wetted")


## The area is the union, so overlap is stored once rather than twice.
func test_a_fused_pool_stores_the_overlap_once() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast_at(bundle, Vector2.ZERO)
	_cast_at(bundle, Vector2(25.0, 0.0))
	## Columns -2..1 and 0..2 union to five, times four rows.
	assert_eq(_of_kind(bundle[0], Terrain.Kind.WATER).size(), 5 * 4,
		"the overlapping half should be stored once, not twice")


## The 147x redundancy #504 measured is mostly this case.
func test_a_cast_onto_ground_already_wet_stores_nothing() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast_at(bundle, Vector2.ZERO)
	var before := _stamps(bundle[0]).size()
	var terrain_events_before: int = _terrain_events(bundle[0]).size()
	_cast_at(bundle, Vector2.ZERO)
	assert_eq(_stamps(bundle[0]).size(), before,
		"a stamp landing entirely on wet ground should add no geometry")
	assert_eq(_terrain_events(bundle[0]).size(), terrain_events_before,
		"and it should report no terrain change, because nothing changed")


## The negative: a cast that lands clear of the puddle must still paint.
func test_a_cast_on_dry_ground_still_paints() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast_at(bundle, Vector2.ZERO)
	var before := _stamps(bundle[0]).size()
	_cast_at(bundle, Vector2(400.0, 400.0))
	assert_true(_stamps(bundle[0]).size() > before,
		"dry ground must still get wet, or the containment check is swallowing everything")
	assert_true(_wet(bundle[0], Vector2(400.0, 400.0)))


