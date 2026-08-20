extends Node

## Issue 351: the three-column party screen. Pawns left, the selected pawn's
## plans and equipment in the middle, where to fight and Start on the right.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("PartyScreenShot: use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("PartyScreenShot: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	await _shot("wren_party_three_columns_fresh")

	var select := _node_with("PartySelect.gd")
	## By the card's own `class_def`, never by index: the first four cards of an
	## alphabetical roster are never a Warrior (#350). The partition's last
	## party holds the classes a prefix never reached.
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	var party_ids: Array = ScreenSweepScript.sweep_parties(Registry.all_class_ids())[-1]
	for id in party_ids:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	await _shot("wren_party_three_columns_picked")

	## The pawn the middle column is about, chosen the way a player chooses it.
	if party_ids.size() > 1 and by_id.has(party_ids[1]):
		by_id[party_ids[1]].toggled.emit(true)
	await _settle()
	print("PartyScreenShot: middle column is showing %s" % select.focused_pawn().display_name)
	await _shot("wren_party_three_columns_focused")

	## The argument for one column: put WIS gear on and watch the plan budget
	## in the panel above move, without leaving the screen.
	var pawn = select.focused_pawn()
	print("PartyScreenShot: before, %s" % _budget_line(select))
	var armors: Array = select._equip_panel.offered_items(pawn, EquipmentDef.Slot.ARMOR)
	for i in armors.size():
		if armors[i].attribute_percent.get(CG.Attribute.WIS, 0.0) > 0.0 				or armors[i].attribute_flat.get(CG.Attribute.WIS, 0.0) > 0.0:
			select._equip_panel._on_slot_selected(pawn, EquipmentDef.Slot.ARMOR, armors, i + 1)
			print("PartyScreenShot: put on %s" % armors[i].display_name)
			break
	await _settle()
	print("PartyScreenShot: after,  %s" % _budget_line(select))
	await _shot("wren_party_wis_moves_the_budget")

func _budget_line(select) -> String:
	for n in _walk(select._inspect_panel):
		if n is Label and n.text.contains("plan blocks used"):
			return n.text
	return "(no budget line)"
