extends Node

## Issue 131: a generated pawn's stats have to be visible, and where they came
## from has to be findable. Two seeds typed into the real seed field, the same
## class read off the real attribute chips both times.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _res_tag: String = ""
var _failures: Array[String] = []

func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("RolledStatShot: %s" % msg)

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("RolledStatShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var size := DisplayServer.window_get_size()
	_res_tag = "%dx%d" % [int(size.x), int(size.y)]
	await _run()
	if _failures.is_empty():
		get_tree().quit(0)
		return
	printerr("RolledStatShot: %d STEP(S) FAILED:" % _failures.size())
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
	print("RolledStatShot: %s" % path)

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

## The seed the way a player sets it: type into the field and press enter.
func _type_seed(text: String) -> bool:
	for n in _walk(_main):
		if n is LineEdit:
			n.text = text
			n.text_submitted.emit(text)
			return true
	_fail("no seed field on the screen")
	return false

## The attribute chips as the screen renders them, not as PawnData holds them,
## with the hover that says where each number came from. #343 cut the plan
## editor's own attribute row when embedded, so these are the equip panel's.
func _chips() -> Array[String]:
	var out: Array[String] = []
	for n in _walk(_main):
		if not (n is Label and n.is_visible_in_tree()):
			continue
		for name in ["STR", "DEX", "AGI", "CON", "INT", "ATN"]:
			if not n.text.begins_with(name + " "):
				continue
			## An item description also starts "STR ", so require a number next.
			if not n.text.split(" ")[1].is_valid_int():
				continue
			var rolled := "rolled" if n.tooltip_text.contains("rolled") else "-"
			out.append("%s [%s]" % [n.text, rolled])
	return out

## Scroll the attribute chips into view before capturing.
##
## Without this the picture is inert evidence: the chips sit below the fold, so
## the PNG came out byte-identical across two completely different stat lines
## and would have been cited as proof of them. `ensure_control_visible` aims at
## the chip itself rather than scrolling to the bottom, which overshot it.
func _scroll_to_attributes() -> void:
	var chip := _last_chip()
	if chip == null:
		_fail("no ATN chip to scroll to")
		return
	var box := chip.get_parent()
	while box != null and not (box is ScrollContainer):
		box = box.get_parent()
	if box == null:
		_fail("the attribute chips are in no ScrollContainer")
		return
	(box as ScrollContainer).ensure_control_visible(chip)
	await _settle()
	if not _inside(box as ScrollContainer, chip):
		_fail("the chips are still off screen, so the capture shows nothing")

func _last_chip() -> Control:
	for n in _walk(_main):
		if n is Label and n.is_visible_in_tree() and n.text.begins_with("ATN ") 				and n.text.split(" ")[1].is_valid_int():
			return n
	return null

## Clipped-out content still intersects the window rect, so the test has to be
## against the scrolling viewport rather than against the screen.
func _inside(box: ScrollContainer, c: Control) -> bool:
	var view := Rect2(box.global_position, box.size)
	return view.encloses(Rect2(c.global_position, c.size))

func _report(tag: String) -> Array[String]:
	var chips := _chips()
	print("RolledStatShot: %s -> %s" % [tag, chips])
	if chips.is_empty():
		_fail("%s: no attribute chips on the screen" % tag)
	return chips

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	if not _type_seed("0000000A"):
		return
	await _settle()
	if not _focus_class(&"warrior"):
		return
	await _settle()
	await _scroll_to_attributes()
	var first := _report("seed 0000000A")
	await _shot("finch_131_rolled_seed_a")

	if not _type_seed("0000000B"):
		return
	await _settle()
	if not _focus_class(&"warrior"):
		return
	await _settle()
	await _scroll_to_attributes()
	var second := _report("seed 0000000B")
	await _shot("finch_131_rolled_seed_b")
	if not first.is_empty() and first == second:
		_fail("two seeds produced the same Warrior; the field is not reaching the roster")

	# And back, which is the reproducibility the issue asks for by name.
	if not _type_seed("0000000A"):
		return
	await _settle()
	if not _focus_class(&"warrior"):
		return
	await _settle()
	await _scroll_to_attributes()
	var again := _report("seed 0000000A again")
	if again != first:
		_fail("retyping a seed did not reproduce its roster")
