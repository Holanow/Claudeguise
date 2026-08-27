extends Node

## Issue 440. The same seed, room, party and tick, drawn under the shipped
## defaults and again with the two noisy options switched on.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const SEED := 0x2A
const ENC := &"floor1_hazard"
const PARTY := ["abomination", "geysermancer", "priest", "siege_master"]
const TICK := 154
const SHOTS := [
	{"on": false, "out": "res://Screenshots/issue440_defaults_off.png"},
	{"on": true, "out": "res://Screenshots/issue440_switched_on.png"},
]

var _battle: Node = null
var _i := 0
var _busy := false

func _ready() -> void:
	Offscreen.hide_window(self)
	_start()

func _start() -> void:
	DisplayOptions.reset()
	if SHOTS[_i]["on"]:
		DisplayOptions.set_enabled(&"name_plates", true)
		DisplayOptions.set_enabled(&"log_hazard_ticks", true)
	var cfg := RunConfig.new()
	cfg.party = _party(PARTY)
	cfg.encounter_id = ENC
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
			ClassLibrary.get_class_def(StringName(cid)).display_name))
	return out

func _process(_delta: float) -> void:
	if _busy or _battle == null or _battle.state == null or _i >= SHOTS.size():
		return
	if _battle.state.tick < TICK and _battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		return
	_busy = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOTS[_i]["out"])
	print("wrote ", SHOTS[_i]["out"], " at tick ", _battle.state.tick)
	_busy = false
	_i += 1
	if _i < SHOTS.size():
		_start()
		return
	get_tree().quit(0)
