extends Control
class_name TeamStatusView


## The player's whole team in one place that does not move: health, resource,
## statuses and cooldowns in a fixed column, which is what makes comparing two
## party compositions possible.
const MAX_PAWN_ROWS := 4
const MAX_SUMMON_ROWS := 2
const MAX_ROWS := MAX_PAWN_ROWS + MAX_SUMMON_ROWS

## From the measurement above. A third slot has never been earned.
const MAX_COOLDOWN_CHIPS := 2

const BAR_WIDTH := 172.0
const PANEL_WIDTH := BAR_WIDTH + Palette.SPACE_S * 2.0
const HP_BAR_HEIGHT := 8.0
const RESOURCE_BAR_HEIGHT := 6.0
const LINE_SEPARATION := 2.0
const ROW_SEPARATION := 6.0

## **A summon gets one line, a pawn gets four, and that asymmetry is the only
## reason this panel fits beside the log at 1280x720.**
##
## It is also true rather than convenient. A siege engine has no resource, no
## plans, and no action carrying a cooldown -- three of a pawn row's four lines
## would be permanently empty on it. What a player needs to know about a summon
## is that it is there and how much of it is left, which is a name and a health
## bar.
const MAX_PANEL_HEIGHT := 438.0

var _rows: VBoxContainer = null
var _backdrop: ColorRect = null
var _row_by_id: Dictionary = {}
var _overflow_label: Label = null

func _ready() -> void:
	theme = AppTheme.paper()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

	_backdrop = ColorRect.new()
	_backdrop.color = Palette.PAPER_LEAF
	_backdrop.color.a = 0.72
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_rows = VBoxContainer.new()
	_rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rows.offset_left = Palette.SPACE_S
	_rows.offset_right = -Palette.SPACE_S
	_rows.offset_top = Palette.SPACE_S
	_rows.offset_bottom = -Palette.SPACE_S
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", int(ROW_SEPARATION))
	add_child(_rows)

	var heading := Label.new()
	heading.text = "Your team"
	heading.add_theme_color_override("font_color", Palette.INK_DIM)
	heading.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_rows.add_child(heading)

	_overflow_label = Label.new()
	_overflow_label.add_theme_color_override("font_color", Palette.INK_DIM)
	_overflow_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_overflow_label.visible = false
	_rows.add_child(_overflow_label)

# --- what goes in it -------------------------------------------------------
#
# Every question the panel answers is a static function taking the state, so a
# test can ask it without a viewport. The board's rule 2 is the reason: a thing
# that can only be reached through `_draw()` is a thing no assertion can see,
# and this project has shipped twelve features that were unreachable.

## The units that get a row, in the order they get one: the player's pawns in
## party order first, then whatever they have summoned that is still alive.
static func rows_for(state: CombatState) -> Array:
	var pawns := _player_pawns(state)
	var summons := _live_summons(state)
	return pawns.slice(0, mini(pawns.size(), MAX_PAWN_ROWS)) \
		+ summons.slice(0, mini(summons.size(), MAX_SUMMON_ROWS))

## Counted per kind, not off one total, because the two caps are separate. A
## fifth pawn and a third engine are both hidden and one total would be able to
## report zero while a row was missing.
static func hidden_row_count(state: CombatState) -> int:
	return maxi(0, _player_pawns(state).size() - MAX_PAWN_ROWS) \
		+ maxi(0, _live_summons(state).size() - MAX_SUMMON_ROWS)

static func is_summon(u: CombatUnit) -> bool:
	return u.team == CG.Team.PLAYER and not CombatSim.is_party_member(u)

static func _player_pawns(state: CombatState) -> Array:
	var out: Array = []
	for u in state.units:
		if CombatSim.is_party_member(u):
			out.append(u)
	return out

static func _live_summons(state: CombatState) -> Array:
	var out: Array = []
	for u in state.units:
		if is_summon(u) and u.alive:
			out.append(u)
	return out

## Whether this unit owns any action that is gated by a cooldown at all.
static func has_cooldown_actions(u: CombatUnit) -> bool:
	for action_id in u.actions:
		var a = ActionLibrary.get_action(action_id)
		if a != null and a.cooldown_ticks > 0:
			return true
	return false

## The cooldowns actually running on this unit right now, soonest ready first,
## capped at MAX_COOLDOWN_CHIPS.
static func cooldowns_for(state: CombatState, u: CombatUnit) -> Array:
	var running: Array = []
	if state.outcome != CombatState.Outcome.UNRESOLVED:
		return running
	for action_id in u.actions:
		var a = ActionLibrary.get_action(action_id)
		if a == null or a.cooldown_ticks <= 0:
			continue
		if not u.cooldowns.has(action_id):
			continue
		var left: int = int(u.cooldowns[action_id]) - state.tick
		if left <= 0:
			continue
		running.append({
			"action_id": action_id,
			"ticks_left": left,
			"fraction": clampf(float(left) / float(a.cooldown_ticks), 0.0, 1.0),
			"damage_type": a.damage_type,
			"display_name": a.display_name if a.display_name != "" else String(action_id).capitalize(),
			"cooldown_ticks": a.cooldown_ticks,
		})
	running.sort_custom(func(x, y): return int(x["ticks_left"]) < int(y["ticks_left"]))
	if running.size() <= MAX_COOLDOWN_CHIPS:
		return running
	return running.slice(0, MAX_COOLDOWN_CHIPS)

## What the cooldown line says when there are no chips to draw on it. Empty
## string means chips are being drawn and this is not used.
static func cooldown_summary(state: CombatState, u: CombatUnit) -> String:
	## Issue 442: a cooldown is a statement about what this unit does next, and
	## a resolved fight has no next. A blind playtester read a 29.1s countdown
	## beside a card saying the fight took 15.6s and had ended.
	if state.outcome != CombatState.Outcome.UNRESOLVED:
		return ""
	if not cooldowns_for(state, u).is_empty():
		return ""
	if not has_cooldown_actions(u):
		return "No cooldowns"
	return "All ready"

static func seconds_text(ticks: int) -> String:
	return "%.1fs" % (float(ticks) / float(CG.TICKS_PER_SECOND))

# --- drawing it ------------------------------------------------------------

## Called every stepped tick from `BattleView._process`. Rows are added and
## removed only when the set of units changes; everything else is written into
## nodes that already exist.
func sync(state: CombatState) -> void:
	if state == null or _rows == null:
		return
	var units := rows_for(state)
	var wanted := {}
	for u in units:
		wanted[u.id] = true
	for id in _row_by_id.keys():
		if not wanted.has(id):
			_rows.remove_child(_row_by_id[id])
			_row_by_id[id].queue_free()
			_row_by_id.erase(id)
	for i in units.size():
		var u: CombatUnit = units[i]
		if not _row_by_id.has(u.id):
			_row_by_id[u.id] = _build_row(u)
			_rows.add_child(_row_by_id[u.id])
		# +1 for the heading, which is always child 0.
		_rows.move_child(_row_by_id[u.id], i + 1)
		_update_row(_row_by_id[u.id], state, u)
	_rows.move_child(_overflow_label, _rows.get_child_count() - 1)
	var hidden := hidden_row_count(state)
	_overflow_label.visible = hidden > 0
	_overflow_label.text = "+%d more" % hidden
	# The backdrop is drawn to the rows it actually has, so a fight with no
	# summons does not show two empty slots waiting for one. The log's inset does
	# NOT follow this (see MAX_PANEL_HEIGHT) -- the panel may grow and shrink, the
	# log may not move.
	offset_bottom = offset_top + panel_height()

	# Issue 245. The status popups now carry a stack count and a countdown, so a
	# popout pinned off one of these chips has to be re-read or it says something
	# that was true four seconds ago. Driven from here rather than from a timer
	# because this is the function that knows the numbers moved, and a popout on
	# its own clock could show a different tick from the chip above it.
	var layer := PopoutLayer.of(self)
	if layer != null:
		layer.refresh()

## What the panel is tall right now, summed off the rows that exist rather than
## computed from constants describing them. `state` is unused and kept because
## every caller has one and a height that silently stopped following the fight
## would be the hard kind of wrong.
func panel_height(_state: CombatState = null) -> float:
	var total := Palette.SPACE_S * 2.0
	var shown := 0
	for child in _rows.get_children():
		if not child.visible:
			continue
		total += child.get_combined_minimum_size().y
		shown += 1
	return total + float(maxi(shown - 1, 0)) * ROW_SEPARATION

func row_count() -> int:
	return _row_by_id.size()

## One row's nodes, built once. Every chip slot is created here and shown or
## hidden later rather than created on demand, so a chip the player is hovering
## survives the status it names being reapplied.
func _build_row(u: CombatUnit) -> Control:
	if is_summon(u):
		return _build_summon_row(u)
	return _build_pawn_row(u)

func _build_summon_row(u: CombatUnit) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0.0, IconChip.ICON_SIZE)
	row.set_meta("summon", true)

	var name_label := Label.new()
	name_label.set_script(GlossaryLabel)
	name_label.text = u.display_name
	name_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	if not name_label.is_inside_tree():
		name_label._ready()
	row.add_child(name_label)
	row.set_meta("name_label", name_label)
	row.set_meta("hp_fill", _build_bar(row, HP_BAR_HEIGHT, SUMMON_BAR_WIDTH))
	return row

func _build_pawn_row(u: CombatUnit) -> Control:
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(LINE_SEPARATION))
	row.set_meta("summon", false)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	head.custom_minimum_size = Vector2(0.0, IconChip.ICON_SIZE)
	row.add_child(head)

	var name_label := Label.new()
	name_label.set_script(GlossaryLabel)
	name_label.text = u.display_name
	name_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	if not name_label.is_inside_tree():
		name_label._ready()
	head.add_child(name_label)
	row.set_meta("name_label", name_label)

	var status_chips: Array[Control] = []
	for i in UnitView.MAX_STATUS_BADGES:
		var chip := _new_chip()
		head.add_child(chip)
		status_chips.append(chip)
	row.set_meta("status_chips", status_chips)

	# Issue 449: a "+2" nobody can expand hides exactly the two statuses a player
	# most wants named, so it is a hover target rather than a Label.
	var overflow := Label.new()
	overflow.set_script(GlossaryLabel)
	overflow.add_theme_color_override("font_color", Palette.INK_DIM)
	overflow.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	overflow.visible = false
	if not overflow.is_inside_tree():
		overflow._ready()
	head.add_child(overflow)
	row.set_meta("status_overflow", overflow)

	row.set_meta("hp_fill", _build_bar(row, HP_BAR_HEIGHT))
	row.set_meta("resource_fill", _build_bar(row, RESOURCE_BAR_HEIGHT))

	var cd_line := HBoxContainer.new()
	cd_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_line.custom_minimum_size = Vector2(0.0, IconChip.ICON_SIZE)
	row.add_child(cd_line)

	var cd_chips: Array[Control] = []
	for i in MAX_COOLDOWN_CHIPS:
		var chip := _new_chip()
		cd_line.add_child(chip)
		cd_chips.append(chip)
	row.set_meta("cooldown_chips", cd_chips)

	var cd_note := Label.new()
	cd_note.add_theme_color_override("font_color", Palette.INK_DIM)
	cd_note.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	cd_note.visible = false
	cd_line.add_child(cd_note)
	row.set_meta("cooldown_note", cd_note)

	return row

func _new_chip() -> Control:
	var chip := Control.new()
	chip.set_script(IconChip)
	chip.visible = false
	if not chip.is_inside_tree():
		chip._ready()
	return chip

## A trough and a fill, the same two-rect language the unit bars and the two
## team summary bars already use. Fixed width rather than the container's, so
## the fill can be resized before the container has ever been laid out -- which
## is every test and the first frame.
func _build_bar(parent: Control, height: float, width: float = BAR_WIDTH) -> ColorRect:
	var back := ColorRect.new()
	back.color = Palette.PAPER_SHADE
	back.custom_minimum_size = Vector2(width, height)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_meta("bar_width", width)
	parent.add_child(back)

	var fill := ColorRect.new()
	fill.position = Vector2.ZERO
	fill.size = Vector2(width, height)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return fill

## A summon's bar is short and sits beside its name rather than under it. Its
## own trough carries its width so the fill is not scaled against the pawn
## rows' 244.
const SUMMON_BAR_WIDTH := 96.0

static func _set_bar(fill: ColorRect, fraction: float, color: Color) -> void:
	var width: float = fill.get_parent().get_meta("bar_width")
	fill.size.x = width * clampf(fraction, 0.0, 1.0)
	fill.color = color

static func _fraction(current: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return clampf(float(maxi(current, 0)) / float(total), 0.0, 1.0)

func _update_row(row: Control, state: CombatState, u: CombatUnit) -> void:
	var name_label: Label = row.get_meta("name_label")
	name_label.text = u.display_name
	# Issue 449. Written every sync, not once at build: the old sentence named
	# the bars ("health, then resource, then anything this pawn is waiting on"),
	# which a player can already see. What they cannot see is the numbers in it.
	name_label.tooltip_text = Glossary.team_row_text(state, u)
	# A dead pawn keeps its row and stops shouting from it. The name is the only
	# thing left that can carry "this one is gone" once both bars read zero.
	name_label.add_theme_color_override("font_color", Palette.INK if u.alive else Palette.INK_DIM)

	var hp_fraction := _fraction(u.hp, u.hp_max)
	_set_bar(row.get_meta("hp_fill"), hp_fraction, Palette.hp_color(hp_fraction))
	if bool(row.get_meta("summon")):
		return

	_set_bar(row.get_meta("resource_fill"), _fraction(u.resource, u.resource_max),
		Palette.resource_color(u.resource_kind))
	_update_status_chips(row, state, u)
	_update_cooldown_chips(row, state, u)

## The same two badges the unit itself carries, from the same ordering, so a
## player looking from the panel to the pawn is not shown two different answers.
func _update_status_chips(row: Control, state: CombatState, u: CombatUnit) -> void:
	var badges := UnitView.status_badges(u)
	var chips: Array = row.get_meta("status_chips")
	for i in chips.size():
		var chip: Control = chips[i]
		if i >= badges.size():
			chip.visible = false
			continue
		var status: CG.Status = badges[i]
		chip.kind = IconChip.Kind.STATUS
		chip.status = status
		chip.text = ""
		chip.sweep = -1.0
		chip.pin_title = status_name(status)
		chip.tooltip_text = Glossary.status_popup_text(u, status, state.tick)
		chip.custom_minimum_size = Vector2(chip.measured_width(), IconChip.ICON_SIZE)
		chip.visible = true
		chip.queue_redraw()
	var overflow: Label = row.get_meta("status_overflow")
	var hidden := UnitView.hidden_status_count(u)
	overflow.visible = hidden > 0
	overflow.text = "+%d" % hidden
	overflow.tooltip_text = Glossary.hidden_statuses_text(state, u)

## `CG.Status.keys()` is what the log, the plan sentence and the condition editor
## all read, and this is the fourth reader. Four screens calling one status three
## different names is the failure this avoids.
static func status_name(status: CG.Status) -> String:
	return Glossary.status_name(status)

func _update_cooldown_chips(row: Control, state: CombatState, u: CombatUnit) -> void:
	var running := cooldowns_for(state, u)
	var chips: Array = row.get_meta("cooldown_chips")
	for i in chips.size():
		var chip: Control = chips[i]
		if i >= running.size():
			chip.visible = false
			continue
		var entry: Dictionary = running[i]
		chip.kind = IconChip.Kind.ACTION
		chip.action_id = entry["action_id"]
		chip.damage_type = entry["damage_type"]
		chip.sweep = entry["fraction"]
		chip.text = seconds_text(int(entry["ticks_left"]))
		chip.pin_title = entry["display_name"]
		chip.tooltip_text = "%s is on cooldown for another %s of %s." % [
			entry["display_name"],
			seconds_text(int(entry["ticks_left"])),
			seconds_text(int(entry["cooldown_ticks"])),
		]
		chip.custom_minimum_size = Vector2(chip.measured_width(), IconChip.ICON_SIZE)
		chip.visible = true
		chip.queue_redraw()
	var note: Label = row.get_meta("cooldown_note")
	var summary := cooldown_summary(state, u)
	note.visible = summary != ""
	note.text = summary
