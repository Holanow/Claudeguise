extends Node

## Issue 386. The movement chip in use, driven through the OptionButton a
## player clicks rather than through `_set_movement` underneath it.

const OUT_DIR := "res://Screenshots"

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("MovementBlockShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var s := DisplayServer.window_get_size()
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%dx%d.png" % [OUT_DIR, name, int(s.x), int(s.y)])
	print("MovementBlockShot: %s_%dx%d.png" % [name, int(s.x), int(s.y)])

func _pickers(node: Node) -> Array:
	var out := []
	if node is OptionButton:
		out.append(node)
	for c in node.get_children():
		out.append_array(_pickers(c))
	return out

func _run() -> bool:
	var pawn := PawnFactory.make_starter_pawn(&"geysermancer", &"shot_pawn", "Geysermancer")
	if pawn == null:
		print("MovementBlockShot: no geysermancer")
		return false
	## The editor starts empty since #399, so the library is loaded here and then
	## trimmed: without it there is no plan row at all and no chip to find.
	pawn.plans = PresetPlans.for_class(pawn.pawn_class.id)
	while pawn.plans.size() > 2:
		pawn.plans.remove_at(pawn.plans.size() - 1)
	if pawn.plans.is_empty():
		print("MovementBlockShot: the geysermancer library is empty, so there is no row to edit")
		return false

	var panel := InspectPanel.create()
	add_child(panel)
	panel.open([pawn])
	await _settle()

	## Found by its own contents rather than by position on the row: the
	## movement chip is the one offering exactly the interpreter's ops plus the
	## no-movement entry.
	var chips := _pickers(panel._detail_box)
	var moved := false
	for chip in chips:
		if chip.get_item_count() == PlanInterpreter.MOVEMENT_OPS.size() + 1 \
				and chip.get_item_text(0) == InspectPanel.NO_MOVEMENT_CAPTION and not chip.disabled:
			chip.item_selected.emit(1 + PlanInterpreter.MOVEMENT_OPS.find(&"keep_distance"))
			moved = true
			break
	if not moved:
		print("MovementBlockShot: no live movement chip found")
		return false
	await _settle()

	var block = InspectPanel.movement_block_of(pawn.plans[0])
	print("MovementBlockShot: plan 1 now holds %s %s, %d blocks" % [
		block.op if block != null else "nothing", block.args if block != null else {},
		pawn.plans[0].block_count()])
	await _shot("wren_movement_block")
	return block != null
