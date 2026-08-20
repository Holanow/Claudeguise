extends Node

## Issue 245, through the controls a player uses.
##
##   godot --path . --resolution 1280x720 res://Tools/StatusPopupShot.tscn
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## The player asked to *"mouse over a status icon in the party overview and get a
## more indepth description"*. The hover box and the pinned popout carry the same
## string, and only one of the two can be photographed -- Godot's tooltip needs a
## real cursor sitting still, which no scripted run can produce (`DeployView`'s
## own tests record the same limitation about motion events). **So this pins,
## which is the same text through the same field, and says so rather than
## implying the hover itself was captured.**
##
## **`push_input`, not `_gui_input`.** Calling the handler proves the handler is
## right and proves nothing about a click reaching it, which is where
## `mouse_filter` defects live -- and this panel sets `MOUSE_FILTER_IGNORE` on
## itself and on its row container, so whether a right-click ever reaches a chip
## inside it is a real question, not a formality.
##
## And it takes TWO shots of the same pinned popout, ticks apart. The live
## numbers are the point of the issue, and a popout that froze at the tick it was
## pinned on would look perfectly correct in a single frame.


const OUT_DIR := "res://Screenshots"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const ROOM := &"floor1_room1"

var _main: Node

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("StatusPopupShot: use a worktree."); get_tree().quit(2); return
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("StatusPopupShot: wrote %s.png (%dx%d)" % [name, img.get_width(), img.get_height()])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	printerr("StatusPopupShot: no button '%s'" % prefix); return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _right_click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)
	await _settle()

## A visible status chip on the team panel, or null. Statuses come and go, so
## this is called in a loop rather than once.
func _status_chip(panel: Node) -> Control:
	for n in _walk(panel):
		if n.get_script() == IconChip and n.visible and n.is_visible_in_tree() \
				and n.kind == IconChip.Kind.STATUS and n.tooltip_text != "":
			return n
	return null

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null and PARTY.has(String(n.class_def.id)):
				n.toggled.emit(true)
	await _settle()

	var select := _node_with("PartySelect.gd")
	var picker: OptionButton = select._room_picker
	for i in picker.item_count:
		if picker.get_item_metadata(i) == ROOM:
			picker.selected = i
			picker.item_selected.emit(i)
	await _settle()
	if not _press("start fight"): return
	await _settle()
	if not _press("start fight"): return
	await _settle(2)

	var battle := _node_with("BattleView.gd")
	if battle == null:
		printerr("StatusPopupShot: never reached the battle"); return
	var panel = battle._team_status

	# Wait for a real status to land on a real party pawn. Nothing is staged:
	# whichever status the fight produces first is the one photographed.
	var chip: Control = null
	var frames := 0
	while chip == null and frames < 100000 \
			and battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		await get_tree().process_frame
		frames += 1
		chip = _status_chip(panel)
	if chip == null:
		printerr("StatusPopupShot: no status chip appeared in the whole fight"); return

	var status_name := String(CG.Status.keys()[chip.status]).capitalize()
	print("StatusPopupShot: tick %d, chip is %s at %s" % [
		battle.state.tick, status_name, chip.get_global_rect()])
	print("   hover text, verbatim:")
	for line in chip.tooltip_text.split("\n"):
		if line.strip_edges() != "":
			print("      %s" % line)

	await _right_click(chip.get_global_rect().get_center())
	var layer = _node_with("PopoutLayer.gd")
	if layer == null or layer.get_child_count() == 0:
		printerr("StatusPopupShot: THE RIGHT-CLICK NEVER REACHED THE CHIP -- pinned=%d" % [
			0 if layer == null else layer.get_child_count()])
		return
	var popout: Control = layer.get_child(layer.get_child_count() - 1)
	print("StatusPopupShot: pinned %d, title %s" % [layer.get_child_count(), popout.title_text()])
	await _shot("status_popup_pinned")
	var first_body: String = popout.body_text()
	print("   pinned body: %s" % first_body.replace("\n", " / "))

	# Let the fight run on. The countdown in the pinned popout has to move, or
	# the popout is a snapshot wearing a live number.
	var target: int = battle.state.tick + 15
	while battle.state.tick < target \
			and battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		await get_tree().process_frame
	await _settle(2)
	await _shot("status_popup_a_second_later")
	var second_body: String = popout.body_text()
	print("StatusPopupShot: tick %d" % battle.state.tick)
	print("   pinned body: %s" % second_body.replace("\n", " / "))
	if second_body == first_body:
		printerr("StatusPopupShot: THE PINNED POPOUT DID NOT MOVE -- it is a snapshot")
	else:
		print("StatusPopupShot: the pinned popout followed the fight")
