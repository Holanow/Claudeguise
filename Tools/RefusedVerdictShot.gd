extends Node

## Issue 721: a photograph of the `refused` verdict -- a row whose condition
## holds, whose pawn is free, and whose skill `action_can_fire` refuses
## anyway, with the reason named beneath it. Driven through the screens a
## player uses -- party select, the room picker, the battle screen, its
## "Plans" button -- with a real fight running behind the panel.

const OUT_DIR := "res://Screenshots"
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const PARTY := [&"abomination", &"priest", &"geysermancer", &"warrior"]

var _main: Node
var _tag := ""

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("RefusedVerdictShot: refusing to run in the main checkout -- use a worktree.")
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
	print("RefusedVerdictShot: %s_%s.png" % [name, _tag])

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
	print("RefusedVerdictShot: no visible button '%s'" % prefix)
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
	print("RefusedVerdictShot: the picker offers no room matching '%s'" % want)
	return false

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var select := _node_with("PartySelect.gd")
	select._seed_edit.text = "00000001"
	select._seed_edit.text_submitted.emit("00000001")
	await _settle()
	if not ScreenSweepScript.add_presets(_main):
		print("RefusedVerdictShot: no PartySelect to add preset plans to")
		return false
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in PARTY:
		if not by_id.has(id):
			print("RefusedVerdictShot: no party card for class '%s'" % id)
			return false
		by_id[id].toggled.emit(true)
	await _settle()
	if not _select_room(select._room_picker, "room1"):
		return false
	await _settle()
	if not _press("start fight"):
		return false
	await _settle()
	var setup_view = _node_with("BattleView.gd")
	if setup_view != null and setup_view.setup:
		if not _press("start fight"):
			return false
		await _settle()
	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("RefusedVerdictShot: no battle screen")
		return false

	## One tick per call through the screen's own frame handler, with the
	## engine's own _process off so nothing else advances the fight -- the
	## same shape `Tools/HeldVerdictShot.gd` already uses for the same reason.
	battle.set_process(false)
	var probe := InspectPanel.create()
	probe._ready()
	var found = null
	for tick in 3000:
		battle._process(CG.TICK_SECONDS)
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		found = _pawn_with_a_refused_row(probe, battle.state)
		if found != null:
			break
	probe.free()
	if found == null:
		print("RefusedVerdictShot: no pawn carried a refused row across this fight")
		return false
	print("RefusedVerdictShot: %s has a refused row at tick %d" % [found.display_name, battle.state.tick])

	if not _press("plans"):
		return false
	await _settle()
	var panel := _node_with("InspectPanel.gd")
	if panel == null:
		print("RefusedVerdictShot: no plan editor")
		return false
	for n in _walk(panel):
		if n is Button and n.text == found.display_name:
			n.emit_signal("pressed")
			break
	await _settle()

	var refused_rows := 0
	for i in found.plans.size():
		var said: String = panel._live_verdict(found, found.plans[i])
		if said == InspectPanel.VERDICT_REFUSED:
			refused_rows += 1
		print("RefusedVerdictShot:   row %d %-38s screen says %s" % [
			i + 1, found.plans[i].display_name, said])
	for n in _walk(panel):
		if n is ScrollContainer:
			n.scroll_vertical = 100000
	await _settle()
	await _shot("sable_721_refused_names_the_gate")
	var rows: int = ScreenSweepScript.plan_row_count(panel)
	print("RefusedVerdictShot: the panel shows %d plan row(s), %d of them refused" % [rows, refused_rows])
	if rows == 0:
		printerr("RefusedVerdictShot: the plan editor is EMPTY, so the capture is of")
		printerr("  nothing and must not be cited as a picture of plan rows.")
		return false
	if refused_rows == 0:
		printerr("RefusedVerdictShot: no row reads `refused` here, so this picture is not")
		printerr("  evidence of the new word and must not be cited as it.")
		return false
	return true

## A party pawn that is free and carries at least one row the panel calls
## refused: condition held, `action_can_fire` did not.
func _pawn_with_a_refused_row(probe, state):
	probe._live_state = state
	for u in state.units:
		if not u.alive or u.pawn == null or u.is_busy():
			continue
		for plan in u.pawn.plans:
			if probe._live_verdict(u.pawn, plan) == InspectPanel.VERDICT_REFUSED:
				return u.pawn
	return null
