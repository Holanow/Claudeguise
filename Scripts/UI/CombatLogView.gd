extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")

## The scrolling record of the fight, in words. One line per CombatEvent worth
## showing.
##
## OWNER: pike.
##
## This is half of how the combat gets judged. "That felt bad" has to be
## traceable to a cause, so a line names the actor, the action, the target, the
## number and the mitigation when there was any. A line reading "Warrior hits
## Rat for 7" is not enough to tell a tuning problem from a targeting problem.

var _label: RichTextLabel = null

func _ready() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_following = true
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_top = -220.0
	_label.custom_minimum_size = Vector2(0.0, 200.0)
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
		CG.EventKind.HEAL:
			return "%s heals %s for %d" % [source_name, target_name, e.amount]
		CG.EventKind.DEATH:
			return "[color=%s]%s dies.[/color]" % [Palette.TEAM_ENEMY.to_html(), target_name]
		CG.EventKind.ACTION_START:
			return "%s begins %s" % [source_name, String(e.action_id)]
		CG.EventKind.ACTION_FIRE:
			return "%s's %s fires" % [source_name, String(e.action_id)]
		CG.EventKind.STATUS_APPLIED:
			return "%s is afflicted with %s" % [target_name, CG.Status.keys()[e.status]]
		CG.EventKind.STATUS_EXPIRED:
			return "%s's %s fades" % [target_name, CG.Status.keys()[e.status]]
		CG.EventKind.RESOURCE_SPENT:
			return ""
	return ""
