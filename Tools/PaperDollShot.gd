extends Node

## Issue 744: the equip screen's paper doll, through the real screen and the
## real controls. Proves the two things the issue is about: the doll is the
## pawn (the held weapon changes when the picker changes), and the screen
## scales down to a narrow popout column.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""
var _failures: Array[String] = []

func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("PaperDollShot: %s" % msg)

func _ready() -> void:
	if not Offscreen.require_renderer(self):
		return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("PaperDollShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	await _run_narrow()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("PaperDollShot: %d STEP(S) FAILED:" % _failures.size())
	for f in _failures:
		printerr("  - %s" % f)
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
	print("PaperDollShot: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _focus_class(class_id: StringName) -> bool:
	for n in _walk(_main):
		if n is PartyCard and (n as PartyCard).class_def != null \
				and (n as PartyCard).class_def.id == class_id:
			n.toggled.emit(true)
			return true
	_fail("no party card for class '%s'" % class_id)
	return false

## The picker showing "Main Hand" as its own row -- found by walking to the
## first `OptionButton` after that row's label.
func _weapon_picker() -> OptionButton:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("EquipPanel.gd"):
			var seen := false
			for c in _walk(n):
				if c is Label and c.text == "Main Hand":
					seen = true
				elif seen and c is OptionButton:
					return c
	_fail("no picker under the Main Hand label")
	return null

func _body_picker() -> OptionButton:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("EquipPanel.gd"):
			var seen := false
			for c in _walk(n):
				if c is Label and c.text == "Body":
					seen = true
				elif seen and c is OptionButton:
					return c
	_fail("no picker under the Body label")
	return null

func _equip_body(label: String) -> bool:
	var picker := _body_picker()
	if picker == null:
		return false
	for i in picker.item_count:
		if picker.get_item_text(i) == label:
			picker.selected = i
			picker.item_selected.emit(i)
			print("PaperDollShot: equipped body '%s'" % label)
			return true
	_fail("no body picker entry '%s'" % label)
	return false

func _equip(label: String) -> bool:
	var picker := _weapon_picker()
	if picker == null:
		return false
	for i in picker.item_count:
		if picker.get_item_text(i) == label:
			picker.selected = i
			picker.item_selected.emit(i)
			print("PaperDollShot: equipped '%s'" % label)
			return true
	_fail("no picker entry '%s'" % label)
	return false

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	if not _focus_class(&"siege_master"):
		return
	await _settle()

	if not _equip("Sword"):
		return
	await _settle()
	await _shot("kestrel_744_doll_sword")

	if not _equip("Bow"):
		return
	await _settle()
	await _shot("kestrel_744_doll_bow")

	if not _equip("(nothing)"):
		return
	await _settle()
	await _shot("kestrel_744_doll_unarmed")

	## A TANK for this one: Plate Mail is MARTIAL and TANK, and Siege Master
	## is DPS, so it would be refused rather than shown worn.
	if not _focus_class(&"warrior"):
		return
	await _settle()
	if not _equip("Sword"):
		return
	if not _equip_body("Plate Mail"):
		return
	await _settle()
	await _shot("kestrel_744_doll_full_gear")

	_main.queue_free()
	await _settle()

## The narrow-popout case, per #742's own method: `EquipPanel` embedded and
## pinned to a fixed-width column inside a taller window.
func _run_narrow() -> void:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	pawn.main_hand = ItemLibrary.get_equipment(&"sword")
	for w in [320, 240]:
		var panel := EquipPanel.create()
		add_child(panel)
		panel.anchor_left = 0.0
		panel.anchor_top = 0.0
		panel.anchor_right = 0.0
		panel.anchor_bottom = 0.0
		panel.offset_left = 0.0
		panel.offset_top = 0.0
		panel.offset_right = float(w)
		panel.offset_bottom = 720.0
		await get_tree().process_frame
		panel.embed()
		panel.show_pawn(pawn)
		await _settle()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		var path := "%s/kestrel_744_doll_narrow_%dpx.png" % [OUT_DIR, w]
		image.save_png(path)
		print("PaperDollShot: %s" % path)
		panel.queue_free()
		await _settle()
