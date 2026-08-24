extends Node

## Issue 495. The cover pair in the condition dropdown, picked through the
## OptionButton a player clicks rather than through `_set_condition_op`
## underneath it.

const OUT_DIR := "res://Screenshots"

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("CoverConditionShot: refusing to run in the main checkout -- use a worktree.")
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
	print("CoverConditionShot: %s_%dx%d.png" % [name, int(s.x), int(s.y)])

func _pickers(node: Node) -> Array:
	var out := []
	if node is OptionButton:
		out.append(node)
	for c in node.get_children():
		out.append_array(_pickers(c))
	return out

## The condition chip is the one offering exactly the interpreter's whitelist.
func _condition_chips(panel) -> Array:
	var out := []
	for chip in _pickers(panel._detail_box):
		if chip.get_item_count() == PlanInterpreter.CONDITION_OPS.size() and not chip.disabled:
			out.append(chip)
	return out

func _run() -> bool:
	var pawn := PawnFactory.make_starter_pawn(&"geysermancer", &"shot_pawn", "Geysermancer")
	if pawn == null:
		print("CoverConditionShot: no geysermancer")
		return false
	## The editor starts empty since #399, so the library is loaded here and
	## trimmed to the two rows the pair is written on.
	pawn.plans = PresetPlans.for_class(pawn.pawn_class.id)
	while pawn.plans.size() > 2:
		pawn.plans.remove_at(pawn.plans.size() - 1)
	if pawn.plans.size() < 2:
		print("CoverConditionShot: fewer than two rows to edit")
		return false

	var panel := InspectPanel.create()
	add_child(panel)
	panel.open([pawn])
	await _settle()

	var chips := _condition_chips(panel)
	if chips.is_empty():
		print("CoverConditionShot: no live condition chip found")
		return false
	print("CoverConditionShot: the dropdown offers --")
	for i in chips[0].get_item_count():
		print("CoverConditionShot:   %s" % chips[0].get_item_text(i))

	## Row 1 asks whether the pawn is out of cover, row 2 whether it is in it:
	## the two halves of the pair, on two ordinary rows, in one screenshot.
	chips[0].item_selected.emit(PlanInterpreter.CONDITION_OPS.find(&"self_not_in_cover"))
	await _settle()
	var again := _condition_chips(panel)
	if again.size() < 2:
		print("CoverConditionShot: the panel did not rebuild both rows")
		return false
	again[1].item_selected.emit(PlanInterpreter.CONDITION_OPS.find(&"self_in_cover"))
	await _settle()

	print("CoverConditionShot: row 1 reads '%s', row 2 reads '%s'" % [
		pawn.plans[0].condition.op, pawn.plans[1].condition.op])
	await _shot("wren_cover_condition")
	return pawn.plans[0].condition.op == &"self_not_in_cover" \
		and pawn.plans[1].condition.op == &"self_in_cover"
