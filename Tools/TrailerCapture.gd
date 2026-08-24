extends Node

## Records real gameplay as a numbered PNG frame sequence, one file per rendered
## frame, so a trailer can be cut from it.
##
## Every frame is driven by hand and every clip is pinned to a literal party,
## room and seed, so two runs write byte-identical files. Launch it with
## `-FixedFps 60`: the particle system ages on the engine's own delta and
## nothing in a tool can reach it, so without a fixed delta the debris in a
## frame depends on how long the previous `save_png` took.

const FRAMES_PER_TICK := 4
const SIZE := Vector2i(1280, 720)
## Pinned by id, never by registry order, so the party is the same in every
## process (board FINDING 4).
const PARTY: Array = [&"warrior", &"priest", &"geysermancer", &"abomination"]
const ROOMS: Array = [&"floor1_room1", &"floor1_cover", &"floor1_hazard", &"floor1_horde"]
const SEEDS := 24
## A fight long enough to have a shape and short enough to cut.
const MIN_TICKS := 100
const MAX_FIGHT_TICKS := 400
## Frames either side of the killing blow. 120 is two seconds at 60Hz.
const KILL_LEAD := 120
const KILL_TAIL := 90
## The victory banner, held after the fight resolves.
const BANNER_FRAMES := 90
## Four seconds of the same window, once per toggle arm.
const TOGGLE_FRAMES := 240
## Two ticks, which is where a four-frame repeat and a jump both fit.
const INTERP_FRAMES := 8
const LOOSE_LEAD := 8
const LOOSE_FRAMES := 48

## What the trailer shows. Damage numbers and name plates ship off; a trailer
## wants the game at its most legible, so they are on here and every clip's
## manifest line says so.
const SHOWY := {
	&"damage_numbers": true,
	&"name_plates": true,
	&"hit_stop": true,
	&"impact_squash": true,
	&"impact_particles": true,
	&"screen_shake": false,
}

## Body motion only. Plates and numbers are off in the A/B clips for the reason
## HitStopShot kept them off: an overlay that lags its body contaminates a strip
## about where the body is drawn.
const PLAIN := {
	&"damage_numbers": false,
	&"name_plates": false,
	&"hit_stop": true,
	&"impact_squash": true,
	&"impact_particles": true,
	&"screen_shake": false,
}

const CLIPS := ["fight_full", "kill_slowmo", "interp_ab", "ranged_loose", "toggles"]

var _out := ""
var _only := ""
var _n := 0
var _view: Node2D = null
var _manifest: Array[String] = []
var _failures: Array[String] = []


func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("TrailerCapture: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	if not _parse_args():
		get_tree().quit(3)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _run()
	DisplayOptions.reset()
	print("")
	print("MANIFEST (%s)" % _out)
	for line in _manifest:
		print(line)
	if not _failures.is_empty():
		printerr("TrailerCapture: %d clip(s) produced nothing:" % _failures.size())
		for f in _failures:
			printerr("  - %s" % f)
	get_tree().quit(0 if _failures.is_empty() else 1)


## `<dir> [--clip=<name>]`, after `--` on the command line.
func _parse_args() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clip="):
			_only = arg.substr(7)
		elif _out == "":
			_out = arg
	if _out == "":
		printerr("TrailerCapture: needs an output directory.")
		printerr("  ... run.ps1 TrailerCapture -FixedFps 60 -ToolArgs D:\\path\\to\\frames")
		return false
	if _only != "" and not CLIPS.has(_only):
		printerr("TrailerCapture: no clip '%s'. Have: %s" % [_only, ", ".join(CLIPS)])
		return false
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		printerr("TrailerCapture: cannot make %s" % _out)
		return false
	return true


func _run() -> void:
	var fight := _pick_fight()
	if fight.is_empty():
		_failures.append("no party win in %d rooms x %d seeds" % [ROOMS.size(), SEEDS])
		return
	print("TrailerCapture: %s seed %d, %d ticks, %d deaths, %d shots" % [
		fight["room"], fight["seed"], fight["ticks"], fight["deaths"], fight["shots"]])
	if _wanted("fight_full"):
		await _clip_fight_full(fight)
	if _wanted("kill_slowmo"):
		await _clip_kill_slowmo(fight)
	if _wanted("interp_ab"):
		await _clip_interp_ab()
	if _wanted("ranged_loose"):
		await _clip_ranged_loose()
	if _wanted("toggles"):
		await _clip_toggles(fight)


func _wanted(clip: String) -> bool:
	return _only == "" or _only == clip


# --- the simulation-only scans -----------------------------------------------

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in PARTY.size():
		out.append(PawnFactory.make_starter_pawn(
			PARTY[i], StringName("p%d" % i), String(PARTY[i])))
	return out


## The busiest fight the party wins, over a pinned grid of rooms and seeds. The
## deaths are what `kill_slowmo` and `toggles` are cut from, so a fight with few
## of them is the wrong establishing shot as well as a dull one.
func _pick_fight() -> Dictionary:
	var best := {}
	var best_score := -1.0
	for room_id in ROOMS:
		var encounter = Registry.get_encounter(room_id)
		if encounter == null:
			continue
		for s in range(1, SEEDS + 1):
			var run := _play(encounter, s)
			if run["outcome"] != CombatState.Outcome.PLAYER_WIN:
				continue
			if run["ticks"] < MIN_TICKS or run["ticks"] > MAX_FIGHT_TICKS:
				continue
			var score: float = run["deaths"] * 10.0 + run["shots"]
			if score <= best_score:
				continue
			best_score = score
			best = run
			best["room"] = room_id
			best["seed"] = s
	return best


func _play(encounter, s: int) -> Dictionary:
	var state := CombatSim.build(_party(), encounter, s)
	var deaths := 0
	var shots := 0
	var cursor := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		for e in state.events_since(cursor):
			if e.kind == CG.EventKind.DEATH:
				deaths += 1
			elif e.kind == CG.EventKind.ACTION_FIRE:
				shots += 1
		cursor = state.events.size()
	return {"outcome": state.outcome, "ticks": state.tick, "deaths": deaths, "shots": shots}


## The biggest body that dies in this fight, and the tick it dies on. Biggest,
## because four pixels of squash off an eleven-pixel goblin is not a money shot.
func _best_death(room_id: StringName, s: int) -> Dictionary:
	var state := CombatSim.build(_party(), Registry.get_encounter(room_id), s)
	var best := {}
	var best_size := 0.0
	var cursor := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		for e in state.events_since(cursor):
			if e.kind != CG.EventKind.DEATH or state.tick * FRAMES_PER_TICK <= KILL_LEAD:
				continue
			var victim := state.unit(e.target_id)
			if victim == null:
				continue
			var size := UnitView.drawn_half_width(
				UnitView.shape_id(victim), victim.team, UnitView.display_radius(victim))
			if size <= best_size:
				continue
			best_size = size
			best = {"tick": state.tick, "id": victim.id, "name": victim.display_name, "size": size}
		cursor = state.events.size()
	return best


## InterpShot's scan, pinned to this trailer's party and room: the tick where
## some unit covers the most ground in one step is where a 15Hz snap is largest.
func _fastest_walk(room_id: StringName, s: int) -> Dictionary:
	var state := CombatSim.build(_party(), Registry.get_encounter(room_id), s)
	var best := {"tick": -1, "id": -1, "moved": 0.0}
	var was := {}
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		for u in state.units:
			was[u.id] = u.position
		CombatSim.step(state)
		for u in state.units:
			if not u.alive or not was.has(u.id):
				continue
			var moved: float = u.position.distance_to(was[u.id])
			# A walk, not a jump the view is meant to snap through.
			if moved > best["moved"] and moved <= u.move_speed * 3.0 and state.tick > INTERP_FRAMES:
				best = {"tick": state.tick - 1, "id": u.id, "moved": moved}
	return best


## LooseShot's scan: every ACTION_FIRE whose action carries a projectile, won by
## the biggest shooter.
func _loose(room_id: StringName, s: int) -> Dictionary:
	var state := CombatSim.build(_party(), Registry.get_encounter(room_id), s)
	var best := {}
	var best_size := 0.0
	var cursor := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		for e in state.events_since(cursor):
			if e.kind != CG.EventKind.ACTION_FIRE or state.tick * FRAMES_PER_TICK <= LOOSE_LEAD:
				continue
			var action := Registry.get_action(e.action_id)
			if action == null or action.projectile_speed <= 0.0:
				continue
			var source := state.unit(e.source_id)
			if source == null or source.team != CG.Team.PLAYER:
				continue
			var size := UnitView.drawn_half_width(
				UnitView.shape_id(source), source.team, UnitView.display_radius(source))
			if size <= best_size:
				continue
			best_size = size
			best = {"tick": state.tick - 1, "source": source.id,
				"name": source.display_name, "action": e.action_id}
		cursor = state.events.size()
	return best


# --- driving and capturing ---------------------------------------------------

## Started the way the game starts one. Setting `state` by hand instead leaves
## `_text_layer` null and every stepped frame dies inside `_process` (#512).
func _build_view(room_id: StringName, s: int) -> void:
	seed(s)
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = room_id
	cfg.seed = s
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, Registry.get_encounter(room_id))
	_view.set_process(false)


## One rendered frame of the view's clock, at exactly the delta the engine is
## fixed to. `raw` re-renders at alpha 1, which is the pre-#501 picture: the
## body sits on the tick position for all four frames and then jumps.
func _frame(raw: bool = false) -> void:
	_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))
	if raw:
		_view._render(1.0, false, 0.0)


func _teardown() -> void:
	if _view == null:
		return
	_view.queue_free()
	_view = null
	await get_tree().process_frame


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_size() != SIZE:
		if _failures.is_empty() or not _failures[-1].begins_with("frames are"):
			_failures.append("frames are %s, not %s -- launch with -Resolution 1280x720"
				% [img.get_size(), SIZE])
	_n += 1
	img.save_png("%s/frame_%05d.png" % [_out, _n])


## Silent frames: driven and rendered, never written. This is how a clip reaches
## the tick it starts at without the run-up landing in the sequence.
func _skip_to(tick: int) -> void:
	while _view.state.tick < tick and _view.state.outcome == CombatState.Outcome.UNRESOLVED:
		_frame()
		await get_tree().process_frame


func _set_toggles(values: Dictionary) -> void:
	DisplayOptions.reset()
	for id in values:
		DisplayOptions.set_enabled(id, values[id])


func _toggle_text(values: Dictionary) -> String:
	var parts := PackedStringArray()
	for option in DisplayOptions.OPTIONS:
		if values.has(option.id):
			parts.append("%s=%s" % [option.id, "on" if values[option.id] else "off"])
	return " ".join(parts)


func _say(clip: String, from: int, values: Dictionary, detail: String) -> void:
	if _n < from:
		_failures.append("%s wrote no frames" % clip)
		return
	var line := "CLIP %-16s frames %05d-%05d (%d)  %s  toggles: %s" % [
		clip, from, _n, _n - from + 1, detail, _toggle_text(values)]
	_manifest.append(line)
	print(line)


# --- the clips ---------------------------------------------------------------

## The establishing shot and the closer: one whole fight the party wins, at
## normal speed, held on the victory banner at the end.
func _clip_fight_full(fight: Dictionary) -> void:
	_set_toggles(SHOWY)
	await _build_view(fight["room"], fight["seed"])
	var from := _n + 1
	while _view.state.outcome == CombatState.Outcome.UNRESOLVED \
			and _view.state.tick < MAX_FIGHT_TICKS + 1:
		await _capture()
		_frame()
	for i in BANNER_FRAMES:
		await _capture()
		_frame()
	_say("fight_full", from, SHOWY, "%s seed %d, %d ticks, %d deaths, victory banner held %d frames" % [
		fight["room"], fight["seed"], _view.state.tick, fight["deaths"], BANNER_FRAMES])
	await _teardown()


## The money shot. Two seconds before the killing blow and a second and a half
## after it, so the hit stop, the squash, the debris and the death plate all
## have room to read.
func _clip_kill_slowmo(fight: Dictionary) -> void:
	var death := _best_death(fight["room"], fight["seed"])
	if death.is_empty():
		_failures.append("kill_slowmo: no death late enough in %s seed %d"
			% [fight["room"], fight["seed"]])
		return
	_set_toggles(SHOWY)
	await _build_view(fight["room"], fight["seed"])
	await _skip_to(int(death["tick"]) - KILL_LEAD / FRAMES_PER_TICK)
	var from := _n + 1
	for i in KILL_LEAD + KILL_TAIL:
		await _capture()
		_frame()
	_say("kill_slowmo", from, SHOWY,
		"%s seed %d, %s (%.0f px half-width) dies on tick %d, %d frames of lead" % [
			fight["room"], fight["seed"], death["name"], death["size"],
			death["tick"], KILL_LEAD])
	await _teardown()


## The same walking pawn twice: the view interpolating, then forced to the
## pre-#501 picture of four identical frames and a jump.
func _clip_interp_ab() -> void:
	var room: StringName = ROOMS[0]
	var s := 7
	var walk := _fastest_walk(room, s)
	if walk["id"] < 0:
		_failures.append("interp_ab: no walk found in %s seed %d" % [room, s])
		return
	for raw in [false, true]:
		_set_toggles(PLAIN)
		await _build_view(room, s)
		await _skip_to(int(walk["tick"]))
		if raw:
			_view._render(1.0, false, 0.0)
			await get_tree().process_frame
		var from := _n + 1
		for i in INTERP_FRAMES:
			await _capture()
			_frame(raw)
		_say("interp_ab.%s" % ("off" if raw else "on"), from, PLAIN,
			"%s seed %d, unit %d walks %.1f units in one tick from tick %d, interpolation %s" % [
				room, s, walk["id"], walk["moved"], walk["tick"],
				"FORCED OFF (pre-501)" if raw else "on (shipped)"])
		await _teardown()


## A player archer or caster looses a shot, and kicks back off it (#531).
func _clip_ranged_loose() -> void:
	var room: StringName = ROOMS[0]
	var s := 7
	var loose := _loose(room, s)
	if loose.is_empty():
		_failures.append("ranged_loose: no projectile loose in %s seed %d" % [room, s])
		return
	_set_toggles(SHOWY)
	await _build_view(room, s)
	await _skip_to(int(loose["tick"]))
	var shooter: Node2D = _view._unit_views[loose["source"]]
	var at: Vector2 = shooter.get_global_transform_with_canvas().origin
	var from := _n + 1
	for i in LOOSE_FRAMES:
		await _capture()
		_frame()
	_say("ranged_loose", from, SHOWY,
		"%s seed %d, %s looses %s on tick %d, shooter at screen %.0f,%.0f" % [
			room, s, loose["name"], loose["action"], int(loose["tick"]) + 1, at.x, at.y])
	await _teardown()


## The same seconds twice, the two game-feel toggles off and then on.
func _clip_toggles(fight: Dictionary) -> void:
	var death := _best_death(fight["room"], fight["seed"])
	if death.is_empty():
		_failures.append("toggles: no death to centre the window on")
		return
	var start: int = maxi(0, int(death["tick"]) - TOGGLE_FRAMES / (2 * FRAMES_PER_TICK))
	for on in [false, true]:
		var values := SHOWY.duplicate()
		values[&"impact_squash"] = on
		values[&"hit_stop"] = on
		_set_toggles(values)
		await _build_view(fight["room"], fight["seed"])
		await _skip_to(start)
		var from := _n + 1
		for i in TOGGLE_FRAMES:
			await _capture()
			_frame()
		_say("toggles.%s" % ("on" if on else "off"), from, values,
			"%s seed %d, from tick %d, %s dies on tick %d" % [
				fight["room"], fight["seed"], start, death["name"], death["tick"]])
		await _teardown()
