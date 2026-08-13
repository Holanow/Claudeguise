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
			var mitigation := ""
			if e.amount_before_mitigation > e.amount:
				mitigation = " (%d before mitigation)" % e.amount_before_mitigation
			var color := Palette.damage_color(e.damage_type).to_html()
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
			return "%s is afflicted with %s" % [target_name, _status_name(e.status)]
		CG.EventKind.STATUS_EXPIRED:
			return "%s's %s fades" % [target_name, _status_name(e.status)]
		CG.EventKind.RESOURCE_SPENT:
			return ""
	return ""

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
