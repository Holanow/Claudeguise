extends Node

## Issue 269: equipment WIS buys plan blocks, and a row past the budget goes
## visibly inert. Both halves, through the controls a player uses.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""
var _failures: Array[String] = []

## A capture tool that returns early on a failed step reports an absence as a
## result, so every failure is recorded and the run exits non-zero (#371).
func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("WisBudgetShot: %s" % msg)

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("WisBudgetShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("WisBudgetShot: %d STEP(S) FAILED:" % _failures.size())
	for f in _failures:
		printerr("  - %s" % f)
	printerr("  The captures for those steps were not taken.")
	get_tree().quit(3)

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
				_fail("'%s' is DISABLED" % n.text)
				return false
			n.emit_signal("pressed")
			return true
	_fail("no visible button starting with '%s'" % prefix)
	return false

## Who the middle column is about, chosen the way a player chooses: the class
## card's own toggle. #351 put the equip panel and the plan editor side by side
## there and deleted the "Equip pawns" and "Inspect classes" buttons that used
## to open them as screens, which is why this tool pressed a button that no
## longer exists and skipped every capture (#371).
func _focus_class(class_id: StringName) -> bool:
	for n in _walk(_main):
		if n is PartyCard and (n as PartyCard).class_def != null \
				and (n as PartyCard).class_def.id == class_id:
			n.toggled.emit(true)
			return true
	_fail("no party card for class '%s'" % class_id)
	return false

## The class library minus its last row, added the way a player adds rows.
## Since #399 a starter pawn carries none at all, so this pawn sat at 0 of 8 for
## the whole capture, nothing could go inert and the Add button was never the
## interesting kind of live (#417). One row under the unequipped budget is the
## state issue 269 is about.
func _load_library_but_one(class_id: StringName) -> bool:
	for n in _walk(_main):
		if not (n is PartySelect):
			continue
		for pawn in (n as PartySelect).available_pawns():
			if pawn.pawn_class == null or pawn.pawn_class.id != class_id:
				continue
			pawn.plans = PresetPlans.for_class(class_id)
			if not pawn.plans.is_empty():
				pawn.plans.remove_at(pawn.plans.size() - 1)
			return true
	_fail("no %s in the roster to load a plan library onto" % class_id)
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
	_fail("no picker offers '%s'" % label)
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
	_fail("no picker is showing '%s'" % worn)
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

	if not _load_library_but_one(&"geysermancer"):
		return

	# 1. The pawn at exactly its budget, before any equipment. Both panels are
	#    in the middle column at once, so there is no screen to leave and
	#    come back to between the steps below.
	if not _focus_class(&"geysermancer"):
		return
	await _settle()
	if not _clear_armor("Robes"):
		return
	await _settle()
	await _scroll_to_plans()
	print("WisBudgetShot: with nothing equipped --")
	_report()

	# 2. Robes on. +2 WIS, and until this change that bought nothing.
	if not _pick_armor("Robes"):
		return
	await _settle()
	await _shot("wren_wis_robes_equipped")
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
	if not _clear_armor("Robes"):
		return
	await _settle()
	await _scroll_to_plans()
	print("WisBudgetShot: with the Robes taken off --")
	_report()
	await _shot("wren_wis_budget_inert_row")
