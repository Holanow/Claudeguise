extends Node

## Issue 256, on the screen, at a size a body is visible at.
##
##   godot --path . --resolution 1280x720 res://Tools/FacingShot.tscn
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## A body is about 66 px in a 1280x720 capture and which way it is mirrored is
## not readable there, so a full-frame shot would be evidence of nothing. This
## waits for a tick where the fight and the old team rule genuinely disagree --
## `Tools/FacingLoad.gd` measures that at 1.7% of unit-ticks, so it has to be
## found rather than assumed -- then crops to the units that disagree and scales
## the crop up. **Nearest-neighbour, so the zoom adds no pixel the game did not
## draw.**
##
## It also prints, per disagreeing unit, which way the old rule drew it and which
## way it is looking. The picture shows a body; the print says which body and
## why, so a reviewer does not have to trust an eye on a mirrored polygon.


const OUT_DIR := "res://Screenshots"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const ROOM := &"floor1_room1"
const ZOOM := 4
const WANTED := 2

var _main: Node

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("FacingShot: use a worktree."); get_tree().quit(2); return
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	printerr("FacingShot: no button '%s'" % prefix); return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

## Units drawn a different way from the way the old team rule would have drawn
## them. The list, not a count, because the crop is taken around them.
func _disagreeing(state: CombatState) -> Array:
	var out: Array = []
	for u in state.units:
		if not u.alive or u.facing == Vector2.ZERO:
			continue
		if UnitView.facing_left(u) != (u.team == CG.Team.ENEMY):
			out.append(u)
	return out

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
		printerr("FacingShot: never reached the battle"); return

	var turned: Array = []
	var frames := 0
	while turned.size() < WANTED and frames < 200000 \
			and battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		await get_tree().process_frame
		frames += 1
		turned = _disagreeing(battle.state)
	if turned.size() < WANTED:
		printerr("FacingShot: never found %d units drawn against the old rule at once" % WANTED)
		return

	print("FacingShot: tick %d, %d units the old rule would have drawn backwards" % [
		battle.state.tick, turned.size()])
	for u in turned:
		print("   %s (%s): looking %s, the team rule drew it looking %s" % [
			u.display_name,
			"party" if u.team == CG.Team.PLAYER else "enemy",
			"left" if UnitView.facing_left(u) else "right",
			"left" if u.team == CG.Team.ENEMY else "right"])

	# The arena's own transform, so a world position becomes the pixel it is
	# drawn at rather than a guess about the layout.
	var arena: Node2D = battle._arena
	var box := Rect2()
	for i in turned.size():
		var at: Vector2 = arena.position + turned[i].position * arena.scale
		var r := Rect2(at - Vector2(70.0, 70.0), Vector2(140.0, 140.0))
		box = r if i == 0 else box.merge(r)

	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	full.save_png("%s/facing_frame.png" % OUT_DIR)
	print("FacingShot: wrote facing_frame.png (%dx%d)" % [full.get_width(), full.get_height()])

	box = box.intersection(Rect2(Vector2.ZERO, Vector2(full.get_width(), full.get_height())))
	if box.size.x < 1.0 or box.size.y < 1.0:
		printerr("FacingShot: the crop fell outside the frame, nothing zoomed"); return
	var crop := full.get_region(Rect2i(box))
	crop.resize(crop.get_width() * ZOOM, crop.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/facing_turned_x%d.png" % [OUT_DIR, ZOOM])
	print("FacingShot: wrote facing_turned_x%d.png (%dx%d, crop %s)" % [
		ZOOM, crop.get_width(), crop.get_height(), box])
