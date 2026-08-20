extends Node

## Issues 218 and 249, photographed on the endings they are about.
##
##   godot --path . --resolution 1280x720 res://Tools/EndBannerShot.tscn
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## **It finds its own seeds rather than being told them.** A seed hardcoded here
## is a seed that stops meaning what it meant the next time content moves, and
## both of these endings are emergent -- 11 of 40 seeds on `floor1_warden` end
## with the party dead and the engines still standing (issue 233), and
## CANNOT_ACT needs a Warden with nothing left alive that can mark it. So this
## sweeps seeds headlessly first, prints what it found, and only then launches
## the real screen on one of each.
##
## The launch half goes through the controls a player uses: party select, the
## room picker, the seed box, Start fight, deploy, Start fight, then it lets the
## fight run to its own end and photographs the banner.


const OUT_DIR := "res://Screenshots"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const ROOM := &"floor1_warden"
const SEEDS := 40

var _main: Node

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("EndBannerShot: use a worktree."); get_tree().quit(2); return
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("EndBannerShot: wrote %s.png (%dx%d)" % [name, img.get_width(), img.get_height()])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	printerr("EndBannerShot: no button '%s'" % prefix); return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for id in PARTY:
		out.append(PawnFactory.make_starter_pawn(
			StringName(id), StringName(id), Registry.get_class_def(StringName(id)).display_name))
	return out

## Which seed produces which ending, measured rather than assumed.
func _sweep() -> Dictionary:
	var found := {}
	var counts := {"pawnless": 0, "cannot_act": 0, "ordinary": 0}
	for seed in SEEDS:
		var state := CombatSim.build(_party(), Registry.get_encounter(ROOM), seed)
		CombatSim.run(state)
		var pawnless := CombatSim.is_pawnless_win(state)
		var reason := BattleView.end_reason_of(state)
		if pawnless:
			counts["pawnless"] += 1
			if not found.has("pawnless"):
				found["pawnless"] = seed
		if reason == CG.EndReason.CANNOT_ACT:
			counts["cannot_act"] += 1
			if not found.has("cannot_act"):
				found["cannot_act"] = seed
		if not pawnless and reason == CG.EndReason.NO_SURVIVORS:
			counts["ordinary"] += 1
			if not found.has("ordinary"):
				found["ordinary"] = seed
		if reason == CG.EndReason.UNSET:
			printerr("EndBannerShot: seed %d ended with NO REASON SET" % seed)
	print("EndBannerShot: %s over %d seeds on %s" % [counts, SEEDS, ROOM])
	print("EndBannerShot: shooting %s" % found)
	return found

func _to_battle(seed: int) -> Node:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null and PARTY.has(String(n.class_def.id)):
				n.toggled.emit(true)
	await _settle()

	var select := _node_with("PartySelect.gd")
	var picker: OptionButton = select._room_picker
	for i in picker.item_count:
		if picker.get_item_metadata(i) == ROOM:
			picker.selected = i
			picker.item_selected.emit(i)
	# The seed box a player types into, in the format it displays.
	select._seed_edit.text = "%08X" % seed
	select._seed_edit.text_changed.emit(select._seed_edit.text)
	await _settle()
	if not _press("start fight"): return null
	await _settle()
	if not _press("start fight"): return null
	await _settle(2)
	return _node_with("BattleView.gd")

func _run() -> void:
	var found := _sweep()
	for kind in ["pawnless", "cannot_act", "ordinary"]:
		if not found.has(kind):
			printerr("EndBannerShot: no seed in %d produced '%s' -- not shot" % [SEEDS, kind])
			continue
		var battle = await _to_battle(int(found[kind]))
		if battle == null:
			printerr("EndBannerShot: never reached the battle for %s" % kind)
			return
		var frames := 0
		while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < 400000:
			await get_tree().process_frame
			frames += 1
		await _settle(4)
		await _shot("end_banner_%s" % kind)
		# Read off the screen, not recomputed: the point is what the player is
		# looking at, and a banner that agrees with itself is the whole issue.
		print("EndBannerShot: %s, seed %d, tick %d" % [kind, int(found[kind]), battle.state.tick])
		print("   verdict:  %s" % battle._end_outcome_label.text)
		print("   under it: %s" % battle._end_cost_label.text.replace("\n", " / "))
		_main.queue_free()
		_main = null
		await _settle(4)
