extends Node

## Issue #421: the densest tick `Tools/ArenaDensity.gd` found in each room,
## and the Warden's chamber for contrast. Party, seed and tick come from its
## DENSEST MOMENT table.
const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const SHOTS := [
	{"enc": &"floor1_cover", "seed": 4, "tick": 134,
		"party": ["warrior", "priest", "geysermancer", "siege_master"],
		"out": "res://Screenshots/issue421_cover_t134_10units.png"},
	{"enc": &"floor1_chokepoint", "seed": 0, "tick": 65,
		"party": ["warrior", "abomination", "geysermancer", "siege_master"],
		"out": "res://Screenshots/issue421_chokepoint_t65_9units.png"},
	{"enc": &"floor1_warden", "seed": 0, "tick": 76,
		"party": ["warrior", "abomination", "geysermancer", "siege_master"],
		"out": "res://Screenshots/issue421_warden_t76_5units.png"},
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
	cfg.seed = s["seed"]
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
	if _busy or _i >= SHOTS.size() or _battle == null or _battle.state == null:
		return
	if _battle.state.tick < int(SHOTS[_i]["tick"]):
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
