extends Node

## Watch the Warrior's block happen in the real game, through the real controls.
##
##   godot --path . --resolution 1280x720 res://Tools/BlockOnScreen.tscn
##
## Not part of the game and not part of the gate. swift's, for issue #99.
##
## Built on ScreenSweep's pattern -- real Main scene, real party cards, real
## Start Fight button, no synthetic OS input -- with one difference that is the
## whole point: it picks a party **containing the Warrior**. ScreenSweep takes
## the first four cards, which is every class except the Warrior, so the screen
## it photographs is the one party in the game that never blocks anything.
##
## It also prints what `CombatLogView.line_for_event` returns for the BLOCKED
## events it just watched. That is wren's file and this does not touch it: the
## empty strings in the output are the ask, not a defect I left behind.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatLogView := preload("res://Scripts/UI/CombatLogView.gd")

const OUT_DIR := "res://Screenshots"

var _main: Node

func _ready() -> void:
	await _run()
	get_tree().quit(0)

func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s.png" % [OUT_DIR, name]
	image.save_png(path)
	print("BlockOnScreen: %s" % path)

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _party_cards() -> Array:
	var out := []
	for n in _walk(_main):
		if n is Control and not (n is Button) and n.has_signal("toggled"):
			out.append(n)
	return out

func _run() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn"))
	_main = packed.instantiate()
	add_child(_main)
	await _settle()

	# The Warrior first, then fill to four. Picked by the card's own class_def,
	# not by index: the index is exactly what put the Warrior out of every
	# screenshot the project has.
	var cards := _party_cards()
	var picked := 0
	for c in cards:
		if c.class_def != null and c.class_def.id == &"warrior":
			c.toggled.emit(true)
			picked += 1
	for c in cards:
		if picked >= 4:
			break
		if c.class_def != null and c.class_def.id != &"warrior":
			c.toggled.emit(true)
			picked += 1
	await _settle()

	for b in _walk(_main):
		if b is Button and b.text.to_lower().begins_with("start fight"):
			if b.disabled:
				print("BlockOnScreen: Start Fight is disabled with %d picked; stopping" % picked)
				return
			b.emit_signal("pressed")
			break
	await _settle()

	if _main.get_child(0).name != "Battle":
		print("BlockOnScreen: did not reach the battle screen; stopping")
		return
	var battle := _main.get_child(0)

	# Run the real fight until the first interception, then photograph it.
	var seen := 0
	var frames := 0
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < 60 * 150:
		await get_tree().process_frame
		frames += 1
		seen = 0
		for e in battle.state.events:
			if e.kind == CG.EventKind.BLOCKED:
				seen += 1
		if seen > 0:
			break

	print("BlockOnScreen: tick %d, %d BLOCKED so far" % [battle.state.tick, seen])
	await _shot("block_99_first_block")

	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < 60 * 150:
		await get_tree().process_frame
		frames += 1
	await _shot("block_99_fight_end")

	var blocks := 0
	var log_view := CombatLogView.new()
	print("")
	print("-- every BLOCKED event in one real fight, and what the log says today --")
	for e in battle.state.events:
		if e.kind != CG.EventKind.BLOCKED:
			continue
		blocks += 1
		var shooter = battle.state.unit(e.source_id)
		var blocker = battle.state.unit(e.target_id)
		if blocks <= 6:
			print("  tick %4d  %s's %s stopped by %s   log line: \"%s\"" % [
				e.tick,
				shooter.display_name if shooter != null else "?",
				String(e.action_id),
				blocker.display_name if blocker != null else "?",
				log_view.line_for_event(battle.state, e),
			])
	log_view.free()
	print("  %d BLOCKED events in this fight, outcome %s at tick %d" % [
		blocks, CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick,
	])
