extends Node

## Issue 276: does the impact ring stay on the body it is marking? Four frames
## of one flash's life, cropped around it and magnified, as one strip.

const OUT_DIR := "res://Screenshots"
const SEED := 7
const LIFE_TICKS := 4
const CROP := Vector2i(96, 72)
const ZOOM := 7
const MIN_TARGET_MOVE := 5.0

var _view: Node2D = null
var _arena: Node2D = null

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("ImpactFollowShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	await _run()
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var party: Array[PawnData] = []
	var class_ids := Registry.all_class_ids()
	for i in mini(4, class_ids.size()):
		party.append(PawnFactory.make_starter_pawn(class_ids[i], StringName("p%d" % i), String(class_ids[i])))
	return party

## Pass one, simulation only: the hit whose target walks furthest over the
## ring's life, so the strip shows the defect at its plainest rather than at
## its median.
func _find_moving_hit() -> Dictionary:
	var state := CombatSim.build(_party(), Registry.get_encounter(Registry.all_encounter_ids()[0]), SEED)
	var seen := 0
	var pending := []
	var best := {"tick": -1, "id": -1, "moved": 0.0}
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state)
		for e in state.events_since(seen):
			if e.kind == CG.EventKind.DAMAGE and e.target_id >= 0 and state.unit(e.target_id) != null:
				pending.append({"tick": state.tick, "id": e.target_id, "at": state.unit(e.target_id).position})
		seen = state.events.size()
		var still := []
		for p in pending:
			if state.tick < p["tick"] + LIFE_TICKS:
				still.append(p)
				continue
			var u := state.unit(p["id"])
			if u == null:
				continue
			var moved := u.position.distance_to(p["at"])
			if moved > best["moved"]:
				best = {"tick": p["tick"], "id": p["id"], "moved": moved}
		pending = still
	if best["moved"] < MIN_TARGET_MOVE:
		print("ImpactFollowShot: no hit with a target that moves; nothing to show")
		return {}
	print("ImpactFollowShot: hit at tick %d, unit %d, target walks %.1f units over %d ticks" % [
		best["tick"], best["id"], best["moved"], LIFE_TICKS])
	return best

## One simulation tick per rendered frame, driven by hand: the view's own
## `_process` spends wall-clock, which would make the strip unrepeatable.
func _step() -> void:
	_view._process(CG.TICK_SECONDS)
	for child in _arena.get_children():
		if child.get_script() == ImpactFlash and not child.is_queued_for_deletion():
			# Off the engine's own clock as well, or a slow frame ages the ring
			# twice and it is gone before the strip is finished.
			child.set_process(false)
			child._process(CG.TICK_SECONDS)

## The flash for one named unit, not merely the first one on screen: several
## rings can be alive at once and the wrong one shows nothing.
func _flash_on(unit_id: int) -> Node2D:
	var view: Node2D = _view._unit_views.get(unit_id)
	if view == null:
		return null
	var best: Node2D = null
	var best_d := 1e9
	for child in _arena.get_children():
		if child.get_script() != ImpactFlash or child.is_queued_for_deletion():
			continue
		var d: float = child.position.distance_to(view.position)
		if d < best_d:
			best_d = d
			best = child
	return best

func _panel(centre: Vector2) -> Image:
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var origin := Vector2i(centre) - CROP / 2
	origin = origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
	var panel := full.get_region(Rect2i(origin, CROP))
	panel.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return panel

func _run() -> void:
	var hit := _find_moving_hit()
	if hit.is_empty():
		return
	var target_tick: int = hit["tick"]
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.set_process(false)
	_view.state = CombatSim.build(_party(), Registry.get_encounter(Registry.all_encounter_ids()[0]), SEED)
	_view.event_cursor = 0
	_arena = _view.get_node("Arena")

	while _view.state.tick < target_tick:
		_step()
	await get_tree().process_frame

	var panels: Array[Image] = []
	var centre := Vector2.ZERO
	var tracked: Node2D = null
	for i in LIFE_TICKS:
		# One ring, identified once and then followed by reference. Re-finding
		# the nearest ring each frame would report the gap as zero by
		# construction, and the crop would centre the very error on show.
		if i == 0:
			tracked = _flash_on(hit["id"])
			centre = tracked.get_global_transform_with_canvas().origin if tracked != null \
				else Vector2(get_viewport().get_visible_rect().size) * 0.5
		var body: Node2D = _view._unit_views.get(hit["id"])
		if tracked != null and is_instance_valid(tracked) and body != null:
			print("  frame %d  ring %s  body %s  gap %.1f" % [
				i, tracked.position, body.position, tracked.position.distance_to(body.position)])
		panels.append(await _panel(centre))
		_step()
		await get_tree().process_frame

	var strip := Image.create(CROP.x * ZOOM * panels.size(), CROP.y * ZOOM, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(i * CROP.x * ZOOM, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var stem := OS.get_environment("IMPACT_SHOT_NAME")
	if stem == "":
		stem = "wren_276_flash_follows_target"
	var name := "%s/%s.png" % [OUT_DIR, stem]
	strip.save_png(name)
	print("ImpactFollowShot: %s" % name)
