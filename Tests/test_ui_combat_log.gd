extends "res://Tests/TestCase.gd"

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const CombatLogView := preload("res://Scripts/UI/CombatLogView.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")

## CombatLogView.line_for_event is pure formatting split out of the Control so
## it can be checked without a live RichTextLabel. This is the half of issue 3
## that proves "a hit landed small because it was mitigated" is readable, not
## just "a number changed".

## Issue 29: the log is on the right in landscape and along the bottom in
## portrait, matching whichever orientation BattleView.compute_layout fit
## the arena against — the same rule (size.x >= size.y), so the reservation
## and what's actually drawn never disagree.
##
## **`anchor_top` was 0.0 here and is 1.0 now, and that is the assertion this
## test was written to make rather than an incidental one.** It said the log runs
## the full height of the right-hand column, which was true from issue 29 until
## PLAYTEST-NOTES-2 item 8 — *"the log is too large, move it to a bottom corner"*
## — landed. Changed rather than deleted: which edges the log is docked to is
## still exactly what belongs here, and the corner is two edges instead of three.
func test_landscape_docks_the_log_to_the_bottom_right_corner() -> void:
	var view := CombatLogView.new()
	view._ready()
	view.set_landscape(true)
	assert_eq(view._backdrop.anchor_left, 1.0)
	assert_eq(view._backdrop.anchor_right, 1.0)
	assert_eq(view._backdrop.anchor_top, 1.0)
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

# ---------------------------------------------------------------------------
# Issue 151: the guard, and then the five kinds that were rendering nothing.
# ---------------------------------------------------------------------------

## THE POINT OF ISSUE 151. `line_for_event` is a `match` with `return ""`
## underneath, so a kind appended to `CG.EventKind` renders nothing in real
## fights with the gate green throughout. It happened five times to three
## people. A status cannot be added invisibly -- three gate tests refuse one
## with no glyph and no glossary entry -- and there was no equivalent for the
## other enum.
##
## Walked from the real enum, not from a list typed here, so appending a kind
## fails this test rather than shipping silent. A kind that is meant to be
## silent goes in `CombatLogView.SILENT_KINDS` and says so out loud.
##
## The event this builds is deliberately generic: a real source, a real target,
## a real action, an amount. A kind that needs something more specific than that
## to produce a line is a kind whose line is fragile.
func test_every_event_kind_speaks_or_is_named_silent() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var kinds: Array = CG.EventKind.values()
	assert_true(kinds.size() > 10, "the walk must have something to walk")
	for kind in kinds:
		var e := CombatEvent.make(kind, 1)
		e.source_id = 0
		e.target_id = 1
		e.action_id = &"warrior_strike"
		e.amount = 6
		e.amount_before_mitigation = 6
		var line: String = view.line_for_event(state, e)
		var name: String = CG.EventKind.keys()[kind]
		if CombatLogView.SILENT_KINDS.has(kind):
			assert_eq(line, "", "%s is on SILENT_KINDS but produced: %s" % [name, line])
		else:
			assert_ne(line, "", "CG.EventKind.%s renders nothing. Give it a line in CombatLogView.line_for_event, or put it on SILENT_KINDS and say why." % name)
	view.free()

## The negative half of the guard: it must be able to fail. A test that walks an
## enum and finds every entry handled looks identical whether the check works or
## is inert, so this proves the branch that fires. A kind not on SILENT_KINDS
## and not in the match is exactly the defect, and RESOURCE_SPENT is the only
## kind in the game that renders empty on purpose.
func test_the_guard_would_catch_a_silent_kind() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.RESOURCE_SPENT, 1)
	e.source_id = 0
	e.target_id = 1
	assert_eq(view.line_for_event(state, e), "", "RESOURCE_SPENT is the silent one")
	assert_true(CombatLogView.SILENT_KINDS.has(CG.EventKind.RESOURCE_SPENT),
		"the only kind that renders empty must be the one the list names, or the guard above passes for the wrong reason")
	assert_eq(CombatLogView.SILENT_KINDS.size(), 1,
		"a second deliberate silence needs its own reasoning in the list, not a quiet append")
	view.free()

## #99: the block was in the event stream for weeks and a player could not see
## one. `target_id` is the BLOCKER, `source_id` the shooter.
func test_a_block_names_the_guard_and_the_shot_it_took() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.BLOCKED, 1)
	e.source_id = 1
	e.target_id = 0
	e.action_id = &"goblin_arrow"
	var line := view.line_for_event(state, e)
	assert_true(line.contains("Warrior"), line)
	assert_true(line.contains("Rat"), line)
	assert_true(line.to_lower().contains("block"), line)
	view.free()

## #61: a channel's middle was visible as a badge and its two ends were not.
## SUSTAIN_END carries the held duration in `amount`, and it is the one thing
## about a channel that is unrecoverable from the stream any other way.
func test_a_channel_logs_both_ends_and_says_how_long_it_was_held() -> void:
	var state := _make_state()
	var view := CombatLogView.new()

	var started := CombatEvent.make(CG.EventKind.SUSTAIN_START, 1)
	started.source_id = 0
	started.target_id = -1
	started.action_id = &"warrior_strike"
	var start_line := view.line_for_event(state, started)
	assert_true(start_line.contains("Warrior"), start_line)

	var ended := CombatEvent.make(CG.EventKind.SUSTAIN_END, 40)
	ended.source_id = 0
	ended.target_id = -1
	ended.action_id = &"warrior_strike"
	ended.amount = 30
	var end_line := view.line_for_event(state, ended)
	assert_true(end_line.contains("Warrior"), end_line)
	assert_true(end_line.contains("2.0s"), "30 ticks at 15/s is 2.0s: " + end_line)
	assert_ne(start_line, end_line, "the two ends of a channel must not read alike")
	view.free()

## #121: the Brute cancels a cast in silence today. `source_id` is the unit that
## LOST the action, not the interrupter -- the same subject ACTION_START used
## for "X begins Y" -- and `amount` is the wind-up thrown away with no refund.
func test_an_interrupt_names_the_pawn_the_action_and_what_it_cost() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.INTERRUPTED, 12)
	e.source_id = 0
	e.target_id = -1
	e.action_id = &"warrior_strike"
	e.amount = 15
	var line := view.line_for_event(state, e)
	assert_true(line.contains("Warrior"), line)
	assert_true(line.to_lower().contains("interrupt"), line)
	assert_true(line.contains("1.0s"), "15 ticks at 15/s is 1.0s of wind-up lost: " + line)
	view.free()

## #193: `target_id` is the NEW unit, not a foe, so the line can name what
## arrived. Without it a rat appears on screen and nothing says where from.
func test_a_summon_names_the_summoner_and_the_unit_that_arrived() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.SUMMONED, 1)
	e.source_id = 0
	e.target_id = 1
	e.action_id = &"warrior_strike"
	var line := view.line_for_event(state, e)
	assert_true(line.contains("Warrior"), line)
	assert_true(line.contains("Rat"), line)
	view.free()

# ---------------------------------------------------------------------------
# Issue 186: a consumed burn, a cleansed one and one that simply ran out were
# three different events printing one sentence.
# ---------------------------------------------------------------------------

## The defect. `CombatSim._consume_status` carries the caster and the consuming
## action on its STATUS_EXPIRED for exactly this reason -- its own comment calls
## that pair "the only thing separating 'Blast ate the burn' from 'the burn ran
## out'" -- and the log read neither field.
func test_a_consumed_burn_reads_differently_from_one_that_ran_out() -> void:
	var state := _make_state()
	var view := CombatLogView.new()

	var ran_out := CombatEvent.make(CG.EventKind.STATUS_EXPIRED, 40)
	ran_out.source_id = -1
	ran_out.target_id = 1
	ran_out.status = CG.Status.BURN

	var eaten := CombatEvent.make(CG.EventKind.STATUS_EXPIRED, 40)
	eaten.source_id = 0
	eaten.target_id = 1
	eaten.action_id = &"geyser_blast"
	eaten.status = CG.Status.BURN

	var ran_out_line := view.line_for_event(state, ran_out)
	var eaten_line := view.line_for_event(state, eaten)
	assert_ne(ran_out_line, eaten_line, "the log cannot tell the player Blast did it")
	assert_true(ran_out_line.contains("fades"), ran_out_line)
	assert_true(eaten_line.contains("Warrior"), "the consumer must be named: " + eaten_line)
	assert_true(eaten_line.to_lower().contains("consume"), eaten_line)
	view.free()

## The real action, not a synthetic id: `geyser_blast` is the one that eats a
## burn, and the branch keys off `ActionDef.consumes_status`, so a fixture id
## would prove the formatting and not the lookup.
func test_the_real_blast_is_recognised_as_a_consume() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var blast = Registry.get_action(&"geyser_blast")
	assert_true(blast != null, "geyser_blast is missing from the registry")
	assert_true(blast.consumes_status_enabled, "geyser_blast no longer consumes anything; this test is measuring nothing")

	var e := CombatEvent.make(CG.EventKind.STATUS_EXPIRED, 40)
	e.source_id = 0
	e.target_id = 1
	e.action_id = &"geyser_blast"
	e.status = blast.consumes_status
	var line := view.line_for_event(state, e)
	assert_true(line.to_lower().contains("consume"), line)
	assert_true(line.contains(blast.display_name), line)
	view.free()

## A cleanse also carries a caster and an action, so it must not be mistaken for
## a consume. The two are told apart by asking the ActionDef what it eats.
func test_a_cleanse_lifts_rather_than_consumes() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.STATUS_EXPIRED, 40)
	e.source_id = 0
	e.target_id = 1
	e.action_id = &"priest_cleanse"
	e.status = CG.Status.POISON
	var line := view.line_for_event(state, e)
	assert_false(line.to_lower().contains("consume"), "a cleanse is not a consume: " + line)
	assert_true(line.contains("Warrior"), line)
	assert_true(line.contains("Rat"), line)
	view.free()

## The other half of #186: the strength is stored, drives the payoff, and
## appeared nowhere in words. STATUS_APPLIED.amount already carries it.
func test_a_burn_says_how_strong_it_is_and_a_bleed_says_how_many_stacks() -> void:
	var state := _make_state()
	var view := CombatLogView.new()

	var burn := CombatEvent.make(CG.EventKind.STATUS_APPLIED, 10)
	burn.target_id = 1
	burn.status = CG.Status.BURN
	burn.amount = 18
	var burn_line := view.line_for_event(state, burn)
	assert_true(burn_line.contains("18"), burn_line)
	assert_false(burn_line.contains("stack"), "a burn's magnitude is a strength, not a count: " + burn_line)

	var bleed := CombatEvent.make(CG.EventKind.STATUS_APPLIED, 10)
	bleed.target_id = 1
	bleed.status = CG.Status.BLEED
	bleed.amount = 3
	var bleed_line := view.line_for_event(state, bleed)
	assert_true(bleed_line.contains("3 stacks"), bleed_line)

	var one := CombatEvent.make(CG.EventKind.STATUS_APPLIED, 10)
	one.target_id = 1
	one.status = CG.Status.BLEED
	one.amount = 1
	assert_true(view.line_for_event(state, one).contains("1 stack)"), "singular")
	view.free()

## THE TRAP THIS SHAPE AVOIDS, and the reason the two sets are read from
## CombatSim rather than typed here. TAUNTED stores the TAUNTER'S UNIT ID in
## `status_magnitude`, and SUSTAINING stores an action. A generic "print amount
## when it is non-zero" would have published a unit id to the player as a
## strength.
func test_a_status_whose_magnitude_is_not_a_strength_prints_no_number() -> void:
	var state := _make_state()
	var view := CombatLogView.new()
	for status in [CG.Status.TAUNTED, CG.Status.SUSTAINING, CG.Status.STUN, CG.Status.SHIELD]:
		var e := CombatEvent.make(CG.EventKind.STATUS_APPLIED, 10)
		e.target_id = 1
		e.status = status
		e.amount = 7
		var line := view.line_for_event(state, e)
		assert_false(line.contains("7"),
			"%s's magnitude is not a strength and must not be printed as one: %s" % [CG.Status.keys()[status], line])
	view.free()

# ---------------------------------------------------------------------------
# Issue 155: the log names the plan row that chose the action
# ---------------------------------------------------------------------------
#
# "I wrote the brain and was never shown it thinking." The log named the action
# and never the row, so four different reasons a pawn ignored a plan looked
# identical.
#
# `Intent.source_plan` has existed since the skeleton with a comment saying it
# is "written into the combat log", and NOTHING EVER READ IT: an intent dies
# inside one `step()`, and no event carried the field out. There was also no
# test anywhere asserting the ACTION_START line's text at all, which is why
# that stayed true for five releases.

## Against a real fight, through the real `line_for_event`, rather than against
## a hand-built event -- the shape being checked is that the simulation carries
## the field out of the tick it was created in, and a synthetic event proves
## only that this function formats one.
func test_a_real_fight_names_the_plan_row_behind_a_pawns_action() -> void:
	var state := _real_fight()
	var view := CombatLogView.new()
	var tagged := 0
	var fallback := 0
	for e in state.events:
		if e.kind != CG.EventKind.ACTION_START:
			continue
		var source := state.unit(e.source_id)
		if source == null or source.pawn == null:
			continue
		var line := view.line_for_event(state, e)
		if line.contains("[fallback]"):
			fallback += 1
			continue
		var row := view.plan_row_number(source.pawn, e.source_plan)
		assert_true(row > 0, "a pawn action with no fallback tag must name a real row: %s" % line)
		assert_true(line.contains("[plan %d]" % row), line)
		tagged += 1
	assert_true(tagged > 0, "no pawn action in a whole fight named its plan")
	assert_true(fallback > 0,
		"no pawn action fell through to the fallback, so that wording went unexercised")
	view.free()

## The negative half, and it is where the volume argument lives. An enemy has no
## plans and never will, so a tag on its line names nothing the player can go
## and change -- and enemies are roughly half of every fight's actions. A
## detector that fires on everything becomes furniture.
func test_an_enemys_action_carries_no_plan_tag_at_all() -> void:
	var state := _real_fight()
	var view := CombatLogView.new()
	var checked := 0
	for e in state.events:
		if e.kind != CG.EventKind.ACTION_START:
			continue
		var source := state.unit(e.source_id)
		if source == null or source.pawn != null:
			continue
		var line := view.line_for_event(state, e)
		assert_false(line.contains("["), "an enemy has no plans to name: %s" % line)
		checked += 1
	assert_true(checked > 0, "no enemy acted, so the quiet case was never exercised")
	view.free()

## The number in the log is the number the plan editor draws down the same list
## (`InspectPanel._plan_row` prints "%d." % (index + 1)), so a player reading
## "plan 3" can go to row 3 and find it. Checked against real preset plans.
func test_the_row_number_is_the_editors_row_number() -> void:
	var view := CombatLogView.new()
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
	assert_true(pawn.plans.size() > 1, "a one-plan pawn cannot detect an off-by-one")
	for i in pawn.plans.size():
		assert_eq(view.plan_row_number(pawn, pawn.plans[i].id), i + 1)
	assert_eq(view.plan_row_number(pawn, &"no_such_plan"), 0)
	view.free()

## A plan id with no row prints the id rather than a wrong number -- a plan
## removed while its action was still winding up. Exercised against the failing
## case rather than reasoned about: a naive `index + 1` over a -1 miss would
## print "plan 0", which is a row that does not exist.
func test_an_unknown_plan_id_prints_the_id_rather_than_a_wrong_row() -> void:
	var state := _make_state()
	state.unit(0).pawn = PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
	var view := CombatLogView.new()
	var e := CombatEvent.make(CG.EventKind.ACTION_START, 4)
	e.source_id = 0
	e.action_id = &"warrior_strike"
	e.source_plan = &"a_plan_that_was_deleted"
	var line := view.line_for_event(state, e)
	assert_true(line.contains("a_plan_that_was_deleted"), line)
	assert_false(line.contains("plan 0"), line)
	view.free()

## The compulsion is a THIRD reason, not a shade of the fallback, and it is the
## one a player is most likely to be confused by: their pawn abandoning the row
## they wrote. Left at &"" it would read "[fallback]", a confident wrong answer.
##
## Built here rather than sampled, because `Tools/PlanAttribution.gd` measured
## 4404 tagged actions over 100 real fights and NOT ONE was a compulsion -- no
## offered room taunts a pawn. A path real content never walks is exactly the
## path that ships broken.
func test_a_taunted_pawn_says_so_instead_of_blaming_the_fallback() -> void:
	var state := _make_state()
	state.unit(0).pawn = PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
	var view := CombatLogView.new()

	var compelled := CombatEvent.make(CG.EventKind.ACTION_START, 4)
	compelled.source_id = 0
	compelled.action_id = &"warrior_strike"
	compelled.source_plan = Intent.COMPELLED
	var line := view.line_for_event(state, compelled)
	assert_true(line.contains("[taunted]"), line)
	assert_false(line.contains("fallback"), line)

	var fell_through := CombatEvent.make(CG.EventKind.ACTION_START, 4)
	fell_through.source_id = 0
	fell_through.action_id = &"warrior_strike"
	assert_true(view.line_for_event(state, fell_through).contains("[fallback]"),
		"and an unstamped intent still reads as the fallback")
	view.free()

## The simulation's half: `CombatSim._compelled_intent` has to stamp the
## sentinel, or the line above formats a value nothing in the game produces.
func test_the_compulsion_stamps_its_own_sentinel_on_both_intents() -> void:
	var taunter := CombatUnit.new()
	taunter.id = 0
	taunter.position = Vector2.ZERO
	var victim := CombatUnit.new()
	victim.id = 1
	victim.actions = [&"claw"]

	var claw := ActionDef.new()
	claw.id = &"claw"
	claw.range_units = 40.0
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName) -> ActionDef:
		return claw if id == &"claw" else null
	deps.default_attack_action = func(defs: Array, ranged: bool) -> ActionDef:
		return null if ranged else (defs[0] if not defs.is_empty() else null)

	victim.position = Vector2(20.0, 0.0)
	assert_eq(CombatSim._compelled_intent(victim, taunter, deps).source_plan, Intent.COMPELLED,
		"the compelled attack")
	victim.position = Vector2(500.0, 0.0)
	assert_eq(CombatSim._compelled_intent(victim, taunter, deps).source_plan, Intent.COMPELLED,
		"and the compelled walk into range")

## `line_for_event` is the whole log, so a party of four fighting a real room is
## the only fixture that can say what the log actually reads like.
func _real_fight() -> CombatState:
	var party: Array[PawnData] = []
	for cid in Registry.all_class_ids().slice(0, 4):
		party.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s" % cid), Registry.get_class_def(cid).display_name))
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 155)
	CombatSim.run(state)
	return state
