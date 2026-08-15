extends Node

## Issue 145: drive the deploy screen the way a player does, and prove the
## fight starts the party where they put them.
##
##   godot --path . --resolution 1280x720 res://Tools/DeployShot.tscn
##
## Built on EquipShot's pattern -- the real Main scene, real controls. The drag
## is a real pushed press and a real pushed release on the canvas, not a call
## into the canvas's own methods: **pushed mouse BUTTON events do carry the
## position they are pushed with** (pushed *motion* events do not, which is why
## the move happens between press and release rather than during it).
##
## The last step is the one the issue actually asks for. It reads the party's
## positions out of the running `CombatState` after Start Fight, and compares
## them to what was on the deploy screen. A screenshot shows the pawns moved;
## only this shows the simulation agreed.

const CG := preload("res://Scripts/Core/CG.gd")

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""
var _failures: int = 0

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("DeployShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	print("DeployShot: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _settle(frames: int = 6) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, name, _res_tag]
	image.save_png(path)
	print("DeployShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("DeployShot: no visible button starting with '%s'" % prefix)
	return false

func _node_with(file: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(file):
			return n
	return null

func _check(ok: bool, message: String) -> void:
	if ok:
		print("DeployShot: OK   %s" % message)
	else:
		print("DeployShot: FAIL %s" % message)
		_failures += 1

## A real click at a world position, through the canvas's own `_gui_input`.
func _click_world(canvas: Control, world: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.world_to_local(world)
	canvas._gui_input(event)

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	# A fresh roster has nothing picked and the button reads "Pick a party to
	# fight", so pick four the way ScreenSweep does before anything else.
	var cards: Array[Node] = []
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	for i in mini(4, cards.size()):
		cards[i].toggled.emit(true)
	await _settle()

	if not _press("start fight"):
		return
	await _settle()

	var deploy := _node_with("DeployView.gd")
	_check(deploy != null, "Start Fight reaches the deploy screen")
	if deploy == null:
		return
	await _shot("wren_deploy_room")

	var canvas: Control = deploy._canvas
	var opened: Array = deploy.placements()
	print("DeployShot: opened at %s" % str(opened))
	_check(opened.size() >= 4, "a marker for every party member")

	# Drag the LAST pawn to the front of the line. That is the decision the
	# issue is about: who stands nearest, which list order used to decide
	# invisibly.
	var last := opened.size() - 1
	var target := Vector2(CG.party_deploy_max_x() - 30.0, 0.0)
	_click_world(canvas, opened[last], true)
	_check(canvas.held_party_spawn() == last, "pressing on a pawn picks it up")
	_click_world(canvas, target, false)
	await _settle()

	var after: Array = deploy.placements()
	print("DeployShot: after drag %s" % str(after))
	_check(after[last] != opened[last], "a real pushed press and release moved the pawn")
	_check(after[last].x <= CG.party_deploy_max_x() + 0.001,
		"and it stayed inside the deploy zone (x=%.1f, line=%.1f)" % [after[last].x, CG.party_deploy_max_x()])
	await _shot("wren_deploy_moved")

	# Try to shove one past the line, which a player will do within seconds.
	_click_world(canvas, after[0], true)
	_click_world(canvas, Vector2(400.0, 0.0), false)
	await _settle()
	var shoved: Array = deploy.placements()
	_check(shoved[0].x <= CG.party_deploy_max_x() + 0.001,
		"dragging past the line is refused, not obeyed (x=%.1f)" % shoved[0].x)
	await _shot("wren_deploy_zone_refused")

	var expected: Array = deploy.placements()
	if not _press("start fight"):
		return

	# ONE frame, not ten. The first version settled ten and then compared, and
	# two pawns had already started walking -- so it reported a mismatch that
	# was my instrument advancing the fight, not the placement being ignored.
	# A start position can only be read before the thing starts moving.
	await get_tree().process_frame

	var battle := _node_with("BattleView.gd")
	_check(battle != null, "Start Fight reaches the battle")
	if battle == null:
		return

	# THE CRITERION. Where the simulation actually put them, at tick 0.
	var tick: int = battle.state.tick
	var placed: Array = []
	for u in battle.state.units:
		if u.team == CG.Team.PLAYER:
			placed.append(u.position)
	print("DeployShot: at tick %d the fight has the party at %s" % [tick, str(placed)])
	_check(tick == 0, "read before the fight moved anybody (tick %d)" % tick)
	_check(placed.size() == expected.size(), "the fight built every party member")
	var all_match := placed.size() == expected.size()
	for i in mini(placed.size(), expected.size()):
		if placed[i] != expected[i]:
			all_match = false
			print("DeployShot:   pawn %d placed at %s, fight started it at %s" % [i, str(expected[i]), str(placed[i])])
	_check(all_match, "THE FIGHT STARTED THE PARTY WHERE THEY WERE PLACED")

	await _settle()
	await _shot("wren_deploy_fight_started")
	await _terrain_room()

## The issue names terrain as the thing that makes placement a decision rather
## than a fiddle, and `floor1_room1` -- the only room the menus can currently
## reach -- has none. So this renders a room that does, directly rather than
## through the menu, and says so.
##
## **Reaching any other room from the menu is issue 94's room picker, which is
## not built.** Naming the gap rather than letting a capture of room 1 imply
## terrain was verified.
func _terrain_room() -> void:
	var Registry = load("res://Scripts/Content/Registry.gd")
	var RunConfigScript = load("res://Scripts/Core/RunConfig.gd")
	var PawnFactory = load("res://Scripts/Content/PawnFactory.gd")
	var chosen: StringName = &""
	for id in Registry.all_encounter_ids():
		if not Registry.get_encounter(id).terrain.is_empty():
			chosen = id
			break
	if chosen == &"":
		print("DeployShot: no registered room has terrain -- nothing to show")
		return
	print("DeployShot: rendering '%s', which has terrain" % chosen)

	_main.queue_free()
	await _settle()
	var cfg = RunConfigScript.new()
	var party: Array = []
	var ids = Registry.all_class_ids()
	for i in 4:
		party.append(PawnFactory.make_starter_pawn(ids[i % ids.size()], StringName("p%d" % i), String(ids[i % ids.size()]).capitalize()))
	cfg.party.assign(party)
	cfg.encounter_id = chosen
	cfg.seed = 7

	var screen := Control.new()
	screen.set_script(load("res://Scripts/UI/DeployView.gd"))
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _settle()
	screen.open(cfg)
	await _settle()
	_check(screen._canvas._floor.terrain.size() > 0,
		"the room's terrain reached the ArenaFloor that draws it (%d features)" % screen._canvas._floor.terrain.size())
	await _shot("wren_deploy_terrain_room")
