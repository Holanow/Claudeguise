extends Node

## Issue 535. A still of a paused fight proves nothing -- the whole claim is
## that the picture STOPS. So this pauses on a fresh death and shoots the same
## screen 1.2 real seconds apart, then counts the pixels that moved between
## them. Held means ZERO, not a small number: the ring lives 0.35s and the
## plate 2.4s, so without the fix both have moved on under the player's eyes.

const OUT_DIR := "res://Screenshots"
const HOLD_SECONDS := 1.2

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("PauseHoldShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("PauseHoldShot: %s_%s.png" % [name, _tag])
	return img

## How many pixels two frames disagree on, which is the measurement. A COUNT
## and not a fraction: held has to mean nothing moved, and a fraction rounds
## the interesting answer to 0.00%. Measured -- the unfixed view scores 368
## pixels here, which is 0.04% and slid under a 0.05% floor.
func _moved(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return a.get_width() * a.get_height()
	var differing := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				differing += 1
	return differing

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("PauseHoldShot: no visible button '%s'" % prefix)
	return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _to_battle() -> Node:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	# The seed first, and rerolled from it: it picks the roster as well as the
	# fight, so choosing cards before setting it gives a different party and a
	# different fight every run.
	var select := _node_with("PartySelect.gd")
	select._seed_edit.text = "00000001"
	select._seed_edit.text_submitted.emit("00000001")
	await _settle()
	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	for id in [&"warrior", &"priest", &"geysermancer"]:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	if not _press("start fight"):
		return null
	await _settle()
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		if not _press("start fight"):
			return null
		await _settle()
	return _node_with("BattleView.gd")

func _run() -> bool:
	# Damage numbers on, because the number is one of the three marks that used
	# to age away under the player's eyes.
	DisplayOptions.set_enabled(&"damage_numbers", true)
	var battle := await _to_battle()
	if battle == null:
		print("PauseHoldShot: no battle screen")
		return false
	battle.set_process(false)
	# Held on a DEATH: the plate is the 2.4s mark and the longest thing pause
	# has to hold, and it is the one the player is looking hardest at.
	for i in 600:
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		battle._process(CG.TICK_SECONDS)
		if _death_plates(battle) > 0:
			break
	if _death_plates(battle) == 0:
		print("PauseHoldShot: nothing on screen to hold -- the fixture found no death")
		return false
	print("PauseHoldShot: paused on a death at tick %d, %d marks live" % [
		battle.state.tick, _fresh_marks(battle)])

	# The player's own action, through the control the player uses.
	battle.set_process(true)
	if not _press("pause"):
		return false
	await _settle(2)
	var first := await _shot("teal_535_paused_at_the_hit")
	await get_tree().create_timer(HOLD_SECONDS).timeout
	var second := await _shot("teal_535_paused_%.1fs_later" % HOLD_SECONDS)
	var held_move := _moved(first, second)
	print("PauseHoldShot: %d pixels moved across %.1fs of pause" % [held_move, HOLD_SECONDS])

	# The negative. A picture that never moves again is the same defect wearing
	# the other sign, and it looks identical in one still.
	if not _press("resume"):
		return false
	await get_tree().create_timer(0.4).timeout
	var third := await _shot("teal_535_resumed")
	var resumed_move := _moved(first, third)
	print("PauseHoldShot: %d pixels moved in 0.4s after the resume" % [resumed_move])

	if held_move != 0:
		print("PauseHoldShot: FAIL -- the paused picture kept moving")
		return false
	if resumed_move == 0:
		print("PauseHoldShot: FAIL -- the picture never started again")
		return false
	print("PauseHoldShot: PASS")
	return true

func _death_plates(battle: Node) -> int:
	var n := 0
	for child in battle._arena.get_children():
		var script = child.get_script()
		if script != null and script.resource_path.ends_with("DamageFloater.gd"):
			if child.death_marker:
				n += 1
	return n

## Damage numbers, death plates and impact rings live under the arena. Anything
## still on screen is something a pause is meant to hold.
func _fresh_marks(battle: Node) -> int:
	var n := 0
	for child in battle._arena.get_children():
		var script = child.get_script()
		if script == null:
			continue
		var path: String = script.resource_path
		if path.ends_with("DamageFloater.gd") or path.ends_with("ImpactFlash.gd"):
			n += 1
	return n
