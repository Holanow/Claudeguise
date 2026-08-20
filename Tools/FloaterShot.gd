extends Node

## Issue 136: is the arena actually quieter with the numbers off?
##   godot --path . --resolution 1280x720 res://Tools/FloaterShot.tscn
## Runs one fight to mid, captures default (off), the panel, and the same
## fight with them on. Counts live floaters so the claim is measured, not eyed.

const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")

const OUT_DIR := "res://Screenshots"
var _main: Node
var _tag := ""
var _fail := 0

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("FloaterShot: use a worktree."); get_tree().quit(2); return
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	await _run()
	print("FloaterShot: %d failure(s)" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("FloaterShot: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	print("FloaterShot: no button '%s'" % prefix); return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _check(ok: bool, msg: String) -> void:
	print("FloaterShot: %s %s" % ["OK  " if ok else "FAIL", msg])
	if not ok: _fail += 1

## Death markers and miss markers share `DamageFloater`'s script, so counting by
## script counts them too -- which it did, and reported 8 "damage numbers" still
## on screen with the option off. They were the markers the issue says must
## STAY. A damage number is the subset whose text is a bare number.
func _floaters(battle) -> int:
	var n := 0
	for c in battle._arena.get_children():
		if c.get_script() == DamageFloaterScript and c._text.is_valid_int():
			n += 1
	return n

func _markers(battle) -> int:
	var n := 0
	for c in battle._arena.get_children():
		if c.get_script() == DamageFloaterScript and not c._text.is_valid_int():
			n += 1
	return n

## Run the fight far enough that damage is landing every tick.
func _advance(battle, ticks: int) -> void:
	for i in ticks:
		battle._process(CG.TICK_SECONDS)
		await get_tree().process_frame

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var cards: Array[Node] = []
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	for i in mini(4, cards.size()):
		cards[i].toggled.emit(true)
	await _settle()
	if not _press("start fight"): return
	await _settle()
	if not _press("start fight"): return
	await _settle()

	var battle := _node_with("BattleView.gd")
	_check(battle != null, "reached the battle")
	if battle == null: return

	await _advance(battle, 120)
	await _settle(2)
	var off := _floaters(battle)
	_check(off == 0, "no damage numbers on screen by default (%d)" % off)
	_check(_markers(battle) > 0, "death and miss markers still drawn (%d)" % _markers(battle))
	await _shot("wren_floaters_off")

	if not _press("what to show"): return
	await _settle()
	await _shot("wren_floaters_panel")

	var panel := _node_with("DisplayOptionsPanel.gd")
	for n in _walk(panel):
		if n is CheckBox:
			n.button_pressed = true
			break
	await _advance(battle, 60)
	await _settle(2)
	var on := _floaters(battle)
	_check(on > 0, "ticking the box brings them back (%d on screen)" % on)
	print("FloaterShot: %d floaters with them ON, %d with them OFF" % [on, off])
	await _shot("wren_floaters_on")
