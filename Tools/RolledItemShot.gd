extends Node

## Issue 916: the equip screen naming a rolled item's affixes. Staged rather
## than photographed in flight -- one pawn, one slot, one fixed seed.

const OUT_DIR := "user://probe"
const SEED := 916

var _main: Node

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("RolledItemShot: use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
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

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

## Scrolls whichever container holds the line naming the affixes, so the shot
## frames that line rather than whatever happened to be at the top.
func _scroll_to(root: Node, needle: String) -> void:
	for n in _walk(root):
		if not (n is Label) or not n.text.contains(needle):
			continue
		var p: Node = n.get_parent()
		while p != null and not (p is ScrollContainer):
			p = p.get_parent()
		if p == null:
			return
		var box: ScrollContainer = p
		box.scroll_vertical += int(n.global_position.y - box.global_position.y) - 120
		return

## The first roll off this seed that actually carried two affixes, so the shot
## shows the screen naming more than one.
func _two_affix_roll(base: EquipmentDef) -> EquipmentDef:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in 200:
		var item := ItemRoller.roll(base, 1, rng)
		if item.affixes.size() == 2:
			return item
	return null

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var select := _node_with("PartySelect.gd")
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	if by_id.has(&"warrior"):
		by_id[&"warrior"].toggled.emit(true)
	await _settle()

	var pawn = select.focused_pawn()
	var rolled := _two_affix_roll(ItemLibrary.get_equipment(&"plate_mail"))
	if rolled == null:
		printerr("RolledItemShot: no two-affix roll in 200 draws at seed %d" % SEED)
		return
	pawn.body = rolled
	select._equip_panel._refresh(pawn)
	await _settle()
	print("RolledItemShot: %s -- %s" % [
		rolled.display_name, EquipPanel.item_effect_text(rolled)])

	## The Equipment section is below the fold with the plan library open, and
	## a screenshot of it is a screenshot of nothing.
	for n in _walk(select):
		if n is Button and n.text == "Hide library":
			n.pressed.emit()
			break
	await _settle()
	_scroll_to(select, "Vital (")
	await _settle()

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/kestrel7_916_rolled_affixes.png" % OUT_DIR)
	print("RolledItemShot: kestrel7_916_rolled_affixes.png")
