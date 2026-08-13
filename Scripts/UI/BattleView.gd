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
var _seed_label: Label = null
var _outcome_label: Label = null
var _pause_button: Button = null

var _party_summary_fill: ColorRect = null
var _enemy_summary_fill: ColorRect = null

func _ready() -> void:
	_arena = get_node("Arena")
	_combat_log = get_node("Hud/CombatLog")
	_build_top_bar()
	# Guarded so a test can call _ready() directly on an instantiated-but-not-
	# added scene to reach the HUD nodes begin() needs, without a live viewport.
	if is_inside_tree():
		_layout_arena()
		get_viewport().size_changed.connect(_layout_arena)

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

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.add_theme_constant_override("separation", int(Palette.SPACE_M))
	bar.offset_left = Palette.SPACE_M
	bar.offset_top = Palette.SPACE_M
	hud.add_child(bar)

	# Issue 15: "you cannot tell who is winning" without parsing seven small
	# bars. Two aggregate bars answer that at a glance, colour-coded the same
	# way a single unit's own hp bar is.
	var summary := HBoxContainer.new()
	summary.set_anchors_preset(Control.PRESET_TOP_WIDE)
	summary.add_theme_constant_override("separation", int(Palette.SPACE_M))
	summary.offset_left = Palette.SPACE_M
	summary.offset_top = _SUMMARY_ROW_TOP
	hud.add_child(summary)
	_party_summary_fill = _build_summary_bar(summary, "Party", Palette.TEAM_PLAYER)
	_enemy_summary_fill = _build_summary_bar(summary, "Enemies", Palette.TEAM_ENEMY)

	_party_label = Label.new()
	_party_label.add_theme_color_override("font_color", Palette.TEXT)
	bar.add_child(_party_label)

	_seed_label = Label.new()
	_seed_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	bar.add_child(_seed_label)

	_outcome_label = Label.new()
	_outcome_label.add_theme_color_override("font_color", Palette.TEXT)
	_outcome_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING)
	bar.add_child(_outcome_label)

	# Issue 18 criterion 3: every control at least Palette.TOUCH_TARGET_MIN on
	# its short side. Unset, a Button's default minimum height (theme padding
	# around the font) comes in under 48 — not visible in a screenshot, only
	# by measuring, which is why the issue says to assert it rather than look.
	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	_pause_button.pressed.connect(func(): set_paused(not paused))
	bar.add_child(_pause_button)

	var restart_button := Button.new()
	restart_button.text = "Restart (same seed)"
	restart_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	restart_button.pressed.connect(func(): restart_requested.emit())
	bar.add_child(restart_button)

	var back_button := Button.new()
	back_button.text = "Change party"
	back_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	back_button.pressed.connect(func(): back_requested.emit())
	bar.add_child(back_button)

const _SUMMARY_ROW_TOP := Palette.SPACE_M * 2.0 + Palette.TOUCH_TARGET_MIN
const _SUMMARY_ROW_HEIGHT := 20.0
const _SUMMARY_BAR_WIDTH := 120.0

## One "<Label> [======    ]" row: a Label plus a back/fill ColorRect pair.
## Returns the fill rect so _update_team_summary can resize it later.
func _build_summary_bar(parent: HBoxContainer, label_text: String, color: Color) -> ColorRect:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
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
const _MARGIN_TOP := 150.0
const _MARGIN_BOTTOM := 70.0
const _MARGIN_SIDE := 45.0

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

## Split out from _layout_arena so the fit math can be checked without a
## live viewport — Godot only gives get_viewport_rect() a real answer inside
## a tree, which is exactly what made the canvas_items/expand behaviour this
## depends on (see the const comments above) hard to pin down without
## launching real processes at real resolutions in the first place.
static func compute_layout(size: Vector2) -> Dictionary:
	var fit_half_width := CG.ARENA_HALF_WIDTH + _MARGIN_SIDE
	var fit_top := CG.ARENA_HALF_HEIGHT + _MARGIN_TOP
	var fit_bottom := CG.ARENA_HALF_HEIGHT + _MARGIN_BOTTOM
	var fit_width := fit_half_width * 2.0
	var fit_height := fit_top + fit_bottom
	var scale_factor: float = min(size.x / fit_width, size.y / fit_height)
	var box := Vector2(fit_width, fit_height) * scale_factor
	var offset := (size - box) * 0.5
	return {
		"position": offset + Vector2(fit_half_width, fit_top) * scale_factor,
		"scale": Vector2(scale_factor, scale_factor),
	}

func begin(cfg: RunConfig) -> void:
	config = cfg
	var encounter = Registry.get_encounter(cfg.encounter_id)
	state = CombatSim.build(cfg.party, encounter, cfg.seed)
	event_cursor = 0
	_tick_accumulator = 0.0
	set_paused(false)
	_rebuild_units()
	if _combat_log != null:
		_combat_log.clear_log()
	_party_label.text = "Party: " + ", ".join(cfg.party.map(func(p): return p.display_name))
	_seed_label.text = "Seed " + cfg.seed_text()
	_outcome_label.text = ""
	_update_team_summary()
	set_process(true)

func set_paused(p: bool) -> void:
	paused = p
	if _pause_button != null:
		_pause_button.text = "Resume" if paused else "Pause"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		set_paused(not paused)
		if is_inside_tree():
			get_viewport().set_input_as_handled()

func _rebuild_units() -> void:
	for child in _arena.get_children():
		child.queue_free()
	_unit_views.clear()
	if state == null:
		return
	for u in state.units:
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
	for id in _unit_views:
		_unit_views[id].sync(state)
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
		elif e.kind == CG.EventKind.DEATH:
			_spawn_death_marker(e)
		elif e.kind == CG.EventKind.MISS:
			_spawn_miss_marker(e)

func _spawn_floater(e: CombatEvent) -> void:
	var target := state.unit(e.target_id)
	if target == null:
		return
	var floater := Node2D.new()
	floater.set_script(DamageFloaterScript)
	_arena.add_child(floater)
	floater.position = target.position
	var color := Palette.damage_color(e.damage_type) if e.kind == CG.EventKind.DAMAGE else Palette.HP_FULL
	floater.show_amount(e.amount, color)

## A death lands as an event, not as a unit quietly disappearing: named text
## rising from where the unit fell, on screen noticeably longer than a damage
## number. Offset above the unit's own position: the killing blow's DAMAGE
## event fires the same tick and spawns a floater starting at that exact
## point, and the two must not spawn on top of each other and read as one
## garbled string.
const _DEATH_MARKER_OFFSET := Vector2(0.0, -22.0)

func _spawn_death_marker(e: CombatEvent) -> void:
	var target := state.unit(e.target_id)
	if target == null:
		return
	var marker := Node2D.new()
	marker.set_script(DamageFloaterScript)
	_arena.add_child(marker)
	marker.position = target.position + _DEATH_MARKER_OFFSET
	marker.show_text("%s dies" % target.display_name, Palette.TEAM_ENEMY, 1.8, Palette.FONT_SIZE_BODY)

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
	marker.position = target.position
	marker.show_text("Miss", Palette.TEXT_DIM)

func _show_outcome() -> void:
	match state.outcome:
		CombatState.Outcome.PLAYER_WIN:
			_outcome_label.text = "Victory (%d ticks)" % state.tick
		CombatState.Outcome.ENEMY_WIN:
			_outcome_label.text = "Defeat (%d ticks)" % state.tick
		CombatState.Outcome.DRAW:
			_outcome_label.text = "Draw (%d ticks)" % state.tick
