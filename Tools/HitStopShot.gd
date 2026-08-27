extends Node

## Issue 515: does the picture hold on a death, and does it lurch afterwards?
## Two strips of the same fight across the same death, hit stop off and on, one
## panel per rendered frame, with a fixed ruler painted down every panel. A
## still cannot show either half, and without the ruler the crops look identical.
##
## The proof of "dropped, not banked" is in the spacing AFTER the hold: the
## frames either side of it must move the same distance. A double-spaced frame
## on the way out is the freeze repaying itself.

const OUT_DIR := "res://Screenshots"
const SEED := 7
## A 60Hz display against a 15Hz simulation.
const FRAMES_PER_TICK := 4
const FRAMES := 20
## Panels per row of the strip, so twenty of them stay a readable picture.
const ROW := 10
## Two frames of run-up before the killing tick, so the hold has a before.
const LEAD_FRAMES := 2
## Tight on purpose. At 96x72 a frame's 8px of walk is 2% of the panel and the
## twenty crops look identical; at 48x36 it is a body's width.
const CROP := Vector2i(64, 48)
const ZOOM := 6
const RULER := Color(1.0, 0.2, 0.6)
const RULER_WIDTH := 3
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("HitStopShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	await _run()
	get_tree().quit(0)

func _party(party_ids: Array) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for i in party_ids.size():
		party.append(PawnFactory.make_starter_pawn(
			party_ids[i], StringName("p%d" % i), String(party_ids[i])))
	return party

func _encounter():
	return Registry.get_encounter(Registry.all_encounter_ids()[0])

## Simulation only. A death is worth a strip when something else is walking
## through it: a hold on a screen where nothing was moving proves nothing.
func _walked_death() -> Dictionary:
	var best := {"tick": -1, "id": -1, "moved": 0.0, "party": []}
	for party_ids in ScreenSweepScript.sweep_parties(ClassLibrary.all_ids()):
		var state := CombatSim.build(_party(party_ids), _encounter(), SEED)
		var was := {}
		while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
			for u in state.units:
				was[u.id] = u.position
			var cursor := state.events.size()
			CombatSim.step(state)
			if state.tick <= FRAMES or not _has_death(state, cursor):
				continue
			for u in state.units:
				if not u.alive or not was.has(u.id):
					continue
				var moved: float = u.position.distance_to(was[u.id])
				# A walk, not a jump the view is meant to snap through.
				if moved > best["moved"] and moved <= u.move_speed * 3.0:
					best = {"tick": state.tick - 1, "id": u.id,
						"moved": moved, "party": party_ids}
	print("HitStopShot: party %s, unit %d walks %.1f units through the death on tick %d" % [
		", ".join(PackedStringArray(best["party"])), best["id"],
		best["moved"], best["tick"]])
	return best

func _has_death(state: CombatState, from: int) -> bool:
	for i in range(from, state.events.size()):
		if state.events[i].kind == CG.EventKind.DEATH:
			return true
	return false

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
	_view.set_process(false)

## One rendered frame of wall clock, driven by hand: the view's own `_process`
## spends real time, which would make the strip unrepeatable.
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

func _run() -> void:
	var death := _walked_death()
	if death["id"] < 0:
		printerr("HitStopShot: no walked death found; nothing to draw")
		return
	# Name plates stay off, their default: #511 is not landed and a plate that
	# lags its body would contaminate a strip about holding a picture still.
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"hit_stop", false)
	await _strip(death, "swift_515_hit_stop_off")
	DisplayOptions.set_enabled(&"hit_stop", true)
	await _strip(death, "swift_515_hit_stop_on")
	DisplayOptions.reset()

func _strip(death: Dictionary, stem: String) -> void:
	await _build_view(death["party"])
	while _view.state.tick < int(death["tick"]) - 1:
		_frame()
	for i in LEAD_FRAMES:
		_frame()
	await get_tree().process_frame

	var body: Node2D = _view._unit_views[death["id"]]
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	var panels: Array[Image] = []
	var last := Vector2.INF
	var steps: Array[float] = []
	var previous: Image = null
	var changed: Array[int] = []
	var held := 0
	for i in FRAMES:
		var at: Vector2 = body.position
		var moved := 0.0 if last == Vector2.INF else at.distance_to(last)
		if last != Vector2.INF:
			steps.append(moved)
			if is_zero_approx(moved):
				held += 1
		print("  frame %2d  tick %4d  drawn %8.2f, %8.2f  moved %6.3f  freeze %.3f  pixels changed %d" % [
			i, _view.state.tick, at.x, at.y, moved, _view._freeze_left,
			0 if changed.is_empty() else changed[-1]])
		last = at
		var panel := await _panel(centre)
		changed.append(0 if previous == null else _changed_pixels(previous, panel))
		previous = panel
		panels.append(panel)
		_frame()
		await get_tree().process_frame
	_report(steps, held)
	_report_pixels(changed)
	_save(panels, stem)
	_view.queue_free()
	_view = null
	await get_tree().process_frame

## The whole verification. The first version of this compared the largest gap in
## the strip against the mean and fired on the run with hit stop OFF, where
## there is no freeze at all -- units genuinely jump, and a detector that cannot
## stay quiet on healthy input is furniture within a minute.
##
## So it compares only what it has to: the gaps immediately BEFORE the hold
## against the gaps immediately AFTER it. A banked freeze pays itself back in
## exactly those frames and nowhere else.
const _SHOULDER := 3

func _report(steps: Array[float], held: int) -> void:
	var first := -1
	var last := -1
	for i in steps.size():
		if is_zero_approx(steps[i]):
			if first < 0:
				first = i
			last = i
	if first < 0:
		print("  no hold in %d gaps: the picture never stopped" % steps.size())
		return
	var before := _mean(steps, maxi(0, first - _SHOULDER), first)
	var after := _mean(steps, last + 1, mini(steps.size(), last + 1 + _SHOULDER))
	print("  hold is %d frames (gaps %d-%d of %d); %.3f per frame before it, %.3f after" % [
		held, first, last, steps.size(), before, after])
	if after > before * 1.5 and before > 0.0:
		printerr("  ^ THE FRAMES AFTER THE HOLD COVER MORE GROUND THAN THE ONES BEFORE.")
		printerr("    That is the freeze repaying its delta. It must be dropped.")

## The drawn positions above are geometry, and geometry is the proxy this
## project has been burned by: a body can hold still while the panel does not.
## So the panels themselves are compared, pixel for pixel.
func _report_pixels(changed: Array[int]) -> void:
	var still := 0
	var most := 0
	for i in range(1, changed.size()):
		if changed[i] == 0:
			still += 1
		most = maxi(most, changed[i])
	print("  %d of %d panel pairs are pixel-identical; busiest pair changes %d of %d pixels" % [
		still, changed.size() - 1, most, CROP.x * ZOOM * CROP.y * ZOOM])

## Byte-wise, so it counts what a viewer sees rather than what the scene graph
## says. A body held still under an overlay that is still animating shows up
## here and nowhere in the drawn positions.
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

func _mean(steps: Array[float], from: int, to: int) -> float:
	var sum := 0.0
	var n := 0
	for i in range(from, to):
		if not is_zero_approx(steps[i]):
			sum += steps[i]
			n += 1
	return 0.0 if n == 0 else sum / float(n)

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
	print("HitStopShot: %s" % path)
