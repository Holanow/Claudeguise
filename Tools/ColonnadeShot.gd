extends Node

## Issue 330: the re-authored colonnade, at the tick the two lines meet.

const OUT_DIR := "res://Screenshots"
const TICKS := 90

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _run() -> void:
	var battle: BattleView = load("res://Scenes/Battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame

	var cfg := RunConfig.new()
	cfg.encounter_id = &"floor1_cover"
	cfg.seed = 3
	## Not an alphabetical prefix of the roster, which is how seven tools ended
	## up unable to photograph a Warrior. See #350.
	var ids: Array[StringName] = [&"warrior", &"abomination", &"geysermancer", &"priest"]
	for i in ids.size():
		cfg.party.append(PawnFactory.make_starter_pawn(ids[i], StringName("%s_%d" % [ids[i], i]), String(ids[i])))
	battle.begin_with_encounter(cfg, RoomLibrary.get_room(cfg.encounter_id))
	battle.set_paused(true)
	for i in TICKS:
		CombatSim.step(battle.state)
	battle.consume_events()
	battle.queue_redraw()
	for i in 6:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/heron_330_colonnade.png" % OUT_DIR
	image.save_png(path)
	print("ColonnadeShot: %s at tick %d" % [path, battle.state.tick])
