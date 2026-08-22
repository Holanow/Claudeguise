extends Node

## Issue 442: the defeat card the seventh blind playtester photographed, on the
## real screen, with the real team panel beside it. The loss is FORCED rather
## than fought -- every pawn is killed and two engines are left standing -- so
## the layout is real and the fight is not.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"

var _main: Node

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("EndCardShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	return false

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var s := DisplayServer.window_get_size()
	img.save_png("%s/%s_%dx%d.png" % [OUT_DIR, name, int(s.x), int(s.y)])
	print("EndCardShot: %s_%dx%d.png" % [name, int(s.x), int(s.y)])

func _to_battle() -> Node:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in ScreenSweepScript.sweep_parties(Registry.all_class_ids())[-1]:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	if not _press("start fight"):
		return null
	await _settle()
	## The battle screen opens held before its first tick with the party
	## draggable, and its own button carries the same words.
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		if not _press("start fight"):
			return null
		await _settle()
	return _node_with("BattleView.gd")

func _engine(state: CombatState, id: int) -> void:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.hp = 40
	u.hp_max = 40
	u.alive = true
	u.enemy_id = &"siege_engine"
	u.display_name = "Siege Engine"
	state.units.append(u)

func _run() -> bool:
	var battle := await _to_battle()
	if battle == null:
		print("EndCardShot: never reached the battle screen")
		return false
	battle.set_process(false)
	for i in 240:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)

	var state: CombatState = battle.state
	for u in state.units:
		if u.team == CG.Team.PLAYER and u.enemy_id == &"":
			u.hp = 0
			u.alive = false
	_engine(state, 900)
	_engine(state, 901)
	state.outcome = CombatState.Outcome.ENEMY_WIN
	var end_event := CombatEvent.make(CG.EventKind.FIGHT_END, state.tick)
	end_event.end_reason = CG.EndReason.CANNOT_ACT
	state.emit(end_event)
	battle._team_status.sync(state)
	battle._show_outcome()
	await _settle()
	await _shot("wren_442_defeat_card")

	var panel: Rect2 = battle._team_status.get_global_rect()
	var ok := true
	for pair in [["cost", battle._end_cost_label], ["prompt", battle._end_prompt_label]]:
		var label: Label = pair[1]
		if not label.visible:
			continue
		var box: Rect2 = label.get_global_rect()
		var clash := box.intersects(panel)
		print("EndCardShot: %s label %s vs panel %s -> %s" % [
			pair[0], box, panel, "OVERLAPS" if clash else "clear"])
		if clash:
			ok = false
	print("EndCardShot: card text is %s" % ["\n  " + battle._end_cost_label.text.replace("\n", "\n  ")])
	return ok
