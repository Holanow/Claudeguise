extends Node

## Issue 818: the Broken Colonnade through the real BattleView, at deploy and
## across the approach, so the goblin archer that replaced the second rat can
## be seen standing where the rat stood.

const OUT_DIR := "res://Screenshots"
const AT_TICKS := [0, 45, 90, 180]

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
	var ids: Array[StringName] = [&"warrior", &"abomination", &"geysermancer", &"priest"]
	for i in ids.size():
		cfg.party.append(PawnFactory.make_preset_pawn(ids[i], StringName("%s_%d" % [ids[i], i]), String(ids[i])))
	battle.begin_with_encounter(cfg, RoomLibrary.get_room(cfg.encounter_id))
	battle.set_paused(true)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var last := 0
	for at in AT_TICKS:
		while last < at:
			CombatSim.step(battle.state)
			last += 1
		battle.consume_events()
		battle.queue_redraw()
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/linnet_818_cover_t%03d.png" % [OUT_DIR, at]
		get_viewport().get_texture().get_image().save_png(path)
		print("Linnet818Shot: %s at tick %d" % [path, battle.state.tick])

	var names := PackedStringArray()
	for spawn in RoomLibrary.get_room(&"floor1_cover").enemy_spawns:
		names.append("%s@%s" % [spawn.enemy_id, spawn.position])
	print("Linnet818Shot: roster %s" % ", ".join(names))
