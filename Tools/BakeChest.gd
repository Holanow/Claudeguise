extends SceneTree

## Issue 919: the chest a cleared room leaves behind, baked once the way
## `Tools/BakeDoors.gd` bakes the doors it stands between.
##
##   godot --headless --path . --script res://Tools/BakeChest.gd

const SIZE := 128
const OUT := "res://Assets/UI/room/chest.png"

const WOOD := Color(0.45, 0.30, 0.18, 1.0)
const WOOD_DARK := Color(0.28, 0.18, 0.10, 1.0)
const BAND := Color(0.80, 0.66, 0.34, 1.0)

func _initialize() -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, 18, 52, 110, 108, WOOD)
	_lid(img)
	_rect(img, 18, 52, 110, 58, WOOD_DARK)
	_rect(img, 56, 44, 72, 78, BAND)
	_rect(img, 24, 68, 104, 74, WOOD_DARK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Assets/UI/room"))
	img.save_png(OUT)
	print("wrote %s" % OUT)
	quit(0)

func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(maxi(0, y0), mini(SIZE - 1, y1) + 1):
		for x in range(maxi(0, x0), mini(SIZE - 1, x1) + 1):
			img.set_pixel(x, y, c)

## A half-barrel lid, so the silhouette is a chest rather than a crate.
func _lid(img: Image) -> void:
	for x in range(18, 111):
		var t := (float(x) - 64.0) / 46.0
		var top := 52.0 - sqrt(maxf(0.0, 1.0 - t * t)) * 26.0
		_rect(img, x, int(top), x, 52, WOOD)
