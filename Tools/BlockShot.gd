extends Node

## The battle screen at the tick a Warrior first raises his block, because
## `ScreenSweep` takes the first four class cards and the Warrior is the fifth,
## so no whole-game screenshot this project has ever taken contains one.

const OUT_DIR := "res://Screenshots"

## Since #399 a starter pawn has NO plan rows, so a Warrior picked out of the
## roster never casts anything and this tool photographed 262 ticks of nothing.
## It adds the class's presets, which is the state a player reaches by adding
## every row in the library; it does not author a plan the game cannot.
const SHOT_NAME := "sable_block_named"

## A fixed seed, so a before and an after are the same fight at the same tick.
const SEED := "81F7614F"

var _main: Node
var _res_tag: String = ""

func _ready() -> void:
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	get_tree().quit(0)

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	_add_presets()
	_set_seed()
	var cards := _party_cards()
	var warrior_card := _warrior_card(cards)
	if warrior_card == null:
		printerr("BlockShot: no Warrior card found among %d cards" % cards.size())
		return
	warrior_card.toggled.emit(true)
	var picked := 1
	for c in cards:
		if picked >= 4:
			break
		if c != warrior_card:
			c.toggled.emit(true)
			picked += 1
	await _settle()

	_press_named("start fight")
	await _settle()
	if _screen_is_in_setup():
		_press_named("start fight")
		await _settle()
	if _current_screen_name() != "Battle":
		printerr("BlockShot: did not reach Battle, got '%s'" % _current_screen_name())
		return

	var battle := _main.get_child(0)
	var frames := 0
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < 60 * 400:
		await get_tree().process_frame
		frames += 1
		var shielder := _shielder(battle.state)
		if shielder != null:
			await _shot(SHOT_NAME)
			print("BlockShot: %s is SHIELDING at tick %d, position %s, facing %s" % [
				shielder.display_name, battle.state.tick, shielder.position, shielder.facing])
			return
	printerr("BlockShot: no shield went up before the fight ended (tick %d)" % battle.state.tick)

func _set_seed() -> void:
	for n in _walk(_main):
		if n is PartySelect:
			(n as PartySelect).prefill_seed(SEED)
			return

func _add_presets() -> void:
	for n in _walk(_main):
		if not (n is PartySelect):
			continue
		for pawn in (n as PartySelect)._available:
			pawn.plans = PresetPlans.for_class(pawn.pawn_class.id)
		return
	printerr("BlockShot: no PartySelect to add presets to")

func _shielder(state: CombatState) -> CombatUnit:
	for u in state.living(CG.Team.PLAYER):
		if u.has_status(CG.Status.SHIELDING) and u.facing != Vector2.ZERO:
			return u
	return null

func _warrior_card(cards: Array) -> Control:
	for c in cards:
		if not (c is PartyCard) or (c as PartyCard).class_def == null:
			continue
		if String((c as PartyCard).class_def.display_name).findn("warrior") != -1:
			return c
	return null

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var tag := OS.get_environment("BLOCKSHOT_TAG")
	var path := "%s/%s_%s%s.png" % [OUT_DIR, name, _res_tag, "" if tag == "" else "_" + tag]
	image.save_png(path)
	print("BlockShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _party_cards() -> Array:
	var out := []
	for n in _walk(_main):
		if n is Control and not (n is Button) and n.has_signal("toggled"):
			out.append(n)
	return out

func _press_named(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and (n as Button).text.to_lower().begins_with(prefix.to_lower()) \
				and (n as Button).is_visible_in_tree() and not (n as Button).disabled:
			(n as Button).emit_signal("pressed")
			return true
	printerr("BlockShot: no visible button starting with '%s'" % prefix)
	return false

func _current_screen_name() -> String:
	for c in _main.get_children():
		return c.name
	return "<none>"

## True while the battle screen is held before its first tick with the party
## draggable, which is where "Start Fight" means "begin" rather than "place".
func _screen_is_in_setup() -> bool:
	var screen = _main._current if _main != null else null
	return screen != null and "setup" in screen and screen.setup
