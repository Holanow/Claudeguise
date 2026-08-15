extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Glossary := preload("res://Scripts/UI/Glossary.gd")

## The scrolling record of the fight, in words. One line per CombatEvent worth
## showing.
##
## OWNER: pike.
##
## This is half of how the combat gets judged. "That felt bad" has to be
## traceable to a cause, so a line names the actor, the action, the target, the
## number and the mitigation when there was any. A line reading "Warrior hits
## Rat for 7" is not enough to tell a tuning problem from a targeting problem.

## Screen-space, not world-space, so neither scales with the arena.
## BattleView.compute_layout reserves exactly one of these (whichever
## matches the current orientation) before fitting the arena into what's
## left (issue 26/29), so a change here has to be matched there.
##
## Issue 29: landscape used to reserve LOG_HEIGHT along the bottom, same as
## portrait still does here. That fixed a real overlap (three of seven units
## drawn behind the log's text) at the cost of the arena's own size — rook
## measured the fix at "about a quarter of the screen", a real regression
## against "everything larger and more readable". A 16:9 arena in a
## wider-than-16:9 window already leaves empty side margins it can never
## use; landscape now spends those on the log instead, side rather than
## below. Portrait keeps the bottom strip: width is portrait's scarce
## dimension, not height, so a side column would cost far more there than a
## thin bottom strip does — confirmed by the regression this file's own
## history includes, where applying the side reservation unconditionally
## dropped the pinned portrait height fraction under its floor.
##
## PLAYTEST-NOTES-2 item 8: *"The log is too large. Move it to a bottom
## corner, out of the way."* It is one box now, `LOG_WIDTH` x `LOG_HEIGHT`,
## pinned to the bottom of whichever strip the orientation reserves -- the
## bottom-right corner in landscape, the bottom band in portrait. It used to
## run the whole height of the landscape column, and after the team status
## panel took the top of that column (issue 113) what was left was twelve
## lines. **The manager's ruling: twelve lines is already more than a player
## reads mid-fight, so take the shorter log and move it.**
##
## The reservation in `BattleView.compute_layout` is unchanged and still the
## full column, because the panel is in the top of it. **Measured before
## touching it: at 1280x720 the arena is height-limited -- a 1095x870 fit into
## a usable 1020x720 is 0.932 by width and 0.828 by height -- so the 260 px
## column costs the arena nothing at all. Same at 844x390 (0.533 by width,
## 0.448 by height).** Reclaiming the column would not have grown the arena by
## a pixel; only the log's own size was ever on the table here.
const LOG_WIDTH := 260.0
const LOG_HEIGHT := 200.0
const LOG_MARGIN := -20.0

var _label: RichTextLabel = null
var _backdrop: ColorRect = null
var _seam: ColorRect = null
var _landscape := true

func _ready() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Palette.BACKGROUND
	_backdrop.color.a = 0.72
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	# Left open when issue 15 merged: the arena's own boundary (ArenaFloor)
	# goes ambiguous under the backdrop's semi-transparent edge — not
	# invisible, just unclear whether it is still the arena there. A seam at
	# the near edge of the log says the transition is deliberate rather than
	# a fade nobody meant.
	_seam = ColorRect.new()
	_seam.color = Palette.ARENA_EDGE
	_seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seam)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_following = true
	# RichTextLabel does not clip to its own rect by default: without this,
	# every line ever appended keeps drawing past the bottom of the panel
	# instead of scrolling out of view. Found by rendering a real fight
	# through six frames (Tools/ContactSheet.gd) — the log ran off the
	# bottom of the screen and the newest line, the one that matters, was
	# the one lost off the edge.
	_label.clip_contents = true
	_label.add_theme_color_override("default_color", Palette.TEXT)
	add_child(_label)

	_apply_orientation()

## Called by BattleView._layout_arena, same trigger as the arena's own
## rescale, so the log flips sides exactly when the fit it shares math with
## does. Landscape is size.x >= size.y, matching compute_layout's own rule.
func set_landscape(landscape: bool) -> void:
	if landscape == _landscape:
		return
	_landscape = landscape
	_apply_orientation()

## One box, two anchorings. It was two nine-line branches that differed only in
## which preset and which pair of offsets they set, and the `_top_inset` the
## landscape branch carried is gone with the full-height column it belonged to:
## the log is pinned to the bottom now, so nothing has to be told where the team
## status panel ends.
##
## The seam is the box's own top edge in both orientations. That is the edge
## facing the fight -- the arena is above the log in landscape and in portrait
## alike -- and it is what says the transition is deliberate rather than the
## backdrop's translucent edge fading out over the arena's boundary.
func _apply_orientation() -> void:
	var preset := Control.PRESET_BOTTOM_RIGHT if _landscape else Control.PRESET_BOTTOM_WIDE
	for node in [_backdrop, _seam, _label]:
		# set_anchors_preset resets the offsets, so they go on afterwards.
		node.set_anchors_preset(preset)
		node.offset_top = LOG_MARGIN - LOG_HEIGHT
		node.offset_bottom = LOG_MARGIN
		node.offset_left = LOG_MARGIN - LOG_WIDTH if _landscape else 0.0
		node.offset_right = LOG_MARGIN if _landscape else 0.0
	_seam.offset_bottom = _seam.offset_top + 2.0

func append_event(state: CombatState, event: CombatEvent) -> void:
	var line := line_for_event(state, event)
	if line != "" and _label != null:
		_label.append_text(line + "\n")

func clear_log() -> void:
	if _label != null:
		_label.clear()

## Pure formatting, split out so it can be tested without a live RichTextLabel.
func line_for_event(state: CombatState, e: CombatEvent) -> String:
	var source := state.unit(e.source_id)
	var target := state.unit(e.target_id)
	var source_name := source.display_name if source != null else "?"
	var target_name := target.display_name if target != null else "?"

	match e.kind:
		CG.EventKind.FIGHT_START:
			return "[color=%s]The fight begins.[/color]" % Palette.TEXT_DIM.to_html()
		CG.EventKind.FIGHT_END:
			return "[b]The fight ends.[/b]"
		CG.EventKind.DAMAGE:
			var color := Palette.damage_color(e.damage_type).to_html()
			# Issue 33: a poison/burn tick and a hazard tick both carry no
			# source — the cultist that applied the poison may be dead, and
			# attributing the damage to them would be a worse lie than
			# omitting a source. Neither fits "X hits Y", which needs an X.
			# _tick_dot_statuses (CombatSim.gd) sets `status` on every
			# affliction tick; a hazard tick never touches it,
			# leaving the field at its unrelated default (SHIELD) — that
			# is what tells the two apart here, since the event itself
			# carries nothing more explicit than that.
			if e.source_id == -1:
				# Issue 24: a poison/burn tick fires once per afflicted unit
				# per tick — correct for the simulation, and twelve
				# identical "X suffers 1 damage" lines in a ~20-line visible
				## log buried the two events a player actually reads ("X
				# dies", "Y hits Z for N"). Dropped rather than coalesced or
				# summarised: the affliction is not lost, it logs once when
				# applied and once when it fades (STATUS_APPLIED/EXPIRED
				# below) and every tick still floats a number on the unit
				# via BattleView.consume_events, which spawns from the event
				# itself, not from what this function returns. A hazard
				# tick (source_id == -1, status left at its unset default)
				# is unaffected — standing somewhere bad is different
				# information from being afflicted, and is not the thing
				# twelve identical lines were measured on.
				#
				# Issue 202: this used to name the two afflictions it knew
				# about (BURN, POISON) and let the ground line catch
				# everything else. BLEED joined `_DOT_STATUSES` afterwards
				# and fell into that "everything else", so the Rat King's
				# nest, which has no terrain at all, logged a column of
				# "Geysermancer takes 2 Physical damage from the ground" --
				# and bleed is the King's own signature mechanic. Both of
				# issue 24's defects in one line: the flood was never
				# collapsed for bleed either.
				#
				# Written the other way round now. The ground has to
				# identify itself (`status` still at its unset default) and
				# anything else sourceless is an affliction. A future
				# damage-over-time status is then silent by default rather
				# than misattributed by default, which is the safe
				# direction: an empty line is a gap a player might notice,
				# a confident wrong attribution is one they will believe.
				if e.status != CG.Status.SHIELD:
					return ""
				return "%s takes [color=%s]%d[/color] %s damage from the ground" % [
					target_name, color, e.amount, CG.damage_type_name(e.damage_type)
				]
			# Issue 74: a summon or a buff still resolves through
			# _apply_action_effect and still emits a DAMAGE event -- the
			# event stream is correct, CombatSim must not change (rook's
			# own instruction) -- but the action never rolled any damage at
			# all: power_scale is 0 for these, so amount_before_mitigation
			# is 0 too, not just amount. That is the one signal that tells
			# "this action does not deal damage" apart from "this attack
			# was fully absorbed", which the very next check below still
			# has to keep showing (amount 0, amount_before_mitigation > 0)
			# per issue 14's own finding that a miss and a fully-mitigated
			# hit must read differently. Suppressed rather than reworded:
			# ACTION_FIRE and, where relevant, STATUS_APPLIED already say
			# what the action actually did on the surrounding lines.
			if e.amount == 0 and e.amount_before_mitigation == 0:
				return ""
			var mitigation := ""
			if e.amount_before_mitigation > e.amount:
				mitigation = " (%d before mitigation)" % e.amount_before_mitigation
			return "%s hits %s for [color=%s]%d[/color] %s damage%s" % [
				source_name, target_name, color, e.amount,
				CG.damage_type_name(e.damage_type), mitigation
			]
		CG.EventKind.MISS:
			return "[color=%s]%s's %s misses %s[/color]" % [
				Palette.TEXT_DIM.to_html(), source_name, _action_name(e.action_id), target_name
			]
		CG.EventKind.HEAL:
			return "%s heals %s for %d" % [source_name, target_name, e.amount]
		CG.EventKind.DEATH:
			return "[color=%s]%s dies.[/color]" % [Palette.TEAM_ENEMY.to_html(), target_name]
		CG.EventKind.ACTION_START:
			return "%s begins %s%s" % [source_name, _action_name(e.action_id), _plan_tag(source, e)]
		CG.EventKind.ACTION_FIRE:
			return "%s's %s fires" % [source_name, _action_name(e.action_id)]
		CG.EventKind.STATUS_APPLIED:
			# PLAYTEST-NOTES-2 item 6: a beneficial status ("the Warrior is
			# afflicted with Shielding") read as a curse landing on the
			# player's own unit. CG.is_harmful already classifies exactly
			# this -- built for Cleanse, per its own doc comment -- and the
			# log never asked it.
			var strength := _magnitude_text(e)
			if CG.is_harmful(e.status):
				return "%s is afflicted with %s%s" % [target_name, _status_name(e.status), strength]
			return "%s gains %s%s" % [target_name, _status_name(e.status), strength]
		CG.EventKind.STATUS_EXPIRED:
			# Issue 186: three different things end a status and all three used
			# to print the same sentence. The simulation has always told them
			# apart and the log never asked -- a natural expiry carries no
			# source (`_tick_statuses`), while a consume and a cleanse both
			# carry the caster and the action that did it, exactly so this line
			# could separate them (`_consume_status`'s own comment says it is
			# "the only thing separating 'Blast ate the burn' from 'the burn
			# ran out'").
			#
			# It matters most for the consume, because the payoff is invisible
			# otherwise: the bonus scales off the eaten burn's own strength, so
			# "Scald hard, then Blast" is a sequence the player is meant to
			# discover, and until now the eating was not even reported. The
			# DAMAGE line lands on the next line and this is its cause.
			if e.source_id != -1:
				var action := Registry.get_action(e.action_id)
				if action != null and action.consumes_status_enabled and action.consumes_status == e.status:
					return "[color=%s]%s's %s consumes %s's %s[/color]" % [
						Palette.damage_color(CG.DamageType.FIRE).to_html(),
						source_name, _action_name(e.action_id), target_name, _status_name(e.status)
					]
				# The other sourced ending is a cleanse (`_cleanse_harmful`), and
				# it is one of the few things a support pawn does that has never
				# been visible as an action rather than as an absence.
				return "%s's %s lifts %s's %s" % [
					source_name, _action_name(e.action_id), target_name, _status_name(e.status)
				]
			if CG.is_harmful(e.status):
				return "%s's %s fades" % [target_name, _status_name(e.status)]
			return "%s's %s ends" % [target_name, _status_name(e.status)]
		CG.EventKind.BLOCKED:
			# `target_id` is the BLOCKER, not the unit the shot was aimed at --
			# see CG.EventKind.BLOCKED's own comment. The aimed-at unit is
			# already gone from the outcome by the time this fires, so naming
			# it here would need a field the event does not carry, and the
			# interesting subject is the guard anyway.
			#
			# Logged on every one, ~19.5 a fight on swift's measurement,
			# against a log already running a few hundred lines. That is a few
			# percent, and it buys the thing #99 exists for: the block has been
			# in the event stream for weeks and a player could not see a single
			# one of them. The DAMAGE line that follows on the same tick shows
			# the guard being hit rather than the ally it was aimed at, which is
			# only comprehensible with this line in front of it.
			return "[color=%s]%s blocks %s's %s[/color]" % [
				Palette.TEAM_PLAYER.to_html(), target_name, source_name, _action_name(e.action_id)
			]
		CG.EventKind.SUSTAIN_START:
			# ACTION_FIRE printed "X's Y fires" on this same tick, and a channel
			# is exactly the case where firing is not the end of it.
			return "%s holds %s" % [source_name, _action_name(e.action_id)]
		CG.EventKind.SUSTAIN_END:
			# `amount` is the ticks it was held for, and it is the one thing a
			# player wants from a channel once it is over -- not recoverable
			# from the event stream any other way. Shown in seconds, the unit
			# every other duration on this screen already uses.
			return "%s stops %s after %s" % [
				source_name, _action_name(e.action_id), _seconds(e.amount)
			]
		CG.EventKind.INTERRUPTED:
			# `source_id` is the unit that LOST the action, not the interrupter.
			# That matches ACTION_START, which is the event this one cancels, so
			# a log that printed "Geysermancer begins Blast" prints the same
			# subject losing it. What did the interrupting is the STATUS_APPLIED
			# on the same tick.
			#
			# `amount` is the wind-up already invested and thrown away, and the
			# resource is NOT refunded (the player's ruling). That is the most
			# punishing thing that can happen to a pawn, so it takes a loud
			# colour rather than the dim treatment a miss gets. BattleView also
			# flashes the unit on this event: the line says what happened, the
			# flash says it happened now, and the player asked for both.
			return "[color=%s]%s's %s is interrupted, %s of wind-up lost[/color]" % [
				Palette.TEAM_ENEMY.to_html(), source_name,
				_action_name(e.action_id), _seconds(e.amount)
			]
		CG.EventKind.SUMMONED:
			# `target_id` is the NEW unit, not a foe. swift's shape, with
			# "summons" where they wrote "builds": the Siege Master builds an
			# engine and the Rat King does not build a rat, and one verb has to
			# cover both.
			return "%s summons %s" % [source_name, target_name]
		CG.EventKind.RESOURCE_SPENT:
			# Deliberate. See SILENT_KINDS below -- the list is what makes this
			# silence distinguishable from an oversight.
			return ""
	return ""

## Every CG.EventKind either produces a line above or is named here, and
## `Tests/test_ui_combat_log.gd::test_every_event_kind_speaks_or_is_named_silent`
## walks the real enum to enforce it.
##
## Issue 151, and this guard is the point of that issue rather than the lines.
## `line_for_event` is a `match` with `return ""` underneath, so a kind added to
## the enum renders nothing at all, in real fights, with the gate green
## throughout. That happened FIVE times to THREE people -- BLOCKED,
## SUSTAIN_START, SUSTAIN_END, INTERRUPTED, and SUMMONED -- including from a
## pull request whose entire purpose was to stop the Warrior's block being
## invisible.
##
## Adding a `CG.Status` has never been able to happen invisibly: three gate
## tests refuse a status with no glyph and no glossary entry. This is that guard
## for the other enum. The working precedent is swift's
## `test_audio.gd::test_the_replacement_instructions_name_every_event_kind`,
## which caught a missing kind on its own first gate run.
##
## A deliberate silence goes in this list, and that is what makes it
## distinguishable from an oversight -- which is the whole difference the guard
## buys.
const SILENT_KINDS := [
	# The spend is already on screen twice: the resource bar drops on the same
	# tick, and ACTION_START names what it was spent on. A line per spend is one
	# per action per pawn, the largest thing that could be added to this log and
	# the least informative.
	CG.EventKind.RESOURCE_SPENT,
]

## Issue 186. A burn's strength and a bleed's stack count are stored on the unit
## and, until this, appeared nowhere in words -- so the payoff of eating a burn
## varied from fight to fight for a reason the player could not see. The whole
## design only works if it can be learned: hit hard, get a big burn, eat it for
## a big Blast.
##
## `STATUS_APPLIED.amount` already carries the resulting magnitude
## (`CombatSim._apply_status` sets it for exactly this), so nothing new is read.
##
## THE NUMBER MEANS TWO DIFFERENT THINGS AND IS THEREFORE WORDED TWO DIFFERENT
## WAYS. A stacking status counts applications; a hit-scaled one carries the
## damage of the hit that set it. Printing a bare "(3)" for both would invite
## reading a burn's strength as a stack count.
##
## And it is silent for every other status ON PURPOSE, by walking CombatSim's
## own two sets rather than a list typed here. TAUNTED stores **the taunter's
## unit id** in the same field, and SUSTAINING stores an action -- a generic
## "print amount when non-zero" would have published a unit id to the player as
## if it were a strength. That is the trap this shape avoids, and it is the
## reason the sets are read from where they are defined.
##
## Issue 245: the wording moved to `Glossary.status_magnitude_text` and this
## calls it. The status popup on the team panel has to say the same thing about
## the same badge, and this rule -- which statuses may show a number at all, and
## in which of two units -- is the part that must not exist twice. The output is
## unchanged; only the parentheses are still this function's.
func _magnitude_text(e: CombatEvent) -> String:
	var text := Glossary.status_magnitude_text(e.status, e.amount)
	return "" if text == "" else " (%s)" % text

## Issue 155. The half of "what happened **and why**" the log has never had.
##
## A fresh-eyes playtester: *"I wrote the brain and was never shown it
## thinking."* The log named the action and never the row that chose it, so a
## Priest smiting instead of healing looked identical whether the heal's
## condition was false, the heal was unaffordable, the heal sat below Smite in
## the order, or no row fired at all and the fallback decided.
##
## THE VOLUME DECISION, since the issue asks for it explicitly and a fresh reader
## has already said the arena stops helping once they are reading the log.
##
##   - **In the line, not in a hover:** which row fired is the reason for the
##     line, and a reason you have to go and ask for is a reason nobody reads
##     while a fight is running. The whole complaint is about following a fight
##     *without pausing*.
##   - **On ACTION_START only.** One tag per decision, not per consequence. The
##     damage, the status and the death that follow inherit their reason from the
##     line above them, and tagging each would say the same thing four times.
##   - **On pawns only.** An enemy has no plans and never will (`CLAUDE.md`:
##     "enemies have no plans and do not need them"), so `[fallback]` on a goblin
##     names nothing the player can go and change. Enemies are roughly half of
##     every fight's actions, so this is also where the volume is.
##   - **Why the other rows did not fire is NOT here.** That is four facts per
##     row per tick and it would bury the log. It lives in the pause inspection
##     instead — `InspectPanel` marks every row with its live verdict — which
##     costs the log nothing and puts the answer in the screen where the fix is
##     made.
##
## The number is the row number the plan editor shows (`InspectPanel._plan_row`
## draws "1.", "2." down the same list in the same order), so "plan 2" in the log
## and row 2 on the editor are the same row by construction rather than by
## agreement. An id with no row -- a plan removed while its action was still
## winding up -- prints the id rather than a wrong number.
func _plan_tag(source, e: CombatEvent) -> String:
	if source == null or source.pawn == null:
		return ""
	var text := ""
	if e.source_plan == Intent.COMPELLED:
		text = "taunted"
	elif e.source_plan == &"":
		text = "fallback"
	else:
		var index := plan_row_number(source.pawn, e.source_plan)
		text = "plan %d" % index if index > 0 else String(e.source_plan)
	return " [color=%s][%s][/color]" % [Palette.TEXT_DIM.to_html(), text]

## 1-based row number of `plan_id` in the pawn's plans, or 0 when it has none.
## Public because the test suite asserts the log's number against the editor's.
func plan_row_number(pawn, plan_id: StringName) -> int:
	for i in pawn.plans.size():
		if pawn.plans[i].id == plan_id:
			return i + 1
	return 0

## Ticks as the seconds a player reads off the clock, matching BattleView's own
## elapsed display, so a duration in the log and a duration on the HUD are the
## same unit.
func _seconds(ticks: int) -> String:
	return "%.1fs" % (float(ticks) / float(CG.TICKS_PER_SECOND))

## Issue 19: "warrior_strike fires" is the same developer-language problem
## the win screen's tick count was, in a quieter place. Prefers the real
## ActionDef's display_name; falls back to humanizing the raw id (String's
## own capitalize() turns snake_case into Title Case) so a hand-built test
## fixture using a synthetic action id — not a real registered one — still
## reads as words rather than crashing or showing nothing.
func _action_name(action_id: StringName) -> String:
	var action := Registry.get_action(action_id)
	if action != null and action.display_name != "":
		return action.display_name
	return String(action_id).capitalize()

func _status_name(status: CG.Status) -> String:
	return String(CG.Status.keys()[status]).capitalize()
