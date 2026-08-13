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
	backdrop.offset_bottom = Palette.SPACE_M * 2.0 + Palette.TOUCH_TARGET_MIN
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(backdrop)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.add_theme_constant_override("separation", int(Palette.SPACE_M))
	bar.offset_left = Palette.SPACE_M
	bar.offset_top = Palette.SPACE_M
	hud.add_child(bar)

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

	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.pressed.connect(func(): set_paused(not paused))
	bar.add_child(_pause_button)

	var restart_button := Button.new()
	restart_button.text = "Restart (same seed)"
	restart_button.pressed.connect(func(): restart_requested.emit())
	bar.add_child(restart_button)

	var back_button := Button.new()
	back_button.text = "Change party"
	back_button.pressed.connect(func(): back_requested.emit())
	bar.add_child(back_button)

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
const _MARGIN_TOP := 110.0
const _MARGIN_BOTTOM := 70.0
const _MARGIN_SIDE := 45.0

func _layout_arena() -> void:
	if _arena == null:
		return
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var fit_half_width := CG.ARENA_HALF_WIDTH + _MARGIN_SIDE
	var fit_top := CG.ARENA_HALF_HEIGHT + _MARGIN_TOP
	var fit_bottom := CG.ARENA_HALF_HEIGHT + _MARGIN_BOTTOM
	var fit_width := fit_half_width * 2.0
	var fit_height := fit_top + fit_bottom
	var scale_factor: float = min(size.x / fit_width, size.y / fit_height)
	var box := Vector2(fit_width, fit_height) * scale_factor
	var offset := (size - box) * 0.5
	_arena.position = offset + Vector2(fit_half_width, fit_top) * scale_factor
	_arena.scale = Vector2(scale_factor, scale_factor)

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

func _show_outcome() -> void:
	match state.outcome:
		CombatState.Outcome.PLAYER_WIN:
			_outcome_label.text = "Victory (%d ticks)" % state.tick
		CombatState.Outcome.ENEMY_WIN:
			_outcome_label.text = "Defeat (%d ticks)" % state.tick
		CombatState.Outcome.DRAW:
			_outcome_label.text = "Draw (%d ticks)" % state.tick
