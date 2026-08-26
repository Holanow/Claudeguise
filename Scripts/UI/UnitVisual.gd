extends Node2D
class_name UnitVisual


## One body, as a tree of `Sprite2D` slots.
##
## A node per slot in `UnitRecipes.SLOTS` order, each holding one sprite per part
## the recipe put in it. Draw order is tree order, so nothing sorts at runtime,
## and an empty slot is a node with no sprites under it.
##
## This node draws BEHIND its parent (`show_behind_parent`), because the bars,
## badges and name plate `UnitView` draws are the reading surface and must sit
## over the body. Its own `_draw` is the layer under the body, which is where the
## targeting line goes.

var _slots: Dictionary = {}

## The posed half. Facing and the impact squash live on this node, so the focus
## line `_draw` puts under the body is not mirrored or squashed with it.
var _body: Node2D = null
var _shape: StringName = &""
var _team: int = -1
var _radius: float = 0.0

## Where the focus line ends, in this node's local space. `INF` is "no line".
var _focus_to: Vector2 = Vector2.INF

func _ready() -> void:
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Builds the tree for this body, or leaves it alone when nothing about it has
## changed. Rebuilding every frame would make a sprite tree slower than the
## immediate-mode draw it replaces, which is the whole point of using one.
func build(shape_id: StringName, team: CG.Team, radius: float) -> void:
	if _shape == shape_id and _team == int(team) and is_equal_approx(_radius, radius):
		return
	_shape = shape_id
	_team = int(team)
	_radius = radius
	if _body != null:
		# Removed before it is freed: `queue_free` alone leaves the old tree in
		# place for the rest of the frame, and both bodies would draw.
		remove_child(_body)
		_body.queue_free()
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)
	_slots.clear()
	for slot in UnitRecipes.SLOTS:
		var node := Node2D.new()
		node.name = String(slot)
		_body.add_child(node)
		_slots[slot] = node
	var n := UnitArt.canvas_size(shape_id, team)
	var scale_to := 1.0 if n <= 0.0 else (radius * 2.0) / n
	var sprites := UnitArt.sprites_for(shape_id, team)
	# A shape with no recipe at all is a black square, per the player's ruling.
	# Six empty slots would draw nothing, and an invisible unit is a worse defect
	# than an obvious one -- it is issue #75 all over again.
	if sprites.is_empty():
		_add(&"Body", _black_square(), Color.BLACK, Vector2(radius * 2.0, radius * 2.0), &"")
		return
	for s in sprites:
		# A missing part file is a black square too, and for the same reason.
		var tex: Texture2D = s["tex"]
		var missing := tex == null
		_add(s["slot"],
			_black_square() if missing else tex,
			Color.BLACK if missing else s["color"],
			Vector2(radius * 2.0, radius * 2.0) if missing else Vector2(scale_to, scale_to),
			s["part"])

func _add(slot: StringName, tex: Texture2D, color: Color, scale_to: Vector2, part: StringName) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.scale = scale_to
	sprite.modulate = color
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.set_meta(&"part", part)
	sprite.set_meta(&"color", color)
	(_slots[slot] as Node2D).add_child(sprite)

## One white pixel, scaled to the footprint. The black square, and it is white in
## the file because every sprite here takes its colour from `modulate`.
static var _square: Texture2D = null

static func _black_square() -> Texture2D:
	if _square == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color.WHITE)
		_square = ImageTexture.create_from_image(img)
	return _square

## Where one slot sits this frame, relative to where its parts were authored.
## `PartAnimation` scales its throw per part, so the offset is applied to each
## sprite rather than to the slot: `hands_wide` reaches further than `hands`.
func offset_slot(slot: StringName, offset: Vector2) -> void:
	if not _slots.has(slot):
		return
	for sprite in (_slots[slot] as Node2D).get_children():
		var part: StringName = sprite.get_meta(&"part", &"")
		sprite.position = offset * float(PartAnimation.PARTS.get(part, 1.0))

## Issue 553. The struck body goes white. The parts are binary-alpha masks, so
## drawing white over one at alpha `a` and tinting it toward white by `a` put the
## same colour on the screen -- the white copy of the body that used to slide out
## from under a thrust hand cannot exist any more.
## Where a slot is drawn this frame, in this node's parent space. Averaged over
## the slot's sprites because a recipe may put two of them there, and composed
## through both transforms so the mirror on this node is already applied.
func slot_offset(slot: StringName) -> Vector2:
	if not _slots.has(slot):
		return Vector2.ZERO
	var node: Node2D = _slots[slot]
	var kids := node.get_children()
	if kids.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for k in kids:
		sum += node.transform * (k as Node2D).position
	return transform * (sum / float(kids.size()))

func flash(color: Color, strength: float) -> void:
	for slot in _slots.values():
		for sprite in (slot as Node2D).get_children():
			var own: Color = sprite.get_meta(&"color", Color.WHITE)
			sprite.modulate = own.lerp(color, clampf(strength, 0.0, 1.0))

## Which way the body faces, and how far a live impact has squashed it. Both are
## this node's own transform: the body moves and the reading surface does not.
func pose(facing_left: bool, squash: Vector2, recoil: Vector2, bottom: float) -> void:
	if _body == null:
		return
	_body.scale = Vector2(-squash.x if facing_left else squash.x, squash.y)
	_body.position = recoil + Vector2(0.0, bottom * (1.0 - squash.y))

func set_focus_line(to: Vector2) -> void:
	if to == _focus_to:
		return
	_focus_to = to
	queue_redraw()

## Who is this unit currently after. Drawn here rather than by `UnitView` so it
## lands UNDER the body: this node's own `_draw` runs before its sprite children.
func _draw() -> void:
	if _focus_to == Vector2.INF:
		return
	draw_line(Vector2.ZERO, _focus_to, Color(Palette.BACKGROUND, 0.5), 4.5)
	draw_line(Vector2.ZERO, _focus_to, Palette.FOCUS_LINE, 2.5)
