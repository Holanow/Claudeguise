extends Node2D
class_name BattleView

const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")
const DisplayOptionsPanelScript := preload("res://Scripts/UI/DisplayOptionsPanel.gd")
const ImpactFlashScript := preload("res://Scripts/UI/ImpactFlash.gd")
const ImpactBurstScript := preload("res://Scripts/UI/ImpactBurst.gd")
const DeathExplosionScript := preload("res://Scripts/UI/DeathExplosion.gd")
const TeamStatusViewScript := preload("res://Scripts/UI/TeamStatusView.gd")
const DeployViewScript := preload("res://Scripts/UI/DeployView.gd")
const ArenaTextLayerScript := preload("res://Scripts/UI/ArenaTextLayer.gd")

## Draws one fight and steps it. Reads CombatState and CombatEvent only; it
## never asks the simulation to do anything except step.

signal restart_requested
signal back_requested
## Issue 591: the end card offers the other rooms. The id, not an index --
## #587 is turning rooms into scenes and an index would not survive it.
signal room_requested(encounter_id: StringName)
## Every accepted placement, so `Main` can replay the fight the player watched.
signal placement_changed(positions: Array[Vector2])

var state: CombatState = null
var event_cursor: int = 0
var config: RunConfig = null
var paused: bool = false

## Setup: the fight is built and held before its first tick, and the party is
## draggable. The player's ask -- place them on the screen you fight on.
var setup: bool = false

var _placements: Array[Vector2] = []
## The room WITHOUT the player's placement, so Reset has something to go back to.
var _base_encounter = null
var _deploy_band: Node2D = null
var _unit_layer: Node2D = null
var _bursts: Node2D = null
## Issue 589. The chunks a dead body comes apart into, out of one fixed pool.
var _gibs: Node2D = null
var _text_layer: Node2D = null
var _setup_hint: Label = null
var _reset_button: Button = null

var _grabbed_unit_id: int = -1
var _press_world: Vector2 = Vector2.ZERO
var _drag_moved: bool = false

var _tick_accumulator: float = 0.0

## Issue 501. Where every body and every shot sat on either side of the last
## tick. The display draws 60 times a second and the simulation moves 15, so
## without these three of every four frames are a repeat and the fourth jumps.
var _prev_drawn: Dictionary = {}
var _curr_drawn: Dictionary = {}
var _prev_shots: Dictionary = {}
var _curr_shots: Dictionary = {}

## Issue 515. How long the presentation holds still on a death. Six frames on a
## 60Hz display, a beat and a half of simulation.
const HIT_STOP_SECONDS := 0.10

## Seconds of that hold still to run. Real delta is DROPPED while this is above
## zero, never banked: an accumulator that accrued through the freeze would repay
## every frozen frame as a lurch the moment it released.
var _freeze_left: float = 0.0

## Issue 518. Both halves of a death cue under one clock: how long the arena
## shakes for, and how far it may travel at the worst of it.
const SHAKE_OPTION := &"screen_shake"
const SHAKE_SECONDS := 0.18
const SHAKE_PIXELS := 5.0 * UnitViewScript.DISPLAY_SCALE
## The drawn half-width that earns the whole amplitude. The Rat King, measured;
## a goblin archer is 9.6 of it and shakes the screen just over a quarter as far.
const SHAKE_FULL_BODY := 36.0
## How many times the arena crosses its rest position before it settles.
const SHAKE_CYCLES := 2.5

var _shake_age: float = INF
var _shake_amplitude: float = 0.0
## Where `_layout_arena` put the arena. The shake is written on top of it and
## must land back on it exactly, so it cannot be read off `_arena.position`.
var _arena_base: Vector2 = Vector2.ZERO

var _arena: Node2D = null
var _combat_log = null
var _unit_views: Dictionary = {}
var _vfx: VFXDirector = null

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
var _end_prompt_label: Label = null
var _inspect_panel = null

var _pause_dim: ColorRect = null
var _end_dim: ColorRect = null
var _end_screen: EndScreen = null

var _sound = null

var _unit_card: UnitCard = null
var _click_hint: Label = null
## Whether the pause currently in force is one a unit click put there, so
## closing the card gives the fight back only when the card took it.
var _card_owns_pause: bool = false

func _ready() -> void:
	ViewClock.frozen = false
	_arena = get_node("Arena")
	_combat_log = get_node("Hud/CombatLog")
	# The same guard the other Hud children already carry: a test instantiates
	# this scene and calls _ready() without ever entering a tree, where the
	# engine never fires a child's own -- so the log stayed a bare Control and
	# its mouse_filter, its label and its backdrop did not exist.
	if not _combat_log.is_inside_tree():
		_combat_log._ready()
	_build_pause_dim()
	_build_top_bar()
	_build_team_status()
	_build_end_banner()
	_build_unit_card()
	_build_sound()
	# Guarded so a test can call _ready() directly on an instantiated-but-not-
	# added scene to reach the HUD nodes begin() needs, without a live viewport.
	if is_inside_tree():
		_layout_arena()
		get_viewport().size_changed.connect(_layout_arena)

## Issue 550. The voices live under one child so the tree stays readable, and
## `SoundBank` decides which events are audible -- this end of it only hands it
## the whole stream, exactly as the combat log is handed the whole stream.
func _build_sound() -> void:
	var holder := Node.new()
	holder.name = "Sound"
	add_child(holder)
	_sound = SoundBank.attach(holder)

## Read-only, for tools that measure the bank rather than drive it.
func sound_bank():
	return _sound

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
	_pause_button.pressed.connect(_on_pause_pressed)
	controls.add_child(_pause_button)

	## Getting back to where you started has to be one press: the deploy screen's
	## own rule, kept. It is the only undo placement has.
	_reset_button = Button.new()
	_reset_button.text = "Reset placement"
	_reset_button.custom_minimum_size.y = Palette.TOUCH_TARGET_MIN
	_reset_button.pressed.connect(reset_placement)
	_reset_button.visible = false
	controls.add_child(_reset_button)

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
	view_button.pressed.connect(_on_view_options_pressed)
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
	_display_options.position = Vector2(Palette.SPACE_M, _TOP_BAR_BOTTOM + Palette.SPACE_M)
	_display_options.changed.connect(_rebuild_log)

## The hint sits at the bottom of the arena band and the options panel and the
## plans screen both open across it, so one of them has to give and it is not
## them. Issue 428: the plans screen's fallback row and this hint printed
## through each other at y~688.
func _sync_click_hint() -> void:
	if _click_hint == null:
		return
	var covered := (_display_options != null and _display_options.visible)
	covered = covered or (_inspect_panel != null and _inspect_panel.visible)
	## Issue 552: the end card's buttons stand on the same pixels, and "click any
	## unit" is advice about a fight that is over.
	covered = covered or (_end_banner != null and _end_banner.visible)
	# The setup hint stands on the same pixels and is the one a player needs first.
	covered = covered or setup
	_click_hint.visible = not card_discovered and not covered

func _on_view_options_pressed() -> void:
	_display_options.toggle_visible()
	_sync_click_hint()

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
## Issue 396: this counted ONE summary row while two are drawn, so the backdrop
## stopped 20px above the Enemies bar and the "What to show" panel opened on top
## of it.
const _TOP_BAR_BOTTOM := _SUMMARY_ROW_TOP + 2.0 * _SUMMARY_ROW_HEIGHT + Palette.SPACE_XS + Palette.SPACE_S

const _PANEL_TOP := Palette.SPACE_M

## Issue 19: the outcome is the payoff of the whole fight and used to show as
## a small toolbar label -- same weight as "Seed 0000002A". This is the
## prominent version: a full-screen backdrop shown only once the fight
## actually resolves (built hidden here, shown from _show_outcome, hidden
## again in begin()), so it cannot compete with anything mid-fight.
## How wide the end card's prose is allowed to run before it wraps, and the
## floor below which wrapping it further would be worse than the overlap.
const _END_TEXT_WIDTH := 440.0
const _END_TEXT_MIN := 200.0

## Issue 616: the button row's own height plus the margin above and below it,
## reserved out of the column's rect so Restart, Change party and Plans sit at
## a fixed distance from the bottom of the window rather than after whatever
## height the card above them adds up to.
const _END_BUTTON_ROW_RESERVED := Palette.TOUCH_TARGET_MIN + 2.0 * Palette.SPACE_M

## The card's prose is centred and the team panel is pinned to the right, so
## the prose may be at most twice the gap from the screen's centre to the
## panel's left edge (issue 442). Static and taking the size, like
## `compute_layout`, so the fit can be checked without a live viewport.
static func end_text_width(size: Vector2) -> float:
	var panel_left := size.x + CombatLogView.LOG_MARGIN - TeamStatusView.PANEL_WIDTH
	return clampf(panel_left * 2.0 - size.x, _END_TEXT_MIN, _END_TEXT_WIDTH)

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

	## Issue 552: centred in what is LEFT of the window, not in the window. The
	## card grew from a paragraph to a roster and a log, so a centred column runs
	## its heading and its cost line through the toolbar's buttons.
	##
	## Issue 616: Restart, Change party and Plans used to live in this same
	## column, so a card too tall to fit (a fourth line of prose) pushed them
	## off the bottom of the window with it. They are now a separate control
	## pinned to the bottom of the banner (`_build_end_buttons` below); the
	## column stops short of it instead of running underneath.
	var column := VBoxContainer.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.offset_top = _SUMMARY_ROW_TOP
	column.offset_bottom = -_END_BUTTON_ROW_RESERVED
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.clip_contents = true
	## Issue 552: a container defaults to MOUSE_FILTER_STOP, and this one grew
	## from a paragraph to a roster. It covered Change party and Plans -- issue
	## 343's defect exactly, in a node that was too small to show it before.
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", int(Palette.SPACE_S))
	_end_banner.add_child(column)

	_end_outcome_label = Label.new()
	_end_outcome_label.add_theme_color_override("font_color", Palette.TEXT)
	## Issue 552: was HEADING * 2, which no longer fits above a roster and a log.
	_end_outcome_label.add_theme_font_size_override("font_size", int(Palette.FONT_SIZE_HEADING * 1.15))
	_end_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_outcome_label)

	_end_cost_label = Label.new()
	_end_cost_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_end_cost_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_end_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	## Issue 442: the casualty list arrived in #367 and nobody re-measured the
	## line against the panel beside it, so three strings shared one set of
	## pixels on the defeat screen.
	_end_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_cost_label.custom_minimum_size = Vector2(_END_TEXT_WIDTH, 0.0)
	column.add_child(_end_cost_label)

	## Issue 441. The one place the game says plans exist, shown only to a
	## player who has none, at the moment they have just watched what that
	## costs. The field stays clear of it: this is the end card only.
	_end_prompt_label = Label.new()
	_end_prompt_label.add_theme_color_override("font_color", Palette.TEXT)
	_end_prompt_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	_end_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_prompt_label.custom_minimum_size = Vector2(_END_TEXT_WIDTH, 0.0)
	_end_prompt_label.visible = false
	column.add_child(_end_prompt_label)

	## Issue 552: the roster and the whole log. Inside the banner rather than
	## beside it, so issue 343's arrangement -- dim as a sibling, banner itself
	## on MOUSE_FILTER_IGNORE -- holds for it without being restated.
	_end_screen = EndScreen.create()
	column.add_child(_end_screen)

	var buttons := HBoxContainer.new()
	buttons.anchor_left = 0.0
	buttons.anchor_right = 1.0
	buttons.anchor_top = 1.0
	buttons.anchor_bottom = 1.0
	buttons.offset_top = -_END_BUTTON_ROW_RESERVED
	buttons.offset_bottom = -Palette.SPACE_M
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_theme_constant_override("separation", int(Palette.SPACE_M))
	_end_banner.add_child(buttons)

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

	_build_room_picker(_end_banner)

	_inspect_panel = InspectPanel.create()
	hud.add_child(_inspect_panel)
	if not _inspect_panel.is_inside_tree():
		_inspect_panel._ready()
	_inspect_panel.closed.connect(_on_card_closed)

## Issue 591: another room, from the end card. Plain `Button`s rather than an
## `OptionButton`: the popup of one is a separate window and #520 is what a
## control nothing can really click costs, so every room here takes the same
## event a mouse sends.
##
## **In the left gutter, not in the card's own column.** That column has 604 px
## in a 720 px window and its existing content leaves 6 px spare, so six room
## buttons appended to it would be controls no player can reach. The gutter
## beside it is empty from the summary bars down.
const ROOM_PICKER_NAME := "EndRoomPicker"
const ROOM_PICKER_WIDTH := 260.0
const ROOM_PICKER_CAPTION := "Fight another room"

var _room_buttons: Dictionary = {}

func _build_room_picker(banner: Control) -> Control:
	var side := VBoxContainer.new()
	side.name = ROOM_PICKER_NAME
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	side.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	side.grow_horizontal = Control.GROW_DIRECTION_END
	side.grow_vertical = Control.GROW_DIRECTION_BEGIN
	side.offset_left = Palette.SPACE_M
	side.offset_bottom = -Palette.SPACE_M
	side.custom_minimum_size = Vector2(ROOM_PICKER_WIDTH, 0.0)
	banner.add_child(side)

	var caption := Label.new()
	caption.text = ROOM_PICKER_CAPTION
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	caption.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(caption)

	## `RoomLibrary.pickable_ids()` is the same list party select offers,
	## asked of the registry rather than of that screen. One place decides which
	## rooms exist, which is what #587 has to be able to move.
	for id in RoomLibrary.pickable_ids():
		var room = RoomLibrary.get_room(id)
		var b := Button.new()
		b.text = room_button_text(id, room)
		b.custom_minimum_size = Vector2(ROOM_PICKER_WIDTH, Palette.TOUCH_TARGET_MIN)
		b.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
		b.clip_text = true
		b.tooltip_text = PartySelect.room_summary(id)
		b.set_script(GlossaryButton)
		var room_id: StringName = id
		b.pressed.connect(func(): room_requested.emit(room_id))
		side.add_child(b)
		_room_buttons[id] = b
	return side

## The room the player is already in is shown and dead rather than left out:
## a list that changes length between fights is a list you have to re-read.
func _sync_room_picker() -> void:
	var here: StringName = config.encounter_id if config != null else &""
	for id in _room_buttons:
		_room_buttons[id].disabled = id == here

## "Floor 1, The Narrows" is the room's whole name and half of it is the floor.
## The floor is not a choice on this card, so it is dropped where it is there
## and the full name stands where it is not.
static func room_button_text(id: StringName, room) -> String:
	var full: String = room.display_name if room != null and room.display_name != "" else String(id)
	var comma := full.find(", ")
	return full.substr(comma + 2) if comma >= 0 else full

func _on_inspect_pressed() -> void:
	_open_plans(null)

## The card is docked bottom-left and the plans screen puts its pawn list in the
## same place, so a card left open covers the control you need to correct it.
## It is dismissed rather than closed: the pause it took stays in force until
## the plans screen is shut again.
func _open_plans(focus: PawnData) -> void:
	if _unit_card != null:
		_unit_card.dismiss()
	if _inspect_panel != null and config != null:
		_inspect_panel.open(config.party, state, focus)
	_sync_click_hint()

## Issue 397: this used to call _on_inspect_pressed, which always opened the
## party's first pawn whichever card the button was on.
## Issue 588: the click is the player's input, so the view owns it and the card
## only asks. Pressing it on the enemy already focused clears the focus.
func _on_card_focus_toggled(id: int) -> void:
	if state == null:
		return
	state.player_focus_id = -1 if state.player_focus_id == id else id
	_unit_card.refresh(state)

func _on_card_plans_requested() -> void:
	_open_plans(card_pawn())

## The pawn the open card is about, or null.
func card_pawn() -> PawnData:
	if state == null or _unit_card == null or _unit_card.unit_id < 0:
		return null
	var u := state.unit(_unit_card.unit_id)
	return u.pawn if u != null else null

## Issue 377: a blind playtester clicked and hovered a sprite four times and got
## nothing back, so the arena was not a way in to anything the game knows.
func _build_unit_card() -> void:
	_unit_card = UnitCard.create()
	get_node("Hud").add_child(_unit_card)
	_unit_card.closed.connect(_on_card_closed)
	_unit_card.plans_requested.connect(_on_card_plans_requested)
	_unit_card.focus_toggled.connect(_on_card_focus_toggled)
	_place_unit_card()
	_build_click_hint()

## Issue 397: three of four fights played without finding the card, because
## nothing said a unit was clickable. A line that removes itself the first time
## a card opens costs no permanent space on a screen that has none to give.
func _build_click_hint() -> void:
	_click_hint = Label.new()
	_click_hint.text = CLICK_HINT
	_click_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_click_hint.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_click_hint.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_click_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_click_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_click_hint.offset_left = Palette.SPACE_M
	_click_hint.offset_right = -(CombatLogView.LOG_WIDTH + Palette.SPACE_M)
	_click_hint.offset_top = -(Palette.SPACE_M + _INFO_ROW_HEIGHT)
	_click_hint.offset_bottom = -Palette.SPACE_M
	_click_hint.visible = not card_discovered
	get_node("Hud").add_child(_click_hint)

	## Same band of pixels, shown instead of the click hint while placing.
	_setup_hint = Label.new()
	_setup_hint.text = SETUP_HINT
	_setup_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup_hint.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_setup_hint.add_theme_color_override("font_color", Palette.TEXT)
	_setup_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_setup_hint.offset_left = Palette.SPACE_M
	_setup_hint.offset_right = -(CombatLogView.LOG_WIDTH + Palette.SPACE_M)
	_setup_hint.offset_top = -(Palette.SPACE_M + _INFO_ROW_HEIGHT)
	_setup_hint.offset_bottom = -Palette.SPACE_M
	_setup_hint.visible = false
	get_node("Hud").add_child(_setup_hint)

const CLICK_HINT := "Click any unit to see what it is doing, and why."

const SETUP_HINT := "Drag your pawns to place them. The shaded band is as far forward as they may start. Press Start Fight when you are ready."

## Session-wide, not per fight: a player who has opened one card does not need
## telling again on the next.
static var card_discovered: bool = false

## Clicking pauses. Reading a unit takes longer than the fight gives you, and
## the alternative -- a card whose every number moves while you read it -- is
## the thing the issue is about.
func select_unit_at(point: Vector2) -> void:
	if state == null or _unit_card == null:
		return
	var id := unit_at(state, point, _pick_radius())
	if id < 0:
		_unit_card.close()
		return
	if not paused:
		set_paused(true)
		_card_owns_pause = true
	_unit_card.show_unit(state, state.unit(id))
	card_discovered = true
	if _click_hint != null:
		_click_hint.visible = false

func _on_card_closed() -> void:
	_sync_click_hint()
	if _card_owns_pause:
		_card_owns_pause = false
		set_paused(false)

## Docked bottom-left, not beside the unit. Beside was the first version and the
## click probe caught it: a card placed over the field ate the next click, so
## eight of eleven sprites still reported "nothing happened" -- the exact
## complaint the issue is about, reintroduced by the fix for it.
func _place_unit_card() -> void:
	_unit_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_unit_card.grow_horizontal = Control.GROW_DIRECTION_END
	_unit_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_unit_card.offset_left = Palette.SPACE_M
	_unit_card.offset_top = -Palette.SPACE_M
	_unit_card.offset_bottom = -Palette.SPACE_M

## Half a touch target, in the arena's own world pixels. The arena is drawn at
## about 0.83 at 1280x720, so a target measured in world pixels reads smaller
## than that on screen, which is the size a finger and a mouse both care about.
static func pick_radius_for_scale(arena_scale: float) -> float:
	return Palette.TOUCH_TARGET_MIN * 0.5 / (arena_scale if arena_scale > 0.0 else 1.0)

func _pick_radius() -> float:
	return pick_radius_for_scale(_arena.scale.x if _arena != null else 1.0)

## Which unit a click at `point` (arena-local, which is world space) lands on.
## Bodies answer first, grown to at least `min_radius` so an 11-pixel goblin is
## not an 11-pixel target; a drawn name plate answers only where no body does,
## because a 40-pixel plate reaches over the pawn standing behind it. Within
## either pass the nearest DRAWN centre wins, which is the tie-break in a knot.
## The shield plate counts as part of its shielder.
static func unit_at(state: CombatState, point: Vector2, min_radius: float = Palette.TOUCH_TARGET_MIN * 0.5) -> int:
	var on_body := _nearest(state, point, func(u): return _hits(state, u, point, min_radius))
	if on_body >= 0:
		return on_body
	return _nearest(state, point, func(u): return _hits_plate(state, u, point))

static func _nearest(state: CombatState, point: Vector2, hits: Callable) -> int:
	var best := -1
	var best_distance := INF
	for u in state.units:
		if not u.alive or not hits.call(u):
			continue
		var distance := drawn_position(state, u).distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = u.id
	return best

## The name plate's own chip, and only when it is actually on screen: a name
## nobody can see must not answer for anybody.
static func _hits_plate(state: CombatState, u: CombatUnit, point: Vector2) -> bool:
	if not DisplayOptions.enabled(&"name_plates"):
		return false
	var chip: Rect2 = UnitView.plate_layout(state).get(u.id, Rect2())
	return chip.size.x > 0.0 and chip.has_point(point)

static func drawn_position(_state: CombatState, u: CombatUnit) -> Vector2:
	return UnitView.drawn_position(u)

static func _hits(state: CombatState, u: CombatUnit, point: Vector2, min_radius: float) -> bool:
	var at := drawn_position(state, u)
	var radius := maxf(UnitView.display_radius(u), min_radius)
	var box := UnitView.drawn_box(UnitView.shape_id(u), u.team, UnitView.display_radius(u))
	box.position += at
	var grow_x := maxf(radius - box.size.x * 0.5, 0.0)
	var grow_y := maxf(radius - box.size.y * 0.5, 0.0)
	if box.grow_individual(grow_x, grow_y, grow_x, grow_y).has_point(point):
		return true
	if not ShieldWall.is_up(u):
		return false
	# The plate is drawn from `u.position`, not from the nudged draw position:
	# `ShieldWall.draw_all` sets the canvas transform to the unit's own place.
	var plate := ShieldWall.wall_points(u.facing, ShieldWall.half_width(), u.radius)
	return Geometry2D.is_point_in_polygon(point - u.position, plate)

## e.g. 197 ticks at 30 ticks/second reads as "6.6s" -- a player has never
## seen a tick, and won't start now.
static func _format_duration(ticks: int) -> String:
	return "%.1fs" % (float(ticks) / float(CG.TICKS_PER_SECOND))

## What the fight cost, without asking the player to count bars themselves.
## Issue 442: it says pawns because pawns are what it counts. It said "party"
## while two Siege Engines stood at full health on the same screen, and whether
## a summon is part of your party is not this label's question to answer.
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
		return "Every one of your pawns survived."
	var count := "None of your pawns survived." if alive == 0 \
		else "%d of your %d pawns survived." % [alive, total]
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
	_arena_base = layout.position
	_arena.position = _arena_base + shake_offset(_shake_age, _shake_amplitude)
	_arena.scale = layout.scale
	if _combat_log != null:
		_combat_log.set_landscape(size.x >= size.y)
	_place_click_hint(size.x >= size.y)
	if _unit_card != null:
		_unit_card.body_ceiling = card_body_ceiling(size.y)
	var text_width := end_text_width(size)
	for label in [_end_cost_label, _end_prompt_label]:
		if label != null:
			label.custom_minimum_size.x = text_width

## Issue 396. The card sits between the toolbar and the bottom margin and may
## have all of it. The flat 380 happens to be exactly right at 720 and is wrong
## at every other height -- too tall to fit at 600, and 190 pixels of unused
## screen at 900.
static func card_body_ceiling(viewport_height: float) -> float:
	var free := viewport_height - _TOP_BAR_BOTTOM - 2.0 * Palette.SPACE_M - UnitCard.CHROME_HEIGHT
	return maxf(free, UnitCard.MIN_BODY_HEIGHT)

## Out of the log's way in either orientation: the log is a right-hand column in
## landscape and a full-width band across the bottom in portrait.
func _place_click_hint(landscape: bool) -> void:
	var floor_y := -Palette.SPACE_M if landscape else CombatLogView.LOG_MARGIN - CombatLogView.LOG_HEIGHT - Palette.SPACE_M
	for hint in [_click_hint, _setup_hint]:
		if hint == null:
			continue
		hint.offset_right = -(CombatLogView.LOG_WIDTH + Palette.SPACE_M) if landscape else -Palette.SPACE_M
		hint.offset_top = floor_y - _INFO_ROW_HEIGHT
		hint.offset_bottom = floor_y

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
	begin_with_encounter(cfg, RoomLibrary.get_room(cfg.encounter_id))

## Split out of `begin()` so a caller with an in-memory `Encounter` and no
## registered `encounter_id` -- deploy placement, tools, probes -- can skip the
## `Registry` lookup entirely rather than requiring one: `cfg.encounter_id` is
## simply not read here. `begin()` is unchanged for every existing caller.
func begin_with_encounter(cfg: RunConfig, encounter) -> void:
	config = cfg
	state = CombatSim.build(cfg.party, encounter, cfg.seed)
	event_cursor = 0
	_tick_accumulator = 0.0
	_freeze_left = 0.0
	_shake_age = INF
	_shake_amplitude = 0.0
	ViewClock.frozen = false
	if _gibs != null and is_instance_valid(_gibs):
		_gibs.clear()
	setup = false
	_grabbed_unit_id = -1
	_drag_moved = false
	set_paused(false)
	_rebuild_units()
	_build_deploy_band()
	_arena.grid = state.grid
	_arena.projectiles = []
	_arena.shot_positions = {}
	_prev_drawn = {}
	_prev_shots = {}
	_curr_drawn = _drawn_snapshot()
	_curr_shots = {}
	_arena.units = state.units
	_arena.queue_redraw()
	if _combat_log != null:
		_combat_log.clear_log()
	_party_label.text = "Party: " + ", ".join(cfg.party.map(func(p): return p.display_name))
	_encounter_label.text = encounter.display_name if encounter != null and encounter.display_name != "" else String(cfg.encounter_id)
	_seed_label.text = "Seed " + cfg.seed_text()
	_outcome_label.text = ""
	for label in [_outcome_label, _party_label, _encounter_label, _seed_label]:
		label.visible = true
	_end_banner.visible = false
	_end_dim.visible = false
	if _unit_card != null:
		_unit_card.dismiss()
	_sync_click_hint()
	_card_owns_pause = false
	_update_team_summary()
	if _team_status != null:
		_team_status.sync(state)
	set_process(true)

func set_paused(p: bool) -> void:
	paused = p
	_sync_setup_ui()

## The one place the setup phase reaches the chrome. The dim stays off while
## placing: it exists to say "the fight is held", and a fight that has not
## started is not held, it is being set up on a screen you need to see.
func _sync_setup_ui() -> void:
	if _pause_button != null:
		_pause_button.text = "Start Fight" if setup else ("Resume" if paused else "Pause")
	if _reset_button != null:
		_reset_button.visible = setup
	if _setup_hint != null:
		_setup_hint.visible = setup
	if _deploy_band != null:
		_deploy_band.visible = setup
	if _pause_dim != null:
		_pause_dim.visible = paused and not setup
	_sync_click_hint()

func _on_pause_pressed() -> void:
	if setup:
		start_fight()
	else:
		set_paused(not paused)

# ---------------------------------------------------------------------------
# Placement, on this screen, before the first tick.

## The fight, built and held before its first tick with the party draggable.
## `begin_with_encounter` is deliberately untouched and still starts a running
## fight: a dozen-plus probes call it, and none of them has a player to press
## Start.
func begin_setup(cfg: RunConfig, encounter, positions: Array[Vector2] = []) -> void:
	_base_encounter = encounter
	_placements = positions.duplicate() if not positions.is_empty() \
		else DeployViewScript.authored_positions(encounter, cfg.party.size())
	begin_with_encounter(cfg, DeployViewScript.encounter_with_placement(encounter, _placements))
	setup = true
	set_paused(true)

## Rebuilt through the same `begin_with_encounter` every other caller uses, so
## the fight that runs is built by one path rather than by whatever the setup
## phase left lying in `state`.
func start_fight() -> void:
	if not setup:
		return
	var placed = DeployViewScript.encounter_with_placement(_base_encounter, _placements)
	begin_with_encounter(config, placed)
	placement_changed.emit(placements())

func placements() -> Array[Vector2]:
	return _placements.duplicate()

func reset_placement() -> void:
	if _base_encounter == null:
		return
	_apply_placements(DeployViewScript.authored_positions(_base_encounter, _placements.size()))

## The band draws behind the units, so it is the arena's first child. Rebuilt
## with them because `_rebuild_units` frees every child of the arena.
func _build_deploy_band() -> void:
	_deploy_band = Node2D.new()
	_deploy_band.set_script(DeployViewScript)
	_deploy_band.visible = false
	_arena.add_child(_deploy_band)
	_arena.move_child(_deploy_band, 0)

## The player pawns in the order `CombatSim.build` placed them, which is the
## order `_placements` is in. Summons are excluded and none exists yet anyway.
func _placement_index(unit_id: int) -> int:
	var i := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.enemy_id != &"":
			continue
		if u.id == unit_id:
			return i
		i += 1
	return -1

## Which unit a press in setup picks up, or -1. Hit-tested with `unit_at`, the
## same function a click uses, so grabbing and clicking cannot disagree about
## what is under the pointer.
func _grabbable_at(point: Vector2) -> int:
	var id := unit_at(state, point, _pick_radius())
	if id < 0:
		return -1
	var u := state.unit(id)
	if u == null or u.team != CG.Team.PLAYER or u.enemy_id != &"":
		return -1
	return id

## Clamped into the deploy band and refused outright inside blocking terrain,
## using the same function the simulation's own movement uses.
func _move_grabbed_to(point: Vector2) -> void:
	var index := _placement_index(_grabbed_unit_id)
	if index < 0:
		return
	var u := state.unit(_grabbed_unit_id)
	var target := DeployViewScript.clamp_to_deploy_zone(point, u.radius)
	if state.grid.move_blocked(target, u.radius):
		return
	var next := placements()
	next[index] = target
	_apply_placements(next)

func _apply_placements(positions: Array[Vector2]) -> void:
	_placements = positions
	var i := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.enemy_id != &"":
			continue
		if i < _placements.size():
			u.position = _placements[i]
		i += 1
	# Issue 501. The only place a unit moves outside `CombatSim.step`, so the
	# only place that has to say so: without this the first tick after a drag
	# slides every pawn in from wherever it was standing before.
	_curr_drawn = _drawn_snapshot()
	for id in _unit_views:
		_unit_views[id].sync(state, _curr_drawn.get(id, UnitView.RECOMPUTE_AT))
	if _text_layer != null:
		_text_layer.sync(state)
	if _arena != null:
		_arena.units = state.units
		_arena.queue_redraw()
	placement_changed.emit(placements())

## How far, in screen pixels, a press may travel and still be a click. Placement
## and inspection are both a press on a pawn, and this is what tells them apart:
## a press that stays put opens the card, a press that travels places the pawn.
const DRAG_SLOP_PIXELS := 8.0

func _drag_slop() -> float:
	var s: float = _arena.scale.x if _arena != null and _arena.scale.x > 0.0 else 1.0
	return DRAG_SLOP_PIXELS / s

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if setup:
			start_fight()
		else:
			set_paused(not paused)
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	if _arena == null or state == null:
		return
	# Left button only: a Control that wanted this click has already taken it
	# before _unhandled_input ever runs.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var at: Vector2 = _arena.make_input_local(event).position
		_on_arena_button(event, at)
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var at: Vector2 = _arena.make_input_local(event).position
		if _grabbed_unit_id >= 0:
			if at.distance_to(_press_world) > _drag_slop():
				_drag_moved = true
			_move_grabbed_to(at)
			return
		## The other half of issue 397's discoverability: the pointer changes over
		## anything you can open, which is the affordance every other program uses.
		_set_hand_cursor(unit_at(state, at, _pick_radius()) >= 0)

## Outside setup this is what it always was -- the card opens on the press. In
## setup a press on your own pawn grabs it instead, and the card opens on the
## release only if the pointer never travelled.
func _on_arena_button(event: InputEventMouseButton, at: Vector2) -> void:
	if not setup:
		if event.pressed:
			select_unit_at(at)
		return
	if event.pressed:
		_press_world = at
		_drag_moved = false
		_grabbed_unit_id = _grabbable_at(at)
		return
	var was_a_drag := _drag_moved and _grabbed_unit_id >= 0
	_grabbed_unit_id = -1
	_drag_moved = false
	if not was_a_drag:
		select_unit_at(_press_world)

func _set_hand_cursor(hand: bool) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hand else Input.CURSOR_ARROW)

## The cursor is a global setting, so leaving the fight has to put it back.
func _exit_tree() -> void:
	_set_hand_cursor(false)
	# Issue 528: the freeze belongs to a live battle screen. Leaving one with a
	# hold still running would otherwise hold every overlay on the next.
	ViewClock.frozen = false

func _rebuild_units() -> void:
	for child in _arena.get_children():
		child.queue_free()
	_unit_views.clear()
	_unit_layer = null
	_bursts = null
	_gibs = null
	_text_layer = null
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
	_ensure_layers()
	for u in state.units:
		if _unit_views.has(u.id):
			continue
		var view := Node2D.new()
		view.set_script(UnitViewScript)
		_bodies().add_child(view)
		view.bind(state, u.id)
		_unit_views[u.id] = view
	if _text_layer != null:
		_text_layer.sync(state)

## Issue 512: there is one way in. `_text_layer` used to be built only by
## `_rebuild_units`, which only `begin_with_encounter` calls, while `_process`
## called `_text_layer.sync` unguarded -- so a tool that drove the view by
## assigning `state` got a null and every stepped frame died inside `_process`
## before it rendered, silently, producing a plausible wrong picture.
## Order matters and is asserted by `_bodies`: the unit layer first, the text
## layer after it, so no body can be painted over a name (issue 321).
func _ensure_layers() -> void:
	if _unit_layer == null or not is_instance_valid(_unit_layer):
		_unit_layer = Node2D.new()
		_arena.add_child(_unit_layer)
	# Issue 589: under the debris and over the living, so a chunk cannot be
	# mistaken for a body standing in front of one.
	if _gibs == null or not is_instance_valid(_gibs):
		_gibs = DeathExplosionScript.new()
		_arena.add_child(_gibs)
	# Issue 517: between the two, so debris covers a body and a name covers it.
	if _bursts == null or not is_instance_valid(_bursts):
		_bursts = ImpactBurstScript.new()
		_arena.add_child(_bursts)
	if _text_layer == null or not is_instance_valid(_text_layer):
		_text_layer = ArenaTextLayerScript.new()
		_arena.add_child(_text_layer)
	# Over the bodies and under the text: a beam should cross a goblin and pass
	# beneath the damage number that explains it.
	if _vfx == null or not is_instance_valid(_vfx):
		_vfx = VFXDirector.new()
		_vfx.position_of_fn = _vfx_position_of
		_vfx.hand_of_fn = _vfx_hand_of
		_vfx.hands_of_fn = _vfx_hands_of
		_vfx.facing_of_fn = _vfx_facing_of
		_vfx.shake_fn = _vfx_shake
		_vfx.hit_stop_fn = _hit_stop
		_arena.add_child(_vfx)
		_arena.move_child(_vfx, _text_layer.get_index())

## Issue 321: every body and every bar goes in one layer under the names, so a
## summon added mid-fight cannot be drawn over a plate that was already up.
func _bodies() -> Node2D:
	return _unit_layer if _unit_layer != null else _arena

## Spends wall-clock delta in whole ticks. Frame rate must not change how fast
## the fight plays: a slow frame catches up by stepping several ticks at once
## rather than the view quietly drifting into slow motion.
func _process(delta: float) -> void:
	if state == null:
		return
	# Issue 528: every overlay that animates on real delta reads this. Issue 535:
	# pause is the other trigger, and it is the one the player uses to look at a
	# hit, so it must be written above the return rather than below it.
	ViewClock.frozen = paused or _freeze_left > 0.0
	# Above the decrement, so pausing holds a freeze rather than spending it.
	if paused:
		return
	if _freeze_left > 0.0:
		_freeze_left = maxf(0.0, _freeze_left - delta)
		if _freeze_left > 0.0:
			return
		# Released on the frame it runs out, not the frame after it.
		ViewClock.frozen = false
		# The frames this freeze covered are gone, not owed. See _freeze_left.
		delta = 0.0
	if state.outcome != CombatState.Outcome.UNRESOLVED:
		_show_outcome()
		set_process(false)
		return

	_tick_accumulator += delta
	var stepped := false
	while _tick_accumulator >= CG.TICK_SECONDS and state.outcome == CombatState.Outcome.UNRESOLVED:
		_tick_accumulator -= CG.TICK_SECONDS
		# Inside the loop, because a slow frame runs several steps in one frame.
		_prev_drawn = _curr_drawn
		_prev_shots = _curr_shots
		CombatSim.step(state)
		_curr_drawn = _drawn_snapshot()
		_curr_shots = _shot_snapshot()
		stepped = true

	if stepped:
		_ensure_unit_views()
		consume_events()
		for id in _unit_views:
			_unit_views[id].sync(state, _curr_drawn.get(id, UnitView.RECOMPUTE_AT))
		_text_layer.sync(state)
		_arena.projectiles = state.projectiles
		_arena.units = state.units
		_update_team_summary()
		# Issue 113. Same place and same trigger as the unit views: "live means live"
		if _team_status != null:
			_team_status.sync(state)
		if _unit_card != null:
			_unit_card.refresh(state)

	_render(_tick_accumulator / CG.TICK_SECONDS, stepped, delta)

	# The banner waits out a freeze on the last death, which is the death the
	# player is watching hardest and the one a banner would otherwise cover.
	if state.outcome != CombatState.Outcome.UNRESOLVED and _freeze_left <= 0.0:
		_show_outcome()
		set_process(false)

## Issue 501. Every rendered frame, stepped or not: each body and each shot is
## placed between where it was before the last tick and where it is now.
## Moving a node costs nothing to redraw, so only the arena is asked to.
## Issue 516: the impact decay is spent from here rather than from each view's
## own `_process`, so a hit stop holds it. `_process` returns above this line
## while the picture is frozen, and a body still relaxing through a freeze frame
## is motion in a picture that is meant to have stopped.
func _render(alpha: float, stepped: bool, delta: float = 0.0) -> void:
	alpha = clampf(alpha, 0.0, 1.0)
	_advance_shake(delta)
	if _gibs != null and is_instance_valid(_gibs):
		_gibs.advance(delta)
	var frame_at := {}
	# Issue 583: unconditional, unlike the impact decay above -- an idle bob has
	# no end to test for. Spent here for the same reason: a frozen frame never
	# reaches this line, so nothing animates through a pause or a hit stop.
	var animating: bool = UnitView.animating()
	for id in _unit_views:
		var view = _unit_views[id]
		if animating:
			view.advance_anim(delta, alpha)
		if view.impact_active():
			view.advance_impact(delta)
		var to = _curr_drawn.get(id)
		if to != null:
			var at := _tween_body(int(id), to, alpha)
			view.position = at
			frame_at[id] = at
	# Issue 511: everything that belongs to a body follows the body. What marks
	# an event instead -- a damage number, a death plate -- is left where it was.
	if _text_layer != null:
		_text_layer.set_positions(_curr_drawn, frame_at)
	_arena.unit_positions = frame_at
	var shots := {}
	for p in state.projectiles:
		if p.resolved:
			continue
		var from = _prev_shots.get(p.id)
		shots[p.id] = p.position if from == null else from.lerp(p.position, alpha)
	if not stepped and shots.is_empty() and _arena.shot_positions.is_empty() \
			and not _any_cover_up():
		return
	_arena.shot_positions = shots
	_arena.queue_redraw()

## Whether the arena is drawing a shield plate this frame. The plate rides a
## body, so while one is up the floor has to repaint with it.
func _any_cover_up() -> bool:
	for u in state.units:
		if ShieldWall.is_up(u):
			return true
	return false

func _tween_body(id: int, to: Vector2, alpha: float) -> Vector2:
	var from = _prev_drawn.get(id)
	if from == null:
		return to
	var u := state.unit(id)
	if u == null or from.distance_to(to) > u.move_speed * 3.0 + UnitView.display_radius(u) * 3.0:
		# Further than a walk: a spawn, a teleport, or the crowd nudge throwing a
		# body across a scrum. Sliding through it invents motion nothing did.
		return to
	return from.lerp(to, alpha)

## Issue 537: where a body is DRAWN on the frame an event lands, which is what
## "where it happened" has always meant. Issue 511 plants a mark and does not
## move it again, and that stands; but "planted" was defined before #501, when
## the drawn and the raw position were the same point on every frame. On a
## stepped frame they differ by up to a tick, so a mark anchored to raw
## `position` is planted where the body WILL be, about half a small body ahead
## of where the player can see it.
func _drawn_event_position(unit) -> Vector2:
	if unit == null:
		return Vector2.ZERO
	var to = _curr_drawn.get(unit.id)
	if to != null:
		return _tween_body(unit.id, to, clampf(_tick_accumulator / CG.TICK_SECONDS, 0.0, 1.0))
	# A death leaves the snapshot, which only holds the living, so the last
	# place the body was drawn is the last tick boundary it reached.
	var was = _prev_drawn.get(unit.id)
	return was if was != null else unit.position

func _drawn_snapshot() -> Dictionary:
	var out := {}
	for u in state.units:
		if u.alive:
			out[u.id] = UnitView.drawn_position(u, state.units)
	return out

func _shot_snapshot() -> Dictionary:
	var out := {}
	for p in state.projectiles:
		if not p.resolved:
			out[p.id] = p.position
	return out

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
		# Issue 550. Every event, unfiltered: which ones make a noise is
		# `SoundBank`'s decision and adding a second filter here is the second
		# list #299 refuses. A hit stop is not honoured -- a sound is a mark on
		# a moment rather than an animation, and the freeze is triggered BY the
		# death whose sound it exists to give weight to.
		if _sound != null:
			_sound.play_for(e)
		_play_action_vfx(e)
		if e.kind == CG.EventKind.DAMAGE or e.kind == CG.EventKind.HEAL:
			_spawn_floater(e)
			_spawn_impact_burst(e)
			if e.kind == CG.EventKind.DAMAGE:
				_apply_impact(e)
		elif e.kind == CG.EventKind.DEATH:
			_spawn_death_explosion(e)
			_spawn_death_marker(e)
			_hit_stop()
			_screen_shake(e)
		elif e.kind == CG.EventKind.MISS:
			_spawn_miss_marker(e)
		elif e.kind == CG.EventKind.INTERRUPTED:
			_spawn_interrupt_flash(e)
		elif e.kind == CG.EventKind.ACTION_FIRE:
			_apply_loose(e)

## Issue 518. A decaying oscillation, taken from the clock rather than from any
## random source: `state.rng` belongs to the simulation and a probe that draws
## from it changes the fight. Returns exactly zero once the span is spent, so
## the arena lands back on its layout position rather than near it.
static func shake_offset(age: float, amplitude: float) -> Vector2:
	if amplitude <= 0.0 or age < 0.0 or age >= SHAKE_SECONDS:
		return Vector2.ZERO
	var left := 1.0 - age / SHAKE_SECONDS
	var phase := (age / SHAKE_SECONDS) * TAU * SHAKE_CYCLES
	# Full displacement at the instant of the death, not built up to: a shake
	# that eases in reads as the camera drifting rather than as a blow.
	return Vector2(cos(phase), sin(phase) * 0.5) * (amplitude * left * left)

## Spent from `_render` for the same reason #516's decay is: `_process` returns
## above that line while a hit stop holds the picture, and a screen that keeps
## moving through a freeze frame is the bug #515 and #516 nearly shipped twice.
## Issue 650. An action says what it looks like; this hands that to the
## director. Null `vfx` leaves every existing effect exactly as it was.
func _play_action_vfx(e: CombatEvent) -> void:
	if _vfx == null or e.action_id == &"":
		return
	var action := ActionLibrary.get_action(e.action_id)
	if action == null:
		return
	if e.kind == CG.EventKind.ACTION_START:
		if action.vfx != null:
			_vfx.play(action.vfx, VFXLayer.Cue.WIND_UP, e.source_id, e.target_id,
				float(action.wind_up_ticks) * CG.TICK_SECONDS)
	elif e.kind == CG.EventKind.ACTION_FIRE:
		## Issue 703: a beat states its own vfx; null falls back to the
		## action's, so beat 2 -- unchanged, no vfx of its own -- looks
		## exactly like it did before beats existed.
		var vfx := action.vfx
		if e.beat_index >= 0 and e.beat_index < action.beats.size() and action.beats[e.beat_index].vfx != null:
			vfx = action.beats[e.beat_index].vfx
		if vfx != null:
			_vfx.play(vfx, VFXLayer.Cue.RELEASE, e.source_id, e.target_id, 0.0)
			_vfx.play(vfx, VFXLayer.Cue.IMPACT, e.source_id, e.target_id, 0.0)
	elif e.kind == CG.EventKind.STATUS_EXPIRED:
		## Issue 657: only the status THIS action eats to pay for itself arms the
		## look -- a shield break or a cleanse also emits STATUS_EXPIRED under the
		## breaking action's id, and neither is a consume this action made.
		if action.consumes_status_enabled and e.status == action.consumes_status:
			_vfx.arm_consumed(e.action_id, e.target_id)
	elif e.kind == CG.EventKind.DAMAGE:
		_vfx.play_consume_gated(action.vfx, VFXLayer.Cue.IMPACT, e.action_id, e.source_id, e.target_id)

## Where the director draws a unit, in arena space.
func _vfx_position_of(id: int) -> Vector2:
	var view: Node2D = _unit_views.get(id)
	if view == null:
		return Vector2.ZERO
	return view.position

## Where the caster's hands are drawn, so a beam leaves the pose throwing it.
func _vfx_hand_of(id: int) -> Vector2:
	var view = _unit_views.get(id)
	if view == null:
		return Vector2.ZERO
	return view.hand_anchor()

## Every hand of the caster, tracked separately.
func _vfx_hands_of(id: int) -> PackedVector2Array:
	var view = _unit_views.get(id)
	if view == null:
		return PackedVector2Array()
	return view.hand_anchors()

## Which way a caster faces, straight off the simulation -- the same quantity
## that decides whether the Warrior's guard stops a shot.
func _vfx_facing_of(id: int) -> Vector2:
	var u := state.unit(id) if state != null else null
	return Vector2.RIGHT if u == null else u.facing

## A layer asks for a shake in pixels; the toggle still decides.
func _vfx_shake(pixels: float) -> void:
	if not DisplayOptions.enabled(SHAKE_OPTION):
		return
	if _shake_age < SHAKE_SECONDS and pixels <= _shake_amplitude:
		return
	_shake_age = 0.0
	_shake_amplitude = pixels

func _advance_shake(delta: float) -> void:
	if _shake_age >= SHAKE_SECONDS:
		return
	_shake_age += delta
	if _shake_age >= SHAKE_SECONDS:
		_shake_age = INF
		_shake_amplitude = 0.0
	if _arena != null:
		_arena.position = _arena_base + shake_offset(_shake_age, _shake_amplitude)

## Issue 518. Scaled to the body that died -- a rat is not the Warden -- and set
## rather than added, so a tick that kills three shakes once, at the size of the
## biggest of them. A smaller death inside a live shake is dropped: at 0.18s it
## would land inside the hold it is meant to punctuate.
func _screen_shake(e: CombatEvent) -> void:
	if not DisplayOptions.enabled(SHAKE_OPTION):
		return
	var dead := state.unit(e.target_id)
	if dead == null:
		return
	var body := UnitViewScript.drawn_half_width(
		UnitViewScript.shape_id(dead), dead.team, UnitViewScript.display_radius(dead))
	var amplitude := SHAKE_PIXELS * clampf(body / SHAKE_FULL_BODY, 0.0, 1.0)
	if _shake_age < SHAKE_SECONDS and amplitude <= _shake_amplitude:
		return
	_shake_age = 0.0
	_shake_amplitude = amplitude

## Issue 515. Set, never added: a tick that kills three units holds once rather
## than stalling for three freezes.
func _hit_stop() -> void:
	if DisplayOptions.enabled(&"hit_stop"):
		_freeze_left = HIT_STOP_SECONDS

## Issue 516. How far apart two bodies may be and still have landed a blow on
## each other, in multiples of their own drawn sizes.
const RECOIL_REACH := 2.0

## Issue 516: the struck body squashes, and whoever swung rocks back off it.
## Two gates. `action_id` is empty on poison, burn, bleed and hazard damage,
## which `CombatSim` emits once per afflicted unit per TICK; and a projectile's
## DAMAGE fires when the arrow lands rather than when it was loosed, so recoil
## is melee only.
func _apply_impact(e: CombatEvent) -> void:
	if e.action_id == &"":
		return
	var target := state.unit(e.target_id)
	var struck = _unit_views.get(e.target_id)
	if target == null or struck == null:
		return
	# Issue 553: the type is passed so the flash CAN lean toward it. It ships
	# white; `UnitView.FLASH_TINT` is the one number that changes that.
	struck.struck(e.damage_type)
	var source := state.unit(e.source_id)
	var attacker = _unit_views.get(e.source_id)
	if source == null or attacker == null or source.id == target.id:
		return
	var reach := (UnitViewScript.display_radius(source) + UnitViewScript.display_radius(target)) * RECOIL_REACH
	if source.position.distance_to(target.position) > reach:
		return
	attacker.recoiled(source.position - target.position)

## Issue 531. A ranged attacker kicks back at the loose, which is ACTION_FIRE.
## Projectile actions only: `_apply_impact` already covers a melee swing, whose
## ACTION_FIRE and DAMAGE land on the same tick, and a shot's own DAMAGE arrives
## a second later at the far end of the arena. `ACTION_FIRE` means committed, so
## a loose with no target left still kicks -- the bow was drawn either way.
func _apply_loose(e: CombatEvent) -> void:
	var action := ActionLibrary.get_action(e.action_id)
	if action == null or action.projectile_speed <= 0.0:
		return
	var source := state.unit(e.source_id)
	var target := state.unit(e.target_id)
	var shooter = _unit_views.get(e.source_id)
	if source == null or target == null or shooter == null or source.id == target.id:
		return
	shooter.recoiled(source.position - target.position, UnitViewScript.LOOSE_PIXELS)

## Issue 26 item 3: in a scrum, several floating numbers (or a death marker
## alongside one) used to spawn at the literal same point and read as one
## garbled string -- Tools/preview/fight_04.png had "Cultist dies", a
## floating 2 and a unit label all occupying the same pixels. Floaters are
## transient (0.9-1.8s) so a live count of nearby siblings at spawn time is
## enough: each new one spreads a step further from whichever are already
## there rather than landing on top of them. Deterministic by spawn order
## within a frame, not by anything read off CombatState, so it changes
## nothing about what a player can infer from position.
const _FLOATER_STAGGER_STEP := 18.0 * UnitViewScript.DISPLAY_SCALE

## Issue 378. This counted floaters within a RADIUS OF A POINT and spread the
## new one by that count, which is the defect #367 fixed for death plates and
## did not cover here: what collides is a number as wide as its text, so `22`,
## `2` and `2` stacked into one smear and a gold `0` covered a whole sprite.
## The candidates are tried in a fixed order, so the same fight staggers the
## same way twice.
const _FLOATER_CANDIDATES := [
	Vector2(0.0, 0.0),
	Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0),
	Vector2(1.0, -1.0), Vector2(-1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0),
	Vector2(2.0, 0.0), Vector2(-2.0, 0.0), Vector2(0.0, -2.0), Vector2(0.0, 2.0),
	Vector2(2.0, -1.0), Vector2(-2.0, -1.0), Vector2(2.0, 1.0), Vector2(-2.0, 1.0),
	Vector2(1.0, -2.0), Vector2(-1.0, -2.0), Vector2(1.0, 2.0), Vector2(-1.0, 2.0),
	Vector2(3.0, 0.0), Vector2(-3.0, 0.0), Vector2(0.0, -3.0), Vector2(0.0, 3.0),
]

## How many floating numbers may be on screen at once. Measured on issue 378's
## instrument: a Burn Pit fight with damage numbers on reached 40 live at one
## tick, and past about sixteen no stagger can separate them because there is
## nowhere left to put one. The same reasoning as MAX_STATUS_BADGES.
const MAX_LIVE_FLOATERS := 10

## Frees the oldest numbers until there is room for one more. Deaths and misses
## are exempt: a death is the event the player most needs to see, and there are
## never many at once.
func _make_room_for_a_floater() -> void:
	var plain: Array = []
	for child in _arena.get_children():
		if child.get_script() == DamageFloaterScript and not child.death_marker:
			plain.append(child)
	for i in maxi(0, plain.size() - (MAX_LIVE_FLOATERS - 1)):
		plain[i].queue_free()
		_arena.remove_child(plain[i])

## Every pixel of arena text already spoken for: the live floaters AND the name
## plates, which used to be two searches with no knowledge of each other.
func _occupied_arena_text() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for child in _arena.get_children():
		if child.get_script() != DamageFloaterScript:
			continue
		var box: Rect2 = child.swept_extent()
		if box.size.x > 0.0 and box.size.y > 0.0:
			out.append(box)
	if state != null and DisplayOptions.enabled(&"name_plates"):
		for chip in UnitViewScript.plate_layout(state).values():
			out.append(chip)
	return out

## The offset at which this floater's own extent, once clamped into the arena,
## covers the least of what is already on it -- the first free one wins, and
## past that the least-bad one does. Returning the unstaggered base position
## when nothing is free is what quadrupled floater-on-floater overlap the first
## time this took name plates as obstacles: 6041 pairs to 24846.
func _floater_stagger_offset(base_position: Vector2, text: String, font_size: int, plate: bool = false) -> Vector2:
	var live: Array[Rect2] = _occupied_arena_text()

	var own := DamageFloaterScript.extent_of(text, font_size, base_position, plate)
	var step := Vector2(
		maxf(_FLOATER_STAGGER_STEP, own.size.x * 0.6),
		maxf(_FLOATER_STAGGER_STEP, own.size.y * 0.75))
	var lifetime := DamageFloaterScript.DEATH_LIFETIME if plate else DamageFloaterScript.LIFETIME_SECONDS
	var best := UnitViewScript.into_arena(own)
	var best_area := INF
	for candidate in _FLOATER_CANDIDATES:
		var at: Vector2 = base_position + candidate * step
		var box := DamageFloaterScript.extent_of(text, font_size, at, plate)
		at += UnitViewScript.into_arena(box)
		box = DamageFloaterScript.swept_extent_of(text, font_size, at, plate, lifetime)
		var area := UnitViewScript.overlap_area(box, live)
		if area < best_area:
			best_area = area
			best = at - base_position
		if area <= 0.0:
			break
	return best

## Issue 136: off by default, and the guard is here rather than at the call site
## so nothing can spawn a damage number without passing it.
func _spawn_floater(e: CombatEvent) -> void:
	if not DisplayOptions.enabled(&"damage_numbers"):
		return
	var target := state.unit(e.target_id)
	if target == null:
		return
	var color := Palette.damage_color(e.damage_type) if e.kind == CG.EventKind.DAMAGE else Palette.HP_FULL
	var running = _mergeable_floater(target.id, color)
	if running != null:
		running.add_amount(e.amount)
		return
	_make_room_for_a_floater()
	var size := int(round(Palette.FONT_SIZE_FLOATER * UnitViewScript.DISPLAY_SCALE))
	var anchor := _drawn_event_position(target)
	var at := anchor + _floater_stagger_offset(anchor, str(e.amount), size)
	var floater := Node2D.new()
	floater.set_script(DamageFloaterScript)
	_arena.add_child(floater)
	floater.position = at
	floater.unit_id = target.id
	floater.show_amount(e.amount, color, size)

## Issue 390: past about a dozen live numbers no stagger can separate them,
## because the text needs more area than the fight occupies. Six ticks of `3`
## on one pawn become one `18` that keeps counting, which is both fewer numbers
## and the number the player wanted.
const FLOATER_MERGE_WINDOW := 0.6

func _mergeable_floater(unit_id: int, color: Color):
	for child in _arena.get_children():
		if child.get_script() != DamageFloaterScript:
			continue
		if child.can_merge(unit_id, color, FLOATER_MERGE_WINDOW):
			return child
	return null

## Issue 589. The dead body's own chunks, thrown from where the body was DRAWN
## rather than from where the last tick left it -- the same anchor #537 gave the
## death plate, and here it matters more, because the chunks start as a copy of
## the body and any error is a jump.
##
## A body with no recipe, or one that comes apart into a single chunk, throws
## nothing and vanishes exactly as it did before this issue.
func _spawn_death_explosion(e: CombatEvent) -> void:
	if _gibs == null or not is_instance_valid(_gibs):
		return
	var dead := state.unit(e.target_id)
	if dead == null:
		return
	var shape := UnitViewScript.shape_id(dead)
	var fragments := UnitArt.fragments_for(shape, dead.team)
	if fragments.is_empty():
		return
	var at := _drawn_event_position(dead)
	var radius := UnitViewScript.display_radius(dead)
	## Issue 639: the hands leave the body in the pose they were in, not at rest
	## -- read straight from the same view that just drew this body, so the
	## chunk's frame 0 matches the frame the hit stop is about to hold.
	var view = _unit_views.get(dead.id)
	var main_offset: Vector2 = view._part_offset(dead, radius) if view != null else Vector2.ZERO
	var off_offset: Vector2 = view._off_hand_offset(dead, radius) if view != null else Vector2.ZERO
	_gibs.explode(at, radius, UnitViewScript.facing_left(dead), fragments, dead.id,
		main_offset, off_offset)
	if _bursts != null and is_instance_valid(_bursts) \
			and DisplayOptions.enabled(DeathExplosionScript.OPTION):
		_bursts.death_burst(at, Palette.team_color(dead.team), _event_seed(e))

## Issue 675: a debris burst's own seed, derived from the event rather than the
## wall clock, so the same fight throws the same debris every time it is
## rendered. `sim` never reads this -- it exists only to feed `ImpactBurst`.
func _event_seed(e: CombatEvent) -> int:
	return e.tick * 1000003 + e.target_id * 97 + e.source_id

## Issue 517: off the same event as the ring, and the guard is here rather than
## at the call site so nothing can throw debris without passing it. DAMAGE only,
## and only damage some action dealt.
func _spawn_impact_burst(e: CombatEvent) -> void:
	if e.kind != CG.EventKind.DAMAGE or not DisplayOptions.enabled(&"impact_particles"):
		return
	# The same gate #516's squash uses: `action_id` is empty on poison, burn,
	# bleed and hazard damage, and a tick of poison has no point of impact.
	if e.action_id == &"":
		return
	if _bursts == null or not is_instance_valid(_bursts):
		return
	var target := state.unit(e.target_id)
	if target == null:
		return
	_bursts.burst(_drawn_event_position(target), e.damage_type, _event_seed(e))

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
	var text := "%s dies" % target.display_name
	var size := _death_font_size(target)
	var anchor := _drawn_event_position(target)
	var base := anchor + _DEATH_MARKER_OFFSET + _death_stack_offset(anchor)
	var at := base + _floater_stagger_offset(base, text, size, true)
	var marker := Node2D.new()
	marker.set_script(DamageFloaterScript)
	_arena.add_child(marker)
	marker.position = at
	marker.show_death(text, Palette.team_color(target.team), size)

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
	var size := int(round(Palette.FONT_SIZE_SMALL * UnitViewScript.DISPLAY_SCALE))
	var anchor := _drawn_event_position(target)
	var at := anchor + _floater_stagger_offset(anchor, "Miss", size)
	var marker := Node2D.new()
	marker.set_script(DamageFloaterScript)
	_arena.add_child(marker)
	marker.position = at
	marker.show_text("Miss", Palette.TEXT_DIM, DamageFloaterScript.LIFETIME_SECONDS, size)

func _show_outcome() -> void:
	var verdict := outcome_word(state)
	var duration := _format_duration(state.tick)
	_outcome_label.text = "%s (%s)" % [verdict, duration]

	_end_outcome_label.text = verdict
	_end_outcome_label.add_theme_color_override("font_color",
		Palette.TEAM_PLAYER if verdict == "Victory"
		else Palette.TEAM_ENEMY if verdict == "Defeat"
		else Palette.TEXT)
	## Each sentence on its own line. The duration used to ride on the end of
	## the casualty list and printed through the last name in it (issue 442).
	var lines: Array[String] = [_cost_summary()]
	var reason := end_reason_sentence(state)
	if reason != "":
		lines.append(reason)
	lines.append("The fight lasted %s." % duration)
	_end_cost_label.text = "\n".join(lines)
	var prompt := plans_prompt(state)
	_end_prompt_label.text = prompt
	_end_prompt_label.visible = prompt != ""
	_end_screen.open(state, _combat_log)
	_sync_room_picker()
	_end_banner.visible = true
	_end_dim.visible = true
	## Issue 552: the end card is as tall as the window, so its heading lands on
	## the toolbar's own first row. Every label on that row is either restated by
	## the card or not worth reading over it; the buttons beside them stay, which
	## is the half issue 343 is about. The text stays set, only the drawing stops.
	for label in [_outcome_label, _party_label, _encounter_label, _seed_label]:
		label.visible = false
	_sync_click_hint()

## Issue 441. After #399 the editor starts empty, so a new player's first fight
## is entirely unplanned and nothing on the fight screen ever said so.
static func plans_prompt(state: CombatState) -> String:
	var pawns := 0
	var planless := 0
	for u in state.units:
		if u.team != CG.Team.PLAYER or u.pawn == null:
			continue
		pawns += 1
		if u.pawn.plans.is_empty():
			planless += 1
	if planless == 0:
		return ""
	if planless == pawns:
		return "None of your pawns has a plan, so each one fought on its own default. Press Plans to write one."
	return "%d of your pawns had no plan and fought on their defaults. Press Plans to write one." % planless

## Issue 445: the simulation now ends the fight when the last pawn dies, so the
## banner reads straight off the outcome and cannot contradict the line under it.
static func outcome_word(state: CombatState) -> String:
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
