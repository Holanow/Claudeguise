extends Node

## Issue 573: can a player still tell WHICH body was hit, with the impact ring
## gone, in a scrum? #517's strips crop 64x48 around one body, which is the one
## framing that cannot answer it -- there are no neighbours in the picture.
##
## Same method as `BurstShot` and the same reason: the engine drives the view,
## because a `GPUParticles2D` ages on the engine's own delta and a hand-driven
## strip photographs the same burst twelve times.

const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES := 6
## Wide enough to hold the struck body and its neighbours. #517 used 64x48.
const CROP := Vector2i(190, 150)
const ZOOM := 4
## How close another body has to be to count as a neighbour, in screen pixels.
const NEIGHBOUR_RANGE := 70.0
const NEIGHBOURS_WANTED := 2
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ScrumAttribution: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	await _run()
	get_tree().quit(0)

func _run() -> void:
	await _strip("teal_573_scrum_debris_only", true, false)
	await _strip("teal_573_scrum_ring_only", false, true)
	await _strip("teal_573_scrum_both", true, true)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(ids[i], StringName("p%d" % i), String(ids[i])))
	return out

func _build(party_ids: Array) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = RoomLibrary.all_ids()[0]
	cfg.seed = SEED
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, RoomLibrary.get_room(RoomLibrary.all_ids()[0]))

## The ring is not behind a toggle, so it is suppressed by emptying the arena of
## flashes each frame rather than by adding one. Nothing ships this path.
func _drop_rings() -> void:
	for child in _view._arena.get_children():
		if child is ImpactFlash:
			child.queue_free()

## How many other drawn bodies sit within `NEIGHBOUR_RANGE` of this one.
func _neighbours(target_id: int) -> int:
	var body: Node2D = _view._unit_views.get(target_id)
	if body == null:
		return 0
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	var n := 0
	for id in _view._unit_views:
		if id == target_id:
			continue
		var other: Node2D = _view._unit_views[id]
		if other == null or not is_instance_valid(other) or not other.visible:
			continue
		if centre.distance_to(other.get_global_transform_with_canvas().origin) <= NEIGHBOUR_RANGE:
			n += 1
	return n

func _strip(stem: String, particles: bool, ring: bool) -> void:
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"hit_stop", false)
	DisplayOptions.set_enabled(&"impact_particles", particles)
	await _build(ScreenSweepScript.sweep_parties(ClassLibrary.all_ids())[0])

	# A hit on a body that actually has company. Without this the strip is the
	# same single-body framing #517 already took.
	var seen := 0
	var target_id := -1
	while target_id < 0 and _view.state.tick < CG.MAX_TICKS:
		await RenderingServer.frame_post_draw
		if not ring:
			_drop_rings()
		for i in range(seen, _view.state.events.size()):
			var e = _view.state.events[i]
			if e.kind != CG.EventKind.DAMAGE or _view.state.tick <= 30:
				continue
			if _neighbours(e.target_id) >= NEIGHBOURS_WANTED:
				target_id = e.target_id
				break
		seen = _view.state.events.size()

	if target_id < 0:
		printerr("ScrumAttribution: no damage event on a crowded body; nothing to draw")
		await _teardown()
		return

	var body: Node2D = _view._unit_views[target_id]
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	var panels: Array[Image] = []
	for i in FRAMES:
		if not ring:
			_drop_rings()
		await RenderingServer.frame_post_draw
		var full := get_viewport().get_texture().get_image()
		var origin := Vector2i(centre) - CROP / 2
		origin = origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
		var panel := full.get_region(Rect2i(origin, CROP))
		panel.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
		panels.append(panel)
	print("ScrumAttribution %s: unit %d, tick %d, neighbours within %dpx: %d" % [
		stem, target_id, _view.state.tick, int(NEIGHBOUR_RANGE), _neighbours(target_id)])
	_save(panels, stem)
	DisplayOptions.reset()
	await _teardown()

func _teardown() -> void:
	_view.queue_free()
	_view = null
	await get_tree().process_frame

func _save(panels: Array[Image], stem: String) -> void:
	var w := CROP.x * ZOOM
	var h := CROP.y * ZOOM
	var strip := Image.create(w * panels.size(), h, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(i * w, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s.png" % [OUT_DIR, stem]
	strip.save_png(path)
	print("ScrumAttribution: %s" % path)
