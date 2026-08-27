extends Node

## Issue 641. A live fight decided by `DefaultPlan`, drawn at three ticks, so
## the proof that nothing moved has a picture of the thing that did not move.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const SEED := 0x2A
const ENC := &"floor1_room1"
const PARTY := ["warrior", "priest", "geysermancer", "siege_master"]
const TICKS := [40, 150, 320]

var _battle: Node = null
var _i := 0
var _busy := false

func _ready() -> void:
	Offscreen.hide_window(self)
	var cfg := RunConfig.new()
	cfg.party = _party(PARTY)
	cfg.encounter_id = ENC
	cfg.seed = SEED
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
	if _busy or _battle == null or _battle.state == null or _i >= TICKS.size():
		return
	if _battle.state.tick < TICKS[_i] and _battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		return
	_busy = true
	await RenderingServer.frame_post_draw
	var path := "res://Screenshots/curlew_641_fight_%d.png" % TICKS[_i]
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", path, " at tick ", _battle.state.tick)
	_busy = false
	_i += 1
	if _i >= TICKS.size():
		get_tree().quit(0)
