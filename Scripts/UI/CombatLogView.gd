extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")

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

func _apply_orientation() -> void:
	if _landscape:
		_backdrop.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		_backdrop.offset_left = LOG_MARGIN - LOG_WIDTH
		_backdrop.offset_right = LOG_MARGIN
		_backdrop.offset_top = 0.0
		_backdrop.offset_bottom = 0.0

		_seam.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		_seam.offset_left = LOG_MARGIN - LOG_WIDTH
		_seam.offset_right = LOG_MARGIN - LOG_WIDTH + 2.0
		_seam.offset_top = 0.0
		_seam.offset_bottom = 0.0

		_label.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		_label.offset_left = LOG_MARGIN - LOG_WIDTH
		_label.offset_right = LOG_MARGIN
		_label.offset_top = 0.0
		_label.offset_bottom = 0.0
	else:
		_backdrop.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_backdrop.offset_top = LOG_MARGIN - LOG_HEIGHT
		_backdrop.offset_bottom = LOG_MARGIN
		_backdrop.offset_left = 0.0
		_backdrop.offset_right = 0.0

		_seam.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_seam.offset_top = LOG_MARGIN - LOG_HEIGHT
		_seam.offset_bottom = LOG_MARGIN - LOG_HEIGHT + 2.0
		_seam.offset_left = 0.0
		_seam.offset_right = 0.0

		_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_label.offset_top = LOG_MARGIN - LOG_HEIGHT
		_label.offset_bottom = LOG_MARGIN
		_label.offset_left = 0.0
		_label.offset_right = 0.0

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
			return "%s begins %s" % [source_name, _action_name(e.action_id)]
		CG.EventKind.ACTION_FIRE:
			return "%s's %s fires" % [source_name, _action_name(e.action_id)]
		CG.EventKind.STATUS_APPLIED:
			# PLAYTEST-NOTES-2 item 6: a beneficial status ("the Warrior is
			# afflicted with Shielding") read as a curse landing on the
			# player's own unit. CG.is_harmful already classifies exactly
			# this -- built for Cleanse, per its own doc comment -- and the
			# log never asked it.
			if CG.is_harmful(e.status):
				return "%s is afflicted with %s" % [target_name, _status_name(e.status)]
			return "%s gains %s" % [target_name, _status_name(e.status)]
		CG.EventKind.STATUS_EXPIRED:
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
