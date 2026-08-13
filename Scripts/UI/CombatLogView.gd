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

## Fixed height of the log panel, in pixels. BattleView._layout_arena's
## bottom margin is sized to clear exactly this (see its own comment), so a
## change here has to be matched there.
const LOG_HEIGHT := 200.0
const LOG_BOTTOM_OFFSET := -20.0

var _label: RichTextLabel = null

func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.color.a = 0.72
	backdrop.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	backdrop.offset_top = LOG_BOTTOM_OFFSET - LOG_HEIGHT
	backdrop.offset_bottom = LOG_BOTTOM_OFFSET
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# Left open when issue 15 merged: the arena's own boundary (ArenaFloor)
	# goes ambiguous under the backdrop's semi-transparent lower third — not
	# invisible, just unclear whether it is still the arena there. A seam at
	# the top of the log says the transition is deliberate rather than a
	# fade nobody meant.
	var seam := ColorRect.new()
	seam.color = Palette.ARENA_EDGE
	seam.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	seam.offset_top = LOG_BOTTOM_OFFSET - LOG_HEIGHT
	seam.offset_bottom = LOG_BOTTOM_OFFSET - LOG_HEIGHT + 2.0
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(seam)

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
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_top = LOG_BOTTOM_OFFSET - LOG_HEIGHT
	_label.offset_bottom = LOG_BOTTOM_OFFSET
	_label.add_theme_color_override("default_color", Palette.TEXT)
	add_child(_label)

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
