extends Node

## Issue 575: a photograph of the plan editor saying `ready` beside a row whose
## action cannot fire. Driven through the screens a player uses -- party select,
## the room picker, the battle screen's own tick, its "Plans" button.

const OUT_DIR := "res://Screenshots"
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const PARTY := [&"abomination", &"priest", &"geysermancer", &"warrior"]

var _main: Node
var _tag := ""

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ReadyVerdictShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("ReadyVerdictShot: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("ReadyVerdictShot: no visible button '%s'" % prefix)
	return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _select_room(picker: OptionButton, want: String) -> bool:
	for i in picker.item_count:
		if String(picker.get_item_metadata(i)).contains(want):
			picker.selected = i
			picker.item_selected.emit(i)
			return true
	print("ReadyVerdictShot: the picker offers no room matching '%s'" % want)
	return false

## Whether one row alone could act, asked exactly as `PlanInterpreter.decide`
## asks it, with `state.tick` advanced so cooldowns compare against the tick
## the decide phase would use and `focus_id` restored afterwards.
func _row_can_act(state, unit, plan) -> bool:
	var saved = unit.focus_id
	state.tick += 1
	var out := false
	if PlanInterpreter.condition_holds(state, unit, plan):
		out = PlanInterpreter._run_blocks(state, unit, plan) != null
	state.tick -= 1
	unit.focus_id = saved
	return out

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	## The seed picks the roster as well as the fight and a reroll frees the old
	## pawns, so the library is attached AFTER it (issue 538).
	var select := _node_with("PartySelect.gd")
	select._seed_edit.text = "00000001"
	select._seed_edit.text_submitted.emit("00000001")
	await _settle()
	if not ScreenSweepScript.add_presets(_main):
		print("ReadyVerdictShot: no PartySelect to add preset plans to")
		return false
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in PARTY:
		if not by_id.has(id):
			print("ReadyVerdictShot: no party card for class '%s'" % id)
			return false
		by_id[id].toggled.emit(true)
	await _settle()
	if not _select_room(select._room_picker, "room1"):
		return false
	await _settle()
	if not _press("start fight"):
		return false
	await _settle()
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		if not _press("start fight"):
			return false
		await _settle()
	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("ReadyVerdictShot: no battle screen")
		return false

	if not _press("plans"):
		return false
	await _settle()
	var panel := _node_with("InspectPanel.gd")
	if panel == null:
		print("ReadyVerdictShot: no plan editor")
		return false
	var pawn = null
	for u in battle.state.units:
		if u.pawn != null and u.pawn.pawn_class.id == PARTY[0]:
			pawn = u.pawn
			break
	if pawn == null:
		print("ReadyVerdictShot: no %s in the fight" % PARTY[0])
		return false
	for n in _walk(panel):
		if n is Button and n.text == pawn.display_name:
			n.emit_signal("pressed")
			break
	await _settle()

	var unit = null
	for u in battle.state.units:
		if u.pawn == pawn:
			unit = u
			break
	var wrong := 0
	for i in pawn.plans.size():
		var said: String = panel._live_verdict(pawn, pawn.plans[i])
		var can := _row_can_act(battle.state, unit, pawn.plans[i])
		if said == InspectPanel.VERDICT_READY and not can:
			wrong += 1
		print("ReadyVerdictShot:   row %d %-38s screen says %-8s can act %s" % [
			i + 1, pawn.plans[i].display_name, said, "yes" if can else "NO"])
	await _shot("wren_575_ready_beside_a_row_that_cannot_act")
	var rows: int = ScreenSweepScript.plan_row_count(panel)
	print("ReadyVerdictShot: the panel shows %d plan row(s), %d of them wrongly `ready`" % [rows, wrong])
	if rows == 0:
		printerr("ReadyVerdictShot: the plan editor is EMPTY, so the capture is of")
		printerr("  nothing and must not be cited as a picture of plan rows.")
		return false
	if wrong == 0:
		printerr("ReadyVerdictShot: no row is wrongly `ready` here, so this picture")
		printerr("  is not evidence of the defect and must not be cited as it.")
		return false
	return true
