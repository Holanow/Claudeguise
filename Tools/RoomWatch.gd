extends Node

## Go and watch the rooms. Not a win table -- a fight in each of the five
## offered rooms, driven through the real controls, captured while it runs.
##
##   godot --path . --resolution 1280x720 res://Tools/RoomWatch.tscn
##
## `RoomPickerShot` proves a room is REACHABLE and shoots one frame at tick 0.
## This shoots the fight: four frames spread across it plus the end, and it
## prints, per room, the one measurement that says whether the room's own
## mechanic is doing anything while the player is looking at it.
##
## The party is geysermancer/priest/siege_master/warrior. The Abomination is
## deliberately left out: PR #172 moves it and a picture of it now would be a
## picture of something the game is about to stop being.

const Registry := preload("res://Scripts/Content/Registry.gd")
const PartySelect := preload("res://Scripts/UI/PartySelect.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const CG := preload("res://Scripts/Core/CG.gd")

const OUT_DIR := "res://Screenshots"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const SHOT_TICKS := [40, 100, 200, 340]

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("RoomWatch: use a worktree."); get_tree().quit(2); return
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

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	print("RoomWatch: no button '%s'" % prefix); return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _fresh() -> void:
	if _main != null:
		_main.queue_free()
		await _settle()
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	# Pick by class id, not by card index. Index order is Registry's sort order
	# and the first four of those include the Abomination.
	var ids := Registry.all_class_ids()
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null and PARTY.has(String(n.class_def.id)):
				n.toggled.emit(true)
	await _settle()

func _run() -> void:
	var offered = PartySelect.offered_rooms()
	# `--room chokepoint` watches one room instead of five. Ninety seconds
	# instead of eight minutes when only one number is being re-taken.
	var only := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--room" and i + 1 < args.size():
			only = args[i + 1]
	print("RoomWatch: rooms %s" % str(offered))
	for room_id in offered:
		if only != "" and not String(room_id).ends_with(only): continue
		await _watch(room_id)

func _watch(room_id: StringName) -> void:
	await _fresh()
	var select := _node_with("PartySelect.gd")
	var picker: OptionButton = select._room_picker
	var found := -1
	for i in picker.item_count:
		if picker.get_item_metadata(i) == room_id:
			found = i
	if found < 0:
		print("RoomWatch: %s not offered" % room_id); return
	picker.selected = found
	picker.item_selected.emit(found)
	await _settle()
	if not _press("start fight"): return
	await _settle()
	if not _press("start fight"): return
	await _settle(2)

	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("RoomWatch: %s never reached the battle" % room_id); return
	var short := String(room_id).replace("floor1_", "")
	var probe := _Probe.new(battle.state, short)
	await _shot("room_%s_t000" % short)

	var frames := 0
	var next := 0
	# 90 seconds of real time per room. This runs at the speed a player watches
	# it at -- the point is the picture, and an unresolved fight still produces
	# every frame the shots need. The tick reached is printed either way.
	#
	# **"UNRESOLVED" HERE MEANS THIS CAP, NOT A STALL, AND MY OWN #201 REPORT
	# READ IT THE WRONG WAY.** That run said room1, hazard and rat_king "did not
	# resolve", which invites the reading that three of five rooms hang. They do
	# not. 90 seconds lands near tick 493, and headless over 12 seeds x 5
	# buildable parties (`Tools/SwarmProbe.gd`) **every one of the 300 fights
	# resolved**, none reaching CG.MAX_TICKS:
	#
	#   room                median   p90   max   past tick 493
	#   floor1_room1           337   452   501             3%
	#   floor1_cover           290   364   495             2%
	#   floor1_hazard          345   554   660            22%
	#   floor1_chokepoint      446   548   836            27%
	#   floor1_rat_king        252   478   907            10%
	#
	# So the instrument is short, the fights are not long, and the cap is left
	# where it is: three of these five medians sit inside it, and the shots
	# through tick 340 are what this tool is for. Raising it to catch the tail
	# would cost about a minute per room for the last tenth of the fights.
	# Read an UNRESOLVED line here as "the window closed", and take fight length
	# from SwarmProbe, which measures it properly.
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < 60 * 90:
		await get_tree().process_frame
		frames += 1
		probe.sample(battle.state)
		if next < SHOT_TICKS.size() and battle.state.tick >= SHOT_TICKS[next]:
			await _shot("room_%s_t%03d" % [short, SHOT_TICKS[next]])
			next += 1
	await _shot("room_%s_end" % short)
	print("RoomWatch: %s outcome=%s tick=%d" % [
		room_id, CombatState.Outcome.keys()[battle.state.outcome], battle.state.tick])
	probe.report()

## Per-room instrumentation. Each room gets asked the one question its own
## design comment claims an answer to, sampled every frame of the real fight
## rather than reasoned about from the encounter definition.
class _Probe extends RefCounted:
	var room := ""
	var ticks := 0
	var last_tick := -1
	# colonnade
	var los_blocked_ticks := 0
	var los_pairs := 0
	# burn room
	var lane_ticks := 0
	var fire_ticks := 0
	var burned := {}
	# chokepoint
	var crossed := {}
	var slowed_ticks := 0
	# rat king
	var rat_peak := 0
	var rats_seen := {}
	var pillars: Array = []
	var fires: Array = []
	var tar: Array = []

	func _init(state, r: String) -> void:
		room = r
		for f in state.terrain:
			if f.kind == Terrain.Kind.PILLAR: pillars.append(f)
			elif f.kind == Terrain.Kind.HAZARD and f.damage_per_tick > 0: fires.append(f)
			elif f.kind == Terrain.Kind.HAZARD: tar.append(f)

	func sample(state) -> void:
		if state.tick == last_tick: return
		last_tick = state.tick
		ticks += 1
		var alive: Array = []
		for u in state.units:
			if u.alive: alive.append(u)
		# Colonnade: of every living player/enemy pair, how many cannot see
		# each other. A pillar that is never between anybody is decoration.
		if not pillars.is_empty():
			for a in alive:
				if a.team != CG.Team.PLAYER: continue
				for b in alive:
					if b.team == CG.Team.PLAYER: continue
					los_pairs += 1
					if Terrain.line_is_blocked(state.terrain, a.position, b.position):
						los_blocked_ticks += 1
		# Burn room: is anybody in the clear lanes, and is anybody in the fire.
		if not fires.is_empty():
			for u in alive:
				var in_fire := false
				for f in fires:
					if f.contains_point(u.position): in_fire = true
				if in_fire:
					fire_ticks += 1
					burned[u.id] = true
				elif absf(u.position.y) > 100.0 and absf(u.position.y) < 175.0 and u.position.x > -80.0 and u.position.x < 120.0:
					lane_ticks += 1
		# Chokepoint: who has actually been on the land bridge, and how many
		# unit-ticks of SLOWED the tar produced.
		if not tar.is_empty():
			for u in alive:
				for f in tar:
					if f.contains_point(u.position):
						crossed[u.id] = u.team == CG.Team.PLAYER
				if u.statuses.has(CG.Status.SLOWED): slowed_ticks += 1
		# The Nest: how big does the swarm ever get.
		if room == "rat_king":
			var rats := 0
			for u in alive:
				if u.enemy_id == &"rat":
					rats += 1
					rats_seen[u.id] = true
			rat_peak = maxi(rat_peak, rats)

	func report() -> void:
		if not pillars.is_empty():
			var pct := 100.0 * float(los_blocked_ticks) / maxf(1.0, float(los_pairs))
			print("  COLONNADE: %.1f%% of party/enemy sightlines blocked (%d of %d pair-ticks)" % [
				pct, los_blocked_ticks, los_pairs])
		if not fires.is_empty():
			print("  BURN: %d unit-ticks standing in fire, %d in the clear lanes, %d distinct units burned" % [
				fire_ticks, lane_ticks, burned.size()])
		if not tar.is_empty():
			var party := 0
			for k in crossed:
				if crossed[k]: party += 1
			print("  TAR: %d of 14 units set foot on the bridge (%d party, %d enemy), %d unit-ticks SLOWED" % [
				crossed.size(), party, crossed.size() - party, slowed_ticks])
		if room == "rat_king":
			print("  NEST: peak %d rats alive at once, %d distinct rats ever existed" % [
				rat_peak, rats_seen.size()])
