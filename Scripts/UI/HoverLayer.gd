extends Control
class_name HoverLayer


## Issue 449: the arena's mouse-over glossary. One transparent Control over the
## whole screen that answers "what is under the pointer" out of `UnitView`'s own
## geometry, so a badge, a name plate and a body all have a hover box.

const LAYER_NAME := "HoverLayer"

## Where pinned popouts hang: a second full-rect Control at the front of the HUD,
## because this one is deliberately at the back of it.
const PIN_HOST_NAME := "HoverPinHost"

var pin_host: Control = null

## The arena's transform, for turning a screen point into the world point the
## simulation and every drawn mark are expressed in.
var arena: Node2D = null
var state: CombatState = null

## Set by `_get_tooltip` and read by `_make_custom_tooltip` a moment later, which
## is the only order Godot ever calls the two in.
var _title: String = ""

## The layer for whichever fight `unit_view` is drawn in, created on first use --
## the same self-attaching pattern `PopoutLayer.of` uses, and for the same
## reason: the screen that owns the arena should not have to know this exists.
static var _cached: WeakRef = null

static func of(unit_view: Node2D) -> Control:
	if _cached != null:
		var held = _cached.get_ref()
		if held != null and is_instance_valid(held) and held.is_inside_tree():
			return held
	var hud := _hud_for(unit_view)
	if hud == null:
		return null
	var found := hud.get_node_or_null(NodePath(LAYER_NAME))
	if found != null:
		_cached = weakref(found)
		return found
	# First child, so it is drawn behind everything and picked after everything.
	# Issue 377's complaint was reintroduced once by a panel sitting under the
	# cursor, and this one covers the entire screen: a button it is picked ahead
	# of never sees the press at all.
	var layer := _full_rect(hud, LAYER_NAME, load("res://Scripts/UI/HoverLayer.gd"))
	hud.move_child(layer, 0)
	# And the pins go the other way, to the front, or a popout pinned off the
	# arena is drawn behind the log it was pinned to be read beside.
	layer.pin_host = _full_rect(hud, PIN_HOST_NAME, null)
	_cached = weakref(layer)
	return layer

static func _full_rect(parent: Node, node_name: String, script) -> Control:
	var made := Control.new()
	made.name = node_name
	if script != null:
		made.set_script(script)
	parent.add_child(made)
	# Called by hand for the reason every panel on this project calls it by hand:
	# a screen built outside a live tree never fires `_ready()`.
	if not made.is_inside_tree():
		if script != null:
			made._ready()
	made.name = node_name
	made.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if script == null:
		made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return made

## The HUD is the arena's sibling, and it is a `CanvasLayer` rather than a
## Control, which is why the pins need a Control of their own to hang from.
static func _hud_for(unit_view: Node2D) -> Node:
	var arena := unit_view.get_parent()
	if arena == null or arena.get_parent() == null:
		return null
	return arena.get_parent().get_node_or_null("Hud")

func _ready() -> void:
	name = LAYER_NAME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# PASS, never STOP: this Control exists to be hovered and must not consume a
	# press. `BattleView._unhandled_input` opens the click card, and it only ever
	# runs on an event no Control accepted.
	mouse_filter = Control.MOUSE_FILTER_PASS

func bind(new_state: CombatState, new_arena: Node2D) -> void:
	state = new_state
	arena = new_arena

func _get_tooltip(at_position: Vector2) -> String:
	var found := resolve(at_position)
	_title = String(found.get("title", ""))
	return String(found.get("body", ""))

func _make_custom_tooltip(for_text: String) -> Object:
	return GlossaryTooltip.build(for_text, _title)

## Right-click pins, the same gesture as every other hover box. Pinned at the
## pointer rather than at this Control's corner, which is the screen's corner and
## says nothing about what was hovered.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if not event.pressed:
		return
	var found := resolve(make_input_local(event).position)
	if String(found.get("body", "")) == "" or pin_host == null:
		return
	if PopoutHost.pin_at(pin_host, String(found.get("title", "")), String(found["body"]),
			event.global_position) != null:
		accept_event()

## What the pointer is over, as `{title, body}`, or {} for empty ground.
## Public so a test and `Tools/HoverProbe.gd` can ask without a tooltip timer.
func resolve(at_position: Vector2) -> Dictionary:
	if arena == null or state == null or not is_instance_valid(arena):
		return {}
	# Through the canvas transform both ways. The HUD is a CanvasLayer and the
	# arena is not, so their two `get_global_transform`s are not the same space.
	var screen: Vector2 = get_global_transform_with_canvas() * at_position
	var point: Vector2 = arena.get_global_transform_with_canvas().affine_inverse() * screen
	var mark := UnitView.hover_at(state, point)
	if not mark.is_empty():
		return _mark_text(mark["unit"], mark["mark"])
	# Through `BattleView.unit_at`, not a second hit test: hover and click
	# answering different units in a scrum would be worse than no hover.
	var id := BattleView.unit_at(state, point, BattleView.pick_radius_for_scale(arena.scale.x))
	if id < 0:
		return {}
	var u := state.unit(id)
	if u == null:
		return {}
	return {"title": UnitCard.title_text(u), "body": Glossary.unit_hover_text(state, u)}

func _mark_text(u: CombatUnit, mark: Dictionary) -> Dictionary:
	match mark["kind"]:
		&"status":
			var s: CG.Status = mark["status"]
			return {"title": "%s on %s" % [Glossary.status_name(s), u.display_name],
				"body": Glossary.status_popup_text(u, s, state.tick)}
		&"overflow":
			return {"title": "%d more on %s" % [int(mark["count"]), u.display_name],
				"body": Glossary.hidden_statuses_text(state, u)}
		&"oom":
			return {"title": "%s is out" % u.display_name, "body": Glossary.oom_text(u)}
	return {}
