extends "res://Tests/TestCase.gd"


## Issue 627, and this file is the transcription check rather than a design
## test. Eight constants across thirteen statuses moved into resources; that is
## thirteen chances to fat-finger a number, and the acceptance measurement will
## say a fight moved without saying which number did it.
##
## **Every expected value below is typed from the pre-627 source, not read back
## from the def.** A test that asks the def what the def says proves nothing.

## The eight `Balance` constants and the four `SimDeps` ones, as they read on
## `origin/main` at 227b2a0. Named here after the constant they replaced so the
## comparison is one line of reading.
const OLD_STATUS_SHIELD_REDUCTION := 0.25
const OLD_STATUS_BLOCK_REDUCTION := 0.25
const OLD_POISON_DAMAGE_PERCENT_PER_TICK := 0.30
const OLD_BURN_FRACTION_OF_HIT_PER_TICK := 0.0056
const OLD_BLEED_DAMAGE_PER_STACK_PER_TICK := 1.0
const OLD_HASTE_TICK_SCALE := 0.7
const OLD_SLOWED_SPEED_SCALE := 0.5
const OLD_MARKED_VULNERABILITY_BONUS := 0.25
const OLD_BLEED_TICK_INTERVAL := 5
const OLD_BLEED_STACK_DECAY_TICKS := 30

## `CG.is_harmful`'s whole list before it read a def.
const OLD_HARMFUL: Array = [
	CG.Status.BLEED, CG.Status.BURN, CG.Status.POISON, CG.Status.STUN,
	CG.Status.MARKED, CG.Status.SLOWED, CG.Status.TAUNTED,
]

## `CombatSim._DOT_STATUSES`, which was a status -> damage type map.
const OLD_DOT: Dictionary = {
	CG.Status.BURN: CG.DamageType.FIRE,
	CG.Status.POISON: CG.DamageType.PROFANE,
	CG.Status.BLEED: CG.DamageType.PHYSICAL,
}

const OLD_STACKING: Array = [CG.Status.BLEED]
const OLD_HIT_SCALED: Array = [CG.Status.BURN]

func _def(s: CG.Status) -> StatusDef:
	var d := StatusLibrary.of(s)
	assert_not_null(d, "no StatusDef for %s" % CG.Status.keys()[s])
	return d

## Every enum member has exactly one file, and no file claims a member twice.
## Without this the checks below could all pass on a set with a hole in it.
func test_every_status_has_exactly_one_def() -> void:
	assert_eq(StatusLibrary.PATHS.size(), CG.Status.size(),
		"one .tres per CG.Status member, no more and no fewer")
	var seen: Dictionary = {}
	for path in StatusLibrary.PATHS:
		var d: StatusDef = load(path)
		assert_not_null(d, path + " did not load")
		assert_false(seen.has(d.status),
			"%s and %s both claim %s" % [seen.get(d.status, ""), path, CG.Status.keys()[d.status]])
		seen[d.status] = path
	for s in CG.Status.values():
		assert_true(seen.has(s), "no .tres for %s" % CG.Status.keys()[s])

## The `.tres` stores the enum as a bare integer, so a fat-fingered digit
## silently repoints a whole file and nothing else in the suite would see it.
## The filename is the only human-readable half, so it is what gets checked.
func test_each_file_describes_the_status_its_name_claims() -> void:
	for path in StatusLibrary.PATHS:
		var d: StatusDef = load(path)
		var want := String(path.get_file().get_basename()).to_upper()
		assert_eq(String(CG.Status.keys()[d.status]), want,
			"%s carries status = %d, which is %s" % [path, d.status, CG.Status.keys()[d.status]])

func test_the_damage_reduction_numbers_match_the_constants_they_replaced() -> void:
	assert_eq(_def(CG.Status.SHIELD).damage_reduction, OLD_STATUS_SHIELD_REDUCTION)
	assert_eq(_def(CG.Status.BLOCK).damage_reduction, OLD_STATUS_BLOCK_REDUCTION)
	assert_eq(_def(CG.Status.MARKED).vulnerability, OLD_MARKED_VULNERABILITY_BONUS)

func test_the_damage_over_time_numbers_match_the_constants_they_replaced() -> void:
	assert_eq(_def(CG.Status.POISON).damage_percent_of_max_hp_per_tick, OLD_POISON_DAMAGE_PERCENT_PER_TICK)
	assert_eq(_def(CG.Status.BURN).damage_per_magnitude_per_tick, OLD_BURN_FRACTION_OF_HIT_PER_TICK)
	assert_eq(_def(CG.Status.BLEED).damage_per_magnitude_per_tick, OLD_BLEED_DAMAGE_PER_STACK_PER_TICK)
	assert_eq(_def(CG.Status.BLEED).tick_interval, OLD_BLEED_TICK_INTERVAL)
	assert_eq(_def(CG.Status.BLEED).stack_decay_ticks, OLD_BLEED_STACK_DECAY_TICKS)

func test_the_scale_numbers_match_the_constants_they_replaced() -> void:
	assert_eq(_def(CG.Status.HASTE).tick_scale, OLD_HASTE_TICK_SCALE)
	assert_eq(_def(CG.Status.SLOWED).speed_scale, OLD_SLOWED_SPEED_SCALE)

## The other side of the same check: a number typed onto a status that never had
## one is as wrong as a mistyped digit, and no fight would necessarily show it.
## Every field defaults to what "this status does not do that" used to mean.
func test_no_status_gained_a_number_it_never_had() -> void:
	for d in StatusLibrary.all():
		var name := String(CG.Status.keys()[d.status])
		if d.status != CG.Status.SHIELD and d.status != CG.Status.BLOCK:
			assert_eq(d.damage_reduction, 0.0, name + " reduced no damage before 627")
		if d.status != CG.Status.MARKED:
			assert_eq(d.vulnerability, 0.0, name + " added no vulnerability before 627")
		if d.status != CG.Status.HASTE:
			assert_eq(d.tick_scale, 1.0, name + " did not scale ticks before 627")
		if d.status != CG.Status.SLOWED:
			assert_eq(d.speed_scale, 1.0, name + " did not scale move speed before 627")
		if d.status != CG.Status.BLEED:
			assert_eq(d.tick_interval, 1, name + " ticked every tick before 627")
			assert_eq(d.stack_decay_ticks, 0, name + " did not decay by stacks before 627")

func test_harmful_matches_the_list_is_harmful_used_to_hold() -> void:
	for d in StatusLibrary.all():
		var name := String(CG.Status.keys()[d.status])
		assert_eq(d.harmful, OLD_HARMFUL.has(d.status), name + " changed side")
		assert_eq(CG.is_harmful(d.status), OLD_HARMFUL.has(d.status),
			"CG.is_harmful disagrees with the def for " + name)

func test_the_stacking_and_hit_scaled_rules_match_the_dictionaries_they_replaced() -> void:
	for d in StatusLibrary.all():
		var name := String(CG.Status.keys()[d.status])
		assert_eq(d.stacks, OLD_STACKING.has(d.status), name + "'s stacking rule moved")
		assert_eq(d.hit_scaled, OLD_HIT_SCALED.has(d.status), name + "'s hit-scaled rule moved")

func test_the_damage_over_time_set_and_its_types_match_what_combatsim_held() -> void:
	for d in StatusLibrary.all():
		var name := String(CG.Status.keys()[d.status])
		assert_eq(d.deals_damage_over_time, OLD_DOT.has(d.status), name + " joined or left the DOT set")
		if OLD_DOT.has(d.status):
			assert_eq(d.dot_damage_type, OLD_DOT[d.status], name + "'s damage type moved")

## `CombatSim._DOT_ORDER` is a hand-written list, because the order two
## afflictions tick in decides which draws the fight's RNG first and reordering
## it moves every fight. A hand-written list can fall out of step with the defs,
## so this holds the two together in both directions.
func test_the_dot_order_holds_exactly_the_statuses_whose_def_says_so() -> void:
	assert_eq(CombatSim._DOT_ORDER, [CG.Status.BURN, CG.Status.POISON, CG.Status.BLEED],
		"the tick order is load-bearing: changing it moves every fight")
	for status in CombatSim._DOT_ORDER:
		assert_true(StatusLibrary.of(status).deals_damage_over_time,
			"%s is ticked for damage but its def says it deals none" % CG.Status.keys()[status])
	for d in StatusLibrary.all():
		if d.deals_damage_over_time:
			assert_true(CombatSim._DOT_ORDER.has(d.status),
				"%s says it deals damage over time and nothing ever ticks it" % CG.Status.keys()[d.status])

## The icon used to be derived from the enum name. It is authored now, so the
## derivation is the assertion: all thirteen must still resolve to the file the
## art in `Assets/UI/status/` is actually named.
func test_every_icon_name_is_still_the_lower_cased_enum_name() -> void:
	for d in StatusLibrary.all():
		var want := StringName("status/%s" % String(CG.Status.keys()[d.status]).to_lower())
		assert_eq(d.icon_name, want, "icon for " + String(CG.Status.keys()[d.status]))
		assert_eq(StatusIcons.art_name(d.status), want, "StatusIcons disagrees with the def")

## The trap the issue names: a write to a getter-only property in GDScript
## silently does nothing, so a suite gets defaults and passes. Every StatusDef
## field is a plain `@export var`, and this proves one of them takes a write.
func test_a_statusdef_field_can_actually_be_written() -> void:
	var d := StatusDef.new()
	d.damage_reduction = 0.42
	assert_eq(d.damage_reduction, 0.42, "a StatusDef field silently refused a write")
