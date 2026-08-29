extends Control

## Issue 799: what the log says when the party heals on arriving in a room. The
## event comes from `FloorRun.carry_into`, the real emitter, and is rendered by
## a real `CombatLogView` -- staged rather than filmed, because in a live fight
## nothing holds still on the tick a room opens.

const OUT_DIR := "res://Screenshots"
const ROOM_ID := &"floor1_cover"

## What each pawn walked out of the last room with, as a fraction of its max hp.
const CARRIED := [0.25, 0.5, 0.1, 0.75]

var _log: CombatLogView = null

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ArrivalHealShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> bool:
	## Sized explicitly: nothing resizes a tool scene's root Control, and the log
	## anchors its box to the bottom-right corner of whatever rect it is given.
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
	for e in state.events:
		var line := _log.line_for_event(state, e)
		if line == "":
			continue
		lines.append(line)
		_log.append_event(state, e)
	await _settle()

	print("ArrivalHealShot: %d lines on arrival in %s" % [lines.size(), ROOM_ID])
	for line in lines:
		print("ArrivalHealShot:   %s" % line)
	await _shot("linnet_799_arrival_heal", _log._label.get_global_rect().grow(8.0))

	if lines.is_empty():
		print("ArrivalHealShot: FAIL nothing was logged -- the heal did not fire")
		return false
	for line in lines:
		if line.contains("?"):
			print("ArrivalHealShot: FAIL the log still cannot name it: %s" % line)
			return false
	return true

## A party that fought a room, took real damage, and walks into the next one.
func _arrive() -> CombatState:
	var party: Array[PawnData] = []
	var ids := ClassLibrary.all_ids()
	for i in mini(CARRIED.size(), ids.size()):
		var c := StringName(ids[i])
		party.append(PawnFactory.make_preset_pawn(c, c, ClassLibrary.get_class_def(c).display_name))
	var state := CombatSim.build(party, RoomLibrary.get_room(ROOM_ID), 1)
	var run := FloorRun.new()
	for i in party.size():
		var unit := state.unit(i)
		run.record_result(party[i].id, int(unit.hp_max * float(CARRIED[i])), unit.resource_max, true)
	## The whole point of the shot: this call is the one that emits the heals.
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
	print("ArrivalHealShot: %s.png" % name)
