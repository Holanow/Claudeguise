extends Node

## Issue 517, and the frames issue 197 has been waiting for. Three strips of the
## same hit at the same tick: debris only, ring only, and both together.
##
## The engine drives the view here rather than this tool driving it by hand.
## Every other strip in `Tools/` steps `_process` itself, which costs almost no
## wall clock -- and a `GPUParticles2D` ages on the engine's own delta, so a
## hand-driven strip would photograph the same burst twelve times.

const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES := 8
const CROP := Vector2i(64, 48)
const ZOOM := 9
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("BurstShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	await _run()
	get_tree().quit(0)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("p%d" % i), String(ids[i])))
	return out

func _encounter():
	return Registry.get_encounter(Registry.all_encounter_ids()[0])

func _run() -> void:
	# Hit stop off: this strip is about what a hit throws, and a freeze in the
	# middle of it would photograph the same burst six times.
	await _strip("swift_517_debris_only", true, false)
	await _strip("swift_517_ring_only", false, true)
	await _strip("swift_517_both", true, true)

func _build(party_ids: Array) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = Registry.all_encounter_ids()[0]
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, _encounter())

## The ring is not behind a toggle, so it is suppressed by emptying the arena of
## flashes each frame rather than by adding one. Nothing ships this path.
func _drop_rings() -> void:
	for child in _view._arena.get_children():
		if child is ImpactFlash:
			child.queue_free()

func _strip(stem: String, particles: bool, ring: bool) -> void:
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"hit_stop", false)
	DisplayOptions.set_enabled(&"impact_particles", particles)
	await _build(ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0])

	var seen := 0
	var target_id := -1
	while target_id < 0 and _view.state.tick < CG.MAX_TICKS:
		await RenderingServer.frame_post_draw
		if not ring:
			_drop_rings()
		for i in range(seen, _view.state.events.size()):
			var e = _view.state.events[i]
			if e.kind == CG.EventKind.DAMAGE and _view.state.tick > 30:
				target_id = e.target_id
				break
		seen = _view.state.events.size()

	if target_id < 0:
		printerr("BurstShot: no damage event found; nothing to draw")
		await _teardown()
		return

	var body: Node2D = _view._unit_views[target_id]
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	var panels: Array[Image] = []
	var lit: Array[int] = []
	var previous: Image = null
	for i in FRAMES:
		if not ring:
			_drop_rings()
		await RenderingServer.frame_post_draw
		var full := get_viewport().get_texture().get_image()
		var origin := Vector2i(centre) - CROP / 2
		origin = origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
		var panel := full.get_region(Rect2i(origin, CROP))
		lit.append(0 if previous == null else _changed(previous, panel))
		previous = panel.duplicate()
		panel.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
		panels.append(panel)
	print("BurstShot %s: unit %d, tick %d, per-frame changed pixels %s" % [
		stem, target_id, _view.state.tick, str(lit.slice(1))])
	_save(panels, stem)
	DisplayOptions.reset()
	await _teardown()

func _changed(a: Image, b: Image) -> int:
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

func _teardown() -> void:
	_view.queue_free()
	_view = null
	await get_tree().process_frame

func _save(panels: Array[Image], stem: String) -> void:
	var w := CROP.x * ZOOM
	var h := CROP.y * ZOOM
	var per_row := 8
	var rows := int(ceil(float(panels.size()) / float(per_row)))
	var strip := Image.create(w * per_row, h * rows, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()),
			Vector2i((i % per_row) * w, (i / per_row) * h))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s.png" % [OUT_DIR, stem]
	strip.save_png(path)
	print("BurstShot: %s" % path)
