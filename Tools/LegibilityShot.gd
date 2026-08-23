extends Node

## Issue 378. One fight, one tick, plates and numbers on, so a before and an
## after are the same seed, room, party and tick.
##
## `Screenshots/issue378_before_*.png` were taken by this file on `main` at
## aaaf679 with the output names changed; the `after` pair is what it writes.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const SEED := 0x2A
const SHOTS := [
	{"enc": &"floor1_room1", "party": ["warrior", "abomination", "geysermancer", "priest"], "tick": 116,
		"out": "res://Screenshots/issue378_after_room1_t116.png"},
	{"enc": &"floor1_hazard", "party": ["abomination", "geysermancer", "priest", "siege_master"], "tick": 154,
		"out": "res://Screenshots/issue378_after_hazard_t154.png"},
]

var _battle: Node = null
var _i := 0
var _busy := false

func _ready() -> void:
	Offscreen.hide_window(self)
	DisplayOptions.set_enabled(&"name_plates", true)
	DisplayOptions.set_enabled(&"damage_numbers", true)
	_start()

func _start() -> void:
	var s: Dictionary = SHOTS[_i]
	var cfg := RunConfig.new()
	cfg.party = _party(s["party"])
	cfg.encounter_id = s["enc"]
	cfg.seed = SEED
	if _battle != null:
		_battle.queue_free()
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ids:
		out.append(PawnFactory.make_starter_pawn(
			StringName(cid), StringName("%s_%d" % [cid, out.size()]),
			Registry.get_class_def(StringName(cid)).display_name))
	return out

func _process(_delta: float) -> void:
	if _busy or _battle == null or _battle.state == null:
		return
	if _battle.state.tick < int(SHOTS[_i]["tick"]):
		return
	_busy = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOTS[_i]["out"])
	print("wrote ", SHOTS[_i]["out"], " at tick ", _battle.state.tick)
	_i += 1
	## `quit()` takes effect at the end of the frame, so `_process` runs again
	## after it: `_busy` stays true past the last shot or line 51 indexes off
	## the end of SHOTS and the tool throws on its way out (#426).
	if _i >= SHOTS.size():
		get_tree().quit(0)
		return
	_busy = false
	_start()
