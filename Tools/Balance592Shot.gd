extends Node

## Issue 592: the four content changes on screen. The nest, because tankier
## rats are the change a player reads as more bodies standing; and the hazard
## room, because that is where the two casters' 350-unit reach shows.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const SHOTS := [
	{"enc": &"floor1_rat_king", "seed": 3, "tick": 260, "out": "res://Screenshots/finch_592_ratking.png"},
	{"enc": &"floor1_hazard", "seed": 3, "tick": 200, "out": "res://Screenshots/finch_592_reach.png"},
]

var _battle: Node = null
var _i := 0
var _busy := false

func _ready() -> void:
	Offscreen.hide_window(self)
	_start()

func _start() -> void:
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"name_plates", true)
	var cfg := RunConfig.new()
	cfg.party = _party(PARTY)
	cfg.encounter_id = SHOTS[_i]["enc"]
	cfg.seed = SHOTS[_i]["seed"]
	if _battle != null:
		_battle.queue_free()
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ids:
		out.append(PawnFactory.make_preset_pawn(
			StringName(cid), StringName("%s_%d" % [cid, out.size()]),
			Registry.get_class_def(StringName(cid)).display_name))
	return out

func _process(_delta: float) -> void:
	if _busy or _battle == null or _battle.state == null or _i >= SHOTS.size():
		return
	if _battle.state.tick < int(SHOTS[_i]["tick"]) and _battle.state.outcome == CombatState.Outcome.UNRESOLVED:
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
