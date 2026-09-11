extends Node2D
class_name FloorDoors

## Issue 805: the floor's picker, drawn in the room rather than on a map. One
## door per exit, on the arena edge that exit leaves through.

## The drawn side of one door, in arena units. Big enough to be a comfortable
## click target at every window size the arena is scaled to.
const DOOR_SIZE := 110.0

## `{"room_id": int, "dir": Vector2i}`, straight from `FloorPlan.exits_of`.
var exits: Array[Dictionary] = []

func show_exits(list: Array[Dictionary]) -> void:
	exits = list
	visible = true
	queue_redraw()

func clear_exits() -> void:
	exits = []
	visible = false
	queue_redraw()

## Where a door on `dir` is drawn, in the arena's own coordinates. Inset by
## half its own size so the whole door sits inside the boundary.
static func rect_for(dir: Vector2i) -> Rect2:
	var half := Vector2(CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_HEIGHT) - Vector2.ONE * DOOR_SIZE * 0.5
	var centre := Vector2(dir) * half
	return Rect2(centre - Vector2.ONE * DOOR_SIZE * 0.5, Vector2.ONE * DOOR_SIZE)

## The room a click at `point` (arena coordinates) walks into, or -1.
func room_at(point: Vector2) -> int:
	if not visible:
		return -1
	for e in exits:
		if rect_for(e["dir"]).has_point(point):
			return int(e["room_id"])
	return -1

func _draw() -> void:
	for e in exits:
		var rect := rect_for(e["dir"])
		var tex := UIArt.texture_for(
			StringName("door/%s" % FloorPlan.direction_name(e["dir"])))
		if tex == null:
			draw_rect(rect, Color.BLACK)
			continue
		UIArt.draw_fit(self, tex, rect)
