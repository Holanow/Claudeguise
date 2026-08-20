extends Control
class_name PopoutLayer

const PopoutScript := preload("res://Scripts/UI/Popout.gd")

## Issue 112: where pinned popouts live, and the one place that knows how to
## make one.

const LAYER_NAME := "PopoutLayer"

## Where a new popout lands relative to the control it came from: just below its
## bottom-left corner, so it does not cover the thing it describes. Dragging is
## the fix when it still does, which is the other half of the issue.
const OFFSET := Vector2(0.0, Palette.SPACE_XS)

## Popouts are staggered when several are pinned from the same control, so a
## second pin is visibly a second popout rather than one hiding the other.
const STAGGER := Vector2(Palette.SPACE_M, Palette.SPACE_M)

func _ready() -> void:
	name = LAYER_NAME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## The layer for whichever screen `node` is on, created on first use.
static func of(node: Node) -> Control:
	var screen := node
	var walk := node
	while walk != null:
		if walk is Control:
			screen = walk
		walk = walk.get_parent()
	if screen == null or not (screen is Control):
		return null
	for child in screen.get_children():
		if child is Control and child.name == LAYER_NAME:
			return child
	var layer := Control.new()
	layer.set_script(load("res://Scripts/UI/PopoutLayer.gd"))
	# Called directly for the reason every panel on this project calls it
	# directly: a screen built outside a live tree never fires _ready(), and
	# several tests and every panel-built-before-add_child path do exactly that.
	screen.add_child(layer)
	if not layer.is_inside_tree():
		layer._ready()
	else:
		layer.name = LAYER_NAME
	return layer

## Pin one. Returns the popout so a caller can position or test it.
func pin(title: String, body: String, at: Vector2, source: Control = null) -> Control:
	var popout := PopoutScript.build(title, body)
	if source != null:
		popout.source = weakref(source)
	add_child(popout)
	popout.move_to(at + OFFSET + STAGGER * float(get_child_count() - 1))
	return popout

## Re-read every pinned popout from whatever pinned it.
func refresh() -> void:
	for child in get_children():
		if child.has_method("refresh"):
			child.refresh()

func pinned() -> Array[Node]:
	return get_children()

func pinned_count() -> int:
	return get_child_count()

## Not wired to a control today -- there is no "unpin everything" button, and
## adding one before there is a screen crowded enough to need it would be
## furniture. Here because a test that pins needs to leave the layer clean.
func clear() -> void:
	for child in get_children():
		child.free()
