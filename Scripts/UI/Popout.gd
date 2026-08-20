extends PanelContainer
class_name Popout


## Issue 112: "I need to be able to pin and drag any popup that is created
## outside of a menu."

const MAX_WIDTH := 260.0

## How far a pointer may travel with the button down before it counts as a drag
## rather than a click. Without it every press nudges the popout by a pixel or
## two, which reads as the panel being loose.
const DRAG_SLOP := 3.0

signal closed

var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO
var _press_position: Vector2 = Vector2.ZERO

## Built by hand rather than from a .tscn: every other Control on this project
## is, and the content is three nodes.
static func build(title: String, body: String) -> Control:
	var popout := PanelContainer.new()
	popout.set_script(load("res://Scripts/UI/Popout.gd"))
	popout.add_theme_stylebox_override("panel", _style())
	popout.mouse_filter = Control.MOUSE_FILTER_STOP
	# A pinned popout is placed by its owner and then by the player, so it must
	# not be laid out by a container. PopoutLayer is a bare Control for the same
	# reason.
	popout.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	popout.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	popout.add_child(column)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", int(Palette.SPACE_S))
	column.add_child(header)

	var title_label := Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	title_label.add_theme_color_override("font_color", Palette.TEXT)
	header.add_child(title_label)

	var close := Button.new()
	close.name = "Close"
	close.text = "X"
	close.mouse_filter = Control.MOUSE_FILTER_STOP
	close.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	close.pressed.connect(popout._on_close)
	header.add_child(close)

	var body_label := Label.new()
	body_label.name = "Body"
	body_label.text = body
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_label.custom_minimum_size = Vector2(MAX_WIDTH, 0.0)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	body_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(body_label)
	return popout

## The same bordered box GlossaryTooltip draws, with a brighter border so a
## pinned popout reads as the one you are holding rather than one more panel.
static func _style() -> StyleBox:
	return UIArt.panel_style(&"", Palette.ARENA_FLOOR, Palette.TEAM_PLAYER, 1, Palette.SPACE_S)

## The control this popout was pinned from, so the text can be kept true.
var source: WeakRef = null

## Re-read the body from whatever pinned this. Silent when there is no source or
## it is gone -- a popout pinned from a control that has since been freed keeps
## the last thing it truthfully said rather than blanking.
func refresh() -> void:
	if source == null:
		return
	var host = source.get_ref()
	if host == null or not is_instance_valid(host):
		return
	for node in _descendants(self):
		if node is Label and node.name == "Body" and node.text != host.tooltip_text:
			node.text = host.tooltip_text

func title_text() -> String:
	return _find_label("Title")

func body_text() -> String:
	return _find_label("Body")

func _find_label(name: String) -> String:
	for node in _descendants(self):
		if node is Label and node.name == name:
			return node.text
	return ""

func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out

func _on_close() -> void:
	closed.emit()
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_position = event.global_position
			_grab_offset = event.global_position - global_position
			_dragging = false
			# A pinned popout the player touches comes to the front. Two pinned
			# popouts overlapping and the wrong one on top is the state that
			# makes comparison -- the point of the feature -- not work.
			move_to_front()
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _grab_offset != Vector2.ZERO:
		if not _dragging and event.global_position.distance_to(_press_position) < DRAG_SLOP:
			return
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_grab_offset = Vector2.ZERO
			return
		_dragging = true
		move_to(event.global_position - _grab_offset)
		accept_event()

## Public so a test can drag without synthesising input, and so the clamp is
## one function rather than repeated at the two call sites that place a popout.
func move_to(target: Vector2) -> void:
	# The parent's own `size`, not `get_parent_area_size()`. That call returns
	# (0, 0) for a Control outside a live SceneTree however large its parent
	# really is -- measured, not assumed -- so the clamp would have been dead
	# code in every test and alive only in the game, which is the worst place
	# for a difference between the two.
	var parent := get_parent()
	var bounds: Vector2 = parent.size if parent is Control else Vector2.ZERO
	# A layer with no size yet has not been through a layout pass, and clamping
	# against zero would pin every popout to the top-left corner and look like a
	# placement bug. That state is real between `add_child` and the next frame.
	if bounds.x <= 0.0 or bounds.y <= 0.0:
		position = target
		return
	position = Vector2(
		clampf(target.x, 0.0, maxf(0.0, bounds.x - size.x)),
		clampf(target.y, 0.0, maxf(0.0, bounds.y - size.y)))
