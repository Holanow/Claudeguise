extends Node

## Issue 112: pin two popouts and drag one, through the viewport's own input
## path, and photograph the result.
##
##   godot --path . --resolution 1280x720 res://Tools/PopoutShot.tscn
##
## **`push_input`, not `_gui_input`.** The unit tests call the host's handler
## directly, which proves the handler is right and proves nothing about whether
## a real click ever reaches it. `mouse_filter` is the trap this issue names,
## and it lives entirely in the hit-testing between a click and a handler --
## the layer covering the screen, the popout's labels swallowing the drag, the
## engine's IGNORE default on `Label`. Only real input exercises it.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("PopoutShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	get_tree().quit(0)

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s_%s.png" % [OUT_DIR, name, _res_tag]
	image.save_png(path)
	print("PopoutShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("PopoutShot: no visible button starting with '%s'" % prefix)
	return false

func _right_click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)
	await _settle()

## The press goes through `push_input`, so the popout is found by real
## hit-testing. **The motions do not, and this is a limitation of the harness
## rather than a choice.** Measured here: a pushed `InputEventMouseMotion`
## arrives at `_gui_input` carrying a constant position -- the same local
## coordinate for all eight of eight different pushed positions -- because the
## viewport takes the motion's position from the real cursor, which nothing in
## a scripted run moves. Pushed *button* events do use the position given,
## which is why the pin above is exercised end to end and this is not.
##
## So the movement is delivered to the handler directly. What that still proves:
## the drag arithmetic, the slop threshold and the clamp. What it does not:
## that a motion event reaches the popout rather than something above it. The
## press does prove routing, and the popout is the topmost thing at that point.
func _drag(from: Vector2, to: Vector2, popout: Control) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	get_viewport().push_input(down)
	await get_tree().process_frame
	for i in range(1, 9):
		var at := from.lerp(to, float(i) / 8.0)
		var move := InputEventMouseMotion.new()
		move.position = at - popout.global_position
		move.global_position = at
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		popout._gui_input(move)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	get_viewport().push_input(up)
	await _settle()

func _layer() -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PopoutLayer.gd"):
			return n
	return null

func _chips() -> Array[Node]:
	var out: Array[Node] = []
	for n in _walk(_main):
		if n is Label and n.get_script() != null \
				and n.get_script().resource_path.ends_with("GlossaryLabel.gd") \
				and n.is_visible_in_tree() and n.tooltip_text != "":
			out.append(n)
	return out

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	if not _press("inspect classes"):
		return
	await _settle()
	await _shot("wren_popout_before")

	# Two attribute chips on the same pawn -- the comparison case the issue
	# says is the whole reason pinning is worth building.
	var chips := _chips()
	if chips.size() < 3:
		print("PopoutShot: found %d hoverable chips, expected at least 3" % chips.size())
		return
	# Two attribute chips, not the class-tags line above them. Pinning from that
	# line first put its popout over the whole attribute row and the second
	# right-click landed on the popout instead of the chip -- which is correct
	# behaviour (a popout takes input, that is the feature) and a bad capture.
	# Worth saying rather than quietly picking different chips: a popout lands
	# under the control it came from and therefore covers whatever was below it,
	# and dragging is the only answer this issue gives for that.
	for chip in [chips[1], chips[2]]:
		await _right_click(chip.get_global_rect().get_center())

	var layer := _layer()
	print("PopoutShot: pinned=%d (2 expected)" % (0 if layer == null else layer.get_child_count()))
	await _shot("wren_popout_two_pinned")

	if layer == null or layer.get_child_count() == 0:
		return
	# The topmost popout, not the first. Two staggered popouts overlap, and a
	# press at the lower one's centre lands on whichever is drawn above it --
	# which is correct (the front one takes the click) and made the first
	# version of this capture drag nothing at all.
	var first: Control = layer.get_child(layer.get_child_count() - 1)
	var before := first.global_position
	await _drag(first.get_global_rect().get_center(), Vector2(820.0, 470.0), first)
	print("PopoutShot: dragged from %s to %s" % [before, first.global_position])
	await _shot("wren_popout_dragged")

	# The layer covers the whole screen, so if its `mouse_filter` stopped input
	# nothing underneath it would be clickable ever again. A real left-click,
	# pushed through the viewport at the Back button's own rect -- not
	# `emit_signal`, which would prove the button works and nothing about
	# whether a click can still reach it.
	for node in _walk(_main):
		if node is Button and node.text == "Back" and node.is_visible_in_tree():
			var at: Vector2 = node.get_global_rect().get_center()
			for pressed in [true, false]:
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				event.position = at
				event.global_position = at
				get_viewport().push_input(event)
			break
	await _settle()
	print("PopoutShot: after clicking Back through the layer, screen is '%s'" % _screen_name())
	await _shot("wren_popout_layer_does_not_block")

func _screen_name() -> String:
	for node in _walk(_main):
		if node is Control and node.get_script() != null:
			return node.get_script().resource_path.get_file()
	return "<none>"
