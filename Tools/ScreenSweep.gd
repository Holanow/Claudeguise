extends Node

## Issue 53: sweep every screen the game has, at both resolutions the game is
## required to work at, and actually look. Built on Issue32Play's pattern --
## real Main scene, real controls, no synthetic OS input -- extended to visit
## every screen rather than only the battle loop: party select (empty and
## full), inspect (which is also where the plan editor lives -- there is no
## separate plan-editor screen, see InspectPanel.gd), floor map, battle,
## end-of-fight banner, and the level editor.
##
##   godot --path . --resolution 1280x720 res://Tools/ScreenSweep.tscn
##   godot --path . --resolution 844x390  res://Tools/ScreenSweep.tscn
##
## Screenshots land in Screenshots/ with a _<w>x<h> suffix matching the launch
## resolution, so both passes can run into the same directory without
## clobbering each other.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ScreenSweep: refusing to run in the main checkout -- run from a")
		printerr("  detached worktree instead.")
		get_tree().quit(2)
		return
	# get_viewport().get_visible_rect().size is the project's *logical*
	# canvas_items/expand coordinate space, not the physical window --
	# project.godot keeps design height fixed and widens design width to
	# match a wider physical aspect, so an 844x390 launch reports a viewport
	# of roughly 1558x720 in design space. lark found the same trap in issue
	# 42's own disclosure (a synthetic Control root there; this is the real
	# window). The filenames need to say what was actually launched.
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	get_tree().quit(0)

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, name, _res_tag]
	image.save_png(path)
	print("ScreenSweep: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for n in _walk(_main):
		if n is Button:
			out.append(n)
	return out

func _party_cards() -> Array:
	var out := []
	for n in _walk(_main):
		if n is Control and not (n is Button) and n.has_signal("toggled"):
			out.append(n)
	return out

func _press_named(prefix: String) -> bool:
	for b in _buttons():
		if b.text.to_lower().begins_with(prefix.to_lower()) and b.is_visible_in_tree():
			if b.disabled:
				print("ScreenSweep: button '%s' is DISABLED, not pressing" % b.text)
				return false
			b.emit_signal("pressed")
			return true
	print("ScreenSweep: no visible button starting with '%s' found" % prefix)
	return false

func _current_screen_name() -> String:
	for c in _main.get_children():
		return c.name
	return "<none>"

func _fresh_main() -> void:
	if _main != null:
		_main.queue_free()
		await _settle()
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

# ---------------------------------------------------------------------------

func _run() -> void:
	await _party_select_empty()
	await _party_select_full_and_start_fight()
	await _inspect_from_party_select()
	await _level_editor()
	await _floor_map_and_end_of_fight()

## Party select, nothing picked yet -- the very first screen a player sees.
func _party_select_empty() -> void:
	await _fresh_main()
	await _shot("sweep_party_select_empty")

## Pick a full party of four, then confirm Start Fight is on screen and
## clickable before pressing it, then follow the fight to its end banner.
func _party_select_full_and_start_fight() -> void:
	await _fresh_main()
	var cards := _party_cards()
	for i in mini(4, cards.size()):
		cards[i].toggled.emit(true)
	await get_tree().process_frame
	await _shot("sweep_party_select_full")

	var start_btn: Button = null
	for b in _buttons():
		if b.text.to_lower().begins_with("start fight"):
			start_btn = b
			break
	if start_btn == null:
		print("ScreenSweep: NO 'Start Fight' BUTTON FOUND at %s" % _res_tag)
	else:
		var rect := start_btn.get_global_rect()
		var vp := get_viewport().get_visible_rect()
		var on_screen := vp.intersects(rect) and rect.position.y >= 0.0 and rect.position.y < vp.size.y
		print("ScreenSweep: Start Fight rect=%s viewport=%s on_screen=%s disabled=%s at %s" % [
			rect, vp.size, on_screen, start_btn.disabled, _res_tag
		])

	_press_named("start fight")
	await _settle()
	if _current_screen_name() != "Battle":
		print("ScreenSweep: did not reach Battle from Start Fight at %s" % _res_tag)
		return
	var battle := _main.get_child(0)
	await _shot("sweep_battle_start")

	var frames := 0
	var max_wait_frames := 60 * 150
	var mid_shot_taken := false
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < max_wait_frames:
		await get_tree().process_frame
		frames += 1
		if not mid_shot_taken and battle.state.tick >= 60:
			mid_shot_taken = true
			await _shot("sweep_battle_mid")

	await _shot("sweep_battle_end_banner")
	print("ScreenSweep: fight ended outcome=%s tick=%d at %s" % [
		CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick, _res_tag
	])

## The inspect screen, opened from party select. This is also where the plan
## editor lives -- issue 53 names it separately but InspectPanel.gd's own
## header comment is explicit there is no separate screen. Pick a pawn with
## real plans (Warrior ships one) and scroll the detail panel so the plan
## row's Condition/Targeting/Action editors are actually on screen, since
## that is where the reported overlap lives.
func _inspect_from_party_select() -> void:
	await _fresh_main()
	if not _press_named("inspect classes"):
		return
	await _settle()
	await _shot("sweep_inspect_default")

	# Select the Warrior specifically -- it ships a real plan with a
	# Condition, a Targeting block and an Action block, which is the row
	# the overlap was found in.
	var inspect_panel = null
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("InspectPanel.gd"):
			inspect_panel = n
			break
	if inspect_panel == null:
		print("ScreenSweep: could not find InspectPanel node")
		return
	for b in _buttons():
		if b.text == "Warrior":
			b.emit_signal("pressed")
			break
	await _settle()

	# Scroll the detail panel to the bottom so the plan row's pickers are in
	# frame -- ScrollContainer under body/detail_scroll per InspectPanel.gd.
	for n in _walk(inspect_panel):
		if n is ScrollContainer:
			n.scroll_vertical = 100000
	await _settle()
	await _shot("sweep_inspect_plan_editor")

## The level editor, reached from party select.
func _level_editor() -> void:
	await _fresh_main()
	if not _press_named("level editor"):
		return
	await _settle()
	await _shot("sweep_level_editor")

## The floor map, reached via Start Run, plus whichever room resolves first.
func _floor_map_and_end_of_fight() -> void:
	await _fresh_main()
	var cards := _party_cards()
	for i in mini(4, cards.size()):
		cards[i].toggled.emit(true)
	await get_tree().process_frame

	var run_btn: Button = null
	for b in _buttons():
		if b.text.to_lower().begins_with("start run"):
			run_btn = b
			break
	if run_btn == null:
		print("ScreenSweep: NO 'Start Run' BUTTON FOUND at %s" % _res_tag)
		return
	run_btn.emit_signal("pressed")
	await _settle()
	if _current_screen_name() != "FloorMap":
		print("ScreenSweep: did not reach FloorMap from Start Run at %s" % _res_tag)
		return
	await _shot("sweep_floor_map")
