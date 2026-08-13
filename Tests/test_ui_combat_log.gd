extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const CombatLogView := preload("res://Scripts/UI/CombatLogView.gd")

## CombatLogView.line_for_event is pure formatting split out of the Control so
## it can be checked without a live RichTextLabel. This is the half of issue 3
## that proves "a hit landed small because it was mitigated" is readable, not
## just "a number changed".

## Issue 29: the log is a side column in landscape and a bottom strip in
## portrait, matching whichever orientation BattleView.compute_layout fit
## the arena against — the same rule (size.x >= size.y), so the reservation
## and what's actually drawn never disagree.
func test_landscape_docks_the_log_to_the_right_edge() -> void:
	var view := CombatLogView.new()
	view._ready()
	view.set_landscape(true)
	assert_eq(view._backdrop.anchor_left, 1.0)
	assert_eq(view._backdrop.anchor_right, 1.0)
	assert_eq(view._backdrop.anchor_top, 0.0)
	assert_eq(view._backdrop.anchor_bottom, 1.0)
	view.free()

func test_portrait_docks_the_log_to_the_bottom_edge() -> void:
	var view := CombatLogView.new()
	view._ready()
	view.set_landscape(false)
	assert_eq(view._backdrop.anchor_top, 1.0)
	assert_eq(view._backdrop.anchor_bottom, 1.0)
	assert_eq(view._backdrop.anchor_left, 0.0)
	assert_eq(view._backdrop.anchor_right, 1.0)
	view.free()

func _make_state() -> CombatState:
	var state := CombatState.new(1)
	var attacker := CombatUnit.new()
	attacker.id = 0
	attacker.team = CG.Team.PLAYER
	attacker.display_name = "Warrior"
	state.units.append(attacker)

	var target := CombatUnit.new()
	target.id = 1
	target.team = CG.Team.ENEMY
	target.display_name = "Rat"
	state.units.append(target)
	return state

## Issue 33: a poison/burn tick and a hazard tick both emit DAMAGE with
## source_id = -1 on purpose (CombatSim.gd) — the source may be dead, and
## attributing the damage to it would be a worse lie than having none.
## "X hits Y" needs an X; neither case fits it and both used to render "?"
## as a unit's name.
func test_a_poison_tick_names_no_source_and_reads_as_suffering() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 3
	e.amount_before_mitigation = 3
	e.damage_type = CG.DamageType.PROFANE
	e.status = CG.Status.POISON
	var line := view.line_for_event(state, e)
	assert_false(line.contains("?"), line)
	assert_true(line.contains("Rat"), line)
	assert_true(line.contains("suffers"), line)
	view.free()

func test_a_burn_tick_also_reads_as_suffering_not_a_hit() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 2
	e.amount_before_mitigation = 2
	e.damage_type = CG.DamageType.FIRE
	e.status = CG.Status.BURN
	var line := view.line_for_event(state, e)
	assert_false(line.contains("?"), line)
	assert_true(line.contains("suffers"), line)
	view.free()

## A hazard tick also carries source_id = -1, but never touches e.status
## (CombatSim._tick_hazards), so it must read differently from a status
## tick even though both currently reach the same code path check —
## "you are standing somewhere bad and could move" is different
## information from "you are afflicted and moving will not help".
func test_a_hazard_tick_names_no_source_and_reads_differently_from_poison() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 5
	e.amount_before_mitigation = 5
	e.damage_type = CG.DamageType.FIRE
	# status left at its default (SHIELD) — matches what _tick_hazards
	# actually emits, never setting it.
	var line := view.line_for_event(state, e)
	assert_false(line.contains("?"), line)
	assert_true(line.contains("Rat"), line)
	assert_false(line.contains("suffers"), "a hazard tick must not read like a status tick: " + line)

	var poison := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	poison.source_id = -1
	poison.target_id = 1
	poison.amount = 5
	poison.amount_before_mitigation = 5
	poison.damage_type = CG.DamageType.FIRE
	poison.status = CG.Status.POISON
	assert_ne(line, view.line_for_event(state, poison), "hazard and poison must not read identically")
	view.free()

## Checked rather than assumed, per the issue's own instruction: MISS is
## always emitted with the acting unit as source (CombatSim.gd:461), never
## -1, so it was never actually exposed to this bug. Pinning that here so a
## future change to who emits MISS doesn't reopen it silently.
func test_miss_always_names_a_real_source() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.MISS, 1)
	e.source_id = 0
	e.target_id = 1
	e.action_id = &"swing"
	var line := view.line_for_event(state, e)
	assert_false(line.contains("?"), line)
	view.free()

func test_damage_line_names_actor_target_and_amount() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = 0
	e.target_id = 1
	e.amount = 7
	e.amount_before_mitigation = 7
	e.damage_type = CG.DamageType.PHYSICAL
	var line := view.line_for_event(state, e)
	assert_true(line.contains("Warrior"), line)
	assert_true(line.contains("Rat"), line)
	assert_true(line.contains("7"), line)
	view.free()

func test_mitigated_hit_shows_the_raw_roll_too() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = 0
	e.target_id = 1
	e.amount = 4
	e.amount_before_mitigation = 10
	var line := view.line_for_event(state, e)
	assert_true(line.contains("4"), line)
	assert_true(line.contains("10"), line)
	view.free()

func test_unmitigated_hit_does_not_mention_a_second_number() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = 0
	e.target_id = 1
	e.amount = 7
	e.amount_before_mitigation = 7
	var line := view.line_for_event(state, e)
	assert_false(line.contains("before mitigation"), line)
	view.free()

func test_death_line_names_the_unit() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DEATH, 3)
	e.target_id = 1
	var line := view.line_for_event(state, e)
	assert_true(line.contains("Rat"), line)
	assert_true(line.contains("dies"), line)
	view.free()

func test_miss_line_names_actor_action_and_target() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.MISS, 1)
	e.source_id = 0
	e.target_id = 1
	e.action_id = &"geyser_scald"
	var line := view.line_for_event(state, e)
	assert_true(line.contains("Warrior"), line)
	assert_true(line.contains("Rat"), line)
	assert_true(line.contains("misses"), line)
	view.free()

## Issue 14's own finding: a miss, a landed hit, and a hit fully absorbed by
## mitigation are three different events and a player must be able to tell
## them apart. Three different sentence shapes, checked pairwise.
func test_miss_reads_differently_from_a_landed_hit_and_a_fully_mitigated_one() -> void:
	var state := _make_state()
	var view := CombatLogView.new()

	var miss := CombatEvent.make(CG.EventKind.MISS, 1)
	miss.source_id = 0
	miss.target_id = 1
	miss.action_id = &"swing"

	var landed := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	landed.source_id = 0
	landed.target_id = 1
	landed.amount = 7
	landed.amount_before_mitigation = 7

	var absorbed := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	absorbed.source_id = 0
	absorbed.target_id = 1
	absorbed.amount = 0
	absorbed.amount_before_mitigation = 12

	var miss_line := view.line_for_event(state, miss)
	var landed_line := view.line_for_event(state, landed)
	var absorbed_line := view.line_for_event(state, absorbed)

	assert_ne(miss_line, landed_line)
	assert_ne(miss_line, absorbed_line)
	assert_ne(landed_line, absorbed_line)
	assert_true(miss_line.contains("misses"))
	assert_false(landed_line.contains("misses"))
	assert_true(absorbed_line.contains("before mitigation"), "a fully absorbed hit must still show the raw roll, not read like a miss")
	view.free()
