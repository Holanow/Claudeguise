extends Node

## Issue 589. Two strips of the SAME death on the same frames, explosion off and
## on. A still cannot show an explosion, so this is one panel per rendered frame
## with a fixed ruler painted down every panel.
##
## It also answers the freeze question in pixels rather than in prose: the panels
## covering the 0.10 s hit stop are printed with the count of pixels that changed
## since the previous one, so "the freeze holds the explosion's first frame" is
## a measurement and not a claim.

const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES_PER_TICK := 4
const FRAMES := 20
const ROW := 10
## Two frames of run-up, so the hold has a before.
const LEAD_FRAMES := 2
## Wider than #515's 64x48: parts leave the body, and a crop that clips them
## measures the crop rather than the explosion.
const CROP := Vector2i(112, 84)
const ZOOM := 4
const RULER := Color(1.0, 0.2, 0.6)
const RULER_WIDTH := 3
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("GibShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var death := _first_death()
	if death["id"] < 0:
		printerr("GibShot: no death found; nothing to draw")
		get_tree().quit(3)
		return
	DisplayOptions.reset()
	await _staged()
	DisplayOptions.set_enabled(&"death_explosion", false)
	await _strip(death, "sable_589_explosion_off")
	DisplayOptions.set_enabled(&"death_explosion", true)
	await _strip(death, "sable_589_explosion_on")
	DisplayOptions.reset()
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# The staged half: one body per row, on an empty floor, killed by hand. Nothing
# else moves, so every moving pixel in a panel is the explosion.
# ---------------------------------------------------------------------------

## Three bodies that come apart differently: the goblin is the plain three-chunk
## case, the Rat King has a tail of its own and a hat that must leave with its
## head, and the Siege Engine has no hands at all and comes apart into wheels
## and a barrel.
const STAGED := [&"goblin", &"rat_king", &"siege_engine"]
const STAGED_CROP := Vector2i(96, 96)
const STAGED_ZOOM := 5
## Panels across a staged row: one for the frozen rest pose, the rest spread
## evenly over the whole flight.
const STAGED_COLUMNS := 10

func _staged() -> void:
	DisplayOptions.set_enabled(&"death_explosion", true)
	await _build_view(ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0])
	var state: CombatState = _view.state
	state.units.clear()
	var gap := float(CG.ARENA_HALF_WIDTH) * 1.6 / float(STAGED.size() + 1)
	for i in STAGED.size():
		state.units.append(_stand(STAGED[i], i,
			Vector2(-CG.ARENA_HALF_WIDTH * 0.8 + gap * float(i + 1), 0.0)))
	_view._rebuild_units()
	_view._curr_drawn = _view._drawn_snapshot()
	_view._prev_drawn = _view._curr_drawn
	await RenderingServer.frame_post_draw

	var centres: Array[Vector2] = []
	for i in STAGED.size():
		centres.append(_view._unit_views[i].get_global_transform_with_canvas().origin)
	var alive: Array[Image] = []
	for i in STAGED.size():
		alive.append(_crop(await _full(), centres[i], STAGED_CROP, STAGED_ZOOM))

	for u in state.units:
		u.hp = 0
		u.alive = false
		var death := CombatEvent.make(CG.EventKind.DEATH, 0)
		death.target_id = u.id
		state.events.append(death)
	_view.consume_events()
	for id in _view._unit_views:
		_view._unit_views[id].sync(state)
	# Tool-side isolation, and it changes nothing that ships: the death plate and
	# the debris land in the same crop and would swamp the one question this
	# staged run asks, which is whether the chunks at rest ARE the body.
	_hide_the_rest()

	var panels: Array = []
	for i in STAGED.size():
		panels.append([])
	var held: Array[int] = []
	var frozen_hold: Array[int] = []
	# Exactly what `BattleView._process` does while `_freeze_left > 0`: it sets
	# `ViewClock.frozen` and RETURNS above `_render`, so a frozen frame is a
	# frame the explosion is never advanced on. Driven by hand rather than by
	# `_process` because a staged floor of corpses resolves the fight, and the
	# end banner then covers the thing being photographed.
	ViewClock.frozen = true
	var frozen_frames := int(round(BattleView.HIT_STOP_SECONDS * 60.0))
	var first: Array[Image] = []
	for f in frozen_frames:
		var full := await _full()
		for i in STAGED.size():
			var panel := _crop(full, centres[i], STAGED_CROP, STAGED_ZOOM)
			if f == 0:
				held.append(_changed_pixels(alive[i], panel))
				first.append(panel)
				panels[i].append(panel)
			else:
				frozen_hold.append(_changed_pixels(first[i], panel))
	ViewClock.frozen = false

	# The whole life of a chunk, sampled evenly, because the interesting half is
	# the arc and a strip of consecutive frames covers a fifth of it.
	var span := int(ceil(DeathExplosion.LIFETIME * 60.0))
	var keep: Array[int] = []
	for i in range(1, STAGED_COLUMNS):
		keep.append(int(round(float(i) * float(span - 1) / float(STAGED_COLUMNS - 1))))
	for f in span:
		_view._render(0.0, false, 1.0 / 60.0)
		var full := await _full()
		if not keep.has(f):
			continue
		for i in STAGED.size():
			panels[i].append(_crop(full, centres[i], STAGED_CROP, STAGED_ZOOM))

	var total := STAGED_CROP.x * STAGED_ZOOM * STAGED_CROP.y * STAGED_ZOOM
	print("GibShot rest pose, the frozen frame against the living body, in DRAWN pixels:")
	for i in STAGED.size():
		# WHERE they differ, not only how many. A count alone cannot tell a chunk
		# drawn in the wrong place from a health bar the corpse no longer carries,
		# and guessing which it was is the mistake #566 made four times.
		var box := _difference_box(alive[i], first[i])
		var half := float(STAGED_CROP.y * STAGED_ZOOM) * 0.5
		var k := _arena_scale() * float(STAGED_ZOOM)
		var radius := UnitView.display_radius(state.units[i])
		print("  %-14s %6d of %d differ (%.2f%%); they lie in y %d..%d, the body's own ink in y %d..%d, its bar stack ends at y %d" % [
			STAGED[i], held[i], total, 100.0 * float(held[i]) / float(total),
			int(box.position.y), int(box.end.y),
			int(half - UnitView.drawn_top(STAGED[i], CG.Team.ENEMY, radius) * k),
			int(half + UnitView.drawn_bottom(STAGED[i], CG.Team.ENEMY, radius) * k),
			int(half)])
	var worst := 0
	for n in frozen_hold:
		worst = maxi(worst, n)
	print("  and across the whole %d-frame hold the busiest panel changes %d pixels" % [
		frozen_frames, worst])
	_save_rows("sable_589_staged", panels, STAGED_CROP, STAGED_ZOOM)
	_view.queue_free()
	_view = null
	await get_tree().process_frame

## The box every differing pixel falls inside, in panel pixels.
func _difference_box(a: Image, b: Image) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) == b.get_pixel(x, y):
				continue
			lo = Vector2(minf(lo.x, float(x)), minf(lo.y, float(y)))
			hi = Vector2(maxf(hi.x, float(x)), maxf(hi.y, float(y)))
	return Rect2() if lo.x == INF else Rect2(lo, hi - lo)

## How many screen pixels one arena pixel covers, read off the arena rather than
## assumed: the battle screen scales it to fit whatever window it is given.
func _arena_scale() -> float:
	return _view._arena.get_global_transform_with_canvas().get_scale().y

func _hide_the_rest() -> void:
	_view._bursts.visible = false
	for child in _view._arena.get_children():
		if child.get_script() == load("res://Scripts/UI/DamageFloater.gd"):
			child.queue_free()

## A standing body of a named shape. Nothing steps it, so it is the view's input
## and nothing else.
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

func _full() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _crop(full: Image, centre: Vector2, size: Vector2i, zoom: int) -> Image:
	var origin := Vector2i(centre) - size / 2
	origin = origin.clamp(Vector2i.ZERO, full.get_size() - size)
	var panel := full.get_region(Rect2i(origin, size))
	panel.resize(size.x * zoom, size.y * zoom, Image.INTERPOLATE_NEAREST)
	return panel

func _save_rows(stem: String, rows: Array, size: Vector2i, zoom: int) -> void:
	var w := size.x * zoom
	var h := size.y * zoom
	var kept: int = rows[0].size()
	var sheet := Image.create(w * kept, h * rows.size(), false, Image.FORMAT_RGBA8)
	for i in rows.size():
		for f in kept:
			sheet.blit_rect(rows[i][f], Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(f * w, i * h))
			sheet.fill_rect(Rect2i(f * w + w / 2, i * h, RULER_WIDTH, h), RULER)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s.png" % [OUT_DIR, stem]
	sheet.save_png(path)
	print("GibShot: %s -- %d bodies x %d frames" % [path, rows.size(), kept])

func _party(party_ids: Array) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in party_ids.size():
		party.append(PawnFactory.make_starter_pawn(
			party_ids[i], StringName("p%d" % i), String(party_ids[i])))
	return party

func _encounter():
	return Registry.get_encounter(Registry.all_encounter_ids()[0])

## The first death of the first sweep party that lands late enough to have a
## run-up. Simulation only: nothing here renders, so nothing here can perturb
## the strip the renderer then draws.
func _first_death() -> Dictionary:
	for party_ids in ScreenSweepScript.sweep_parties(Registry.all_class_ids()):
		var state := CombatSim.build(_party(party_ids), _encounter(), SEED)
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			var cursor := state.events.size()
			CombatSim.step(state)
			for i in range(cursor, state.events.size()):
				if state.events[i].kind != CG.EventKind.DEATH or state.tick <= FRAMES:
					continue
				var dead := state.unit(state.events[i].target_id)
				print("GibShot: party %s, %s dies on tick %d" % [
					", ".join(PackedStringArray(party_ids)),
					"null" if dead == null else dead.display_name, state.tick - 1])
				return {"tick": state.tick - 1, "id": state.events[i].target_id,
					"party": party_ids}
	return {"tick": -1, "id": -1, "party": []}

func _build_view(party_ids: Array) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = Registry.all_encounter_ids()[0]
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, _encounter())
	# Driven by hand: the view's own clock spends real time, which would make
	# the strip unrepeatable.
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))

func _panel(centre: Vector2) -> Image:
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var origin := Vector2i(centre) - CROP / 2
	origin = origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
	var panel := full.get_region(Rect2i(origin, CROP))
	panel.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return panel

func _strip(death: Dictionary, stem: String) -> void:
	await _build_view(death["party"])
	while _view.state.tick < int(death["tick"]) - 1:
		_frame()
	for i in LEAD_FRAMES:
		_frame()
	await get_tree().process_frame

	var body: Node2D = _view._unit_views[death["id"]]
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	# The failure mode the issue names by name: a chunk in flight read as a live
	# unit. That cannot be judged on a crop of one body, so the same frames are
	# kept whole. Four of them, spread across the flight.
	var scrum: Array[Image] = []
	var scrum_frames := [6, 10, 14, 19]
	var panels: Array[Image] = []
	var previous: Image = null
	for i in FRAMES:
		if scrum_frames.has(i):
			scrum.append(await _full())
		var panel := await _panel(centre)
		var changed := 0 if previous == null else _changed_pixels(previous, panel)
		print("  frame %2d  tick %4d  freeze %.3f  pieces %2d  pixels changed %6d" % [
			i, _view.state.tick, _view._freeze_left, _live_pieces(), changed])
		previous = panel
		panels.append(panel)
		_frame()
		await get_tree().process_frame
	_save(panels, stem)
	_save_scrum(scrum, stem)
	_view.queue_free()
	_view = null
	await get_tree().process_frame

## Zero before this issue lands, which is what makes the "off" strip a control
## rather than a copy of the same run.
func _live_pieces() -> int:
	if not "_gibs" in _view or _view._gibs == null:
		return 0
	return _view._gibs.live_pieces()

## Byte-wise, so it counts what a viewer sees rather than what the scene graph
## says. A body held still under an overlay that is still moving shows up here
## and nowhere in a position readout.
func _changed_pixels(a: Image, b: Image) -> int:
	var pa := a.get_data()
	var pb := b.get_data()
	if pa.size() != pb.size():
		return -1
	var stride := maxi(1, pa.size() / (a.get_width() * a.get_height()))
	var n := 0
	var i := 0
	while i < pa.size():
		if pa.slice(i, i + stride) != pb.slice(i, i + stride):
			n += 1
		i += stride
	return n

func _save(panels: Array[Image], stem: String) -> void:
	var w := CROP.x * ZOOM
	var h := CROP.y * ZOOM
	var rows := int(ceil(float(panels.size()) / float(ROW)))
	var strip := Image.create(w * ROW, h * rows, false, panels[0].get_format())
	for i in panels.size():
		var at := Vector2i((i % ROW) * w, (i / ROW) * h)
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), at)
		strip.fill_rect(Rect2i(at.x + w / 2, at.y, RULER_WIDTH, h), RULER)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s.png" % [OUT_DIR, stem]
	strip.save_png(path)
	print("GibShot: %s" % path)

## Four frames of the arena itself, at full resolution, tiled two by two. The
## arena is a third of the window, so halving whole frames made the one question
## this sheet exists to ask -- does a flying chunk read as a live unit -- too
## small to answer.
func _save_scrum(frames: Array[Image], stem: String) -> void:
	if frames.size() < 4:
		return
	var t: Transform2D = _view._arena.get_global_transform_with_canvas()
	var box := Rect2(t * UnitView.ARENA_BOUNDS.position,
		UnitView.ARENA_BOUNDS.size * t.get_scale())
	var region := Rect2i(box).intersection(Rect2i(Vector2i.ZERO, frames[0].get_size()))
	var w := region.size.x
	var h := region.size.y
	var sheet := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	for i in 4:
		sheet.blit_rect(frames[i].get_region(region), Rect2i(Vector2i.ZERO, Vector2i(w, h)),
			Vector2i((i % 2) * w, (i / 2) * h))
	var path := "%s/%s_scrum.png" % [OUT_DIR, stem]
	sheet.save_png(path)
	print("GibShot: %s -- 4 arena frames at %dx%d" % [path, w, h])
