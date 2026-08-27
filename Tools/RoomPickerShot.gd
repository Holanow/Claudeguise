extends Node

## Issue 176: can a player actually reach all four rooms?


const OUT_DIR := "res://Screenshots"
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
var _main: Node
var _tag := ""
var _fail := 0

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("RoomPickerShot: use a worktree."); get_tree().quit(2); return
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	print("RoomPickerShot: %d failure(s)" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("RoomPickerShot: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	print("RoomPickerShot: no button '%s'" % prefix); return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _check(ok: bool, msg: String) -> void:
	print("RoomPickerShot: %s %s" % ["OK  " if ok else "FAIL", msg])
	if not ok: _fail += 1

## Selects the named classes by their card's own `class_def`, never by index:
## the first four cards of an alphabetical roster are never a Warrior (#350).
func _fresh(party_ids: Array) -> void:
	if _main != null:
		_main.queue_free()
		await _settle()
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in party_ids:
		if not by_id.has(id):
			_check(false, "no party card for class '%s'" % id)
			continue
		by_id[id].toggled.emit(true)
	await _settle()

func _run() -> void:
	var offered = PartySelect.offered_rooms()
	print("RoomPickerShot: picker offers %s" % str(offered))
	# Not hardcoded to four: the Rat King joined the picker on #192 and the next
	# room should not require editing this line to be checked.
	_check(offered.size() >= 4, "the picker offers %d rooms" % offered.size())

	## The parties rotate room by room so the shots between them hold every
	## class; the reachability checks below do not depend on which party plays.
	var parties: Array = ScreenSweepScript.sweep_parties(ClassLibrary.all_ids())
	var shot_classes := {}

	var reached := {}
	for room_index in offered.size():
		var room_id = offered[room_index]
		var party_ids: Array = parties[room_index % parties.size()]
		for id in party_ids:
			shot_classes[id] = true
		await _fresh(party_ids)
		var select := _node_with("PartySelect.gd")
		var picker: OptionButton = select._room_picker
		_check(picker != null, "%s: the picker is on the screen" % room_id)
		if picker == null: return

		var found := -1
		for i in picker.item_count:
			if picker.get_item_metadata(i) == room_id:
				found = i
		if found < 0:
			_check(false, "%s: not offered by the picker" % room_id)
			continue
		picker.selected = found
		picker.item_selected.emit(found)
		await _settle()
		if room_id == offered[1]:
			await _shot("wren_room_picker")

		if not _press("start fight"): return
		await _settle()
		if not _press("start fight"): return
		await get_tree().process_frame

		var battle := _node_with("BattleView.gd")
		if battle == null:
			_check(false, "%s: never reached the battle" % room_id)
			continue

		# Compare the built fight against the room that was chosen. Terrain
		# count and enemy positions, not the printed name.
		var room = Registry.get_encounter(room_id)
		var enemies := 0
		for u in battle.state.units:
			if u.team == CG.Team.ENEMY:
				enemies += 1
		var same_terrain: bool = battle.state.grid.count() == room.cells.size()
		var same_enemies: bool = enemies == room.enemy_spawns.size()
		_check(same_terrain and same_enemies,
			"%s REACHES A REAL FIGHT (terrain %d/%d, enemies %d/%d)" % [
				room_id, battle.state.grid.count(), room.cells.size(), enemies, room.enemy_spawns.size()])
		reached[room_id] = true
		await _settle()
		await _shot("wren_room_%s" % String(room_id).replace("floor1_", ""))

	_check(reached.size() == offered.size(),
		"ALL %d ROOMS REACHABLE THROUGH THE CONTROLS (reached %d)" % [offered.size(), reached.size()])

	var missing := []
	for id in ClassLibrary.all_ids():
		if not shot_classes.has(id):
			missing.append(String(id))
	_check(missing.is_empty(), "every class appears in some room shot (missing: %s)" % str(missing))
