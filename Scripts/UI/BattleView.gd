extends Node2D
class_name BattleView

const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")
const DisplayOptionsPanelScript := preload("res://Scripts/UI/DisplayOptionsPanel.gd")
const ImpactFlashScript := preload("res://Scripts/UI/ImpactFlash.gd")
const TeamStatusViewScript := preload("res://Scripts/UI/TeamStatusView.gd")

## Draws one fight and steps it. Reads CombatState and CombatEvent only; it
## never asks the simulation to do anything except step.

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
var _team_status: Control = null

var _party_summary_fill: ColorRect = null
var _enemy_summary_fill: ColorRect = null

var _end_banner: Control = null
var _end_outcome_label: Label = null
var _end_cost_label: Label = null
var _inspect_panel = null

var _pause_dim: ColorRect = null
var _end_dim: ColorRect = null

func _ready() -> void:
	_arena = get_node("Arena")
	_combat_log = get_node("Hud/CombatLog")
	_build_pause_dim()
	_build_top_bar()
	_build_team_status()
	_build_end_banner()
	# Guarded so a test can call _ready() directly on an instantiated-but-not-
	# added scene to reach the HUD nodes begin() needs, without a live viewport.
	if is_inside_tree():
		_layout_arena()
		get_viewport().size_changed.connect(_layout_arena)

## PLAYTEST-NOTES-2 item 5: "pause needs to be obvious -- grey the screen
## or similar. Nothing currently indicates it."
func _build_pause_dim() -> void:
	_pause_dim = _build_dim(0.55)

## A full-screen dim that reads as "the fight is held" without taking the
## screen's words with it. Moved to the front of Hud's child order, so the log,
## the toolbar and the team panel all draw over it and stay fully legible --
## reading the log is the reason to pause or to look at a Victory screen at all
## (issue 343). `CombatLog` is a scene child and is therefore already Hud's
## first, which is why this needs move_child rather than being added early.
func _build_dim(alpha: float) -> ColorRect:
	var hud := get_node("Hud")
	var dim := ColorRect.new()
	dim.color = Palette.BACKGROUND
	dim.color.a = alpha
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	hud.add_child(dim)
	hud.move_child(dim, 0)
	return dim

func _build_top_bar() -> void:
	var hud := get_node("Hud")

	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.color.a = 0.72
	backdrop.set_anchors_preset(Control.PRESET_TOP_WIDE)
	backdrop.offset_bottom = _TOP_BAR_BOTTOM
	backdrop.offset_right = CombatLogView.LOG_MARGIN - TeamStatusViewScript.PANEL_WIDTH
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(backdrop)

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

	_encounter_label = Label.new()
	_encounter_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	bar.add_child(_encounter_label)

	_seed_label = Label.new()
	_seed_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	bar.add_child(_seed_label)

	_outcome_label = Label.new()
	_outcome_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_outcome_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	bar.add_child(_outcome_label)

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

	var view_button := Button.new()
	view_button.text = "What to show"
	view_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	view_button.pressed.connect(func(): _display_options.toggle_visible())
	controls.add_child(view_button)

	var plans_button := Button.new()
	plans_button.text = "Plans"
	plans_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	plans_button.pressed.connect(_on_inspect_pressed)
	controls.add_child(plans_button)

	_display_options = Control.new()
	_display_options.set_script(DisplayOptionsPanelScript)
	hud.add_child(_display_options)
	if not _display_options.is_inside_tree():
		_display_options._ready()
	# Under the control row it belongs to. Issue 145 taught me to add_child
	# before any manual _ready(), or the engine runs a second one.
	_display_options.position = Vector2(Palette.SPACE_M, _SUMMARY_ROW_TOP + _INFO_ROW_HEIGHT + Palette.SPACE_M)
	_display_options.changed.connect(_rebuild_log)

## Issue 319. A log filter that only applies from now on cannot answer "what
## killed my Siege Master", which is the question the ground ticks exist for, so
## turning one on re-reads every event this fight has already produced.
func _rebuild_log() -> void:
	if _combat_log == null or state == null:
		return
	_combat_log.clear_log()
	for i in mini(event_cursor, state.events.size()):
		_combat_log.append_event(state, state.events[i])

## Issue 113: the player's whole team, in a fixed place, above the log.
func _build_team_status() -> void:
	var hud := get_node("Hud")
	_team_status = Control.new()
	_team_status.set_script(TeamStatusViewScript)
	hud.add_child(_team_status)
	if not _team_status.is_inside_tree():
		_team_status._ready()
	_team_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_team_status.offset_right = CombatLogView.LOG_MARGIN
	_team_status.offset_left = CombatLogView.LOG_MARGIN - TeamStatusViewScript.PANEL_WIDTH
	_team_status.offset_top = _PANEL_TOP
	_team_status.offset_bottom = _PANEL_TOP + TeamStatusViewScript.MAX_PANEL_HEIGHT

## Where the top bar's backdrop ends. Still the bar's own height; the panel no
## longer sits under it.
const _TOP_BAR_BOTTOM := _SUMMARY_ROW_TOP + _SUMMARY_ROW_HEIGHT + Palette.SPACE_S

const _PANEL_TOP := Palette.SPACE_M

## Issue 19: the outcome is the payoff of the whole fight and used to show as
## a small toolbar label -- same weight as "Seed 0000002A". This is the
## prominent version: a full-screen backdrop shown only once the fight
## actually resolves (built hidden here, shown from _show_outcome, hidden
## again in begin()), so it cannot compete with anything mid-fight.
func _build_end_banner() -> void:
	var hud := get_node("Hud")

	## Issue 343. The backdrop used to be a full-screen ColorRect INSIDE the
	## banner, above every other Hud child: a blind playtester found Pause,
	## Restart, Change party, What to show and Plans all dead after Victory, and
	## the log neither readable nor scrollable, because one node was eating every
	## mouse event and painting over every word. It is now a sibling at the front
	## of the child order, and the banner itself does not take input -- only its
	## own buttons do.
	_end_dim = _build_dim(0.88)

	_end_banner = Control.new()
	_end_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_banner.visible = false
	hud.add_child(_end_banner)

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

	var inspect_button := Button.new()
	inspect_button.text = "Plans"
	inspect_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	inspect_button.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	inspect_button.pressed.connect(_on_inspect_pressed)
	buttons.add_child(inspect_button)

	_inspect_panel = InspectPanel.create()
	hud.add_child(_inspect_panel)
	if not _inspect_panel.is_inside_tree():
		_inspect_panel._ready()

func _on_inspect_pressed() -> void:
	if _inspect_panel != null and config != null:
		_inspect_panel.open(config.party, state)

## e.g. 197 ticks at 30 ticks/second reads as "6.6s" -- a player has never
## seen a tick, and won't start now.
static func _format_duration(ticks: int) -> String:
	return "%.1fs" % (float(ticks) / float(CG.TICKS_PER_SECOND))

## What the fight cost, without asking the player to count bars themselves:
## how many of the player's own party made it out.
func _cost_summary() -> String:
	var alive := 0
	var total := 0
	var fallen: Array[String] = []
	for u in state.units:
		# PLAYTEST-NOTES 21: a siege engine (or any other mid-fight summon --
		if u.team != CG.Team.PLAYER or u.enemy_id != &"":
			continue
		total += 1
		if u.hp > 0:
			alive += 1
		else:
			fallen.append(u.display_name)
	if alive == total:
		return "Your whole party survived."
	var count := "None of your party survived." if alive == 0 else "%d of %d survived." % [alive, total]
	return "%s  You lost %s." % [count, name_list(fallen)]

## Issue 320. "3 of 4 survived" named nobody, so the playtester restarted the
## fight with name plates on to work out which pawn was missing.
static func name_list(names: Array[String]) -> String:
	if names.size() <= 1:
		return "" if names.is_empty() else names[0]
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[-1]]

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

## "Are we winning" answerable without parsing seven small bars -- issue 15's
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
const _MARGIN_TOP := 150.0 * UnitViewScript.DISPLAY_SCALE
const _MARGIN_BOTTOM := 70.0 * UnitViewScript.DISPLAY_SCALE
const _MARGIN_SIDE := 45.0 * UnitViewScript.DISPLAY_SCALE

## Issue 18, criterion 2 ("in portrait the arena is at least half the
## height, measured") turns out to be geometrically impossible to satisfy
## without cropping the arena horizontally, given a 16:9 arena, uniform
## scaling, and window/stretch/mode canvas_items + expand pinning
## get_viewport_rect()'s width to the design width on a narrower-than-design
## window. Measured on a real 390x844 launch: reported viewport (1280, 2770).
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

## Where the log's box begins, so the team status panel above it can be checked
## against something measured rather than against a constant.
static func log_box_top(size: Vector2) -> float:
	return size.y + CombatLogView.LOG_MARGIN - CombatLogView.LOG_HEIGHT

## Split out from _layout_arena so the fit math can be checked without a
## live viewport -- Godot only gives get_viewport_rect() a real answer inside
## a tree, which is exactly what made the canvas_items/expand behaviour this
## depends on (see the const comments above) hard to pin down without
## launching real processes at real resolutions in the first place.
static func compute_layout(size: Vector2) -> Dictionary:
	var fit_half_width := CG.ARENA_HALF_WIDTH + _MARGIN_SIDE
	var fit_top := CG.ARENA_HALF_HEIGHT + _MARGIN_TOP
	var fit_bottom := CG.ARENA_HALF_HEIGHT + _MARGIN_BOTTOM
	var fit_width := fit_half_width * 2.0
	var fit_height := fit_top + fit_bottom

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
## registered -- it exists only as an in-memory `Encounter` the player is still
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
	_end_dim.visible = false
	_update_team_summary()
	if _team_status != null:
		_team_status.sync(state)
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

	_ensure_unit_views()
	consume_events()
	for id in _unit_views:
		_unit_views[id].sync(state)
	_arena.projectiles = state.projectiles
	_arena.queue_redraw()
	_update_team_summary()
	# Issue 113. Same place and same trigger as the unit views: "live means live"
	if _team_status != null:
		_team_status.sync(state)
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
## garbled string -- Tools/preview/fight_04.png had "Cultist dies", a
## floating 2 and a unit label all occupying the same pixels. Floaters are
## transient (0.9-1.8s) so a live count of nearby siblings at spawn time is
## enough: each new one spreads a step further from whichever are already
## there rather than landing on top of them. Deterministic by spawn order
## within a frame, not by anything read off CombatState, so it changes
## nothing about what a player can infer from position.
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
## needs an attack asset ... so I know what's up" -- melee had nothing but a
## number appearing where DamageFloater already stood in for a hit landing.
func _spawn_impact_flash(e: CombatEvent) -> void:
	var target := state.unit(e.target_id)
	if target == null:
		return
	var flash := Node2D.new()
	flash.set_script(ImpactFlashScript)
	_arena.add_child(flash)
	flash.position = target.position
	flash.follow(_unit_views.get(target.id))
	flash.flash(e.damage_type, UnitViewScript.display_radius(target))

## Issue 151, and the player asked for it twice over: "the stun icon should
## appear and the unit should flash white or something". The badge is already
## drawn by UnitView from the STATUS_APPLIED on the same tick and says WHAT
## happened; this says it happened NOW, which is the half a badge cannot do for
## someone watching without pausing.
func _spawn_interrupt_flash(e: CombatEvent) -> void:
	var unit := state.unit(e.source_id)
	if unit == null:
		return
	var flash := Node2D.new()
	flash.set_script(ImpactFlashScript)
	_arena.add_child(flash)
	flash.position = unit.position
	flash.follow(_unit_views.get(unit.id))
	flash.flash_color(Palette.TEXT, UnitViewScript.display_radius(unit))

## A death lands as an event, not as a unit quietly disappearing: named text
## rising from where the unit fell, on screen noticeably longer than a damage
## number. Offset above the unit's own position: the killing blow's DAMAGE
## event fires the same tick and spawns a floater starting at that exact
## point, and the two must not spawn on top of each other and read as one
## garbled string.
const _DEATH_MARKER_OFFSET := Vector2(0.0, -22.0) * UnitViewScript.DISPLAY_SCALE

## Issue 320. Several deaths in one scrum still printed over each other, because
## `_floater_stagger_offset` compares two points and the thing that collides is
## a plate as wide as "Abomination dies". Deaths stack into a column instead.
const _DEATH_STACK_RADIUS := 150.0 * UnitViewScript.DISPLAY_SCALE
const _DEATH_STACK_STEP := 26.0 * UnitViewScript.DISPLAY_SCALE

func _death_stack_offset(base_position: Vector2) -> Vector2:
	var count := 0
	for child in _arena.get_children():
		if child.get_script() == DamageFloaterScript and child.death_marker \
				and child.position.distance_to(base_position) < _DEATH_STACK_RADIUS:
			count += 1
	return Vector2(0.0, -_DEATH_STACK_STEP * float(count))

## The player's own pawns read larger than an enemy's: issue 320 is about not
## seeing your own party die, and four "Goblin dies" plates are the noise.
func _death_font_size(target) -> int:
	var base := Palette.FONT_SIZE_BODY if target.team == CG.Team.PLAYER else Palette.FONT_SIZE_SMALL
	return int(round(base * UnitViewScript.DISPLAY_SCALE))

func _spawn_death_marker(e: CombatEvent) -> void:
	var target := state.unit(e.target_id)
	if target == null:
		return
	var at := target.position + _DEATH_MARKER_OFFSET \
		+ _floater_stagger_offset(target.position) + _death_stack_offset(target.position)
	var marker := Node2D.new()
	marker.set_script(DamageFloaterScript)
	_arena.add_child(marker)
	marker.position = at
	marker.show_death("%s dies" % target.display_name, Palette.team_color(target.team),
		_death_font_size(target))

## "X's Y fires" with silence after it is what made a miss read as a broken
## game rather than a whiffed shot (issue 14's own finding). A quiet, dim
## "Miss" at the target -- the same place a hit's damage number would have
## landed -- says plainly that the action resolved and simply connected with
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
	marker.show_text("Miss", Palette.TEXT_DIM, DamageFloaterScript.LIFETIME_SECONDS,
		int(round(Palette.FONT_SIZE_SMALL * UnitViewScript.DISPLAY_SCALE)))

func _show_outcome() -> void:
	var verdict := outcome_word(state)
	var duration := _format_duration(state.tick)
	_outcome_label.text = "%s (%s)" % [verdict, duration]

	_end_outcome_label.text = verdict
	_end_outcome_label.add_theme_color_override("font_color",
		Palette.TEAM_PLAYER if verdict == "Victory"
		else Palette.TEAM_ENEMY if verdict == "Defeat"
		else Palette.TEXT)
	var reason := end_reason_sentence(state)
	_end_cost_label.text = "%s  ·  %s" % [_cost_summary(), duration]
	if reason != "":
		_end_cost_label.text = "%s\n%s" % [_end_cost_label.text, reason]
	_end_banner.visible = true
	_end_dim.visible = true

## Issue 218. **The banner used to contradict the line under it**: a fight where
## every pawn died and the siege engines finished the room off printed "Victory"
static func outcome_word(state: CombatState) -> String:
	if CombatSim.is_pawnless_win(state):
		return "Defeat"
	match state.outcome:
		CombatState.Outcome.PLAYER_WIN:
			return "Victory"
		CombatState.Outcome.ENEMY_WIN:
			return "Defeat"
	return "Draw"

## Issue 249: what finished the fight, in words, or "" when saying anything would
## add nothing.
static func end_reason_sentence(state: CombatState) -> String:
	if end_reason_of(state) != CG.EndReason.CANNOT_ACT:
		return ""
	if state.outcome == CombatState.Outcome.PLAYER_WIN:
		return "Nothing on the enemy's side could fight any more."
	if state.outcome == CombatState.Outcome.ENEMY_WIN:
		return "Nothing on your side could fight any more."
	return "Neither side could fight any more."

## The reason off the fight's own FIGHT_END event.
static func end_reason_of(state: CombatState) -> CG.EndReason:
	for i in range(state.events.size() - 1, -1, -1):
		if state.events[i].kind == CG.EventKind.FIGHT_END:
			return state.events[i].end_reason
	return CG.EndReason.UNSET
