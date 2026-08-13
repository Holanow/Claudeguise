extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")

## The pattern to copy. Every test file looks like this: extend TestCase, name
## the file test_*.gd, put it in Tests/, and name each test method test_*.
##
## What it asserts is the frozen contract itself. These are the assumptions
## three sessions are building against in parallel without reading each other's
## code, so if one of them stops holding, everyone finds out here rather than
## in a merge.


func test_tick_constants_agree() -> void:
	assert_eq(CG.TICKS_PER_SECOND, 30)
	assert_almost_eq(CG.TICK_SECONDS * CG.TICKS_PER_SECOND, 1.0)
	assert_true(CG.MAX_TICKS > CG.TICKS_PER_SECOND, "a fight must be able to last past one second")


func test_arena_is_centred_on_origin() -> void:
	# Spawn points are authored as raw Vector2 in Encounter, so every session
	# has to agree on where the middle is.
	assert_true(CG.ARENA_HALF_WIDTH > 0.0)
	assert_true(CG.ARENA_HALF_HEIGHT > 0.0)


func test_same_seed_gives_the_same_rolls() -> void:
	# The one property the whole slice rests on. If this breaks, "re-run the
	# same fight" stops meaning anything and no tuning comparison is valid.
	var a := CombatState.new(12345)
	var b := CombatState.new(12345)
	for i in 20:
		assert_eq(a.rng.randi(), b.rng.randi(), "roll %d diverged" % i)


func test_different_seeds_diverge() -> void:
	# The negative case. Without it, an rng wired to a constant seed would pass
	# the test above perfectly.
	var a := CombatState.new(1)
	var b := CombatState.new(2)
	var same := 0
	for i in 20:
		if a.rng.randi() == b.rng.randi():
			same += 1
	assert_true(same < 5, "two different seeds produced %d/20 identical rolls" % same)


func test_seed_survives_a_round_trip_through_text() -> void:
	# The player types this back in to reproduce a fight they want to talk
	# about, so the text has to come back as the same number.
	var config := RunConfig.new()
	config.seed = 0xDEADBEEF
	assert_eq(config.seed_text(), "DEADBEEF")
	assert_eq(RunConfig.parse_seed(config.seed_text()), 0xDEADBEEF)


func test_unit_lookup_refuses_bad_ids() -> void:
	var state := CombatState.new(0)
	assert_eq(state.unit(-1), null)
	assert_eq(state.unit(0), null)


func test_living_filters_by_team_and_death() -> void:
	var state := CombatState.new(0)
	for i in 3:
		var u := CombatUnit.new()
		u.id = i
		u.team = CG.Team.PLAYER if i < 2 else CG.Team.ENEMY
		state.units.append(u)
	assert_eq(state.living(CG.Team.PLAYER).size(), 2)
	assert_eq(state.living(CG.Team.ENEMY).size(), 1)
	state.units[0].alive = false
	assert_eq(state.living(CG.Team.PLAYER).size(), 1)


func test_events_since_gives_only_the_new_ones() -> void:
	var state := CombatState.new(0)
	for i in 5:
		state.emit(CombatEvent.make(CG.EventKind.DAMAGE, i))
	assert_eq(state.events_since(0).size(), 5)
	assert_eq(state.events_since(3).size(), 2)
	assert_eq(state.events_since(5).size(), 0)
	assert_eq(state.events_since(99).size(), 0)


func test_palette_covers_every_damage_type() -> void:
	# A damage type added to CG without a colour would render as the fallback
	# and silently look like a different type on screen.
	var seen := {}
	for d in CG.DamageType.values():
		var c := Palette.damage_color(d)
		assert_false(seen.has(c), "%s reuses a colour" % CG.damage_type_name(d))
		seen[c] = true


func test_every_attribute_has_a_name() -> void:
	for a in CG.Attribute.values():
		assert_ne(CG.attribute_name(a), "?", "attribute %d has no name" % a)


func test_registry_loads_without_duplicate_ids() -> void:
	# Empty today. It stays meaningful the moment content lands, and it is
	# cheap enough to be worth having before that.
	assert_not_null(Registry.all_class_ids())
	assert_not_null(Registry.all_encounter_ids())


func test_intent_factories_set_their_kind() -> void:
	assert_eq(Intent.idle().kind, CG.IntentKind.IDLE)
	assert_eq(Intent.move_to(Vector2(1.0, 2.0)).kind, CG.IntentKind.MOVE_TO)
	assert_eq(Intent.move_to(Vector2(1.0, 2.0)).destination, Vector2(1.0, 2.0))
	var use := Intent.use_action(&"swing", 3)
	assert_eq(use.kind, CG.IntentKind.USE_ACTION)
	assert_eq(use.action_id, &"swing")
	assert_eq(use.target_id, 3)
