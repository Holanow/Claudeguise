extends Node

## Issue 583. Three strips, because a still cannot show a bob and one goblin
## cannot show generality: one melee definition on three body types, the same
## definition at 6 wind-up ticks and at 20, and five goblins bobbing out of
## phase. Nothing here steps the simulation and every body stands still, so
## anything that moves in a strip is the hands.

const OUT_DIR := "res://Screenshots"
const FRAMES := 8
const FRAMES_PER_TICK := 4
const CROP := Vector2i(84, 92)
const ZOOM := 5

## Painted down the middle of every panel. Without a fixed mark a strip of
## crops of one body looks the same either way.
const RULER := Color(1.0, 0.2, 0.6)
const RULER_WIDTH := 2

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("HandShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# One melee definition, three body types, sampled evenly across the whole
	# eight-tick wind-up.
	await _strip("sable_583_bodies", [
		{"shape": &"priest", "action": &"warrior_strike", "ticks": 8},
		{"shape": &"warrior", "action": &"warrior_strike", "ticks": 8},
		{"shape": &"abomination", "action": &"warrior_strike", "ticks": 8},
	], 8 * FRAMES_PER_TICK)
	# The same definition at 6 ticks and at 20, on the SAME wall-clock frames:
	# the Stab has struck and gone back to idle while the Axe is still winding.
	await _strip("sable_583_ticks", [
		{"shape": &"goblin", "action": &"goblin_stab", "ticks": 6},
		{"shape": &"the_warden", "action": &"warden_axe", "ticks": 20},
	], 20 * FRAMES_PER_TICK)
	# A whole idle cycle, so the bob has somewhere to go.
	await _strip("sable_583_idle", [
		{"shape": &"goblin", "action": &"", "ticks": 0},
		{"shape": &"goblin", "action": &"", "ticks": 0},
		{"shape": &"goblin", "action": &"", "ticks": 0},
		{"shape": &"goblin", "action": &"", "ticks": 0},
		{"shape": &"goblin", "action": &"", "ticks": 0},
	], int(PartAnimation.IDLE_SECONDS * CG.TICKS_PER_SECOND) * FRAMES_PER_TICK)
	# And a real fight, started the way the game starts one and stepped by the
	# view's own clock, because everything above stands units up by hand.
	await _live(false)
	await _live(true)
	get_tree().quit(0)

## One whole frame of a real fight at a fixed tick, with the toggle either way.
const LIVE_TICK := 180

func _live(hands: bool) -> void:
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"part_animation", hands)
	await _build_view()
	_view.set_process(true)
	while _view.state.tick < LIVE_TICK and _view.state.outcome == CombatState.Outcome.UNRESOLVED:
		_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "%s/sable_583_live_hands_%s.png" % [OUT_DIR, "on" if hands else "off"]
	get_viewport().get_texture().get_image().save_png(path)
	print("HandShot: %s -- tick %d, %d unit(s)" % [path, _view.state.tick, _view.state.units.size()])
	DisplayOptions.reset()
	_view.queue_free()
	_view = null
	await get_tree().process_frame

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for id in ClassLibrary.all_ids():
		out.append(PawnFactory.make_starter_pawn(id, StringName("p%d" % out.size()), String(id)))
		if out.size() == 4:
			break
	return out

func _build_view() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = Registry.all_encounter_ids()[0]
	cfg.seed = 7
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, Registry.get_encounter(Registry.all_encounter_ids()[0]))
	# The tool drives `_render` by hand: the view's own clock would step the
	# simulation and every body would walk out of its crop.
	_view.set_process(false)

## A standing body of a named shape. Not a simulated unit: nothing steps, so
## these are the view's input and nothing else.
func _stand(shape: StringName, id: int, at: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.ENEMY
	u.enemy_id = shape
	u.display_name = String(shape)
	u.hp_max = 100
	u.hp = 100
	u.move_speed = 0.0
	u.facing = Vector2.RIGHT
	u.position = at
	return u

func _strip(stem: String, rows: Array, span: int) -> void:
	await _build_view()
	var state: CombatState = _view.state
	state.units.clear()
	var gap := float(CG.ARENA_HALF_WIDTH) * 1.6 / float(rows.size() + 1)
	for i in rows.size():
		var at := Vector2(-CG.ARENA_HALF_WIDTH * 0.8 + gap * float(i + 1), 0.0)
		var u := _stand(rows[i]["shape"], i, at)
		if rows[i]["action"] != &"":
			u.current_action = rows[i]["action"]
			u.action_ticks_total = rows[i]["ticks"]
			u.action_ticks_left = rows[i]["ticks"]
		state.units.append(u)
	_view._rebuild_units()
	_view._curr_drawn = _view._drawn_snapshot()
	_view._prev_drawn = _view._curr_drawn
	await RenderingServer.frame_post_draw

	var centres: Array[Vector2] = []
	var hand_lines: Array[int] = []
	for i in rows.size():
		var t: Transform2D = _view._unit_views[i].get_global_transform_with_canvas()
		centres.append(t.origin)
		# Where the hands are BAKED, in panel pixels: the part sits 5 of the 32
		# design units below the body's centre. A bob is vertical, so a vertical
		# ruler cannot show it.
		hand_lines.append(int(round(
			t.get_scale().y * UnitView.display_radius(state.units[i]) * (5.0 / 16.0))))

	var panels: Array = []
	for i in rows.size():
		panels.append([])
	# Every frame is rendered; `FRAMES` of them are kept, evenly spaced, so a
	# strip covers the whole motion rather than the first fifth of a second.
	var keep: Array[int] = []
	for i in FRAMES:
		keep.append(int(round(float(i) * float(span - 1) / float(FRAMES - 1))))
	for f in span:
		var alpha := float(f % FRAMES_PER_TICK) / float(FRAMES_PER_TICK)
		_view._render(alpha, false, CG.TICK_SECONDS / float(FRAMES_PER_TICK))
		await RenderingServer.frame_post_draw
		if keep.has(f):
			var full := get_viewport().get_texture().get_image()
			for i in rows.size():
				panels[i].append(_crop(full, centres[i]))
		# One rendered frame is a quarter of a tick, so the wind-up loses a tick
		# every fourth frame -- exactly what a 60Hz display shows at 15Hz.
		if alpha >= 1.0 - 1.0 / float(FRAMES_PER_TICK):
			for u in state.units:
				if u.action_ticks_left > 0:
					u.action_ticks_left -= 1
	_write(stem, rows, panels, hand_lines)
	_view.queue_free()
	_view = null
	await get_tree().process_frame

func _crop(full: Image, centre: Vector2) -> Image:
	var origin := Vector2i(centre) - CROP / 2
	origin = origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
	var panel := full.get_region(Rect2i(origin, CROP))
	panel.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return panel

func _write(stem: String, rows: Array, panels: Array, hand_lines: Array) -> void:
	var w := CROP.x * ZOOM
	var h := CROP.y * ZOOM
	var kept: int = panels[0].size()
	var sheet := Image.create(w * kept, h * rows.size(), false, Image.FORMAT_RGBA8)
	for i in rows.size():
		for f in kept:
			sheet.blit_rect(panels[i][f], Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(f * w, i * h))
			sheet.fill_rect(Rect2i(f * w + w / 2, i * h, RULER_WIDTH, h), RULER)
			var y: int = i * h + h / 2 + hand_lines[i] * ZOOM
			if y >= i * h and y < (i + 1) * h:
				sheet.fill_rect(Rect2i(f * w, y, w, RULER_WIDTH), RULER)
	var path := "%s/%s.png" % [OUT_DIR, stem]
	sheet.save_png(path)
	print("HandShot: %s -- %d bodies x %d frames" % [path, rows.size(), kept])
	for i in rows.size():
		print("  row %d  %-12s %-16s %d wind-up tick(s)" % [
			i, rows[i]["shape"], rows[i]["action"], rows[i]["ticks"]])
