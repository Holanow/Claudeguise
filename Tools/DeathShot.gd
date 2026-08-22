extends Node

## Issue 320: the three cases the playtester could not read. A player pawn
## dying, a scrum of simultaneous deaths, and the end card that used to name
## nobody -- all in the Burn Pit, whose orange hatched floor is where the old
## marker disappeared.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("DeathShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
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
	print("DeathShot: %s_%s.png" % [name, _tag])

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
	print("DeathShot: no visible button '%s'" % prefix)
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
	print("DeathShot: the picker offers no room matching '%s'" % want)
	return false

func _to_battle() -> Node:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var select := _node_with("PartySelect.gd")
	## By the card's own `class_def`, never by index: the first four cards of an
	## alphabetical roster are never a Warrior (#350). The partition's last
	## party holds the classes a prefix never reached.
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	var party_ids: Array = ScreenSweepScript.sweep_parties(Registry.all_class_ids())[-1]
	for id in party_ids:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	if not _select_room(select._room_picker, "hazard"):
		return null
	select._seed_edit.text = "00000001"
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
	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("DeathShot: no battle screen")
		return null
	battle.set_process(false)
	return battle

## Damage, not a hand-set `hp`: the death has to come out of the simulation so
## the DEATH event, the log line and the marker are the real ones.
func _kill(battle: Node, unit) -> void:
	unit.hp = 1
	var e := CombatEvent.make(CG.EventKind.DAMAGE, battle.state.tick)
	e.source_id = -1
	e.target_id = unit.id
	e.amount = 1
	e.amount_before_mitigation = 1
	e.damage_type = CG.DamageType.FIRE
	unit.hp = 0
	unit.alive = false
	battle.state.emit(e)
	var d := CombatEvent.make(CG.EventKind.DEATH, battle.state.tick)
	d.target_id = unit.id
	battle.state.emit(d)

func _units_on(battle: Node, team: CG.Team) -> Array:
	var out := []
	for u in battle.state.units:
		if u.team == team and u.hp > 0:
			out.append(u)
	return out

func _run() -> bool:
	## 1. One of the player's own pawns dies, on the hazard floor.
	var battle := await _to_battle()
	if battle == null:
		return false
	for i in 40:
		battle._process(CG.TICK_SECONDS)
	var mine := _units_on(battle, CG.Team.PLAYER)
	if mine.is_empty():
		print("DeathShot: nothing of the player's left to kill")
		return false
	_kill(battle, mine[0])
	battle._process(CG.TICK_SECONDS)
	await _settle(2)
	print("DeathShot: killed %s at tick %d" % [mine[0].display_name, battle.state.tick])
	await _shot("wren_death_own_pawn")

	## 2. A scrum: every enemy still standing dies on the same tick.
	var theirs := _units_on(battle, CG.Team.ENEMY)
	for u in theirs:
		_kill(battle, u)
	battle._process(CG.TICK_SECONDS)
	await _settle(2)
	print("DeathShot: %d enemies died on tick %d" % [theirs.size(), battle.state.tick])
	await _shot("wren_death_scrum")

	## 3. The end card, which is what has to name the casualty.
	for i in 120:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
	await _settle()
	if battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		print("DeathShot: the fight did not resolve, so there is no end card to shoot")
		return false
	print("DeathShot: end card reads %s" % battle._end_cost_label.text.replace("\n", " / "))
	await _shot("wren_death_end_card")
	return true
