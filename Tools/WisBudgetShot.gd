extends Node

## Issue 269: equipment WIS buys plan blocks, and a row past the budget goes
## visibly inert. Both halves, through the controls a player uses.
##
##   godot --path . --resolution 1280x720 res://Tools/WisBudgetShot.tscn
##
## **The whole sequence is reachable today**, which is worth stating because the
## issue reads as though it is not: no starter pawn wears WIS armour (#226 has
## not landed), but `EquipPanel` offers every registered item, so a player can
## put Robes on a pawn themselves. That makes this a real user route rather than
## a harness posing as one.
##
## The route, and it is the issue's own scenario:
##
##   1. Geysermancer, preset plans, 6 of 6 blocks used. Exactly at budget.
##   2. Equip Robes (+2 WIS). Budget 8. **Before this change that did nothing.**
##   3. Add a plan. 8 of 8.
##   4. Take the Robes off again -- the mid-floor edit the player's ruling is
##      about. Budget falls to 6, 8 blocks are spent, and the fourth row is one
##      the pawn can no longer pay for.
##
## Step 4 is the capture that matters. A green suite proves the row is marked;
## only a capture proves the mark is readable next to the row it is about.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("WisBudgetShot: refusing to run in the main checkout -- use a worktree.")
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
	print("WisBudgetShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			if n.disabled:
				print("WisBudgetShot: '%s' is DISABLED" % n.text)
				return false
			n.emit_signal("pressed")
			return true
	print("WisBudgetShot: no visible button starting with '%s'" % prefix)
	return false

func _panel(file: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(file):
			return n
	return null

## The armour picker, driven by its own `item_selected` rather than by reaching
## past it into the panel: the control a player touches has to be the one that
## changes the pawn. Returns false loudly if the item is not offered at all.
func _pick_armor(label: String) -> bool:
	var equip := _panel("EquipPanel.gd")
	for n in _walk(equip):
		if n is OptionButton:
			for i in n.item_count:
				if n.get_item_text(i) == label:
					n.selected = i
					n.item_selected.emit(i)
					print("WisBudgetShot: picked '%s'" % label)
					return true
	print("WisBudgetShot: no picker offers '%s'" % label)
	return false

## Taking the armour off again. Not `_pick_armor("(nothing)")`: every slot's
## picker carries that entry and the weapon's comes first, so the obvious call
## would strip the wrong slot and the capture would be of something else. Find
## the picker that is *showing* the item, and set that one back.
func _clear_armor(worn: String) -> bool:
	var equip := _panel("EquipPanel.gd")
	for n in _walk(equip):
		if n is OptionButton and n.selected >= 0 and n.get_item_text(n.selected) == worn:
			n.selected = 0
			n.item_selected.emit(0)
			print("WisBudgetShot: took '%s' off" % worn)
			return true
	print("WisBudgetShot: no picker is showing '%s'" % worn)
	return false

func _scroll_to_plans() -> void:
	var inspect := _panel("InspectPanel.gd")
	for n in _walk(inspect):
		if n is ScrollContainer:
			n.scroll_vertical = 100000
	await _settle()

## What the plan section reads, printed so a wrong capture is recognisable
## rather than merely unconvincing.
func _report() -> void:
	var inspect := _panel("InspectPanel.gd")
	for n in _walk(inspect):
		if n is Label and (n.text.contains("plan blocks used") or n.text.begins_with("Inert:")):
			print("WisBudgetShot:   %s" % n.text)

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	# 1. The pawn at exactly its budget, before any equipment.
	if not _press("equip pawns"):
		return
	await _settle()
	if not _press("geysermancer"):
		return
	await _settle()

	# 2. Robes on. +2 WIS, and until this change that bought nothing.
	if not _pick_armor("Robes"):
		return
	await _settle()
	await _shot("wren_wis_robes_equipped")

	_press("back")
	await _settle()
	if not _press("inspect classes"):
		return
	await _settle()
	_press("geysermancer")
	await _settle()
	await _scroll_to_plans()
	print("WisBudgetShot: with Robes on --")
	_report()
	await _shot("wren_wis_budget_with_robes")

	# 3. A plan the extra WIS paid for. The Add button being live at all is the
	#    first half of the issue: at 6 of 6 it was disabled.
	if not _press("+ add a plan"):
		return
	await _settle()
	await _scroll_to_plans()
	print("WisBudgetShot: after adding a plan --")
	_report()
	await _shot("wren_wis_budget_plan_added")

	# 4. Robes off, mid-plan. The row the pawn can no longer pay for.
	_press("back")
	await _settle()
	if not _press("equip pawns"):
		return
	await _settle()
	_press("geysermancer")
	await _settle()
	if not _clear_armor("Robes"):
		return
	await _settle()
	_press("back")
	await _settle()
	if not _press("inspect classes"):
		return
	await _settle()
	_press("geysermancer")
	await _settle()
	await _scroll_to_plans()
	print("WisBudgetShot: with the Robes taken off --")
	_report()
	await _shot("wren_wis_budget_inert_row")
