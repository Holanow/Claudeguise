extends Node

## Issue 491. The Warden's chamber and the colonnade, drawn through the real
## Battle scene, so the constant is shown moving a fight rather than a tally.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const SEED := 0
const PARTY := ["warrior", "priest", "geysermancer", "abomination"]
const SHOTS := [
	{"enc": &"floor1_warden", "tick": 400, "out": "res://Screenshots/issue491_warden_t400.png"},
	{"enc": &"floor1_cover", "tick": 260, "out": "res://Screenshots/issue491_cover_t260.png"},
]

var _battle: Node = null
var _i := 0
var _busy := false

func _ready() -> void:
	Offscreen.hide_window(self)
	_start()

func _start() -> void:
	DisplayOptions.reset()
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = SHOTS[_i]["enc"]
	cfg.seed = SEED
	if _battle != null:
		_battle.queue_free()
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in PARTY:
		out.append(PawnFactory.make_starter_pawn(
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
	print("wrote ", SHOTS[_i]["out"], " at tick ", _battle.state.tick,
		" outcome ", CombatState.Outcome.keys()[_battle.state.outcome])
	_busy = false
	_i += 1
	if _i < SHOTS.size():
		_start()
		return
	get_tree().quit(0)
