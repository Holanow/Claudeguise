extends Node

## Records real gameplay as a numbered PNG frame sequence, one file per rendered
## frame, so a trailer can be cut from it.
##
## Launch it with `-FixedFps 60`: the particle system ages on the engine's own
## delta and nothing in a tool can reach it. Add `-WriteMovie <path.avi>` for
## sound -- Godot's movie writer mixes the audio bus per rendered frame rather
## than in real time, which is the only way a loop running at a tenth of real
## time can carry any. The movie covers EVERY engine frame, setup included, so
## each manifest line carries the movie frame range beside the PNG range.

const FRAMES_PER_TICK := 4
const SIZE := Vector2i(1280, 720)
## Pinned by id, never by registry order, so the party is the same in every
## process (board FINDING 4).
const PARTY: Array = [&"warrior", &"priest", &"geysermancer", &"abomination"]
const ROOMS: Array = [&"floor1_room1", &"floor1_cover", &"floor1_hazard", &"floor1_horde"]
## Issue 705: none of the four rooms above ever gives `abomination_hook` a
## reachable target at the pull's own range -- measured, not assumed, over
## 60 seeds each. `floor1_rat_king`'s open arena does. Hook's own search
## widens to this list rather than widening `ROOMS`, which anchors every
## other clip's establishing fight.
const HOOK_ROOMS: Array = [&"floor1_room1", &"floor1_cover", &"floor1_hazard", &"floor1_horde",
	&"floor1_chokepoint", &"floor1_sellsword", &"floor1_rat_king"]
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
	"roster", "interp_ab", "ranged_loose", "toggles", "art_ab",
	"party_deploy", "action_states", "seeker_two", "sellsword_pattern",
	"geyser_blast", "immolate", "summon", "plan_edit", "plan_diff", "warden"]

## Issue 705. The trailer's beat sheet as data, not a comment: act order, the
## title card between acts, and which clips of this tool make up each one.
## `Tools/RenderTrailer.ps1` reads the same file to know where to cut title
## cards in, so this is the one place the sequence is authored.
const BEATS_PATH := "res://Tools/TrailerBeats.json"

## Issue 30's siege engine (`build_siege_engine`) and its mark (`spotter_mark`)
## are the Siege Master's, and `PARTY` above leaves that class out. A second
## party, real and playable, only for the shots that need it.
const SIEGE_PARTY: Array = [&"warrior", &"priest", &"siege_master", &"abomination"]

## Issue 433/406: a Warrior, Priest, Geysermancer and Siege Master never taunt,
## ward, blast or mark on their own -- `DefaultBehavior` never self-buffs a
## pawn and never risks a spender it wasn't told to spend. `PawnFactory.
## make_preset_pawn` is every preset row a class ships added, which is the
## state a player reaches by pressing every Add button in the plan editor.

## The seed `party_deploy` rerolls the roster to, so the shot is reproducible.
const PARTY_DEPLOY_SEED := 0xC1A0D
const PARTY_DEPLOY_FIGHT_FRAMES := 360
const WARDEN_FRAMES := 360

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
	var beats := _load_beats()
	if beats.is_empty():
		_failures.append("TrailerBeats.json has no acts -- nothing to shoot")
		return
	for act in beats:
		for clip in act.get("clips", []):
			if _wanted(clip):
				await _run_clip(clip, fight)


## The beat sheet, as data: `Tools/TrailerBeats.json` names the acts, their
## title cards and which clips belong to each one, and `RenderTrailer.ps1`
## reads the same file to cut title cards into the same places.
func _load_beats() -> Array:
	var f := FileAccess.open(BEATS_PATH, FileAccess.READ)
	if f == null:
		_failures.append("cannot open %s" % BEATS_PATH)
		return []
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_ARRAY:
		_failures.append("%s is not a JSON array" % BEATS_PATH)
		return []
	return data


func _run_clip(clip: String, fight: Dictionary) -> void:
	match clip:
		"fight_full": await _clip_fight_full(fight)
		"kill_slowmo": await _clip_kill_slowmo(fight)
		"hook_drag": await _clip_hook_drag()
		"hands_ab": await _clip_hands_ab(fight)
		"focus_fire": await _clip_focus_fire(fight)
		"roster": await _clip_roster(fight)
		"interp_ab": await _clip_interp_ab()
		"ranged_loose": await _clip_ranged_loose()
		"toggles": await _clip_toggles(fight)
		"art_ab": await _clip_art_ab(fight)
		"party_deploy": await _clip_party_deploy()
		"action_states": await _clip_action_states()
		"seeker_two": await _clip_seeker_two()
		"sellsword_pattern": await _clip_sellsword_pattern()
		"geyser_blast": await _clip_first_cast("geyser_blast", &"geyser_blast", PARTY, ROOMS, KILL_LEAD, KILL_TAIL)
		"immolate": await _clip_first_cast("immolate", &"abomination_immolate", PARTY, ROOMS, KILL_LEAD, KILL_TAIL)
		"summon": await _clip_summon()
		"plan_edit": await _clip_plan_edit()
		"plan_diff": await _clip_plan_diff()
		"warden": await _clip_warden()
		_: _failures.append("no clip function for '%s'" % clip)


func _wanted(clip: String) -> bool:
	return _only == "" or _only == clip


# --- the simulation-only scans -----------------------------------------------

func _party() -> Array[PawnData]:
	return _party_for(PARTY)


func _party_for(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("p%d" % i), String(ids[i])))
	return out


## Every preset row the class ships, added -- the state a player reaches by
## pressing every "Add" button `plan_edit` shows one of.
func _party_preset_for(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_preset_pawn(
			ids[i], StringName("p%d" % i), String(ids[i])))
	return out


## The busiest fight the party wins, over a pinned grid of rooms and seeds. The
## deaths are what `kill_slowmo` and `toggles` are cut from, so a fight with few
## of them is the wrong establishing shot as well as a dull one.
func _pick_fight() -> Dictionary:
	var best := {}
	var best_score := -1.0
	for room_id in ROOMS:
		var encounter = RoomLibrary.get_room(room_id)
		if encounter == null:
			# Loud, not silent: a renamed room used to shrink the grid with
			# nothing said, and the capture simply got less interesting.
			_failures.append("no encounter '%s' -- the ROOMS list is stale" % room_id)
			continue
		for s in range(1, SEEDS + 1):
			var run := _play_party(_party(), encounter, s)
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


func _play_party(party: Array[PawnData], encounter, s: int) -> Dictionary:
	var state := CombatSim.build(party, encounter, s)
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
	var state := CombatSim.build(_party(), RoomLibrary.get_room(room_id), s)
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
	var state := CombatSim.build(_party(), RoomLibrary.get_room(room_id), s)
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
	var state := CombatSim.build(_party(), RoomLibrary.get_room(room_id), s)
	var best := {}
	var best_size := 0.0
	var cursor := 0
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		for e in state.events_since(cursor):
			if e.kind != CG.EventKind.ACTION_FIRE or state.tick * FRAMES_PER_TICK <= LOOSE_LEAD:
				continue
			var action := ActionLibrary.get_action(e.action_id)
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
	var state := CombatSim.build(_party(), RoomLibrary.get_room(room_id), s)
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
	for room_id in HOOK_ROOMS:
		var encounter = RoomLibrary.get_room(room_id)
		if encounter == null:
			continue
		for s in range(1, SEEDS + 1):
			# Issue 705: a starter Abomination never casts Hook -- `DefaultBehavior`
			# picks the cheapest attack, and `abomination_hook` is preset-gated
			# (see `PresetPlans.for_class`). Bare `_party()` found nothing in
			# 4 rooms x 24 seeds; the preset party is what a player who added
			# every row reaches, same as every other act-3/4 scan in this file.
			var state := CombatSim.build(_party_preset_for(PARTY), encounter, s)
			var cursor := 0
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for e in state.events_since(cursor):
					if e.kind != CG.EventKind.ACTION_FIRE or e.action_id != &"abomination_hook":
						continue
					if state.tick * FRAMES_PER_TICK <= HOOK_LEAD:
						continue
					var victim := state.unit(e.target_id)
					# The target has to SURVIVE the hook or there is no drag to
					# photograph. The first cast this scan found killed a Goblin
					# outright and the clip showed a death plate for 132 frames.
					if victim == null or not victim.alive or victim.pull_ticks_left <= 0:
						continue
					return {"room": room_id, "seed": s, "tick": state.tick,
						"target": e.target_id, "name": victim.display_name,
						"hp": victim.hp}
				cursor = state.events.size()
	return {}


## The first `ACTION_FIRE` of `action_id`, over `rooms` x `SEEDS`, built from
## `party_ids` through `_party_preset_for`. Generalises `_hook_cast` for every
## shot that only needs "this fires at all" rather than the hook's
## survive-the-drag check.
func _first_cast(action_id: StringName, party_ids: Array, rooms: Array, lead: int) -> Dictionary:
	for room_id in rooms:
		var encounter = RoomLibrary.get_room(room_id)
		if encounter == null:
			continue
		for s in range(1, SEEDS + 1):
			var state := CombatSim.build(_party_preset_for(party_ids), encounter, s)
			var cursor := 0
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for e in state.events_since(cursor):
					if e.kind != CG.EventKind.ACTION_FIRE or e.action_id != action_id:
						continue
					if state.tick * FRAMES_PER_TICK <= lead:
						continue
					var source := state.unit(e.source_id)
					var target := state.unit(e.target_id)
					return {"room": room_id, "seed": s, "tick": state.tick,
						"source_name": (source.display_name if source != null else "?"),
						"target_name": (target.display_name if target != null else "?")}
				cursor = state.events.size()
	return {}


## The first `EventKind.SUMMONED` a Siege Master's `build_siege_engine` reaches,
## over `rooms` x `SEEDS`. The cast and the unit appearing are different ticks
## (issue 30: the engine builds over time), so this scans the reveal, not the
## cast.
func _first_summon(rooms: Array, lead: int) -> Dictionary:
	for room_id in rooms:
		var encounter = RoomLibrary.get_room(room_id)
		if encounter == null:
			continue
		for s in range(1, SEEDS + 1):
			var state := CombatSim.build(_party_preset_for(SIEGE_PARTY), encounter, s)
			var cursor := 0
			while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
				CombatSim.step(state)
				for e in state.events_since(cursor):
					if e.kind == CG.EventKind.SUMMONED and state.tick * FRAMES_PER_TICK > lead:
						return {"room": room_id, "seed": s, "tick": state.tick}
				cursor = state.events.size()
	return {}


## Issue 705, act 2's mechanic shot: `sellsword_seeker_bolts` hitting two
## different party members in the same fight, close enough together to hold
## in one clip. Only `floor1_sellsword` has the enemy that casts it.
func _seeker_two_scan() -> Dictionary:
	var room_id: StringName = &"floor1_sellsword"
	var encounter = RoomLibrary.get_room(room_id)
	if encounter == null:
		return {}
	for s in range(1, SEEDS + 1):
		var state := CombatSim.build(_party_preset_for(PARTY), encounter, s)
		var cursor := 0
		var first := {}
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			CombatSim.step(state)
			for e in state.events_since(cursor):
				if e.kind != CG.EventKind.ACTION_FIRE or e.action_id != &"sellsword_seeker_bolts":
					continue
				if first.is_empty():
					first = {"tick": state.tick, "target": e.target_id}
					continue
				if e.target_id != first["target"] and state.tick - int(first["tick"]) < 200:
					return {"room": room_id, "seed": s, "tick1": first["tick"], "tick2": state.tick}
			cursor = state.events.size()
	return {}


## Issue 705, act 3: the Sellsword's own pattern, bolts then a close weapon --
## every distinct action of its three that this fight reaches, spanning from
## the first to the last.
func _sellsword_pattern_scan() -> Dictionary:
	var room_id: StringName = &"floor1_sellsword"
	var encounter = RoomLibrary.get_room(room_id)
	if encounter == null:
		return {}
	const WANTED: Array = [&"sellsword_seeker_bolts", &"sellsword_strike", &"sellsword_crescent"]
	for s in range(1, SEEDS + 1):
		var state := CombatSim.build(_party_preset_for(PARTY), encounter, s)
		var cursor := 0
		var seen := {}
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS \
				and seen.size() < WANTED.size():
			CombatSim.step(state)
			for e in state.events_since(cursor):
				if e.kind == CG.EventKind.ACTION_FIRE and WANTED.has(e.action_id) and not seen.has(e.action_id):
					seen[e.action_id] = state.tick
			cursor = state.events.size()
		if seen.size() == WANTED.size():
			var ticks: Array = seen.values()
			return {"room": room_id, "seed": s, "start": ticks.min(), "end": ticks.max(), "seen": seen}
	return {}


## Same seed, two plans, checked for a differing outcome (issue 705 act 4). The
## no-plan party is `DefaultBehavior` alone; the preset party is every row its
## classes ship added -- exactly what the plan editor's own "Add" buttons do.
func _pick_plan_diff() -> Dictionary:
	for room_id in ROOMS:
		var encounter = RoomLibrary.get_room(room_id)
		if encounter == null:
			continue
		for s in range(1, SEEDS + 1):
			var a := _play_party(_party_for(PARTY), encounter, s)
			var b := _play_party(_party_preset_for(PARTY), encounter, s)
			if a["outcome"] != b["outcome"]:
				return {"room": room_id, "seed": s, "default": a, "authored": b}
	return {}


## The enemy with the most health left at `tick`, which is the one worth
## pointing four pawns at and the one whose convergence is longest on screen.
func _fattest_enemy(room_id: StringName, s: int, tick: int) -> Dictionary:
	var state := CombatSim.build(_party(), RoomLibrary.get_room(room_id), s)
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
func _build_view(room_id: StringName, s: int, party: Array[PawnData] = []) -> void:
	seed(s)
	var cfg := RunConfig.new()
	cfg.party = party if not party.is_empty() else _party()
	cfg.encounter_id = room_id
	cfg.seed = s
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, RoomLibrary.get_room(room_id))
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


## One rendered frame of a UI-only screen: no combat clock to advance, so this
## is `_frame()` without the `_view._process` call. Party select and the plan
## editor both hold here between real clicks.
func _capture_ui_frame() -> void:
	await _capture()
	await get_tree().process_frame


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
			% [HOOK_ROOMS.size(), SEEDS])
		return
	_set_toggles(SHOWY)
	await _build_view(hook["room"], hook["seed"], _party_preset_for(PARTY))
	await _skip_to(int(hook["tick"]) - HOOK_LEAD / FRAMES_PER_TICK)
	var from := _begin()
	for i in HOOK_LEAD + CombatSim.PULL_TICKS * FRAMES_PER_TICK + HOOK_TAIL:
		await _capture()
		_frame()
	_say("hook_drag", from, SHOWY,
		"%s seed %d, hook lands on %s at tick %d (survives on %d hp), dragged and stunned for %d ticks (%d frames)" % [
			hook["room"], hook["seed"], hook["name"], hook["tick"], hook["hp"],
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
		var kind := PartAnimation.kind_for(ActionLibrary.get_action(a["action"]))
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
		var kind := PartAnimation.kind_for(ActionLibrary.get_action(a["action"]))
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


## Issue 566. One window of the fight, shot twice, once per working tree: the
## unit art that is in `Assets/Units` now against the art that was there before
## the recipes landed. Godot imports assets at startup, so the swap is driven
## from outside this tool and the commit message carries the four commands.
## Same room, seed, tick and frame count both times, so the two sequences line
## up frame for frame.
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


# --- issue 705: the trailer's own acts -----------------------------------

## Act 1. Party select, deploy, the fight beginning -- one unbroken run, no
## cut inside it, through the actual screens a player uses: cards toggled,
## a room picked, Start pressed, then the fight the click just started.
func _clip_party_deploy() -> void:
	_set_toggles(SHOWY)
	var ps := PartySelect.create()
	add_child(ps)
	await get_tree().process_frame
	ps.reroll_from_seed("%08X" % PARTY_DEPLOY_SEED)
	var from := _begin()
	for i in 30:
		await _capture_ui_frame()
	for class_id in PARTY:
		var pawn: PawnData = null
		for p in ps.available_pawns():
			if p.pawn_class != null and p.pawn_class.id == class_id:
				pawn = p
				break
		if pawn == null:
			continue
		ps.toggle_pawn(pawn, true)
		for i in 20:
			await _capture_ui_frame()
	ps.select_room(ROOMS[0])
	for i in 20:
		await _capture_ui_frame()
	## A single-element box, not a plain local: a GDScript lambda captures an
	## outer local by value, so `config = cfg` inside it would reassign only
	## the closure's own copy and the caller would see `config` stay null.
	var box := {"config": null}
	ps.battle_requested.connect(func(cfg): box["config"] = cfg)
	ps._start_button.pressed.emit()
	for i in 10:
		await _capture_ui_frame()
	ps.queue_free()
	await get_tree().process_frame
	var config: RunConfig = box["config"]
	if config == null:
		_failures.append("party_deploy: Start never emitted battle_requested")
		return
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(config, RoomLibrary.get_room(config.encounter_id))
	_view.set_process(false)
	_cue_cursor = 0
	_cue_tick = -1
	_cue_played.clear()
	for i in PARTY_DEPLOY_FIGHT_FRAMES:
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		await _capture()
		_frame()
	_say("party_deploy", from, SHOWY,
		"party select seed %s -> %s -> %d frames of the fight beginning" % [
			"%08X" % PARTY_DEPLOY_SEED, config.encounter_id, PARTY_DEPLOY_FIGHT_FRAMES])
	await _teardown()


## Act 2. Guard, Taunt and Ward -- three Warrior/Priest states the plan editor
## authors -- then Mark, the Siege Master's, held one after another. Every
## row fired here needs the full preset library (see `_first_cast`).
func _clip_action_states() -> void:
	var arms := [
		{"action": &"warrior_taunt", "party": PARTY},
		{"action": &"warrior_guard", "party": PARTY},
		{"action": &"priest_ward", "party": PARTY},
		{"action": &"spotter_mark", "party": SIEGE_PARTY},
	]
	for arm in arms:
		var cast := _first_cast(arm["action"], arm["party"], ROOMS, KILL_LEAD)
		if cast.is_empty():
			_failures.append("action_states.%s: never fired in %d rooms x %d seeds" % [
				arm["action"], ROOMS.size(), SEEDS])
			continue
		_set_toggles(SHOWY)
		await _build_view(cast["room"], cast["seed"], _party_preset_for(arm["party"]))
		await _skip_to(int(cast["tick"]) - KILL_LEAD / FRAMES_PER_TICK)
		var from := _begin()
		for i in KILL_LEAD + KILL_TAIL:
			await _capture()
			_frame()
		_say("action_states.%s" % arm["action"], from, SHOWY,
			"%s seed %d, %s fires %s on %s at tick %d" % [
				cast["room"], cast["seed"], cast["source_name"], arm["action"],
				cast["target_name"], cast["tick"]])
		await _teardown()


## Act 2's mechanic shot: seeker bolts, with trails, at two different party
## members in one continuous hold.
func _clip_seeker_two() -> void:
	var hit := _seeker_two_scan()
	if hit.is_empty():
		_failures.append("seeker_two: no second target in %d seeds of floor1_sellsword" % SEEDS)
		return
	_set_toggles(SHOWY)
	await _build_view(hit["room"], hit["seed"], _party_preset_for(PARTY))
	await _skip_to(int(hit["tick1"]) - LOOSE_LEAD / FRAMES_PER_TICK)
	var from := _begin()
	for i in LOOSE_LEAD + (int(hit["tick2"]) - int(hit["tick1"])) * FRAMES_PER_TICK + LOOSE_FRAMES:
		await _capture()
		_frame()
	_say("seeker_two", from, SHOWY,
		"%s seed %d, sellsword_seeker_bolts on tick %d then a different target on tick %d" % [
			hit["room"], hit["seed"], hit["tick1"], hit["tick2"]])
	await _teardown()


## Act 3. The Sellsword's full pattern in `floor1_sellsword`: whichever of
## bolts, strike and crescent this fight reaches, from the first to the last.
func _clip_sellsword_pattern() -> void:
	var pat := _sellsword_pattern_scan()
	if pat.is_empty():
		_failures.append("sellsword_pattern: not all three actions fired in %d seeds" % SEEDS)
		return
	_set_toggles(SHOWY)
	await _build_view(pat["room"], pat["seed"], _party_preset_for(PARTY))
	await _skip_to(int(pat["start"]) - KILL_LEAD / FRAMES_PER_TICK)
	var from := _begin()
	for i in KILL_LEAD + (int(pat["end"]) - int(pat["start"])) * FRAMES_PER_TICK + KILL_TAIL:
		await _capture()
		_frame()
	_say("sellsword_pattern", from, SHOWY,
		"%s seed %d, tick %d to %d: %s" % [
			pat["room"], pat["seed"], pat["start"], pat["end"], pat["seen"]])
	await _teardown()


## Act 3. `action_id` cast once, with `lead`/`tail` frames of room either side.
## Shared by `geyser_blast` and `immolate` (dispatched from `_run_clip`).
func _clip_first_cast(clip: String, action_id: StringName, party_ids: Array, rooms: Array,
		lead: int, tail: int) -> void:
	var cast := _first_cast(action_id, party_ids, rooms, lead)
	if cast.is_empty():
		_failures.append("%s: %s never fired in %d rooms x %d seeds" % [
			clip, action_id, rooms.size(), SEEDS])
		return
	_set_toggles(SHOWY)
	await _build_view(cast["room"], cast["seed"], _party_preset_for(party_ids))
	await _skip_to(int(cast["tick"]) - lead / FRAMES_PER_TICK)
	var from := _begin()
	for i in lead + tail:
		await _capture()
		_frame()
	_say(clip, from, SHOWY, "%s seed %d, %s fires %s on %s at tick %d" % [
		cast["room"], cast["seed"], cast["source_name"], action_id,
		cast["target_name"], cast["tick"]])
	await _teardown()


## Act 3. The Siege Master's engine appearing -- held around the reveal tick,
## not the cast, because issue 30 makes the two different ticks.
func _clip_summon() -> void:
	var reveal := _first_summon(ROOMS, KILL_LEAD)
	if reveal.is_empty():
		_failures.append("summon: no SUMMONED event in %d rooms x %d seeds" % [ROOMS.size(), SEEDS])
		return
	_set_toggles(SHOWY)
	await _build_view(reveal["room"], reveal["seed"], _party_preset_for(SIEGE_PARTY))
	await _skip_to(int(reveal["tick"]) - KILL_LEAD / FRAMES_PER_TICK)
	var from := _begin()
	for i in KILL_LEAD + KILL_TAIL:
		await _capture()
		_frame()
	_say("summon", from, SHOWY, "%s seed %d, siege engine summoned at tick %d" % [
		reveal["room"], reveal["seed"], reveal["tick"]])
	await _teardown()


## Act 4's first shot: the plan editor, for real -- open on a fresh Warrior,
## hold, then press the same "Add" button a player presses on the library's
## first preset row.
func _clip_plan_edit() -> void:
	_set_toggles(SHOWY)
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"p0", "Warrior")
	var panel := InspectPanel.create()
	add_child(panel)
	await get_tree().process_frame
	panel.show_pawn(pawn)
	var from := _begin()
	for i in 40:
		await _capture_ui_frame()
	var library: Array[Plan] = PresetPlans.for_class(&"warrior")
	if library.is_empty():
		_failures.append("plan_edit: warrior's preset library is empty")
		panel.queue_free()
		await get_tree().process_frame
		return
	panel._add_preset(pawn, library[0])
	for i in 60:
		await _capture_ui_frame()
	_say("plan_edit", from, SHOWY,
		"warrior, added preset row '%s' via the plan editor's Add button" % library[0].display_name)
	panel.queue_free()
	await get_tree().process_frame


## Act 4's second shot: the same seed, the same room, once with no plan rows
## (`DefaultBehavior` alone) and once with every preset row added, back to
## back. `_pick_plan_diff` only returns a room/seed where the outcome itself
## differs -- if none exists this clip fails loudly rather than faking it.
func _clip_plan_diff() -> void:
	var diff := _pick_plan_diff()
	if diff.is_empty():
		_failures.append("plan_diff: no seed in %d rooms x %d seeds where the outcome differs" % [
			ROOMS.size(), SEEDS])
		return
	var arms := [
		{"name": "default", "party": _party_for(PARTY)},
		{"name": "authored", "party": _party_preset_for(PARTY)},
	]
	for arm in arms:
		_set_toggles(SHOWY)
		await _build_view(diff["room"], diff["seed"], arm["party"])
		var from := _begin()
		# To its own real resolution, not `MAX_FIGHT_TICKS` -- that cap is
		# `_pick_fight`'s "keeps it a watchable establishing shot" choice, and
		# capping it here would show the losing arm mid-fight rather than losing.
		while _view.state.outcome == CombatState.Outcome.UNRESOLVED \
				and _view.state.tick < CG.MAX_TICKS:
			await _capture()
			_frame()
		for i in BANNER_FRAMES:
			await _capture()
			_frame()
		_say("plan_diff.%s" % arm["name"], from, SHOWY,
			"%s seed %d, %s plans: %d ticks, outcome %s" % [
				diff["room"], diff["seed"], arm["name"], _view.state.tick,
				CombatState.Outcome.keys()[_view.state.outcome]])
		await _teardown()


## Act 5. The Warden's chamber, held from the start rather than to a win --
## the room is the point here, not the outcome.
func _clip_warden() -> void:
	var room_id: StringName = &"floor1_warden"
	if RoomLibrary.get_room(room_id) == null:
		_failures.append("warden: no room %s" % room_id)
		return
	_set_toggles(SHOWY)
	await _build_view(room_id, 1, _party_preset_for(PARTY))
	var from := _begin()
	for i in WARDEN_FRAMES:
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		await _capture()
		_frame()
	_say("warden", from, SHOWY, "%s seed 1, %d frames of the Warden's chamber" % [
		room_id, WARDEN_FRAMES])
	await _teardown()
