extends Node

## Launches the real game the way a player does and screenshots what they see.
##
##   godot --path . --resolution 1280x720 res://Tools/LaunchProbe.tscn
##
## MANAGER-OWNED. Not part of the gate.
##
## Instantiates `Scenes/Main.tscn` — the actual main scene from project.godot,
## not a fixture — and captures the first screen a player meets. Then it presses
## the real controls: it finds the class buttons and the start button by walking
## the tree, and clicks them the way a finger would.
##
## Why bother when there are tests: a suite proves the logic and cannot prove the
## screen renders, and everything anybody has verified so far about party select
## was verified against fixtures or against an empty Registry. "Nothing renders"
## and "the start button is disabled forever" are five-second discoveries and
## nobody has spent the five seconds.

const OUT_DIR := "res://Tools/preview"

var _main: Node = null
var _step := 0

func _ready() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	if packed == null:
		printerr("LaunchProbe: main scene did not load")
		get_tree().quit(1)
		return
	_main = packed.instantiate()
	add_child(_main)
	print("LaunchProbe: main scene instantiated: ", _main.name)

func _process(_delta: float) -> void:
	_step += 1
	# A few frames for the screen to build itself before looking at it.
	if _step == 8:
		await _shot("launch_01_party_select")
		_report_buttons()
	elif _step == 16:
		_press_class_buttons()
	elif _step == 24:
		await _shot("launch_02_party_picked")
	elif _step == 32:
		_press_start()
	elif _step == 60:
		await _shot("launch_03_battle")
	elif _step > 60:
		get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	image.save_png("%s/%s.png" % [OUT_DIR, name])
	print("LaunchProbe: wrote ", name)

## Walks the tree for Buttons and prints what a player can actually press. A
## disabled start button is the single most likely way this screen is broken and
## it is invisible in a screenshot unless you know what you are looking at.
func _report_buttons() -> void:
	var buttons := _find_buttons(_main)
	print("LaunchProbe: %d buttons on screen" % buttons.size())
	for b in buttons:
		print("   [%s] '%s' disabled=%s" % [b.get_class(), b.text, b.disabled])

## Toggling, not pressing. A CheckBox has `toggle_mode` on, and Godot emits
## `toggled` for those and `pressed` only for the others — so the first version
## of this probe emitted `pressed` on the class checkboxes, changed nothing, and
## then reported that the Start Fight button was disabled and the game was
## unplayable. That would have been a false defect filed against pike from a
## tool I wrote in the previous five minutes.
##
## Setting `button_pressed` drives the real signal the screen is listening to,
## which is what a finger does.
func _press_class_buttons() -> void:
	var pressed := 0

	# Class selectors were CheckBoxes and are now PartyCards, which are plain
	# Controls that emit `toggled` from _gui_input. This probe went blind the
	# moment that landed and reported "no start button found at all", which is a
	# tool failure that looks exactly like a broken game.
	#
	# Driving the signal rather than synthesising a click, for the same reason
	# the whole probe exists: no mouse capture, nothing that touches the user's
	# desktop.
	for card in _find_party_cards(_main):
		card.toggled.emit(true)
		pressed += 1
		if pressed >= 4:
			break

	if pressed == 0:
		for b in _find_buttons(_main):
			if b.disabled:
				continue
			var t := b.text.to_lower()
			if t.begins_with("start") or t.begins_with("change") or t.begins_with("pause") or t.begins_with("restart"):
				continue
			if b.toggle_mode:
				b.button_pressed = true
			else:
				b.emit_signal("pressed")
			pressed += 1
			if pressed >= 4:
				break

	print("LaunchProbe: selected %d classes" % pressed)

## Anything carrying a `toggled` signal that is not a Button. Found by shape
## rather than by class name, so this keeps working if the card is renamed.
func _find_party_cards(node: Node) -> Array:
	var out: Array = []
	if node is Control and not (node is Button) and node.has_signal("toggled"):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_party_cards(c))
	return out

## The start control's label changes with state — it reads "Pick at least one
## class" when nothing is selected — so matching on the word "start" alone finds
## nothing at the moment it is disabled. Matched on being the only enabled
## non-navigation button instead.
func _press_start() -> void:
	for b in _find_buttons(_main):
		var t := b.text.to_lower()
		if t.begins_with("start") or t.contains("fight"):
			if b.disabled:
				printerr("LaunchProbe: the start button is DISABLED. A player cannot begin a fight.")
				return
			b.emit_signal("pressed")
			print("LaunchProbe: pressed '", b.text, "'")
			return
	printerr("LaunchProbe: no start button found at all")

func _find_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_buttons(c))
	return out
