extends Node

## Issue 488: the Warrior's library on the screen the player meets it on, so
## the Execute row's condition can be read as it now reads.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	get_tree().quit(0)

func _settle(n: int = 8) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var select: Node = null
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartySelect.gd"):
			select = n
	if select == null:
		print("ExecuteRowShot: no party screen")
		get_tree().quit(3)
		return

	var panel = select._inspect_panel
	var pawn = null
	for p in select.available_pawns():
		if p.pawn_class != null and p.pawn_class.id == &"warrior":
			pawn = p
	if pawn == null:
		print("ExecuteRowShot: no Warrior on the party screen")
		get_tree().quit(3)
		return
	## The whole middle column, not just the plan half -- `focus_pawn` is what
	## a card press calls, and calling `show_pawn` alone leaves the equipment
	## panel showing whoever was there before.
	select.focus_pawn(pawn)
	await _settle()
	print("ExecuteRowShot: %s, resource ceiling %d" % [pawn.display_name, Balance.max_resource(pawn)])

	## The row's own condition, read off the screen rather than off the content.
	var wanted := PlanInterpreter.describe_op(
		&"self_resource_at_least_fraction", {"fraction": PresetPlans.EXECUTE_AT_FRACTION})
	var found: Node = null
	for n in _walk(panel):
		if n is Label and n.text.findn(wanted) >= 0:
			found = n
			print("ExecuteRowShot: on screen -- %s" % n.text)
	if found == null:
		print("ExecuteRowShot: no label reads '%s'" % wanted)

	## The row sits down the library, so scroll to it the way a player would.
	if found != null:
		var scroller: Node = found
		while scroller != null and not (scroller is ScrollContainer):
			scroller = scroller.get_parent()
		if scroller is ScrollContainer:
			var box := scroller as ScrollContainer
			box.scroll_vertical = int(found.global_position.y - box.global_position.y
				+ box.scroll_vertical - 220)
			await _settle(16)

	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_viewport().get_texture().get_image().save_png("%s/teal_488_execute_row_%s.png" % [OUT_DIR, _tag])
	print("ExecuteRowShot: wrote teal_488_execute_row_%s.png" % _tag)
	if found == null:
		get_tree().quit(3)
