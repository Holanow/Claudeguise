extends Node

## Issue 625: the floor, drawn from cells, in the real battle screen. Walls,
## pillars and a hazard at once, so a reviewer can see what grid-snapping did
## to each of them rather than read a description of it.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const SHOTS := [
	{"enc": &"floor1_chokepoint", "tick": 60, "out": "res://Screenshots/teal_625_cells_chokepoint.png"},
	{"enc": &"floor1_cover", "tick": 60, "out": "res://Screenshots/teal_625_cells_cover.png"},
]
const PARTY := ["warrior", "abomination", "geysermancer", "siege_master"]

var _battle: Node = null
var _i := 0
var _busy := false

func _ready() -> void:
	Offscreen.hide_window(self)
	_start()

func _start() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = SHOTS[_i]["enc"]
	cfg.seed = 1
	if _battle != null:
		_battle.queue_free()
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in PARTY:
		out.append(PawnFactory.make_starter_pawn(StringName(cid),
			StringName("%s_%d" % [cid, out.size()]),
			Registry.get_class_def(StringName(cid)).display_name))
	return out

func _process(_delta: float) -> void:
	if _busy or _i >= SHOTS.size() or _battle == null or _battle.state == null:
		return
	if _battle.state.tick < int(SHOTS[_i]["tick"]):
		return
	_busy = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOTS[_i]["out"])
	print("wrote ", SHOTS[_i]["out"], " at tick ", _battle.state.tick,
		", ", _battle.state.grid.count(), " cells")
	_busy = false
	_i += 1
	if _i < SHOTS.size():
		_start()
	else:
		get_tree().quit(0)
