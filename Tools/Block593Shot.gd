extends Node

## Issue 593: the Warrior's block on screen, with the plate wall drawn and the
## log saying what the shield ate. Preset pawns, because a starter pawn carries
## no plan rows and never raises it.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const PARTY := ["warrior", "priest", "geysermancer", "siege_master"]
const SHOTS := [
	{"enc": &"floor1_chokepoint", "seed": 1, "tick": 120, "out": "res://Screenshots/finch_593_block.png"},
	{"enc": &"floor1_chokepoint", "seed": 1, "tick": 260, "out": "res://Screenshots/finch_593_shield_spent.png"},
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
