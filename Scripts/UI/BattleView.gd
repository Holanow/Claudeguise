extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatEvent := preload("res://Scripts/Core/CombatEvent.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")
const DisplayOptions := preload("res://Scripts/UI/DisplayOptions.gd")
const DisplayOptionsPanelScript := preload("res://Scripts/UI/DisplayOptionsPanel.gd")
const ImpactFlashScript := preload("res://Scripts/UI/ImpactFlash.gd")
const InspectPanelScript := preload("res://Scripts/UI/InspectPanel.gd")
const CombatLogView := preload("res://Scripts/UI/CombatLogView.gd")

## Draws one fight and steps it. Reads CombatState and CombatEvent only; it
## never asks the simulation to do anything except step.
##
## OWNER: pike.
##
## Real time, with a pause: wall-clock delta accumulates and is spent in whole
## ticks, so the fight runs at CG.TICKS_PER_SECOND regardless of frame rate,
## catching up if frames were dropped rather than quietly running in slow
## motion. Pause just stops spending the accumulator; it never touches
## Engine.time_scale or the scene tree pause, so floaters and log entries from
## before the pause keep finishing on wall clock time.

signal restart_requested
signal back_requested

var state: CombatState = null
var event_cursor: int = 0
var config: RunConfig = null
var paused: bool = false

var _tick_accumulator: float = 0.0

var _arena: Node2D = null
var _combat_log = null
var _unit_views: Dictionary = {}

var _party_label: Label = null
var _encounter_label: Label = null
var _seed_label: Label = null
var _outcome_label: Label = null
var _display_options: Control = null
var _pause_button: Button = null

var _party_summary_fill: ColorRect = null
var _enemy_summary_fill: ColorRect = null

var _end_banner: Control = null
var _end_outcome_label: Label = null
var _end_cost_label: Label = null
var _inspect_panel = null

var _pause_dim: ColorRect = null

func _ready() -> void:
	_arena = get_node("Arena")
	_combat_log = get_node("Hud/CombatLog")
	_build_pause_dim()
	_build_top_bar()
	_build_end_banner()
	# Guarded so a test can call _ready() directly on an instantiated-but-not-
	# added scene to reach the HUD nodes begin() needs, without a live viewport.
	if is_inside_tree():
		_layout_arena()
		get_viewport().size_changed.connect(_layout_arena)

## PLAYTEST-NOTES-2 item 5: "pause needs to be obvious -- grey the screen
## or similar. Nothing currently indicates it." Added first, before any
## other Hud child, so later Hud elements (the top bar, the pause button
## itself, the combat log) draw on top of it and stay fully legible while
## the arena underneath reads as held. Hud is its own CanvasLayer above
## Arena's, so this only needs to sit early in Hud's own child order to
## land between the two -- it does not need a z_index or a second layer.
func _build_pause_dim() -> void:
	var hud := get_node("Hud")
	_pause_dim = ColorRect.new()
	_pause_dim.color = Palette.BACKGROUND
	_pause_dim.color.a = 0.55
	_pause_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_dim.visible = false
	hud.add_child(_pause_dim)

func _build_top_bar() -> void:
	var hud := get_node("Hud")

	# The arena now fills almost the whole viewport (see _layout_arena), so
	# the HUD strip overlays it rather than sitting over empty margin. A
	# backdrop keeps it legible against whatever the arena is drawing
	# underneath, the same reasoning as CombatLogView's own backdrop.
	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.color.a = 0.72
	backdrop.set_anchors_preset(Control.PRESET_TOP_WIDE)
	backdrop.offset_bottom = _SUMMARY_ROW_TOP + _SUMMARY_ROW_HEIGHT + Palette.SPACE_S
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(backdrop)

	# Issue 43: this used to be one HBoxContainer holding four labels and
	# three buttons, all in a single row — it overflowed the viewport the
	# moment a wide label (the room name, issue 36) or a narrow phone
	# width made the row longer than the screen. Split into an info row
	# (labels, which can wrap or clip without losing function) and a
	# controls row (buttons, which must stay tappable and never clip).
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.add_theme_constant_override("separation", int(Palette.SPACE_M))
	bar.offset_left = Palette.SPACE_M
	bar.offset_right = -Palette.SPACE_M
	bar.offset_top = Palette.SPACE_M
	hud.add_child(bar)

	var controls := HBoxContainer.new()
	controls.set_anchors_preset(Control.PRESET_TOP_WIDE)
	controls.add_theme_constant_override("separation", int(Palette.SPACE_M))
	controls.offset_left = Palette.SPACE_M
	controls.offset_top = Palette.SPACE_M + _INFO_ROW_HEIGHT + Palette.SPACE_S
	hud.add_child(controls)

	# Issue 15: "you cannot tell who is winning" without parsing seven small
	# bars. Two aggregate bars answer that at a glance, colour-coded the same
	# way a single unit's own hp bar is.
	# Issue 82: the two bars are stacked, not side by side, and their labels are
	# one fixed width.
	#
	# A fresh reader measured them as "teal ~117px, red ~133px at full" and
	# concluded the comparison was meaningless. The troughs were always the same
	# width -- what differed was where each one *started*, because "Party" and
	# "Enemies" are different lengths and each bar sat in its own row after its
	# own label. **Two bars you are meant to compare must share a left edge**,
	# or the eye is comparing right-hand ends that begin in different places.
	# The one question a spectator has is *am I ahead*, and this is the control
	# that answers it.
	var summary := VBoxContainer.new()
	summary.set_anchors_preset(Control.PRESET_TOP_LEFT)
	summary.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	summary.offset_left = Palette.SPACE_M
	summary.offset_top = _SUMMARY_ROW_TOP
	hud.add_child(summary)
	_party_summary_fill = _build_summary_bar(summary, "Party", Palette.TEAM_PLAYER)
	_enemy_summary_fill = _build_summary_bar(summary, "Enemies", Palette.TEAM_ENEMY)

	_party_label = Label.new()
	_party_label.add_theme_color_override("font_color", Palette.TEXT)
	bar.add_child(_party_label)

	# Issue 36's own "while you are there": the room's name existed
	# (Encounter.display_name) and nothing showed it, which is exactly
	# what let PartySelect fight the wrong room invisibly for as long as
	# it did. A player who cannot tell one room from another cannot tell
	# that class of bug is happening either.
	_encounter_label = Label.new()
	_encounter_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	bar.add_child(_encounter_label)

	_seed_label = Label.new()
	_seed_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	bar.add_child(_seed_label)

	# Issue 19: this used to be the *only* place the outcome showed, at the
	# same weight as everything else in the toolbar — "looks like a status
	# field" for the payoff of the entire fight. Kept small here as a
	# passive echo; _build_end_banner is the prominent version, shown only
	# once the fight actually resolves.
	_outcome_label = Label.new()
	_outcome_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_outcome_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	bar.add_child(_outcome_label)

	# Issue 18 criterion 3: every control at least Palette.TOUCH_TARGET_MIN on
	# its short side. Unset, a Button's default minimum height (theme padding
	# around the font) comes in under 48 — not visible in a screenshot, only
	# by measuring, which is why the issue says to assert it rather than look.
	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	_pause_button.pressed.connect(func(): set_paused(not paused))
	controls.add_child(_pause_button)

	var restart_button := Button.new()
	restart_button.text = "Restart (same seed)"
	restart_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	restart_button.pressed.connect(func(): restart_requested.emit())
	controls.add_child(restart_button)

	var back_button := Button.new()
	back_button.text = "Change party"
	back_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	back_button.pressed.connect(func(): back_requested.emit())
	controls.add_child(back_button)

	# Issue 136. On the control row beside Pause, because the point of turning
	# the numbers off is to change what you are looking at while you are looking
	# at it -- a display toggle on a menu screen would be the wrong control
	# however tidy it looked there.
	var view_button := Button.new()
	view_button.text = "What to show"
	view_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	view_button.pressed.connect(func(): _display_options.toggle_visible())
	controls.add_child(view_button)

	_display_options = Control.new()
	_display_options.set_script(DisplayOptionsPanelScript)
	hud.add_child(_display_options)
	if not _display_options.is_inside_tree():
		_display_options._ready()
	# Under the control row it belongs to. Issue 145 taught me to add_child
	# before any manual _ready(), or the engine runs a second one.
	_display_options.position = Vector2(Palette.SPACE_M, _SUMMARY_ROW_TOP + _INFO_ROW_HEIGHT + Palette.SPACE_M)

## Issue 19: the outcome is the payoff of the whole fight and used to show as
## a small toolbar label — same weight as "Seed 0000002A". This is the
## prominent version: a full-screen backdrop shown only once the fight
## actually resolves (built hidden here, shown from _show_outcome, hidden
## again in begin()), so it cannot compete with anything mid-fight.
func _build_end_banner() -> void:
	var hud := get_node("Hud")

	_end_banner = Control.new()
	_end_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_banner.visible = false
	hud.add_child(_end_banner)

	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.color.a = 0.88
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_banner.add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", int(Palette.SPACE_M))
	_end_banner.add_child(column)

	_end_outcome_label = Label.new()
	_end_outcome_label.add_theme_color_override("font_color", Palette.TEXT)
	_end_outcome_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING * 2)
	_end_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_outcome_label)

	_end_cost_label = Label.new()
	_end_cost_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_end_cost_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_end_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_cost_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", int(Palette.SPACE_M))
	column.add_child(buttons)

	var restart_button := Button.new()
	restart_button.text = "Restart (same seed)"
	restart_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	restart_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	restart_button.pressed.connect(func(): restart_requested.emit())
	buttons.add_child(restart_button)

	var back_button := Button.new()
	back_button.text = "Change party"
	back_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	back_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	back_button.pressed.connect(func(): back_requested.emit())
	buttons.add_child(back_button)

	# Issue 21b: reachable from the end of a fight, per the issue's own note
	# that this is "probably the more useful" place — it is exactly when a
	# player has just watched something confusing.
	var inspect_button := Button.new()
	inspect_button.text = "Inspect party"
	inspect_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	inspect_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	inspect_button.pressed.connect(_on_inspect_pressed)
	buttons.add_child(inspect_button)

	_inspect_panel = Control.new()
	_inspect_panel.set_script(InspectPanelScript)
	hud.add_child(_inspect_panel)
	if not _inspect_panel.is_inside_tree():
		_inspect_panel._ready()

func _on_inspect_pressed() -> void:
	if _inspect_panel != null and config != null:
		_inspect_panel.open(config.party)

## e.g. 197 ticks at 30 ticks/second reads as "6.6s" — a player has never
## seen a tick, and won't start now.
static func _format_duration(ticks: int) -> String:
	return "%.1fs" % (float(ticks) / float(CG.TICKS_PER_SECOND))

## What the fight cost, without asking the player to count bars themselves:
## how many of the player's own party made it out.
func _cost_summary() -> String:
	var alive := 0
	var total := 0
	for u in state.units:
		# PLAYTEST-NOTES 21: a siege engine (or any other mid-fight summon --
		# _spawn_summon builds it via _build_enemy_unit, same as an enemy,
		# only on the caster's team) is a player-team unit built from an
		# EnemyDef, so it carries a real enemy_id. A party pawn never does
		# (CombatSim.build sets .pawn instead and leaves enemy_id at its
		# default &""). "3 of 4 survived" is a count of the party the player
		# actually picked; a summon was never one of the four and should not
		# move either number.
		if u.team != CG.Team.PLAYER or u.enemy_id != &"":
			continue
		total += 1
		if u.hp > 0:
			alive += 1
	if alive == total:
		return "Your whole party survived."
	elif alive == 0:
		return "None of your party survived."
	return "%d of %d survived." % [alive, total]

## Issue 43: height reserved for the info row (labels only, no touch
## target requirement) now that it is split from the controls row below
## it. Matches Palette.FONT_SIZE_BODY's natural line height closely enough
## that the two rows don't visibly overlap; not exact since Label sizes
## itself from font metrics, not this constant, but this only positions
## the *next* row, so a few pixels of slack costs nothing.
const _INFO_ROW_HEIGHT := 28.0
const _SUMMARY_ROW_TOP := Palette.SPACE_M * 2.0 + _INFO_ROW_HEIGHT + Palette.SPACE_S + Palette.TOUCH_TARGET_MIN
const _SUMMARY_ROW_HEIGHT := 20.0
const _SUMMARY_BAR_WIDTH := 120.0

## One "<Label> [======    ]" row: a Label plus a back/fill ColorRect pair.
## Returns the fill rect so _update_team_summary can resize it later.
## One fixed label width so both troughs begin at the same x. Issue 82: without
## it the two bars start in different places and cannot be compared by eye,
## which is the only thing they exist for.
const _SUMMARY_LABEL_WIDTH := 64.0

func _build_summary_bar(parent: Container, label_text: String, color: Color) -> ColorRect:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(_SUMMARY_LABEL_WIDTH, 0.0)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	row.add_child(label)

	var back := ColorRect.new()
	back.color = Palette.HP_BACK
	back.custom_minimum_size = Vector2(_SUMMARY_BAR_WIDTH, _SUMMARY_ROW_HEIGHT)
	row.add_child(back)

	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2.ZERO
	fill.size = Vector2(_SUMMARY_BAR_WIDTH, _SUMMARY_ROW_HEIGHT)
	back.add_child(fill)

	return fill

## "Are we winning" answerable without parsing seven small bars — issue 15's
## first failure. Total hp_max is each side's starting capacity; total hp
## (0 for a dead unit, not removed from the total) is what is left of it, so
## the bar reads as "how much of this side's health is gone", the same
## reading a single unit's own hp bar gives.
func _update_team_summary() -> void:
	if state == null or _party_summary_fill == null:
		return
	_party_summary_fill.size.x = _SUMMARY_BAR_WIDTH * _team_hp_fraction(CG.Team.PLAYER)
	_enemy_summary_fill.size.x = _SUMMARY_BAR_WIDTH * _team_hp_fraction(CG.Team.ENEMY)

func _team_hp_fraction(team: CG.Team) -> float:
	var total := 0
	var current := 0
	for u in state.units:
		if u.team != team:
			continue
		total += u.hp_max
		current += maxi(u.hp, 0)
	if total <= 0:
		return 0.0
	return float(current) / float(total)

## World-space room added around the arena's own bounds when fitting it to
## the viewport.
##
## This used to be a large fixed *screen-pixel* reservation sized to clear
## the HUD strip and the whole log panel, which insets the *rect* rather than
## the *fit*: at 1280x720 it shrank the arena to roughly 600x340, about 22%
## of the screen, most of it empty. rook caught this from
## Screenshots/readability_log_and_labels_1.png. The fix is to expand what
## gets fit — the arena plus this margin — rather than shrink the space it's
## fit into: the arena now fills essentially the whole viewport, and the HUD
## and the combat log overlay it as thin/translucent strips instead of
## displacing it. World-space, not screen-pixel, so the margin scales with
## the arena instead of eating a fixed chunk regardless of zoom.
##
## Sized to the actual worst case a unit draws at its own position, per
## UnitView's stack (BAR_GAP/BAR_HEIGHT/FONT_SIZE_SMALL, all Palette's
## phone-scale values now): radius(22) + gap + resource bar + gap + hp bar +
## gap + name text + its chip padding, roughly 90 above; radius + status-tag
## text + its chip below, roughly 70; radius + half a bar width to the sides,
## roughly 45. Verified against units placed at the *literal* simulated
## corner (Screenshots/edges_1280x720.png) — the same trap issue 6 hit,
## caught again here before it merged this time.
##
## Issue 31: that whole stack now draws at UnitViewScript.DISPLAY_SCALE, so
## the margin sized to its worst case has to grow with it or the claim above
## stops being true — caught on a real launch: a party pawn near the top of
## its deploy column had its name label land inside the HUD's own summary
## row, which the margin exists specifically to prevent. World-space, so
## this trades a little of DISPLAY_SCALE's own gain for headroom (a bigger
## fit box means a slightly smaller scale_factor) rather than reopening the
## clipping bug this margin was built to fix.
const _MARGIN_TOP := 150.0 * UnitViewScript.DISPLAY_SCALE
const _MARGIN_BOTTOM := 70.0 * UnitViewScript.DISPLAY_SCALE
const _MARGIN_SIDE := 45.0 * UnitViewScript.DISPLAY_SCALE

## Issue 18, criterion 2 ("in portrait the arena is at least half the
## height, measured") turns out to be geometrically impossible to satisfy
## without cropping the arena horizontally, given a 16:9 arena, uniform
## scaling, and window/stretch/mode canvas_items + expand pinning
## get_viewport_rect()'s width to the design width on a narrower-than-design
## window. Measured on a real 390x844 launch: reported viewport (1280, 2770).
## I tried making the arena's own height reach 50% of that (scale ~2.56) and
## it works exactly as arithmetic — and it pushes the arena to ~2462 logical
## units wide against a visible width of 1280, cropping symmetrically at
## both edges. On the actual encounter's spawn layout that crop hid the
## *entire player party*, which is a worse failure than a small arena: see
## the finding in TEAM_LOG rather than shipped here. Kept the safe, fully-
## visible fit; flagging the conflict for rook rather than silently picking
## a side of it.
func _layout_arena() -> void:
	if _arena == null:
		return
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var layout := compute_layout(size)
	_arena.position = layout.position
	_arena.scale = layout.scale
	if _combat_log != null:
		_combat_log.set_landscape(size.x >= size.y)

## Split out from _layout_arena so the fit math can be checked without a
## live viewport — Godot only gives get_viewport_rect() a real answer inside
## a tree, which is exactly what made the canvas_items/expand behaviour this
## depends on (see the const comments above) hard to pin down without
## launching real processes at real resolutions in the first place.
## Issue 26, item 2 first put the log's reservation into this fit: it is a
## fixed *screen-pixel* strip, not a world-space margin, and did not scale
## with the arena the way _MARGIN_BOTTOM does, so a bottom-docked log at
## ordinary scale factors used to draw over units _MARGIN_BOTTOM (issue 8)
## never actually cleared. Issue 29 moves the strip from the bottom to the
## side in landscape: rook's own measurement was that fixing the overlap by
## eating vertical space cost the arena down to about a quarter of the
## screen, and a 16:9 arena in a wider-than-16:9 window already leaves side
## margins it can never use — reserving CombatLogView.LOG_WIDTH from the
## width instead costs nothing the arena could have used anyway.
##
## Portrait keeps the original bottom reservation, on purpose: width is
## portrait's scarce dimension, not height, so a side column costs far more
## there than a thin bottom strip does. Applying the side reservation
## unconditionally was tried and measured first — it dropped the pinned
## portrait height fraction under its own regression floor, confirming the
## two orientations need two different answers. CombatLogView.set_landscape
## keeps what's actually drawn in sync with this same rule.
static func compute_layout(size: Vector2) -> Dictionary:
	var fit_half_width := CG.ARENA_HALF_WIDTH + _MARGIN_SIDE
	var fit_top := CG.ARENA_HALF_HEIGHT + _MARGIN_TOP
	var fit_bottom := CG.ARENA_HALF_HEIGHT + _MARGIN_BOTTOM
	var fit_width := fit_half_width * 2.0
	var fit_height := fit_top + fit_bottom

	# Floors of 1.0, not fit_width/fit_height: those are world-space
	# quantities (the divisors used to compute scale_factor below) and
	# usable_width/usable_height are screen pixels — comparing them was a
	# real bug caught by this file's own regression test the first time
	# this reservation was added, at plain 1280x720. The floor only exists
	# so a viewport narrower/shorter than the log strip itself does not
	# divide by zero.
	var usable_size: Vector2
	if size.x >= size.y:
		usable_size = Vector2(max(size.x - CombatLogView.LOG_WIDTH, 1.0), size.y)
	else:
		usable_size = Vector2(size.x, max(size.y - CombatLogView.LOG_HEIGHT, 1.0))
	var scale_factor: float = min(usable_size.x / fit_width, usable_size.y / fit_height)
	var box := Vector2(fit_width, fit_height) * scale_factor
	var offset := (usable_size - box) * 0.5
	return {
		"position": offset + Vector2(fit_half_width, fit_top) * scale_factor,
		"scale": Vector2(scale_factor, scale_factor),
	}

func begin(cfg: RunConfig) -> void:
	begin_with_encounter(cfg, Registry.get_encounter(cfg.encounter_id))

## Issue 19: the level editor needs to test-fight a room that has never been
## registered — it exists only as an in-memory `Encounter` the player is still
## placing enemies and terrain into, with nothing to hand `Registry` and no
## `encounter_id` naming it yet. Split out of `begin()` so that path skips the
## `Registry` lookup entirely rather than requiring one: `cfg.encounter_id` is
## simply not read here. `begin()` is unchanged for every existing caller.
func begin_with_encounter(cfg: RunConfig, encounter) -> void:
	config = cfg
	state = CombatSim.build(cfg.party, encounter, cfg.seed)
	event_cursor = 0
	_tick_accumulator = 0.0
	set_paused(false)
	_rebuild_units()
	# Issue 26 item 1: the room's terrain, if any — CombatState.terrain is
	# empty by default, so a fight built without one draws exactly as it
	# did before this.
	_arena.terrain = state.terrain
	_arena.projectiles = []
	_arena.queue_redraw()
	if _combat_log != null:
		_combat_log.clear_log()
	_party_label.text = "Party: " + ", ".join(cfg.party.map(func(p): return p.display_name))
	_encounter_label.text = encounter.display_name if encounter != null and encounter.display_name != "" else String(cfg.encounter_id)
	_seed_label.text = "Seed " + cfg.seed_text()
	_outcome_label.text = ""
	_end_banner.visible = false
	_update_team_summary()
	set_process(true)

func set_paused(p: bool) -> void:
	paused = p
	if _pause_button != null:
		_pause_button.text = "Resume" if paused else "Pause"
	if _pause_dim != null:
		_pause_dim.visible = paused

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		set_paused(not paused)
		if is_inside_tree():
			get_viewport().set_input_as_handled()

func _rebuild_units() -> void:
	for child in _arena.get_children():
		child.queue_free()
	_unit_views.clear()
	_ensure_unit_views()

## Issue 75. `_rebuild_units` has exactly one call site, at fight start, so it
## builds one view per unit in `state.units` *at that instant*. A unit appended
## mid-fight -- CombatSim's summon path is generic (`ActionDef.summons_unit_id`,
## either team), so this is every summon and not one class's bug -- never got a
## view node at all. It fought, dealt and took damage, and died entirely
## invisibly. That is the real cause of "siege engines are still invisible";
## the silhouette rook added was necessary and nowhere near sufficient.
##
## Called every stepped tick, and it only ever *adds*. Rebuilding the whole set
## per tick would be the obvious wrong fix: every UnitView carries per-instance
## state that only means anything across ticks (`_label_last_active_tick`,
## `_last_seen_hp`/`_last_seen_resource`), so a fresh node each tick would
## reset the label hysteresis every frame and bring back exactly the name
## flicker PLAYTEST-NOTES 20 was about.
##
## Nothing here removes a view for a dead unit: `CombatState.units` never
## shrinks (death sets `alive` false and `sync` hides the node), so a removal
## branch would be code for a case that cannot happen.
func _ensure_unit_views() -> void:
	if state == null:
		return
	for u in state.units:
		if _unit_views.has(u.id):
			continue
		var view := Node2D.new()
		view.set_script(UnitViewScript)
		_arena.add_child(view)
		view.bind(state, u.id)
		_unit_views[u.id] = view

## Spends wall-clock delta in whole ticks. Frame rate must not change how fast
## the fight plays: a slow frame catches up by stepping several ticks at once
## rather than the view quietly drifting into slow motion.
func _process(delta: float) -> void:
	if state == null or state.outcome != CombatState.Outcome.UNRESOLVED:
		return
	if paused:
		return

	_tick_accumulator += delta
	var stepped := false
	while _tick_accumulator >= CG.TICK_SECONDS and state.outcome == CombatState.Outcome.UNRESOLVED:
		_tick_accumulator -= CG.TICK_SECONDS
		CombatSim.step(state)
		stepped = true

	if not stepped:
		return

	consume_events()
	# Issue 75: before syncing, not after -- a unit summoned this tick has to
	# get its node in the same frame it starts existing, or the first thing a
	# player sees of a summon is a health bar that was already there.
	_ensure_unit_views()
	for id in _unit_views:
		_unit_views[id].sync(state)
	# Issue 18's real travelling shots (CombatState.projectiles) have per-tick
	# positions; the arena needs the live array and a redraw every stepped
	# tick, the same as terrain gets it once at begin() -- terrain never
	# moves, this does. See ArenaFloor.gd's own doc comment.
	_arena.projectiles = state.projectiles
	_arena.queue_redraw()
	_update_team_summary()
	if state.outcome != CombatState.Outcome.UNRESOLVED:
		_show_outcome()
		set_process(false)

## Drains the events the simulation emitted since the last frame and turns them
## into floating numbers and log lines.
func consume_events() -> void:
	if state == null:
		return
	var events := state.events_since(event_cursor)
	event_cursor = state.events.size()
	for e in events:
		if _combat_log != null:
			_combat_log.append_event(state, e)
		if e.kind == CG.EventKind.DAMAGE or e.kind == CG.EventKind.HEAL:
			_spawn_floater(e)
			_spawn_impact_flash(e)
		elif e.kind == CG.EventKind.DEATH:
			_spawn_death_marker(e)
		elif e.kind == CG.EventKind.MISS:
			_spawn_miss_marker(e)
		elif e.kind == CG.EventKind.INTERRUPTED:
			_spawn_interrupt_flash(e)

## Issue 26 item 3: in a scrum, several floating numbers (or a death marker
## alongside one) used to spawn at the literal same point and read as one
## garbled string — Tools/preview/fight_04.png had "Cultist dies", a
## floating 2 and a unit label all occupying the same pixels. Floaters are
## transient (0.9-1.8s) so a live count of nearby siblings at spawn time is
## enough: each new one spreads a step further from whichever are already
## there rather than landing on top of them. Deterministic by spawn order
## within a frame, not by anything read off CombatState, so it changes
## nothing about what a player can infer from position.
## Issue 31: scaled by UnitViewScript.DISPLAY_SCALE alongside the units
## themselves, so a floater's stagger step keeps the same visual relationship
## to a body that just got bigger, rather than several numbers crowding a
## gap sized for the old, smaller sprite.
const _FLOATER_STAGGER_RADIUS := 40.0 * UnitViewScript.DISPLAY_SCALE
const _FLOATER_STAGGER_STEP := 18.0 * UnitViewScript.DISPLAY_SCALE

func _floater_stagger_offset(base_position: Vector2) -> Vector2:
	var count := 0
	for child in _arena.get_children():
		if child.get_script() == DamageFloaterScript and child.position.distance_to(base_position) < _FLOATER_STAGGER_RADIUS:
			count += 1
	if count == 0:
		return Vector2.ZERO
	var side := 1.0 if count % 2 == 1 else -1.0
	var step := float((count + 1) / 2) * _FLOATER_STAGGER_STEP
	return Vector2(side * step, 0.0)

## Issue 136: off by default, and the guard is here rather than at the call site
## so nothing can spawn a damage number without passing it.
##
## **This is the first thing anyone has proposed removing from this screen.**
## swift measured 861 of 1556 damage events in a real fight as damage-over-time
## ticks -- a drain rather than a happening -- so most floaters were never hits
## at all, and the log already carries every one with source, target, type and
## mitigated-versus-raw. Nothing is lost by the default.
##
## Death markers, miss markers and impact flashes are deliberately NOT behind
## this. They mark events a player has no other way to see at the moment they
## happen; a damage number duplicates a log line.
func _spawn_floater(e: CombatEvent) -> void:
	if not DisplayOptions.enabled(&"damage_numbers"):
		return
	var target := state.unit(e.target_id)
	if target == null:
		return
	var floater := Node2D.new()
	floater.set_script(DamageFloaterScript)
	_arena.add_child(floater)
	floater.position = target.position + _floater_stagger_offset(target.position)
	var color := Palette.damage_color(e.damage_type) if e.kind == CG.EventKind.DAMAGE else Palette.HP_FULL
	floater.show_amount(e.amount, color, int(round(Palette.FONT_SIZE_FLOATER * UnitViewScript.DISPLAY_SCALE)))

## PLAYTEST-NOTES 4 / PR #69 (sable, Scripts/Art/AttackFX.gd): "every class
## needs an attack asset ... so I know what's up" — melee had nothing but a
## number appearing where DamageFloater already stood in for a hit landing.
## Same event, same target position, same e.damage_type the floater above
## already reads two lines up — no new lookup.
func _spawn_impact_flash(e: CombatEvent) -> void:
	var target := state.unit(e.target_id)
	if target == null:
		return
	var flash := Node2D.new()
	flash.set_script(ImpactFlashScript)
	_arena.add_child(flash)
	flash.position = target.position
	flash.flash(e.damage_type, UnitViewScript.display_radius(target))

## Issue 151, and the player asked for it twice over: "the stun icon should
## appear and the unit should flash white or something". The badge is already
## drawn by UnitView from the STATUS_APPLIED on the same tick and says WHAT
## happened; this says it happened NOW, which is the half a badge cannot do for
## someone watching without pausing.
##
## `source_id`, not `target_id` -- INTERRUPTED names the unit that LOST the
## action, and `target_id` is -1 on this kind. Passing it to the damage-shaped
## helpers above would silently flash nothing.
##
## White rather than a damage colour: an interrupt is not damage and has no
## damage type, and borrowing one would put a lie into the vocabulary the
## floating numbers and the projectile marks share.
##
## NOT behind the damage_numbers option, for the same reason death and miss
## markers are not: it marks something a player has no other way to see at the
## moment it happens.
func _spawn_interrupt_flash(e: CombatEvent) -> void:
	var unit := state.unit(e.source_id)
	if unit == null:
		return
	var flash := Node2D.new()
	flash.set_script(ImpactFlashScript)
	_arena.add_child(flash)
	flash.position = unit.position
	flash.flash_color(Palette.TEXT, UnitViewScript.display_radius(unit))

## A death lands as an event, not as a unit quietly disappearing: named text
## rising from where the unit fell, on screen noticeably longer than a damage
## number. Offset above the unit's own position: the killing blow's DAMAGE
## event fires the same tick and spawns a floater starting at that exact
## point, and the two must not spawn on top of each other and read as one
## garbled string.
const _DEATH_MARKER_OFFSET := Vector2(0.0, -22.0) * UnitViewScript.DISPLAY_SCALE

func _spawn_death_marker(e: CombatEvent) -> void:
	var target := state.unit(e.target_id)
	if target == null:
		return
	var marker := Node2D.new()
	marker.set_script(DamageFloaterScript)
	_arena.add_child(marker)
	marker.position = target.position + _DEATH_MARKER_OFFSET + _floater_stagger_offset(target.position)
	# Issue 187. Two changes, and the colour is a defect rather than a taste
	# call: this was `Palette.TEAM_ENEMY` for EVERY death, so **losing your own
	# pawn was announced in the enemy's colour.** Same class of mistake as
	# `HP_LOW` and `TEAM_ENEMY` being the same value on the health bars. The
	# dying unit's own team colour says whose death it was, which is information
	# the old version did not merely omit but actively got wrong.
	#
	# And smaller: a cold reader called this "looks like an error message", and
	# a second one found it overlapping the `Miss` text in large type over live
	# units. It is one event among many, not a banner.
	marker.show_text("%s dies" % target.display_name, Palette.team_color(target.team), 1.8,
		int(round(Palette.FONT_SIZE_SMALL * UnitViewScript.DISPLAY_SCALE)))

## "X's Y fires" with silence after it is what made a miss read as a broken
## game rather than a whiffed shot (issue 14's own finding). A quiet, dim
## "Miss" at the target — the same place a hit's damage number would have
## landed — says plainly that the action resolved and simply connected with
## nothing, using Palette.TEXT_DIM rather than a damage colour so it reads as
## "nothing happened" rather than as a fourth kind of hit.
func _spawn_miss_marker(e: CombatEvent) -> void:
	var target := state.unit(e.target_id)
	if target == null:
		return
	var marker := Node2D.new()
	marker.set_script(DamageFloaterScript)
	_arena.add_child(marker)
	marker.position = target.position + _floater_stagger_offset(target.position)
	# Issue 187: was `FONT_SIZE_FLOATER` -- 34 before the display scale, so
	# **51 pixels of "Miss" across the arena** at the same size as a damage
	# number, which is exactly why a cold reader read it as another overlapping
	# number until they squinted. A miss is the smallest event in the game: the
	# action resolved and connected with nothing. It should be the quietest mark
	# on the screen, not one of the loudest.
	marker.show_text("Miss", Palette.TEXT_DIM, DamageFloaterScript.LIFETIME_SECONDS,
		int(round(Palette.FONT_SIZE_SMALL * UnitViewScript.DISPLAY_SCALE)))

func _show_outcome() -> void:
	var verdict: String
	match state.outcome:
		CombatState.Outcome.PLAYER_WIN:
			verdict = "Victory"
		CombatState.Outcome.ENEMY_WIN:
			verdict = "Defeat"
		_:
			verdict = "Draw"
	var duration := _format_duration(state.tick)
	_outcome_label.text = "%s (%s)" % [verdict, duration]

	_end_outcome_label.text = verdict
	_end_outcome_label.add_theme_color_override("font_color",
		Palette.TEAM_PLAYER if state.outcome == CombatState.Outcome.PLAYER_WIN
		else Palette.TEAM_ENEMY if state.outcome == CombatState.Outcome.ENEMY_WIN
		else Palette.TEXT)
	_end_cost_label.text = "%s  ·  %s" % [_cost_summary(), duration]
	_end_banner.visible = true
