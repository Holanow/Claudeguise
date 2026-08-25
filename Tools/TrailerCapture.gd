extends Node

## Records real gameplay as a numbered PNG frame sequence, one file per rendered
## frame, so a trailer can be cut from it.
##
## Every frame is driven by hand and every clip is pinned to a literal party,
## room and seed, so two runs play the same fight. Launch it with `-FixedFps 60`:
## the particle system ages on the engine's own delta and nothing in a tool can
## reach it, so without a fixed delta the debris in a frame depends on how long
## the previous `save_png` took.
##
## Add `-WriteMovie <path.avi>` for sound. Godot's movie writer mixes the audio
## bus per rendered frame rather than in real time, which is the only way this
## capture can carry sound at all: the loop runs at about a tenth of real time.
## The movie covers EVERY engine frame, including setup and skipped run-up, so
## each manifest line carries the movie frame range beside the PNG range.

const FRAMES_PER_TICK := 4
const SIZE := Vector2i(1280, 720)
## Pinned by id, never by registry order, so the party is the same in every
## process (board FINDING 4).
const PARTY: Array = [&"warrior", &"priest", &"geysermancer", &"abomination"]
const ROOMS: Array = [&"floor1_room1", &"floor1_cover", &"floor1_hazard", &"floor1_horde"]
## The classes `ranged_loose` is about. The party's biggest body is the
## abomination and its hook is a projectile, so a scan won on size alone
## photographs a melee brute rather than the shot this clip exists for.
const CASTERS: Array = ["priest", "geysermancer"]
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
## Issue 562: the hook drags over `CombatSim.PULL_TICKS` and stuns for the same
## span, so the clip has to outlast the drag rather than the cast.
const HOOK_LEAD := 32
const HOOK_TAIL := 72
## A hand animation's length IS its action's tick count (#583), so each arm of
## `hands_ab` is sized from the action rather than from a constant. Only the
## run-out either side is fixed.
const HAND_LEAD := 16
const HAND_TAIL := 40
## Long enough for the party to break off and cross to the enemy that was
## clicked, plus the held card in front of it.
const FOCUS_CARD_FRAMES := 90
const FOCUS_RUN_FRAMES := 200
## Each sort of the post-fight roster, held.
const ROSTER_FRAMES := 120
## The art A/B window. Held long enough for the hands to bob through a cycle.
const ART_FRAMES := 120

## What the trailer shows. Damage numbers and name plates ship off; a trailer
## wants the game at its most legible, so they are on here and every clip's
## manifest line says so.
const SHOWY := {
	&"damage_numbers": true,
	&"name_plates": true,
	&"hit_stop": true,
	&"hit_flash": true,
	&"part_animation": true,
	&"impact_squash": true,
	&"impact_particles": true,
	&"screen_shake": false,
}

## Body position only. Plates, numbers, the white flash and the hands are all
## off for the reason HitStopShot kept the plates off: anything that moves or
## recolours on its own contaminates a strip about where the body is drawn.
const PLAIN := {
	&"damage_numbers": false,
	&"name_plates": false,
	&"hit_stop": true,
	&"hit_flash": false,
	&"part_animation": false,
	&"impact_squash": true,
	&"impact_particles": true,
	&"screen_shake": false,
}

const CLIPS := ["fight_full", "kill_slowmo", "hook_drag", "hands_ab", "focus_fire",
	"roster", "interp_ab", "ranged_loose", "toggles", "art_ab"]

var _out := ""
var _only := ""
var _label := ""
var _n := 0
var _view: Node2D = null
var _manifest: Array[String] = []
var _failures: Array[String] = []
## The movie writer's own frame numbering, so an editor can find a clip in the
## sound track. -1 until this clip's first PNG has been written.
var _movie_first := -1
var _movie_frame := 0
## The cue sheet: one row per sound that will actually be heard. It is the
## fallback when there is no movie writer, and the check on the mix when there
## is -- the first row's time is where the first noise must land.
var _cues: Array[String] = []
var _cue_cursor := 0
var _cue_tick := -1
var _cue_played := {}


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
	_write_cues()
	print("")
	print("MANIFEST (%s)" % _out)
	var mf := FileAccess.open("%s/manifest%s.txt" % [_out, _label], FileAccess.WRITE)
	for line in _manifest:
		print(line)
		if mf != null:
			mf.store_line(line)
	if mf != null:
		mf.close()
	if not _failures.is_empty():
		printerr("TrailerCapture: %d clip(s) produced nothing:" % _failures.size())
		for f in _failures:
			printerr("  - %s" % f)
	get_tree().quit(0 if _failures.is_empty() else 1)


## `<dir> [--clip=<name>] [--label=<suffix>]`, after `--` on the command line.
## `--label` suffixes the frame filenames so two passes over the same clip --
## which is how `art_ab` gets old art against new -- cannot overwrite each other.
func _parse_args() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clip="):
			_only = arg.substr(7)
		elif arg.begins_with("--label="):
			_label = arg.substr(8)
		elif _out == "":
			_out = arg
	if _out == "":
		printerr("TrailerCapture: needs an output directory.")
		printerr("  ... run.ps1 TrailerCapture -FixedFps 60 -ToolArgs D:\\path\\to\\frames")
		return false
	# A caller that folds `-ToolArgs` into one comma-joined string used to make a
	# directory called `frames,--clip=interp_ab` and record the whole trailer
	# into it, which looks exactly like a slow run for the first ten minutes.
	if _out.contains("--"):
		printerr("TrailerCapture: '%s' is not a directory, it is a directory and an option" % _out)
		printerr("  folded together. Pass them as separate array elements:")
		printerr("  -ToolArgs @('D:\\path\\to\\frames', '--clip=kill_slowmo')")
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
	if _wanted("hook_drag"):
		await _clip_hook_drag()
	if _wanted("hands_ab"):
		await _clip_hands_ab(fight)
	if _wanted("focus_fire"):
		await _clip_focus_fire(fight)
	if _wanted("roster"):
		await _clip_roster(fight)
	if _wanted("interp_ab"):
		await _clip_interp_ab()
	if _wanted("ranged_loose"):
		await _clip_ranged_loose()
	if _wanted("toggles"):
		await _clip_toggles(fight)
	if _wanted("art_ab"):
		await _clip_art_ab(fight)


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
			# Loud, not silent: a renamed room used to shrink the grid with
			# nothing said, and the capture simply got less interesting.
			_failures.append("no encounter '%s' -- the ROOMS list is stale" % room_id)
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
## the biggest shooter -- narrowed to `CASTERS`, because the brief is an archer
## or a caster and the abomination outweighs both. `display_name` IS the class
## id here: `_party` names every pawn after the class it is.
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
			if source == null or not CASTERS.has(source.display_name):
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


## Every action a player pawn commits, with the tick it started on and the tick
## it fires on, so a clip can hold the whole wind-up. `action_ticks_total` is
## sampled BEFORE the step that spends it, which is the rule this project keeps
## getting wrong: a unit whose action ends inside a step reads as idle after it.
func _player_actions(room_id: StringName, s: int) -> Array:
	var state := CombatSim.build(_party(), Registry.get_encounter(room_id), s)
	var started := {}
	var out: Array = []
	var cursor := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		for u in state.units:
			if u.team != CG.Team.PLAYER or u.action_ticks_left <= 0:
				continue
			# Derived rather than caught on the tick it began. An action is
			# committed and spent inside one `step()`, so it is never seen with
			# `action_ticks_left == action_ticks_total` from out here.
			started[u.id] = {"tick": state.tick - (u.action_ticks_total - u.action_ticks_left),
				"total": u.action_ticks_total}
		CombatSim.step(state)
		for e in state.events_since(cursor):
			if e.kind != CG.EventKind.ACTION_FIRE or not started.has(e.source_id):
				continue
			var source := state.unit(e.source_id)
			if source == null or source.team != CG.Team.PLAYER:
				continue
			var s0: Dictionary = started[e.source_id]
			out.append({"id": e.source_id, "name": source.display_name, "action": e.action_id,
				"start": s0["tick"], "fire": state.tick, "total": s0["total"]})
			started.erase(e.source_id)
		cursor = state.events.size()
	return out


## The first hook cast anywhere in the pinned grid, with the drag it starts.
## Its own scan rather than the chosen fight's, because the establishing fight is
## won on deaths and shots and need not contain one at all.
func _hook_cast() -> Dictionary:
	for room_id in ROOMS:
		var encounter = Registry.get_encounter(room_id)
		if encounter == null:
			continue
		for s in range(1, SEEDS + 1):
			var state := CombatSim.build(_party(), encounter, s)
			var cursor := 0
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for e in state.events_since(cursor):
					if e.kind != CG.EventKind.ACTION_FIRE or e.action_id != &"abomination_hook":
						continue
					if state.tick * FRAMES_PER_TICK <= HOOK_LEAD:
						continue
					var victim := state.unit(e.target_id)
					return {"room": room_id, "seed": s, "tick": state.tick,
						"target": e.target_id,
						"name": "nobody" if victim == null else victim.display_name}
				cursor = state.events.size()
	return {}


## The enemy with the most health left at `tick`, which is the one worth
## pointing four pawns at and the one whose convergence is longest on screen.
func _fattest_enemy(room_id: StringName, s: int, tick: int) -> Dictionary:
	var state := CombatSim.build(_party(), Registry.get_encounter(room_id), s)
	while state.tick < tick and state.outcome == CombatState.Outcome.UNRESOLVED:
		CombatSim.step(state)
	var best := {}
	var best_hp := 0.0
	for u in state.units:
		if not u.alive or u.team != CG.Team.ENEMY or u.hp <= best_hp:
			continue
		best_hp = u.hp
		best = {"id": u.id, "name": u.display_name, "hp": u.hp}
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
	_cue_cursor = 0
	_cue_tick = -1
	_cue_played.clear()


## One rendered frame of the view's clock, at exactly the delta the engine is
## fixed to. `raw` re-renders at alpha 1, which is the pre-#501 picture: the
## body sits on the tick position for all four frames and then jumps.
func _frame(raw: bool = false) -> void:
	_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))
	if raw:
		_view._render(1.0, false, 0.0)
	_scan_cues()


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
	_movie_frame = int(Engine.get_process_frames())
	if _movie_first < 0:
		_movie_first = _movie_frame
	img.save_png("%s/frame%s_%05d.png" % [_out, _label, _n])


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


## Opens a clip. Everything `_say` reports about where the clip sits is measured
## from here, including the movie writer's own frame numbering.
func _begin() -> int:
	_movie_first = -1
	return _n + 1


func _say(clip: String, from: int, values: Dictionary, detail: String) -> void:
	if _n < from:
		_failures.append("%s wrote no frames" % clip)
		return
	var line := "CLIP %-16s frames %05d-%05d (%d)  movie %d-%d  %s  toggles: %s" % [
		clip, from, _n, _n - from + 1, _movie_first, _movie_frame, detail,
		_toggle_text(values)]
	_manifest.append(line)
	print(line)


# --- the sound cue sheet -----------------------------------------------------

## Every event the view has just handed the sound bank, reduced to the ones that
## make a noise. `SoundBank` collapses repeats of one name inside a tick into a
## single voice, so a cue sheet that does not do the same lists five noises for
## a scrum that made one.
func _scan_cues() -> void:
	if _view == null or _view.state == null:
		return
	for e in _view.state.events_since(_cue_cursor):
		if e.tick != _cue_tick:
			_cue_tick = e.tick
			_cue_played.clear()
		var name := SoundBank.sound_name(e)
		if _cue_played.has(name):
			continue
		if SoundBank.stream_for_event(e) == null:
			continue
		_cue_played[name] = true
		# The frame this becomes audible on: the sound starts inside the
		# `_process` this scan follows, so it is heard from the next one.
		var at := _movie_frame + 1
		_cues.append("%d,%.4f,%d,%s,%s" % [
			at, float(at) / 60.0, e.tick, name, _view.state.tick])
	_cue_cursor = _view.state.events.size()


func _write_cues() -> void:
	var f := FileAccess.open("%s/audio_cues%s.csv" % [_out, _label], FileAccess.WRITE)
	if f == null:
		_failures.append("cannot write the cue sheet into %s" % _out)
		return
	f.store_line("movie_frame,seconds_at_60fps,event_tick,sound_name,view_tick")
	for row in _cues:
		f.store_line(row)
	f.close()
	print("CUES %d sound(s), %s/audio_cues%s.csv" % [_cues.size(), _out, _label])


# --- the clips ---------------------------------------------------------------

## The establishing shot and the closer: one whole fight the party wins, at
## normal speed, held on the victory banner at the end.
func _clip_fight_full(fight: Dictionary) -> void:
	_set_toggles(SHOWY)
	await _build_view(fight["room"], fight["seed"])
	var from := _begin()
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
## after it, so the hit stop, the white flash, the squash, the debris and the
## death plate all have room to read.
func _clip_kill_slowmo(fight: Dictionary) -> void:
	var death := _best_death(fight["room"], fight["seed"])
	if death.is_empty():
		_failures.append("kill_slowmo: no death late enough in %s seed %d"
			% [fight["room"], fight["seed"]])
		return
	_set_toggles(SHOWY)
	await _build_view(fight["room"], fight["seed"])
	await _skip_to(int(death["tick"]) - KILL_LEAD / FRAMES_PER_TICK)
	var from := _begin()
	for i in KILL_LEAD + KILL_TAIL:
		await _capture()
		_frame()
	_say("kill_slowmo", from, SHOWY,
		"%s seed %d, %s (%.0f px half-width) dies on tick %d, %d frames of lead, every mark on: hit stop, white flash, squash, debris, death plate" % [
			fight["room"], fight["seed"], death["name"], death["size"],
			death["tick"], KILL_LEAD])
	await _teardown()


## Issue 562. The hook lands, drags its target over `CombatSim.PULL_TICKS` and
## stuns it for exactly that span. The clip has to outlast the drag: before #562
## the target simply appeared beside the caster in one tick and there was
## nothing here to photograph.
func _clip_hook_drag() -> void:
	var hook := _hook_cast()
	if hook.is_empty():
		_failures.append("hook_drag: no abomination_hook in %d rooms x %d seeds"
			% [ROOMS.size(), SEEDS])
		return
	_set_toggles(SHOWY)
	await _build_view(hook["room"], hook["seed"])
	await _skip_to(int(hook["tick"]) - HOOK_LEAD / FRAMES_PER_TICK)
	var from := _begin()
	for i in HOOK_LEAD + CombatSim.PULL_TICKS * FRAMES_PER_TICK + HOOK_TAIL:
		await _capture()
		_frame()
	_say("hook_drag", from, SHOWY,
		"%s seed %d, hook lands on %s at tick %d, dragged and stunned for %d ticks (%d frames)" % [
			hook["room"], hook["seed"], hook["name"], hook["tick"],
			CombatSim.PULL_TICKS, CombatSim.PULL_TICKS * FRAMES_PER_TICK])
	await _teardown()


## Issue 583. The same wind-up at the shortest and the longest action a player
## pawn takes in this fight, because the animation's duration IS the action's
## tick count: the point of the pair is that one snaps and the other creeps.
func _clip_hands_ab(fight: Dictionary) -> void:
	var actions := _player_actions(fight["room"], fight["seed"])
	if actions.is_empty():
		_failures.append("hands_ab: no player action in %s seed %d"
			% [fight["room"], fight["seed"]])
		return
	# Both arms have to be the SAME motion, or the pair reads as two different
	# animations rather than as one animation at two speeds. Whichever of the
	# three motions holds the widest spread of tick counts wins.
	var by_kind := {}
	for a in actions:
		if a["start"] * FRAMES_PER_TICK <= HAND_LEAD:
			continue
		var kind := PartAnimation.kind_for(Registry.get_action(a["action"]))
		if not by_kind.has(kind):
			by_kind[kind] = {"fast": a, "slow": a}
		if a["total"] < by_kind[kind]["fast"]["total"]:
			by_kind[kind]["fast"] = a
		if a["total"] > by_kind[kind]["slow"]["total"]:
			by_kind[kind]["slow"] = a
	var fast := {}
	var slow := {}
	var spread := 0
	for kind in by_kind:
		var pair: Dictionary = by_kind[kind]
		var d: int = int(pair["slow"]["total"]) - int(pair["fast"]["total"])
		if d <= spread:
			continue
		spread = d
		fast = pair["fast"]
		slow = pair["slow"]
	if fast.is_empty():
		_failures.append("hands_ab: no motion has a fast and a slow player action in %s seed %d"
			% [fight["room"], fight["seed"]])
		return
	for arm in [{"name": "fast", "a": fast}, {"name": "slow", "a": slow}]:
		var a: Dictionary = arm["a"]
		_set_toggles(SHOWY)
		await _build_view(fight["room"], fight["seed"])
		await _skip_to(int(a["start"]) - HAND_LEAD / FRAMES_PER_TICK)
		var from := _begin()
		for i in HAND_LEAD + int(a["total"]) * FRAMES_PER_TICK + HAND_TAIL:
			await _capture()
			_frame()
		var kind := PartAnimation.kind_for(Registry.get_action(a["action"]))
		_say("hands_ab.%s" % arm["name"], from, SHOWY,
			"%s seed %d, %s winds up %s (%s motion) over %d ticks (%d frames) from tick %d, fires on tick %d" % [
				fight["room"], fight["seed"], a["name"], a["action"],
				PartAnimation.Kind.keys()[kind], a["total"],
				int(a["total"]) * FRAMES_PER_TICK, a["start"], a["fire"]])
		await _teardown()


## Issue 588. Through the controls a player uses: click the enemy, which pauses
## the fight and opens its card, press the card's focus control, close the card,
## and watch the party break off and cross to it.
func _clip_focus_fire(fight: Dictionary) -> void:
	var at_tick: int = maxi(1, int(fight["ticks"]) / 4)
	var enemy := _fattest_enemy(fight["room"], fight["seed"], at_tick)
	if enemy.is_empty():
		_failures.append("focus_fire: no enemy alive at tick %d of %s seed %d"
			% [at_tick, fight["room"], fight["seed"]])
		return
	_set_toggles(SHOWY)
	await _build_view(fight["room"], fight["seed"])
	await _skip_to(at_tick)
	var target: CombatUnit = _view.state.unit(enemy["id"])
	if target == null or not target.alive:
		_failures.append("focus_fire: unit %d is not alive in the view at tick %d"
			% [enemy["id"], at_tick])
		await _teardown()
		return
	var from := _begin()
	# The click itself, at the enemy's drawn position. `select_unit_at` pauses
	# and opens the card, exactly as the mouse handler does.
	_view.select_unit_at(BattleView.drawn_position(_view.state, target))
	for i in FOCUS_CARD_FRAMES:
		await _capture()
		_frame()
	_view._on_card_focus_toggled(enemy["id"])
	var picked: int = _view.state.player_focus_id
	_view._unit_card.close()
	for i in FOCUS_RUN_FRAMES:
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		await _capture()
		_frame()
	_say("focus_fire", from, SHOWY,
		"%s seed %d, clicked %s (unit %d) at tick %d, card held %d frames, party_focus_id %d, %d frames of convergence" % [
			fight["room"], fight["seed"], enemy["name"], enemy["id"], at_tick,
			FOCUS_CARD_FRAMES, picked, FOCUS_RUN_FRAMES])
	await _teardown()


## Issue 552. The post-fight roster, sorted by damage dealt and then by damage
## taken, through the two buttons rather than through `set_sort`.
func _clip_roster(fight: Dictionary) -> void:
	_set_toggles(SHOWY)
	await _build_view(fight["room"], fight["seed"])
	await _skip_to(MAX_FIGHT_TICKS + 1)
	# The banner waits out the freeze on the last death, so the end screen is
	# not up the instant the outcome resolves.
	for i in BANNER_FRAMES:
		_frame()
		await get_tree().process_frame
	var screen = _view._end_screen
	if screen == null or not screen.visible:
		_failures.append("roster: the end screen never opened in %s seed %d"
			% [fight["room"], fight["seed"]])
		await _teardown()
		return
	for arm in [{"name": "dealt", "button": EndScreen.SORT_DEALT_NAME},
			{"name": "taken", "button": EndScreen.SORT_TAKEN_NAME}]:
		var button: Node = screen.find_child(arm["button"], true, false)
		if button == null:
			_failures.append("roster: no button named %s" % arm["button"])
			continue
		button.pressed.emit()
		var from := _begin()
		for i in ROSTER_FRAMES:
			await _capture()
			_frame()
		var names := PackedStringArray()
		for row in screen.shown_rows():
			names.append("%s %d" % [row.get("name", "?"), int(row.get(arm["name"], 0))])
		_say("roster.%s" % arm["name"], from, SHOWY,
			"%s seed %d, sorted by damage %s: %s" % [
				fight["room"], fight["seed"], arm["name"], ", ".join(names)])
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
		var from := _begin()
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
	var from := _begin()
	for i in LOOSE_FRAMES:
		await _capture()
		_frame()
	_say("ranged_loose", from, SHOWY,
		"%s seed %d, %s looses %s on tick %d, shooter at screen %.0f,%.0f" % [
			room, s, loose["name"], loose["action"], int(loose["tick"]) + 1, at.x, at.y])
	await _teardown()


## The same seconds four times: hit stop and squash off then on, then the white
## flash off then on. One seed, one window, one row of `DisplayOptions` moving.
func _clip_toggles(fight: Dictionary) -> void:
	var death := _best_death(fight["room"], fight["seed"])
	if death.is_empty():
		_failures.append("toggles: no death to centre the window on")
		return
	var start: int = maxi(0, int(death["tick"]) - TOGGLE_FRAMES / (2 * FRAMES_PER_TICK))
	var arms := [
		{"name": "feel", "rows": [&"impact_squash", &"hit_stop"]},
		{"name": "flash", "rows": [&"hit_flash"]},
	]
	for arm in arms:
		for on in [false, true]:
			var values := SHOWY.duplicate()
			for row in arm["rows"]:
				values[row] = on
			_set_toggles(values)
			await _build_view(fight["room"], fight["seed"])
			await _skip_to(start)
			var from := _begin()
			for i in TOGGLE_FRAMES:
				await _capture()
				_frame()
			_say("toggles.%s.%s" % [arm["name"], "on" if on else "off"], from, values,
				"%s seed %d, from tick %d, %s dies on tick %d" % [
					fight["room"], fight["seed"], start, death["name"], death["tick"]])
			await _teardown()


## Issue 566. One window of the fight, shot twice from two working trees: once
## with the unit art that is in `Assets/Units` now, and once with the art that
## was there before the recipes landed. This tool cannot swap the assets itself
## -- Godot imports them at startup -- so the pass is driven from outside:
##
##   git rm -r --cached -q Assets/Units && rm -rf Assets/Units
##   git checkout <pre-566-ref> -- Assets/Units
##   run.ps1 TrailerCapture ... -ToolArgs <dir>,--clip=art_ab,--label=_old
##   git checkout HEAD -- Assets/Units
##   run.ps1 TrailerCapture ... -ToolArgs <dir>,--clip=art_ab,--label=_new
##
## Same room, same seed, same tick, same frame count, so the two sequences line
## up frame for frame and can be cut as a wipe.
func _clip_art_ab(fight: Dictionary) -> void:
	var at_tick: int = maxi(1, int(fight["ticks"]) / 3)
	_set_toggles(SHOWY)
	await _build_view(fight["room"], fight["seed"])
	await _skip_to(at_tick)
	var from := _begin()
	for i in ART_FRAMES:
		await _capture()
		_frame()
	_say("art_ab%s" % ("" if _label == "" else _label), from, SHOWY,
		"%s seed %d, %d frames from tick %d, label '%s'" % [
			fight["room"], fight["seed"], ART_FRAMES, at_tick, _label])
	await _teardown()
