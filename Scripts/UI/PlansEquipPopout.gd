extends PanelContainer
class_name PlansEquipPopout


## Issue 741: Plans and Equipment as one narrow, tabbed popout, reachable
## during a run. Traditional-roguelike menu shape -- opens over the fight
## rather than replacing it, tabs rather than a second screen, narrow enough
## to sit beside the arena rather than cover it.

signal closed

const InspectPanelScript := preload("res://Scripts/UI/InspectPanel.gd")
const EquipPanelScript := preload("res://Scripts/UI/EquipPanel.gd")

## Issue 742 proved the plan editor's content scales losslessly down to 240px.
## This sits comfortably above that floor without covering a whole 960px arena.
const WIDTH := 340.0

## A fixed height rather than shrink-to-content: `InspectPanel`/`EquipPanel`'s
## own internal scroll only works when something above it in the tree has a
## real, bounded size to hand down -- the same reason PartySelect embeds them
## in a column with a stretch ratio rather than letting the screen grow to
## fit. A `ScrollContainer` wrapped around a shrink-to-fit popout gives that
## scroll nothing to expand into, and the library sat unreachable behind a
## zero-height `DetailScroll` before this was fixed (found by
## `Tools/PresetLibraryProbe.gd`'s real click on a real popout).
const HEIGHT := 480.0

const TAB_PLANS := 0
const TAB_EQUIP := 1

const EQUIP_LOCKED_NOTE := "Locked while this fight is running. Equipment has no staged form yet, so a change here would reach into the running fight -- visit it between rooms instead."

var _inspect: Control = null
var _equip: Control = null
var _tab_buttons: Array[Button] = []
var _pawn_row: HBoxContainer = null
var _pawn_buttons: Array[Button] = []
var _party: Array[PawnData] = []
var _focused: PawnData = null
var _state = null
var _active_tab := TAB_PLANS

static func create() -> PlansEquipPopout:
	var popout := PlansEquipPopout.new()
	popout._build()
	return popout

func _build() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	theme = AppTheme.paper()
	add_theme_stylebox_override("panel", UIArt.panel_style(&"", Palette.PAPER_FIELD, Palette.INK_DIM, 2, Palette.SPACE_S))
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(Palette.SPACE_S))
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	column.add_child(header)

	var plans_tab := _tab_button("Plans", TAB_PLANS)
	var equip_tab := _tab_button("Equipment", TAB_EQUIP)
	_tab_buttons = [plans_tab, equip_tab]
	header.add_child(plans_tab)
	header.add_child(equip_tab)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)

	var close_button := Button.new()
	close_button.text = "Esc"
	close_button.tooltip_text = "Close (Tab switches, Esc closes)"
	close_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_pawn_row = HBoxContainer.new()
	_pawn_row.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	column.add_child(_pawn_row)

	_content_column = column

## Built on first `open()`, not in `_build()`: `create()` runs before this
## popout has a parent, so `_inspect`/`_equip` would enter a not-yet-live
## tree, get a manual `_ready()`, and then get a second, real one for free
## when the whole popout later enters `hud` -- doubling their connections.
## Building them once this popout is already live sidesteps it, matching
## how `PartySelect` embeds the same two panels.
var _content_column: VBoxContainer = null

func _ensure_panels() -> void:
	if _inspect != null:
		return
	_inspect = InspectPanelScript.create()
	_content_column.add_child(_inspect)
	if not _inspect.is_inside_tree():
		_inspect._ready()
	_inspect.embed()
	_inspect.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_equip = EquipPanelScript.create()
	_content_column.add_child(_equip)
	if not _equip.is_inside_tree():
		_equip._ready()
	_equip.embed()
	_equip.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _tab_button(text: String, index: int) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	button.pressed.connect(_show_tab.bind(index))
	return button

## `party`: every pawn this popout may switch between. `state`: the fight it
## was opened over, or null with no fight running. `focus`: who to land on.
func open(party: Array[PawnData], state, focus: PawnData) -> void:
	_ensure_panels()
	_party = party
	_state = state
	_focused = focus if focus != null else (party[0] if not party.is_empty() else null)
	visible = true
	var running: bool = state != null and state.outcome == CombatState.Outcome.UNRESOLVED
	_equip.set_locked(running, EQUIP_LOCKED_NOTE)
	_rebuild_pawn_row()
	_show_pawn(_focused)
	_show_tab(TAB_PLANS)

func _rebuild_pawn_row() -> void:
	for child in _pawn_row.get_children():
		child.free()
	_pawn_buttons = []
	## A single pawn is the common case a unit card opens this to -- no row to
	## switch between when there is nothing to switch to.
	if _party.size() <= 1:
		_pawn_row.visible = false
		return
	_pawn_row.visible = true
	for pawn in _party:
		var button := Button.new()
		button.text = pawn.display_name
		button.toggle_mode = true
		button.button_pressed = pawn == _focused
		button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
		button.pressed.connect(_on_pawn_pressed.bind(pawn))
		_pawn_row.add_child(button)
		_pawn_buttons.append(button)

func _on_pawn_pressed(pawn: PawnData) -> void:
	_focused = pawn
	for b in _pawn_buttons:
		b.button_pressed = b.text == pawn.display_name
	_show_pawn(pawn)

func _show_pawn(pawn: PawnData) -> void:
	if pawn == null:
		return
	_inspect.set_party_roster(_party)
	_inspect.show_pawn(pawn, _state)
	_equip.show_pawn(pawn)

func _show_tab(index: int) -> void:
	_active_tab = index
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == index
	_inspect.visible = index == TAB_PLANS
	_equip.visible = index == TAB_EQUIP

func close() -> void:
	visible = false
	closed.emit()

## Keyboard-first: Tab cycles the two tabs, Esc closes. `_unhandled_key_input`
## rather than `_gui_input` -- a popout that only reacted while it happened to
## hold focus would need a click before a key did anything, and the whole
## point of a keyboard-first menu is that it does not.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB:
		_show_tab(TAB_EQUIP if _active_tab == TAB_PLANS else TAB_PLANS)
		get_viewport().set_input_as_handled()
