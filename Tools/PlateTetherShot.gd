extends Node

## Issue #440: the chokepoint fight at seed 0 with name plates on, shot at the
## first tick nine pawns are alive, which is the count in the playtester's
## `blind7_26_plates_zoom.png`.
const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const ENCOUNTER := &"floor1_chokepoint"
const SEED := 0
const LIVE := 9
const PARTY := ["warrior", "abomination", "geysermancer", "siege_master"]

## Set on the command line so the same tool takes both halves of the
## comparison: `-- --out=res://Screenshots/issue440_before.png`.
const DEFAULT_OUT := "res://Screenshots/issue440_chokepoint_t65_9units.png"

var _battle: Node = null
var _busy := false

func _ready() -> void:
	Offscreen.hide_window(self)
	DisplayOptions.set_enabled(&"name_plates", true)
	DisplayOptions.set_enabled(&"damage_numbers", true)
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = ENCOUNTER
	cfg.seed = SEED
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

static func _out_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return arg.trim_prefix("--out=")
	return DEFAULT_OUT

func _process(_delta: float) -> void:
	if _busy or _battle == null or _battle.state == null:
		return
	var live := 0
	for u in _battle.state.units:
		if u.alive:
			live += 1
	if live != LIVE:
		return
	_busy = true
	await RenderingServer.frame_post_draw
	var path := _out_path()
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote %s at tick %d with %d alive" % [path, _battle.state.tick, live])
	get_tree().quit(0)
