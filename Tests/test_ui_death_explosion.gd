extends "res://Tests/TestCase.gd"

const BattleScene := preload("res://Scenes/Battle.tscn")
const DeathExplosionScript := preload("res://Scripts/UI/DeathExplosion.gd")

## Issue 589. A dead unit comes apart into its own chunks. The cut must not
## change what a living body looks like, the chunks must hold still through the
## hit stop the death itself fires, and turning the option off must leave the
## screen exactly as it was.

func _reset() -> void:
	DisplayOptions.reset()
	ViewClock.reset()

# ---------------------------------------------------------------------------
# The cut. This is the only thing that can silently change a body, so it is
# compared pixel for pixel rather than eyeballed -- the check #583 used, on the
# finer cut.
# ---------------------------------------------------------------------------

func test_the_chunks_hold_every_part_once_in_draw_order() -> void:
	# The only thing that can silently change what a death throws. A part that
	# lands in no chunk vanishes at the moment of the death; a part that lands in
	# two is drawn twice; and a cut that reorders them stacks the body wrong,
	# which shows because each part carries its own outline ring.
	var checked := 0
	for id in UnitRecipes.recipe_ids():
		for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
			var thrown: Array = []
			for cut in UnitArt.fragments_for(id, team):
				for part in cut["pieces"]:
					thrown.append(part["tex"])
			var drawn: Array = []
			for sprite in UnitArt.sprites_for(id, team):
				drawn.append(sprite["tex"])
			assert_eq(thrown, drawn,
				"%s (%d): the chunks are not the drawn body" % [id, int(team)])
			checked += 1
	assert_true(checked >= 38, "only %d bodies were cut" % checked)

## A hat is headwear. #594 added `hat_low` for the Rat King's, and an unmapped hat
## flies on its own while the head it was sitting on goes the other way. #630 made
## the chunk a second question from the slot, so both are asked here.
func test_every_headwear_part_flies_with_the_head_wearing_it() -> void:
	for part in [&"hat", &"hat_low", &"hood", &"helm", &"plume", &"crown"]:
		assert_eq(UnitRecipes.slot_of(part), &"Headwear",
			"'%s' is worn on a head and must be drawn as headwear" % part)
		assert_eq(UnitRecipes.chunk_of(part), &"head",
			"'%s' is worn on a head and must leave with it" % part)

## A part nobody has put in a slot lands in `Extra` rather than silently joining
## the body it was drawn over, and `Extra` is in no chunk, so it flies alone.
func test_an_unknown_part_lands_in_extra_and_is_its_own_chunk() -> void:
	assert_eq(UnitRecipes.slot_of(&"head_round"), &"Head")
	assert_eq(UnitRecipes.slot_of(&"body_skinny"), &"Body")
	assert_eq(UnitRecipes.slot_of(&"hand_wide"), &"HandMain")
	assert_eq(UnitRecipes.slot_of(&"a_part_that_does_not_exist"), &"Extra")
	assert_eq(UnitRecipes.chunk_of(&"a_part_that_does_not_exist"),
		&"a_part_that_does_not_exist",
		"a part in no slot must fly on its own, not join what it was drawn over")

## The chunks one body comes apart into, `[[chunk, [part, ...]], ...]` in draw
## order.
func _chunks(shape_id: StringName) -> Array:
	var out: Array = []
	for entry in UnitRecipes.chunks_for(shape_id):
		var parts: Array = []
		for layer in entry["layers"]:
			parts.append(layer["part"])
		out.append([entry["chunk"], parts])
	return out

## Issue 630's three named cases, written out in full rather than as properties:
## the goblin's head kept its face, the Rat King's head kept its hat, and the
## siege engine came apart again.
func test_the_three_bodies_630_names_come_apart_the_way_the_issue_asks() -> void:
	assert_eq(_chunks(&"goblin"), [
		[&"body", [&"body_skinny"]],
		[&"head", [&"head_round", &"ears_pointed", &"nose_triangle", &"eyes"]],
		[&"hands", [&"hand_off", &"hand"]],
	], "a goblin's head flies bald")
	assert_eq(_chunks(&"rat_king"), [
		[&"body", [&"body_low"]],
		[&"head", [&"head_snouted", &"hat_low", &"eyes_snout"]],
		[&"tail", [&"tail"]],
	], "the Rat King's hat flies alone")
	assert_eq(_chunks(&"siege_engine"), [
		[&"body", [&"body_rotund"]],
		[&"wheels", [&"wheels"]],
		[&"barrel", [&"barrel"]],
	], "the siege engine's wheels and barrel fly as one piece")

## The negative half, and it is the one that matters: the failure mode is a chunk
## quietly joining one it is not attached to, which looks right in any one frame.
## Nothing that was already flying separately may have been merged.
func test_nothing_that_flew_separately_has_been_merged_into_something_else() -> void:
	for id in UnitRecipes.recipe_ids():
		for chunk in _chunks(id):
			var slots := {}
			for part in chunk[1]:
				slots[UnitRecipes.slot_of(part)] = true
			for pair in [
					[&"Body", &"Head"], [&"Body", &"HandMain"], [&"Body", &"HandOff"],
					[&"Head", &"HandMain"], [&"Head", &"HandOff"],
					[&"Body", &"Extra"], [&"Head", &"Extra"],
					[&"HandMain", &"Extra"], [&"HandOff", &"Extra"]]:
				assert_false(slots.has(pair[0]) and slots.has(pair[1]),
					"%s: chunk '%s' holds both a %s part and a %s part" % [
						id, chunk[0], pair[0], pair[1]])

## Every unit in the game has to come apart, or the cue is one the player learns
## to expect and then does not get.
func test_every_recipe_comes_apart_into_at_least_two_chunks() -> void:
	for id in UnitRecipes.recipe_ids():
		for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
			assert_true(UnitArt.fragments_for(id, team).size() >= 2,
				"%s (%d) flies in one piece, which is not coming apart" % [id, int(team)])

# ---------------------------------------------------------------------------
# The toggle, both directions
# ---------------------------------------------------------------------------

func test_the_option_exists_and_ships_on() -> void:
	_reset()
	assert_true(DisplayOptions.enabled(DeathExplosionScript.OPTION),
		"the explosion ships on; the player asked for it, not for a setting")

func _explosion():
	var node = in_tree(Node2D.new())
	node.set_script(DeathExplosionScript)
	node._ready()
	return node

func _fragments() -> Array:
	return UnitArt.fragments_for(&"goblin", CG.Team.ENEMY)

func test_nothing_is_thrown_while_the_option_is_off() -> void:
	_reset()
	var gibs = _explosion()
	DisplayOptions.set_enabled(DeathExplosionScript.OPTION, false)
	gibs.explode(Vector2.ZERO, 30.0, false, _fragments(), 3)
	assert_eq(gibs.live_pieces(), 0, "a body came apart with the option off")

	DisplayOptions.set_enabled(DeathExplosionScript.OPTION, true)
	gibs.explode(Vector2.ZERO, 30.0, false, _fragments(), 3)
	assert_eq(gibs.live_pieces(), _fragments().size(),
		"turning it on must throw every chunk")
	_reset()

# ---------------------------------------------------------------------------
# Issue 528's rule, and this is the fifth effect to have to honour it
# ---------------------------------------------------------------------------

func _positions(gibs) -> Array:
	var out: Array = []
	for slot in gibs._slots:
		for piece in slot["pieces"]:
			out.append(piece["pos"])
	return out

func test_a_frozen_explosion_does_not_move() -> void:
	_reset()
	var gibs = _explosion()
	gibs.explode(Vector2.ZERO, 30.0, false, _fragments(), 3)
	# The frame the death lands on is not frozen yet, and it is the frame that
	# arms the freeze; the chunks must sit exactly where the body stood.
	gibs.advance(1.0 / 60.0)
	var at_rest := _positions(gibs)
	for p: Vector2 in at_rest:
		assert_eq(p, Vector2.ZERO, "a chunk left before the freeze it sets up")

	ViewClock.frozen = true
	for i in 6:
		gibs.advance(1.0 / 60.0)
	assert_eq(_positions(gibs), at_rest, "the chunks moved through the hit stop")

	ViewClock.frozen = false
	gibs.advance(1.0 / 60.0)
	assert_ne(_positions(gibs), at_rest, "and they must fly once the freeze lifts")
	_reset()

## The whole 0.10 s hold is six frames at 60Hz, and every one of them must show
## the body. A chunk that has faded by the time the picture starts again turns
## the freeze back into the hole it used to hold.
func test_a_chunk_outlives_the_hit_stop_it_sets_up() -> void:
	assert_true(DeathExplosionScript.FADE_AFTER > BattleView.HIT_STOP_SECONDS,
		"the chunks start fading before the freeze is even over")
	assert_eq(DeathExplosionScript.alpha_at(0.0), 1.0)
	assert_eq(DeathExplosionScript.alpha_at(DeathExplosionScript.LIFETIME), 0.0,
		"a chunk must be gone at the end of its life, not merely dim")

## The chunk leaves at the body's own colour and darkens as it flies. The first
## half is what makes the frozen frame the body exactly; the second is what
## stops a tumbling goblin head reading as a goblin.
func test_a_chunk_leaves_at_full_colour_and_darkens_in_the_air() -> void:
	assert_eq(DeathExplosionScript.tint_at(0.0), Color.WHITE,
		"the chunks are already dim on the frame the freeze holds")
	# Almost: a Color stores 32-bit channels, so the 0.55 that goes in reads back
	# as 0.55000001192093.
	var flying := DeathExplosionScript.tint_at(DeathExplosionScript.DIM_SECONDS)
	assert_almost_eq(flying.r, DeathExplosionScript.DIM)
	assert_true(flying.r < 1.0, "wreckage must not be the colour a live unit is")
	assert_true(DeathExplosionScript.DIM_SECONDS > 0.0,
		"a chunk that is dim on frame zero is not the body the freeze held")

# ---------------------------------------------------------------------------
# The count, which is the risk
# ---------------------------------------------------------------------------

func test_more_deaths_than_the_pool_recycles_instead_of_growing() -> void:
	_reset()
	var gibs = _explosion()
	for i in DeathExplosionScript.POOL * 3:
		gibs.explode(Vector2.ZERO, 30.0, false, _fragments(), i)
	assert_eq(gibs.live_explosions(), DeathExplosionScript.POOL,
		"the pool must cap the live count")
	assert_eq(gibs._slots.size(), DeathExplosionScript.POOL,
		"no slot may be created after _ready")
	_reset()

func test_clearing_drops_every_chunk() -> void:
	_reset()
	var gibs = _explosion()
	gibs.explode(Vector2.ZERO, 30.0, false, _fragments(), 3)
	gibs.clear()
	assert_eq(gibs.live_pieces(), 0,
		"a restart reuses unit ids; a chunk left running is last fight's body")
	_reset()

# ---------------------------------------------------------------------------
# Through `consume_events`, the real path
# ---------------------------------------------------------------------------

func _make_party() -> Array[PawnData]:
	var cls := ClassDef.new()
	cls.id = &"warrior"
	cls.display_name = "Warrior"
	var pawn := PawnData.new()
	pawn.id = &"test_pawn"
	pawn.display_name = "Test Pawn"
	pawn.pawn_class = cls
	var out: Array[PawnData] = [pawn]
	return out

func _make_encounter() -> RoomData:
	var e := RoomData.new()
	e.enemy_spawns = [{"enemy_id": &"goblin", "position": Vector2(80.0, 0.0)}]
	e.party_spawns = [Vector2(-80.0, 0.0)]
	return e

func _view():
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	var config := RunConfig.new()
	config.seed = 1
	config.party = _make_party()
	view.config = config
	view.state = CombatSim.build(config.party, _make_encounter(), config.seed)
	view.event_cursor = 0
	view._rebuild_units()
	return view

func _kill(view, unit_id: int) -> void:
	var death := CombatEvent.make(CG.EventKind.DEATH, 0)
	death.target_id = unit_id
	view.state.events.append(death)
	view.consume_events()

func test_a_death_event_throws_the_dead_units_own_chunks() -> void:
	_reset()
	var view = _view()
	var goblin: CombatUnit = view.state.units[1]
	_kill(view, goblin.id)
	var want := UnitArt.fragments_for(UnitView.shape_id(goblin), goblin.team)
	assert_true(want.size() >= 2, "the fixture's goblin has nothing to throw")
	assert_eq(view._gibs.live_pieces(), want.size(),
		"the death threw a different number of chunks than the goblin has")
	_reset()

## The chunks are wreckage, so a `_render` that treats them as a body would be
## the failure that matters: a piece with a bar and a name reads as a live unit.
func test_a_thrown_chunk_gets_no_view_of_its_own() -> void:
	_reset()
	var view = _view()
	var before: int = view._unit_views.size()
	_kill(view, view.state.units[1].id)
	assert_eq(view._unit_views.size(), before,
		"an explosion added a unit view; a chunk must never be a unit")
	_reset()

func test_a_death_holds_the_picture_on_the_body_rather_than_on_the_hole() -> void:
	_reset()
	var view = _view()
	_kill(view, view.state.units[1].id)
	assert_true(view._freeze_left > 0.0, "the death must arm the freeze")
	assert_true(view._gibs.live_pieces() > 0,
		"the freeze this death arms would hold an empty floor")
	_reset()
