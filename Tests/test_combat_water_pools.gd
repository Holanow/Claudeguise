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
	state.terrain = terrain
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

func _of_kind(state: CombatState, kind: Terrain.Kind) -> Array:
	var out: Array = []
	for f in state.terrain:
		if f.kind == kind:
			out.append(f)
	return out

func _area(features: Array) -> float:
	var total := 0.0
	for f in features:
		total += f.rect.size.x * f.rect.size.y
	return total

# --- the geometry -----------------------------------------------------------

func test_a_rect_with_nothing_taken_out_of_it_survives_whole() -> void:
	var parts := Terrain.subtract(Rect2(0, 0, 10, 10), Rect2(100, 100, 5, 5))
	assert_eq(parts.size(), 1, "no overlap, no cut")
	assert_eq(parts[0], Rect2(0, 0, 10, 10))

func test_a_hole_punched_in_the_middle_leaves_four_parts() -> void:
	var parts := Terrain.subtract(Rect2(0, 0, 30, 30), Rect2(10, 10, 10, 10))
	assert_eq(parts.size(), 4, "above, below, left and right of the hole")
	assert_almost_eq(_rect_area(parts), 30.0 * 30.0 - 10.0 * 10.0, 0.001,
		"the parts must cover exactly what the hole did not")

func test_a_cut_across_one_edge_leaves_one_part() -> void:
	var parts := Terrain.subtract(Rect2(0, 0, 30, 30), Rect2(-5, -5, 40, 10))
	assert_eq(parts.size(), 1, "the strip spans the full width, so only the remainder below survives")
	assert_eq(parts[0], Rect2(0, 5, 30, 25))

func test_a_rect_swallowed_whole_leaves_nothing() -> void:
	assert_eq(Terrain.subtract(Rect2(5, 5, 10, 10), Rect2(0, 0, 30, 30)).size(), 0)

## The trap rook named: a subtraction that leaves slivers fills `terrain` with
## features nothing can see and everything walks.
func test_slivers_are_dropped_rather_than_kept() -> void:
	var parts := Terrain.subtract(Rect2(0, 0, 30, 30), Rect2(0.1, -5, 40, 40))
	assert_eq(parts.size(), 0,
		"a 0.1-wide leftover is not a feature, it is a rounding artefact: got %s" % [parts])

func test_the_order_of_the_parts_is_fixed() -> void:
	for _i in 5:
		var parts := Terrain.subtract(Rect2(0, 0, 30, 30), Rect2(10, 10, 10, 10))
		assert_eq(parts[0], Rect2(0, 0, 30, 10), "above first")
		assert_eq(parts[1], Rect2(0, 20, 30, 10), "then below")
		assert_eq(parts[2], Rect2(0, 10, 10, 10), "then left")
		assert_eq(parts[3], Rect2(20, 10, 10, 10), "then right")

func _rect_area(parts: Array[Rect2]) -> float:
	var total := 0.0
	for r in parts:
		total += r.size.x * r.size.y
	return total

# --- the rule, through the simulation ---------------------------------------

func test_a_spell_with_no_pool_radius_leaves_no_terrain() -> void:
	var bundle := _arena([], _pool_action(0.0))
	_cast(bundle)
	assert_eq(bundle[0].terrain.size(), 0,
		"every action in the game but two leaves nothing, and this is the control")

func test_a_pool_appears_where_the_effect_landed() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast(bundle)
	var pools := _of_kind(bundle[0], Terrain.Kind.WATER)
	assert_eq(pools.size(), 1)
	assert_eq(pools[0].rect, Rect2(-25.0, -25.0, 50.0, 50.0), "centred on the target it hit")

func test_a_pool_does_nothing_on_its_own() -> void:
	var bundle := _arena([], _pool_action(25.0))
	_cast(bundle)
	var pool: Terrain.Feature = _of_kind(bundle[0], Terrain.Kind.WATER)[0]
	assert_eq(pool.damage_per_tick, 0, "no damage")
	assert_false(pool.applies_status_enabled, "no status")
	assert_false(pool.blocks_movement(), "and it does not block a foot")
	assert_false(pool.blocks_sight(), "or a line of sight")
	assert_eq(Terrain.hazards_at(bundle[0].terrain, Vector2.ZERO).size(), 0,
		"a pool is not a hazard, so nothing standing in it takes a tick of anything")

## **The player's ruling, and the expensive half of it: the whole hazard is not
## erased.** A pool inside a fire punches a hole and the fire comes back as the
## four parts around it.
func test_a_pool_inside_a_fire_punches_a_hole_rather_than_erasing_it() -> void:
	var bundle := _arena([_fire()], _pool_action(25.0))
	_cast(bundle)
	var fires := _of_kind(bundle[0], Terrain.Kind.HAZARD)
	assert_eq(fires.size(), 4, "fire minus the pool is four parts, not nothing")
	assert_almost_eq(_area(fires), 200.0 * 200.0 - 50.0 * 50.0, 0.001,
		"exactly the shared ground came off and no more")
	assert_true(Terrain.hazards_at(bundle[0].terrain, Vector2(90.0, 0.0)).size() > 0,
		"ground the pool never touched is still on fire")
	assert_eq(Terrain.hazards_at(bundle[0].terrain, Vector2.ZERO).size(), 0,
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
	assert_almost_eq(_area(pools), 25.0 * 50.0, 0.001,
		"half the pool overlapped the fire and went with it; half remains")
	var fires := _of_kind(bundle[0], Terrain.Kind.HAZARD)
	assert_almost_eq(_area(fires), 200.0 * 200.0 - 25.0 * 50.0, 0.001,
		"and the fire lost exactly the same ground")

func test_water_only_cancels_fire_and_leaves_other_hazards_alone() -> void:
	var tar := Terrain.hazard(FIRE, 0, CG.DamageType.EARTH)
	var bundle := _arena([tar], _pool_action(25.0))
	_cast(bundle)
	assert_eq(_of_kind(bundle[0], Terrain.Kind.HAZARD).size(), 1, "a tar pit is not on fire")
	assert_eq(_of_kind(bundle[0], Terrain.Kind.WATER).size(), 1, "so nothing was spent putting it out")

func test_a_pool_across_two_fires_is_cut_by_both() -> void:
	var bundle := _arena([
		_fire(Rect2(-200.0, -100.0, 190.0, 200.0)),
		_fire(Rect2(10.0, -100.0, 190.0, 200.0)),
	], _pool_action(25.0))
	_cast(bundle)
	assert_almost_eq(_area(_of_kind(bundle[0], Terrain.Kind.WATER)), 20.0 * 50.0, 0.001,
		"both fires took a 15-wide bite, leaving the 20-wide gap between them")

## A split fire is still the fire it was split from.
func test_the_parts_of_a_split_hazard_keep_what_made_it_dangerous() -> void:
	var bundle := _arena([_fire()], _pool_action(25.0))
	_cast(bundle)
	for f in _of_kind(bundle[0], Terrain.Kind.HAZARD):
		assert_eq(f.damage_per_tick, 2, "a part that stopped hurting is a bug, not a split")
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
	var rebuilt: Array[Rect2] = [FIRE]
	for e in events:
		if e.kind == CG.EventKind.TERRAIN_REMOVED:
			rebuilt.erase(e.terrain_rect)
		else:
			rebuilt.append(e.terrain_rect)
	var live: Array[Rect2] = []
	for f in bundle[0].terrain:
		live.append(f.rect)
	assert_eq(rebuilt.size(), live.size(),
		"replaying the stream must land on the same terrain the simulation holds")
	for r in live:
		assert_true(rebuilt.has(r), "the stream never mentioned %s" % r)

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

# --- determinism ------------------------------------------------------------

func _digest(state: CombatState) -> String:
	var parts: Array[String] = []
	for f in state.terrain:
		parts.append("%d:%s" % [f.kind, f.rect])
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
