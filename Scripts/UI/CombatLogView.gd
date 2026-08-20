extends Control
class_name CombatLogView


## The scrolling record of the fight, in words. One line per CombatEvent worth
## showing.

## Screen-space, not world-space, so neither scales with the arena.
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
	_seam = ColorRect.new()
	_seam.color = Palette.ARENA_EDGE
	_seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seam)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_following = true
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
			if e.source_id == -1:
				if e.status != CG.Status.SHIELD:
					return ""
				return "%s takes [color=%s]%d[/color] %s damage from the ground" % [
					target_name, color, e.amount, CG.damage_type_name(e.damage_type)
				]
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
			var strength := _magnitude_text(e)
			if CG.is_harmful(e.status):
				return "%s is afflicted with %s%s" % [target_name, _status_name(e.status), strength]
			return "%s gains %s%s" % [target_name, _status_name(e.status), strength]
		CG.EventKind.STATUS_EXPIRED:
			if e.source_id != -1:
				var action := Registry.get_action(e.action_id)
				if action != null and action.consumes_status_enabled and action.consumes_status == e.status:
					return "[color=%s]%s's %s consumes %s's %s[/color]" % [
						Palette.damage_color(CG.DamageType.FIRE).to_html(),
						source_name, _action_name(e.action_id), target_name, _status_name(e.status)
					]
				return "%s's %s lifts %s's %s" % [
					source_name, _action_name(e.action_id), target_name, _status_name(e.status)
				]
			if CG.is_harmful(e.status):
				return "%s's %s fades" % [target_name, _status_name(e.status)]
			return "%s's %s ends" % [target_name, _status_name(e.status)]
		CG.EventKind.BLOCKED:
			# `target_id` is the BLOCKER, not the unit the shot was aimed at --
			return "[color=%s]%s blocks %s's %s[/color]" % [
				Palette.TEAM_PLAYER.to_html(), target_name, source_name, _action_name(e.action_id)
			]
		CG.EventKind.SUSTAIN_START:
			# ACTION_FIRE printed "X's Y fires" on this same tick, and a channel
			# is exactly the case where firing is not the end of it.
			return "%s holds %s" % [source_name, _action_name(e.action_id)]
		CG.EventKind.SUSTAIN_END:
			return "%s stops %s after %s" % [
				source_name, _action_name(e.action_id), _seconds(e.amount)
			]
		CG.EventKind.INTERRUPTED:
			# `source_id` is the unit that LOST the action, not the interrupter.
			return "[color=%s]%s's %s is interrupted, %s of wind-up lost[/color]" % [
				Palette.TEAM_ENEMY.to_html(), source_name,
				_action_name(e.action_id), _seconds(e.amount)
			]
		CG.EventKind.SUMMONED:
			return "%s summons %s" % [source_name, target_name]
		CG.EventKind.RESOURCE_SPENT:
			# Deliberate. See SILENT_KINDS below -- the list is what makes this
			# silence distinguishable from an oversight.
			return ""
	return ""

## Every CG.EventKind either produces a line above or is named here, and
## `Tests/test_ui_combat_log.gd::test_every_event_kind_speaks_or_is_named_silent`
const SILENT_KINDS := [
	CG.EventKind.RESOURCE_SPENT,
]

## Issue 186. A burn's strength and a bleed's stack count are stored on the unit
## and, until this, appeared nowhere in words -- so the payoff of eating a burn
## varied from fight to fight for a reason the player could not see. The whole
## design only works if it can be learned: hit hard, get a big burn, eat it for
## a big Blast.
func _magnitude_text(e: CombatEvent) -> String:
	var text := Glossary.status_magnitude_text(e.status, e.amount)
	return "" if text == "" else " (%s)" % text

## Which plan row chose the action -- the "and why" half of the log.
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
## fixture using a synthetic action id -- not a real registered one -- still
## reads as words rather than crashing or showing nothing.
func _action_name(action_id: StringName) -> String:
	var action := Registry.get_action(action_id)
	if action != null and action.display_name != "":
		return action.display_name
	return String(action_id).capitalize()

func _status_name(status: CG.Status) -> String:
	return String(CG.Status.keys()[status]).capitalize()
