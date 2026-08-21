extends "res://Tests/TestCase.gd"

## Does a feature the code contains actually reach the game?


## Enough seeds that a genuinely reachable action shows up, few enough that
## the gate stays quick. An action that needs more than this many attempts
## across every room to fire once is not meaningfully reachable anyway.
const SEEDS := 6

## The five parties the game can build: one card per class, four slots, five
## classes, so every real party is a leave-one-out. Mono-class rosters are not
## reachable, and three issues were once tuned against one.
const CLASSES := ["warrior", "priest", "abomination", "geysermancer", "siege_master"]

# ---------------------------------------------------------------------------
# The core one: an ability no player can reach is not in the game.
# ---------------------------------------------------------------------------

## **Issue 399 WEAKENED this test on purpose, and the weakening is the point of
## the entry.** It used to demand that every starting action FIRES in a real
## fight. A class now ships with no plan rows, so an ally-targeted, zero-power
## or sustained action fires zero times until the player adds a row for it, and
## the old assertion could only be met by putting the rows back. What is left is
## "a player can reach it": fired by the shipped party, or offered by that
## class's preset library. **A library-only action is one nobody who never opens
## the library will ever see**, which is why the partition is printed.
func test_every_starting_action_is_reachable_by_a_player() -> void:
	var fired := _collect_fired_action_ids()
	var library_only: Array[String] = []
	for cid in CLASSES:
		var c := StringName(cid)
		var def := Registry.get_class_def(c)
		for action_id in def.starting_actions:
			if fired.has(action_id):
				continue
			library_only.append("%s/%s" % [cid, action_id])
			assert_true(_preset_offering(c, action_id) != &"",
				("%s lists action '%s'. It never fired in %d real fights AND no preset in its "
				+ "library offers it, so neither the shipped party nor the library reaches it.")
					% [cid, action_id, _fight_count()])
	print("library-only actions (nothing fires these until the player adds a row): ", library_only)

## The preset in `class_id`'s library that uses `action_id`, or `&""`.
func _preset_offering(class_id: StringName, action_id: StringName) -> StringName:
	for plan in PresetPlans.for_class(class_id):
		for block in plan.blocks:
			if block.kind == PlanBlock.Kind.ACTION and block.args.get("action_id", &"") == action_id:
				return plan.id
	return &""

## The negative half: the library is a real path only while the plans in it are
## ones a player can actually pay for and the interpreter can actually run.
func test_a_pawn_that_adds_its_whole_library_can_run_all_of_it() -> void:
	for cid in CLASSES:
		var c := StringName(cid)
		var pawn := PawnFactory.make_preset_pawn(c, c, String(cid))
		assert_true(pawn.plans.size() > 0, "%s's library is empty, so nothing above can be reached from it" % cid)
		assert_eq(PlanInterpreter.active_plan_count(pawn), pawn.plans.size(),
			"a %s that adds every preset cannot pay for them all" % cid)

## A class whose actions all cost resource, in a party that cannot generate
## it, stands still. The player hit this twice -- the Abomination, then the
## Priest and Siege Master -- and both times the class looked complete.
func test_every_starting_pawn_has_an_action_it_can_always_afford() -> void:
	for cid in CLASSES:
		var c := StringName(cid)
		var pawn := PawnFactory.make_starter_pawn(c, c, String(cid))
		var free_actions: Array[StringName] = []
		for action_id in Registry.actions_for_pawn(pawn):
			if Registry.get_action(action_id).resource_cost <= 0:
				free_actions.append(action_id)
		assert_true(free_actions.size() > 0,
			"a starting %s has no action costing zero resource, counting what it is equipped with" % cid)

# ---------------------------------------------------------------------------
# A mechanism nothing invokes is dead code wearing a feature's clothes.
# ---------------------------------------------------------------------------

## Each of these fields gates a whole mechanism. The test is not that the
## field exists -- the parser proves that. It is that some action a real
## fight can reach actually sets it.
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
			"ActionDef.%s is set by no action any class or enemy can use, so nothing in a real fight can reach it." % field)

## A status nothing can inflict is a badge, a glossary entry and a rules
## paragraph describing something that cannot happen.
func test_every_declared_status_can_actually_be_inflicted() -> void:
	var appliable := {}
	for action_id in _reachable_action_ids():
		var a := Registry.get_action(action_id)
		if a.applies_status_enabled:
			appliable[a.applies_status] = action_id

	## Statuses no *action* applies because a **mechanism** does. Each needs a
	## named reason, and the reason has to say what applies it.
	var applied_by_mechanism := {
		CG.Status.TAUNTED: "CombatSim stamps it when a taunt lands; the compulsion reads it, no action sets it",
		CG.Status.SUSTAINING: "CombatSim holds it for the duration of a sustained action",
	}

	for status in CG.Status.values():
		if applied_by_mechanism.has(status):
			continue
		assert_true(appliable.has(status),
			"CG.Status.%s is applied by no action any class or enemy can use. It has a badge and a glossary entry for something that cannot happen."
				% CG.Status.keys()[status])

# ---------------------------------------------------------------------------
# The screen is part of the real path. A thing that fights invisibly is not
# in the game either.

## Catches issue 75 directly, and every future summon with it.
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

## Art nothing calls is art the player never sees.
func test_every_art_module_has_a_caller_in_the_interface() -> void:
	var art_dir := DirAccess.open("res://Scripts/Art")
	assert_true(art_dir != null, "cannot open Scripts/Art")
	if art_dir == null:
		return

	# Scripts/Art as well as Scripts/UI, because reaching the screen through
	# another art module is a real path: UnitArt has no interface caller and is
	# perfectly reachable via Silhouettes, which does. The first version of
	# this test failed it and was wrong -- a crude check is fine, a crude check
	# that cries wolf is not, because the next person deletes it.
	var callers := ""
	var art_files := _gd_files("res://Scripts/Art")
	for path in _gd_files("res://Scripts/UI"):
		callers += _code_only(FileAccess.get_file_as_string(path))
	assert_true(callers.length() > 0, "read no interface source at all")

	for name in art_dir.get_files():
		if not name.ends_with(".gd"):
			continue
		# Comments are stripped before searching, and the needle is a usage
		# `Name.` rather than a bare mention. The first version looked for the
		# bare name and passed `EquipmentIcons` on the strength of one word in a
		# comment. A checker fooled by prose about the thing is worse than none.
		var needle := '%s.' % name.get_basename()
		var seen := callers.contains(needle)
		if not seen:
			# Reaching the screen through another art module is a real path:
			for path in art_files:
				if path.get_file() == name:
					continue
				if _code_only(FileAccess.get_file_as_string(path)).contains(needle):
					seen = true
					break
		assert_true(seen,
			"Scripts/Art/%s is referenced by no interface or art file, so nothing draws it." % name)

func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	return out

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
	# Equipment grants are a real reachability path as of issue 100, and this
	# test did not know it. SHIELDING started failing the status check the
	# moment Directional Block moved off the Warrior class onto plate_mail --
	# reachable through the equip screen the whole time, and reported as
	# impossible. A checker that does not know every route reports working
	# features as broken, which is the cheapest way to get itself deleted.
	for qid in Registry.all_equipment_ids():
		for a in Registry.get_equipment(qid).granted_actions:
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

## Source with whole-line comments removed, so a name mentioned in prose cannot
## be mistaken for a call.
func _code_only(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out += line + "\n"
	return out