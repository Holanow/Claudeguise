extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const CombatLogView := preload("res://Scripts/UI/CombatLogView.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")

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

## Issue 33 fixed the "?" (source_id = -1 on a poison/burn tick, same as a
## hazard tick, per CombatSim.gd — the source may be dead, and attributing
## the damage to it would be a worse lie than having none). Issue 24: that
## made the line readable and did not make it usable — a real fight put
## twelve of these one-per-tick lines in a ~20-line visible log, burying the
## two events a player actually wants ("X dies", "Y hits Z for N"). Per
## rook's own framing, this is presentation, not the event stream: dropped
## from the log entirely rather than coalesced or summarised, because the
## affliction is already visible without it — STATUS_APPLIED/STATUS_EXPIRED
## still log once each ("Rat is afflicted with Poison" / "...fades"), and
## every DAMAGE event still spawns a floating number on the unit regardless
## of what the log shows (BattleView.consume_events spawns a floater from
## the event itself, not from the log line). CombatSim's own stream is
## unchanged; only what this file chooses to print from it moved.
func test_a_poison_tick_is_dropped_from_the_log() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 3
	e.amount_before_mitigation = 3
	e.damage_type = CG.DamageType.PROFANE
	e.status = CG.Status.POISON
	assert_eq(view.line_for_event(state, e), "", "a per-tick poison line is texture, not story")
	view.free()

func test_a_burn_tick_is_dropped_from_the_log_too() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 2
	e.amount_before_mitigation = 2
	e.damage_type = CG.DamageType.FIRE
	e.status = CG.Status.BURN
	assert_eq(view.line_for_event(state, e), "")
	view.free()

## Acceptance criterion 2: an affliction must still be visible in the log
## somewhere even with the per-tick line gone — the moment it starts and the
## moment it ends, not the ticks in between.
func test_status_applied_and_expired_still_log_for_poison_and_burn() -> void:
	var state := _make_state()
	var view := CombatLogView.new()

	var applied := CombatEvent.make(CG.EventKind.STATUS_APPLIED, 1)
	applied.target_id = 1
	applied.status = CG.Status.POISON
	var applied_line := view.line_for_event(state, applied)
	assert_true(applied_line.contains("Rat"), applied_line)
	assert_true(applied_line.to_lower().contains("poison"), applied_line)

	var expired := CombatEvent.make(CG.EventKind.STATUS_EXPIRED, 1)
	expired.target_id = 1
	expired.status = CG.Status.BURN
	var expired_line := view.line_for_event(state, expired)
	assert_true(expired_line.contains("Rat"), expired_line)
	assert_true(expired_line.to_lower().contains("burn"), expired_line)
	view.free()

## append_event must actually skip an empty formatted line rather than
## appending a blank one — a dropped line should leave no trace at all, not
## an empty row a reader has to scroll past.
func test_append_event_does_not_append_a_dropped_line() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	view._ready()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 3
	e.amount_before_mitigation = 3
	e.status = CG.Status.POISON
	view.append_event(state, e)
	assert_eq(view._label.text, "")
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

# ---------------------------------------------------------------------------
# PLAYTEST-NOTES-2 item 6: a beneficial status must not read as an
# affliction.
# ---------------------------------------------------------------------------

func test_a_beneficial_status_gains_rather_than_afflicts() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.STATUS_APPLIED, 1)
	e.target_id = 0
	e.status = CG.Status.SHIELD
	var line := view.line_for_event(state, e)
	assert_true(line.contains("gains"), line)
	assert_false(line.to_lower().contains("afflict"), line)

func test_a_beneficial_status_ends_rather_than_fades() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.STATUS_EXPIRED, 1)
	e.target_id = 0
	e.status = CG.Status.HASTE
	var line := view.line_for_event(state, e)
	assert_true(line.contains("ends"), line)
	assert_false(line.contains("fades"), line)

func test_a_harmful_status_still_reads_as_an_affliction() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var applied := CombatEvent.make(CG.EventKind.STATUS_APPLIED, 1)
	applied.target_id = 1
	applied.status = CG.Status.MARKED
	assert_true(view.line_for_event(state, applied).contains("afflicted"))

	var expired := CombatEvent.make(CG.EventKind.STATUS_EXPIRED, 1)
	expired.target_id = 1
	expired.status = CG.Status.MARKED
	assert_true(view.line_for_event(state, expired).contains("fades"))

# ---------------------------------------------------------------------------
# Issue 74: a non-damaging action must not read as a zero-damage hit.
# ---------------------------------------------------------------------------

func test_a_non_damaging_action_is_dropped_from_the_log() -> void:
	# The exact shape a summon/buff's own DAMAGE event carries: power_scale
	# 0 means both amount and amount_before_mitigation are 0, not just the
	# final amount -- that is what tells it apart from a real attack fully
	# absorbed by armor, which still has to show (see the mitigation test
	# above/below).
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = 0
	e.target_id = 0
	e.amount = 0
	e.amount_before_mitigation = 0
	e.damage_type = CG.DamageType.PHYSICAL
	assert_eq(view.line_for_event(state, e), "", "a summon/buff's own zero-power resolution must not read as a hit")
	view.free()

func test_a_fully_mitigated_real_attack_still_shows_the_raw_roll() -> void:
	# Regression guard for the fix above: the suppression must key on both
	# amount and amount_before_mitigation being 0, not on amount alone --
	# a real attack (amount_before_mitigation > 0) reduced to 0 by
	# mitigation is genuinely different information and issue 14 already
	# requires it to read differently from a miss.
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = 0
	e.target_id = 1
	e.amount = 0
	e.amount_before_mitigation = 12
	var line := view.line_for_event(state, e)
	assert_false(line.is_empty(), "a fully-mitigated real attack must still be visible")
	assert_true(line.contains("before mitigation"), line)
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

# ---------------------------------------------------------------------------
# Issue 202: BLEED was logged as terrain damage, in rooms with no terrain.
# ---------------------------------------------------------------------------

## The defect, reproduced: the ground line was reached by elimination -- "not
## BURN and not POISON" -- so BLEED, which joined `_DOT_STATUSES` long after
## that branch was written, printed "Geysermancer takes 2 Physical damage from
## the ground" in the Rat King's nest, which has no terrain at all. Bleed is the
## King's signature mechanic and the log credited the floor.
func test_a_bleed_tick_is_dropped_from_the_log() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 2
	e.amount_before_mitigation = 2
	e.damage_type = CG.DamageType.PHYSICAL
	e.status = CG.Status.BLEED
	var line := view.line_for_event(state, e)
	assert_false(line.contains("ground"), "bleed is not terrain: " + line)
	assert_eq(line, "", "a per-tick bleed line is texture, not story")
	view.free()

## The guard, so the next damage-over-time status does not repeat this. The
## branch is now written the other way round -- a hazard tick is the one that
## leaves `status` at its unset default, and everything else with no source is
## an affliction -- and this walks CombatSim's own `_DOT_STATUSES` rather than a
## list typed here, so a status added there fails this without anyone editing a
## test. `_DOT_STATUSES` is the same dictionary `_tick_dot_statuses` iterates,
## so the two cannot disagree.
func test_no_damage_over_time_status_is_ever_credited_to_the_ground() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	assert_false(CombatSim._DOT_STATUSES.is_empty(), "the walk must have something to walk")
	for status in CombatSim._DOT_STATUSES:
		var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
		e.source_id = -1
		e.target_id = 1
		e.amount = 2
		e.amount_before_mitigation = 2
		e.damage_type = CombatSim._DOT_STATUSES[status]
		e.status = status
		var line := view.line_for_event(state, e)
		assert_eq(line, "", "%s ticked into the log as: %s" % [CG.Status.keys()[status], line])
	view.free()

## The negative half: the ground line must still exist for a real hazard, or the
## fix above would be "suppress everything with no source", which loses the one
## thing standing in a fire is meant to tell you.
func test_a_real_hazard_tick_still_says_the_ground() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.DAMAGE, 1)
	e.source_id = -1
	e.target_id = 1
	e.amount = 5
	e.amount_before_mitigation = 5
	e.damage_type = CG.DamageType.FIRE
	# status untouched, exactly as CombatSim._tick_hazards emits it.
	var line := view.line_for_event(state, e)
	assert_true(line.contains("ground"), line)
	assert_true(line.contains("Rat"), line)
	view.free()
