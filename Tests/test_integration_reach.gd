extends "res://Tests/TestCase.gd"

## Does a feature the code contains actually reach the game?
##
## MANAGER-OWNED.
##
## **Every other test file in this repository passed all nine times we shipped
## something the player could not reach.** `EquipmentDef`, the wrong-room
## encounter, treasure drops, the unreachable floor, uncalled resource
## recovery, two class abilities, the projectile visuals, hover on the Inspect
## screen, and a summoned unit that never gets drawn. Nine. Each one was
## built, tested, reviewed and merged, and each one looked finished from the
## inside because the tests covering it called it directly.
##
## `test_ui_battle_view.gd` says the quiet part in its own header: it builds a
## `CombatState` by hand and bypasses `begin()`. That is a reasonable unit
## test and it is precisely why it could never have caught any of this. A test
## that constructs the thing it is testing has assumed away the only question
## that matters, which is whether anything constructs it in the real game.
##
## So the rule for this file, and it is the whole point of it:
##
##   **Never build the fixture. Drive the real path and watch what happens.**
##
## A test here starts from something the player actually does -- pick a party,
## start a fight -- and asserts on observable output. If a test in this file
## needs to reach inside and set something up, it belongs in one of the other
## files instead.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")

## Enough seeds that a genuinely reachable action shows up, few enough that
## the gate stays quick. An action that needs more than this many attempts
## across every room to fire once is not meaningfully reachable anyway.
const SEEDS := 6

## The five parties the game can build: one card per class, four slots, five
## classes, so every real party is a leave-one-out. Mono-class rosters are not
## reachable, and three issues were once tuned against one.
const CLASSES := ["warrior", "priest", "abomination", "geysermancer", "siege_master"]

# ---------------------------------------------------------------------------
# The core one: an ability that exists but never fires is not in the game.
# ---------------------------------------------------------------------------

## Catches the failure that hit twice: the Warrior's block and the
## Abomination's hook existed as mechanisms in the simulation, fully tested,
## while no action set the field and no plan ever chose one. The unit tests
## for the mechanisms passed the whole time, because they called the mechanism.
func test_every_starting_action_fires_in_a_real_fight() -> void:
	var fired := _collect_fired_action_ids()
	for cid in CLASSES:
		var def := Registry.get_class_def(StringName(cid))
		for action_id in def.starting_actions:
			assert_true(fired.has(action_id),
				"%s lists action '%s' and it never fired in %d real fights. It is in the game's data and not in the game."
					% [cid, action_id, _fight_count()])

## A class whose actions all cost resource, in a party that cannot generate
## it, stands still. The player hit this twice -- the Abomination, then the
## Priest and Siege Master -- and both times the class looked complete.
func test_every_class_has_an_action_it_can_always_afford() -> void:
	for cid in CLASSES:
		var def := Registry.get_class_def(StringName(cid))
		var free_actions: Array[StringName] = []
		for action_id in def.starting_actions:
			if Registry.get_action(action_id).resource_cost <= 0:
				free_actions.append(action_id)
		assert_true(free_actions.size() > 0,
			"%s has no action costing zero resource. A pawn that cannot afford anything stands still." % cid)

# ---------------------------------------------------------------------------
# A mechanism nothing invokes is dead code wearing a feature's clothes.
# ---------------------------------------------------------------------------

## Each of these fields gates a whole mechanism that somebody built, tested
## and merged. The test is not that the field exists -- the parser proves
## that. It is that some action a real fight can reach actually sets it.
func test_every_action_mechanism_is_reachable_from_some_class_or_enemy() -> void:
	var reachable := _reachable_action_ids()

	var gated := {
		"summons_unit_id": func(a): return a.summons_unit_id != &"",
		"pull_distance": func(a): return a.pull_distance > 0.0,
		"cleanses_harmful": func(a): return a.cleanses_harmful,
		"taunt_radius": func(a): return a.taunt_radius > 0.0,
		"projectile_speed": func(a): return a.projectile_speed > 0.0,
	}

	for field in gated:
		var users: Array[StringName] = []
		for action_id in reachable:
			if gated[field].call(Registry.get_action(action_id)):
				users.append(action_id)
		assert_true(users.size() > 0,
			"ActionDef.%s is set by no action any class or enemy can use. The mechanism is built and unreachable." % field)

# ---------------------------------------------------------------------------
# The screen is part of the real path. A thing that fights invisibly is not
# in the game either.
# ---------------------------------------------------------------------------

## Catches issue 75 directly, and every future summon with it.
##
## `BattleView` built its unit views once, at fight start, from the unit list
## as it stood at that instant. A siege engine summoned thirty seconds in
## fought, dealt damage, took damage and died without ever being drawn. The
## player reported it three times. I "fixed" it twice by confirming the
## silhouette existed in the registry, which is exactly the mistake this whole
## file exists to stop: I checked the artefact instead of the screen.
## Whatever a real fight can put on the field must have something to draw.
##
## A summoned unit appears in no encounter, so a check that walks encounters
## cannot see it -- that is how the siege engine reached the player with no
## silhouette at all. This walks the units a fight actually produced.
##
## The other half of issue 75, that `BattleView` never gives a mid-fight
## summon a view node to draw *into*, is wren's to fix and to test: it needs a
## live scene tree, which this file deliberately does not build.
func test_every_unit_a_real_fight_produces_has_art_to_draw() -> void:
	var state := _run_fight(_party_without("warrior"), &"floor1_room1", 0)
	assert_true(state.units.size() > 0, "fixture produced no units at all")
	for u in state.units:
		var shape := _shape_id_of(u)
		assert_true(Silhouettes.has_shape(shape),
			"unit '%s' reached a real fight with no silhouette for shape '%s'; it would draw the unknown-shape fallback."
				% [u.display_name, shape])

## Proves the fixture above is actually exercising summons rather than
## passing because nothing was ever summoned. A test that cannot fail is
## worse than no test, and this file exists because of tests that could not.
func test_the_summon_path_is_live_in_a_real_fight() -> void:
	var summoning: Array[StringName] = []
	for action_id in _reachable_action_ids():
		if Registry.get_action(action_id).summons_unit_id != &"":
			summoning.append(action_id)
	assert_true(summoning.size() > 0, "no reachable action summons anything")

	var fired := _collect_fired_action_ids()
	var any := false
	for action_id in summoning:
		if fired.has(action_id):
			any = true
	assert_true(any,
		"no summoning action fired in %d real fights, so nothing above actually checks a summoned unit." % _fight_count())

# ---------------------------------------------------------------------------
# helpers -- these drive the real path, they do not stand in for it
# ---------------------------------------------------------------------------

## Mirrors `UnitView._shape_id` exactly: a pawn draws its class, an enemy
## draws its enemy id. Duplicated rather than called because UnitView is a
## Node2D that wants a tree. If that rule ever changes in one place and not
## the other, this test goes quietly wrong -- so it is worth moving onto
## CombatUnit the next time anything touches it.
func _shape_id_of(u) -> StringName:
	if u.pawn != null and u.pawn.pawn_class != null:
		return u.pawn.pawn_class.id
	return u.enemy_id

func _party_without(left_out: String) -> Array:
	var ids: Array = []
	for c in CLASSES:
		if c != left_out:
			ids.append(c)
	return ids

func _fight_count() -> int:
	return CLASSES.size() * Registry.all_encounter_ids().size() * SEEDS

## Every action any class starts with, plus every action any enemy can use.
## "Reachable" means a real fight can produce it, which is the only sense of
## the word that has ever mattered here.
func _reachable_action_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for cid in Registry.all_class_ids():
		for a in Registry.get_class_def(cid).starting_actions:
			if not out.has(a):
				out.append(a)
	for eid in Registry.all_enemy_ids():
		var e := Registry.get_enemy(eid)
		for a in e.actions:
			if not out.has(a):
				out.append(a)
		# A summoned unit's own actions are reachable through the summon, and
		# appear in no encounter.
		for a in out.duplicate():
			var summoned := Registry.get_action(a).summons_unit_id
			if summoned != &"":
				for sa in Registry.get_enemy(summoned).actions:
					if not out.has(sa):
						out.append(sa)
	return out

## Runs every buildable party through every room, several seeds each, and
## returns the set of action ids that actually fired.
func _collect_fired_action_ids() -> Dictionary:
	var fired := {}
	for cid in CLASSES:
		var party := _party_without_only(cid)
		for enc_id in Registry.all_encounter_ids():
			for s in range(SEEDS):
				var state := _run_fight(party, enc_id, s)
				for e in state.events:
					if e.kind == CG.EventKind.ACTION_FIRE:
						fired[e.action_id] = true
	return fired

## The party that *contains* the named class, which is every party except the
## one that leaves it out. Uses the leave-one-out party that omits a different
## class, so the named class is present.
func _party_without_only(must_include: String) -> Array:
	for c in CLASSES:
		if c != must_include:
			return _party_without(c)
	return _party_without("warrior")

func _initial_unit_count(enc_id: StringName, party_size: int) -> int:
	return party_size + Registry.get_encounter(enc_id).spawns.size()

func _run_fight(ids: Array, enc_id: StringName, s: int) -> CombatState:
	var party: Array[PawnData] = []
	for cid in ids:
		var c := StringName(cid)
		party.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, party.size()]), Registry.get_class_def(c).display_name
		))
	var state := CombatSim.build(party, Registry.get_encounter(enc_id), s)
	CombatSim.run(state)
	return state
