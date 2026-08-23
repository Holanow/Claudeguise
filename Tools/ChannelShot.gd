extends Node

## Issue 166: the Channel row on the plan editor, and the same Priest mid-cast
## in a real fight.

const OUT_DIR := "res://Screenshots"
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _main: Node
var _res_tag: String = ""
var _failed := false

func _ready() -> void:
	if not Offscreen.require_renderer(self):
		return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ChannelShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	get_tree().quit(3 if _failed else 0)

## A capture tool that returns early on a failed step reports an absence as a
## result, so a skipped capture fails the run (#371).
func _fail(msg: String) -> void:
	_failed = true
	printerr("ChannelShot: %s" % msg)

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, name, _res_tag]
	image.save_png(path)
	print("ChannelShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _panel(file: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(file):
			return n
	return null

func _reveal(c: Control) -> void:
	for n in _walk(_panel("InspectPanel.gd")):
		if n is ScrollContainer and n.is_ancestor_of(c):
			n.ensure_control_visible(c)
	await _settle()

## The picker showing "Channel", found by what it says rather than by index.
func _channel_picker() -> OptionButton:
	for n in _walk(_panel("InspectPanel.gd")):
		if n is OptionButton and n.selected >= 0 and n.get_item_text(n.selected) == "Channel":
			return n
	return null

func _party_cards() -> Array:
	var out := []
	for n in _walk(_main):
		if n is Control and not (n is Button) and n.has_signal("toggled"):
			out.append(n)
	return out

func _card_for(cards: Array, class_id: StringName) -> Control:
	for c in cards:
		if c is PartyCard and (c as PartyCard).class_def != null 				and (c as PartyCard).class_def.id == class_id:
			return c
	return null

func _press_named(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and (n as Button).text.to_lower().begins_with(prefix.to_lower()) 				and (n as Button).is_visible_in_tree() and not (n as Button).disabled:
			(n as Button).emit_signal("pressed")
			return true
	printerr("ChannelShot: no visible button starting with '%s'" % prefix)
	return false

func _current_screen_name() -> String:
	for c in _main.get_children():
		return c.name
	return "<none>"

func _channeller(state: CombatState) -> CombatUnit:
	for u in state.living(CG.Team.PLAYER):
		if u.current_action == &"channel_mana" and u.action_ticks_left > 0:
			return u
	return null

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	## Since #399 a starter pawn carries no plan rows, so the Priest never held a
	## Channel and both of this tool's "nothing happened" lines were its own
	## blindness rather than a finding (#417).
	if not ScreenSweepScript.add_presets(_main):
		_fail("no PartySelect to add preset plans to")
		return

	var select := _panel("PartySelect.gd")
	if select == null:
		_fail("the landing screen is not PartySelect")
		return
	# The Priest, picked and focused through the same calls a card click makes.
	var cards := _party_cards()
	var priest_card := _card_for(cards, &"priest")
	if priest_card == null:
		_fail("no Priest card")
		return
	priest_card.toggled.emit(true)
	var picked := 1
	for c in cards:
		if picked >= 4:
			break
		if c != priest_card:
			c.toggled.emit(true)
			picked += 1
	select.focus_pawn(select.available_pawns()[cards.find(priest_card)])
	await _settle(8)

	_press_named("start fight")
	await _settle()
	if _screen_is_in_setup():
		_press_named("start fight")
		await _settle()
	if _current_screen_name() != "Battle":
		_fail("did not reach Battle, got '%s'" % _current_screen_name())
		return
	# The full plan screen, where a row is wide enough to read. The embedded
	# panel on PartySelect truncates every picker to two characters.
	_press_named("plans")
	await _settle(8)
	var picker := _channel_picker()
	if picker == null:
		_fail("no row on the plan screen says Channel")
	else:
		await _reveal(picker)
		print("ChannelShot: a Priest row reads '%s'" % picker.get_item_text(picker.selected))
		await _shot("finch_channel_plan_row")
	_press_named("back")
	await _settle(8)

	var battle := _main.get_child(0)
	var frames := 0
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < 60 * 400:
		await get_tree().process_frame
		frames += 1
		var caster := _channeller(battle.state)
		if caster != null:
			await _shot("finch_channel_in_a_fight")
			print("ChannelShot: %s is Channelling at tick %d, %d ticks left" % [
				caster.display_name, battle.state.tick, caster.action_ticks_left])
			return
	_fail("nobody Channelled before the fight ended (tick %d)" % battle.state.tick)

## True while the battle screen is held before its first tick with the party
## draggable, which is where "Start Fight" means "begin" rather than "place".
func _screen_is_in_setup() -> bool:
	var screen = _main._current if _main != null else null
	return screen != null and "setup" in screen and screen.setup
