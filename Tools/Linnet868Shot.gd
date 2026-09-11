extends Control

## Issue 868: what the log says when the party's resource comes back on arrival
## in the next room. The events come from `FloorRun.carry_into`, the real
## emitter, and are rendered by a real `CombatLogView`.

const OUT_DIR := "user://probe"
const ROOM_ID := &"floor1_cover"

## What each pawn walked out of the last room with, as a fraction of its max hp
## and of its max resource.
const CARRIED_HP := [0.25, 0.5, 0.1, 0.75, 0.4]
const CARRIED_RESOURCE := [0.0, 0.2, 0.1, 0.5, 0.0]

var _log: CombatLogView = null

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("Linnet868Shot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> bool:
	## Sized explicitly: nothing resizes a tool scene's root Control.
	size = get_viewport().get_visible_rect().size
	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_log = CombatLogView.new()
	_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_log)
	await _settle()

	var state := _arrive()
	var lines: Array[String] = []
	var recovered := 0
	for e in state.events:
		var line := _log.line_for_event(state, e)
		if line == "":
			continue
		if e.kind == CG.EventKind.RESOURCE_GAINED:
			recovered += 1
		lines.append(line)
		_log.append_event(state, e)
	await _settle()

	print("Linnet868Shot: %d lines on arrival in %s, %d of them resource" % [
		lines.size(), ROOM_ID, recovered])
	for line in lines:
		print("Linnet868Shot:   %s" % line)
	await _shot("linnet6_868_resource_recovers_on_arrival", _log._label.get_global_rect().grow(8.0))

	if recovered == 0:
		print("Linnet868Shot: FAIL no resource was recovered -- nothing calls the recovery")
		return false
	for line in lines:
		if line.contains("?"):
			print("Linnet868Shot: FAIL the log cannot name it: %s" % line)
			return false
	return true

## A party that fought a room, spent itself winning, and walks into the next one.
func _arrive() -> CombatState:
	var party: Array[PawnData] = []
	var ids := ClassLibrary.all_ids()
	for i in mini(CARRIED_HP.size(), ids.size()):
		var c := StringName(ids[i])
		party.append(PawnFactory.make_preset_pawn(c, c, ClassLibrary.get_class_def(c).display_name))
	var state := CombatSim.build(party, RoomLibrary.get_room(ROOM_ID), 1)
	var run := FloorRun.new()
	for i in party.size():
		var unit := state.unit(i)
		run.record_result(party[i].id,
			int(unit.hp_max * float(CARRIED_HP[i])),
			int(unit.resource_max * float(CARRIED_RESOURCE[i])), true)
	## The whole point of the shot: this call is the one that emits them.
	FloorRun.carry_into(run, state, party)
	return state

func _shot(name: String, box: Rect2) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var region := Rect2i(box).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(region)
	crop.resize(region.size.x * 2, region.size.y * 2, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	crop.save_png("%s/%s.png" % [OUT_DIR, name])
	print("Linnet868Shot: %s.png" % name)
