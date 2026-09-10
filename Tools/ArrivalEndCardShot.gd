extends Control

## Issue 801: the end card of a room the party walked into hurt, so the arrival
## heal is in the stream. Staged rather than filmed -- `FloorRun.carry_into` is
## the real emitter and `EndScreen.open` the real screen, but no `BattleView`,
## so the end banner cannot fail to appear the way #827 records.

const OUT_DIR := "user://probe"
const ROOM_ID := &"floor1_cover"
const SHOT := "linnet2_801_arrival_end_card"

## What each pawn walked out of the last room with, as a fraction of its max hp.
const CARRIED := [0.25, 0.5, 0.1, 0.75]

var _screen: EndScreen = null
var _log: CombatLogView = null

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ArrivalEndCardShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> bool:
	size = get_viewport().get_visible_rect().size
	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_log = CombatLogView.new()
	add_child(_log)
	_screen = EndScreen.create()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.offset_left = 24.0
	_screen.offset_top = 24.0
	_screen.offset_right = -24.0
	_screen.offset_bottom = -24.0
	add_child(_screen)
	await _settle()

	var state := _fight_after_arrival()
	var healed := EndScreen.arrival_healed(state)
	_screen.open(state, _log)
	await _settle()

	var summary := ""
	for line in EndScreen.ledger_lines(state):
		summary += "\n  " + line
	print("ArrivalEndCardShot: the party recovered %d on arrival" % healed)
	print("ArrivalEndCardShot: card summary%s" % summary)
	await _shot(SHOT)

	if healed <= 0:
		print("ArrivalEndCardShot: FAIL no arrival heal fired, so this measured nothing")
		return false
	var text: String = _screen._log_label.text
	if not text.contains("Recovered on arrival: %d." % healed):
		print("ArrivalEndCardShot: FAIL the end card never names the arrival heal")
		return false
	print("ArrivalEndCardShot: PASS the end card names it")
	return true

## A party that fought a room, took real damage, walks into the next one and
## fights that one to a finish.
func _fight_after_arrival() -> CombatState:
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
	FloorRun.carry_into(run, state, party, 1)
	for guard in 4000:
		if state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		CombatSim.step(state)
	return state

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("ArrivalEndCardShot: %s.png" % name)
