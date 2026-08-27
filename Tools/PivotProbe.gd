extends Node

## Issue 690. One Sellsword, one pose, `HandMain` and `Weapon` rotated together
## to 0, 25, 50 and 75 degrees, tiled into a strip. Reproduces
## `Screenshots/rook_pivot_probe.png`: the blade must sit in the hand at every
## angle, not just at 0.

const OUT := "res://Screenshots/linnet_690_pivot_fixed.png"
const ANGLES_DEG := [0.0, 25.0, 50.0, 75.0]
const RADIUS := 22.5
const CELL := Vector2i(180, 180)
const ZOOM := 3

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _run() -> void:
	var shots: Array[Image] = []
	for angle_deg in ANGLES_DEG:
		var v := UnitVisual.new()
		add_child(v)
		v.build(&"sellsword", CG.Team.ENEMY, RADIUS, &"sword")
		v.position = Vector2(CELL) * 0.5
		v.rotate_slot(&"HandMain", deg_to_rad(angle_deg))
		v.rotate_slot(&"Weapon", deg_to_rad(angle_deg))
		await RenderingServer.frame_post_draw
		var full := get_viewport().get_texture().get_image()
		var origin := (Vector2i(v.position) - CELL / 2).clamp(Vector2i.ZERO, full.get_size() - CELL)
		var reg := full.get_region(Rect2i(origin, CELL))
		reg.resize(CELL.x * ZOOM, CELL.y * ZOOM, Image.INTERPOLATE_NEAREST)
		shots.append(reg)
		v.queue_free()
		remove_child(v)
	var sheet := Image.create(CELL.x * ZOOM * shots.size(), CELL.y * ZOOM, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL * ZOOM), Vector2i(i * CELL.x * ZOOM, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	sheet.save_png(OUT)
	print("PivotProbe: %s" % OUT)
