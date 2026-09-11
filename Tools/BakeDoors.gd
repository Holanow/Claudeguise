extends SceneTree

## Issue 805: the four arena-edge doors, baked once the way
## `Tools/BakeOffHandIcons.gd` bakes its three. North is drawn and the other
## three are rotations of it, so all four are one shape.
##
##   godot --headless --path . --script res://Tools/BakeDoors.gd

const SIZE := 128
const OUT := "res://Assets/UI/door"

const STONE := Color(0.62, 0.64, 0.72, 1.0)
const STONE_DARK := Color(0.38, 0.40, 0.48, 1.0)
const OPENING := Color(0.06, 0.07, 0.10, 1.0)

func _initialize() -> void:
	var north := _north()
	_save(north, "north")
	var east := north.duplicate()
	east.rotate_90(CLOCKWISE)
	_save(east, "east")
	var south := east.duplicate()
	south.rotate_90(CLOCKWISE)
	_save(south, "south")
	var west := south.duplicate()
	west.rotate_90(CLOCKWISE)
	_save(west, "west")
	quit(0)

func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("wrote %s" % path)

## A doorway in the top wall: stone jambs down either side and a dark arched
## opening between them, standing on the floor so it reads as somewhere to
## walk rather than as a hole in the wall.
func _north() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in SIZE:
		for x in SIZE:
			var c := _pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, c)
	return img

func _pixel(x: int, y: int) -> Color:
	if y > 104 or x < 16 or x > 111:
		return Color(0, 0, 0, 0)
	if _in_opening(x, y):
		return OPENING
	# The outer four pixels of the frame are the shaded edge of the stone.
	if x < 20 or x > 107 or y < 4:
		return STONE_DARK
	return STONE

## The dark gap: an arched head, then straight jambs down to the floor.
func _in_opening(x: int, y: int) -> bool:
	if y < 26 or x < 34 or x > 93:
		return false
	if y > 56:
		return true
	return Vector2(x, y).distance_to(Vector2(63.5, 56.0)) <= 30.0
