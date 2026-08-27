extends Node

## Issue 685. The party in deploy setup, one class per weapon `part`
## (sword/bow/staff/orb/sickle), before the fight starts -- proof a weapon
## shows in a hand at rest, not only mid-swing.

const OUT := "res://Screenshots/sable_685_weapons_rest.png"
const CLASSES := [&"warrior", &"siege_master", &"priest", &"geysermancer", &"abomination"]

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in CLASSES:
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_0" % cid),
			ClassLibrary.get_class_def(cid).display_name))
	return out

func _run() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = &"floor1_warden"
	cfg.seed = 0
	var positions: Array[Vector2] = []
	for i in CLASSES.size():
		positions.append(Vector2(-350.0, -220.0 + float(i) * 110.0))
	var view := (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(view)
	await get_tree().process_frame
	view.begin_setup(cfg, RoomLibrary.get_room(cfg.encounter_id), positions)
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	var full := get_viewport().get_texture().get_image()
	full.save_png(OUT)
	var crop := full.get_region(Rect2i(150, 160, 160, 480))
	crop.resize(160 * 3, 480 * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(OUT.replace(".png", "_zoom.png"))
	print("WeaponsRestShot: %s" % OUT)
