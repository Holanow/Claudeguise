extends Node

## Issue 553. Nine strips of the same hit at the same tick, so the player can
## see the flash on its own, see the two treatments beside each other, and see
## what it does to the ring and the debris when all three land together.
##
## The engine drives the view rather than this tool driving it by hand, the same
## reason `Tools/BurstShot.gd` does: a `GPUParticles2D` ages on the engine's own
## delta.
##
## `CROP`, `ZOOM` and `_changed` are copied from `BurstShot` and must stay
## copied. #517's numbers were taken through them.
const OUT_DIR := "res://Screenshots"
const SEED := 7
const FRAMES := 8
const CROP := Vector2i(64, 48)
const ZOOM := 9
const RULER := Color(1.0, 0.2, 0.6)
const RULER_WIDTH := 2
const COST_FRAMES := 240
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("FlashShot: refusing to run in the main checkout -- use a worktree.")
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
	# One effect at a time first, so each has a changed-pixel count of its own.
	await _strip("sable_553_nothing", false, false, false, 0.0)
	await _strip("sable_553_flash_white", true, false, false, 0.0)
	await _strip("sable_553_flash_tinted", true, false, false, 1.0)
	# The blow above is PHYSICAL, whose damage colour is `d8d3c4` -- an off-white,
	# so the tinted strip beside it shows nothing. The pair below is the same
	# question asked on a hit whose colour is actually a colour.
	await _strip("sable_553_coloured_white", true, false, false, 0.0, _COLOURED)
	await _strip("sable_553_coloured_tinted", true, false, false, 1.0, _COLOURED)
	await _strip("sable_553_ring_only", false, true, false, 0.0)
	await _strip("sable_553_debris_only", false, false, true, 0.0)
	# Then what actually ships, and the same thing with the flash taken out.
	await _strip("sable_553_all_three", true, true, true, 0.0)
	await _strip("sable_553_ring_and_debris", false, true, true, 0.0)
	await _whole_screen()
	for units in [14, 100]:
		await _cost(units, false, false)
		await _cost(units, true, false)
		await _cost(units, true, true)

## The screen a player looks at, at full size, every option at its default.
## Every strip above is a 64x48 crop and a crop cannot show what a flash does to
## a screen that already has bodies, bars and a log on it.
func _whole_screen() -> void:
	DisplayOptions.reset()
	UnitView.reset_flash_tint()
	await _build(ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0])
	while _view.state.tick < 60 and _view.state.outcome == CombatState.Outcome.UNRESOLVED:
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "%s/sable_553_battle_screen.png" % OUT_DIR
	get_viewport().get_texture().get_image().save_png(path)
	print("FlashShot: %s" % path)
	await _teardown()

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

## The damage types worth asking the tint question on: the ones whose colour is
## not already almost white.
const _COLOURED := [CG.DamageType.FIRE, CG.DamageType.PROFANE, CG.DamageType.WATER,
	CG.DamageType.EARTH, CG.DamageType.DIVINE, CG.DamageType.RAW]

func _strip(stem: String, flash: bool, ring: bool, debris: bool, tint: float,
		want: Array = []) -> void:
	DisplayOptions.reset()
	# Hit stop off in every strip: this measures what a blow throws, and a freeze
	# in the middle of it would photograph the same frame six times.
	DisplayOptions.set_enabled(&"hit_stop", false)
	DisplayOptions.set_enabled(&"hit_flash", flash)
	DisplayOptions.set_enabled(&"impact_particles", debris)
	# Off in every strip. The squash moves the body's edges and would be counted
	# as changed pixels belonging to none of the three effects being compared.
	DisplayOptions.set_enabled(&"impact_squash", false)
	UnitView.flash_tint = tint
	await _build(ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0])

	var seen := 0
	var target_id := -1
	while target_id < 0 and _view.state.tick < CG.MAX_TICKS \n			and _view.state.outcome == CombatState.Outcome.UNRESOLVED:
		await RenderingServer.frame_post_draw
		if not ring:
			_drop_rings()
		for i in range(seen, _view.state.events.size()):
			var e = _view.state.events[i]
			if e.kind != CG.EventKind.DAMAGE or e.action_id == &"" or _view.state.tick <= 30:
				continue
			if not want.is_empty() and not want.has(e.damage_type):
				continue
			target_id = e.target_id
			print("FlashShot %s: damage type %d" % [stem, e.damage_type])
			break
		seen = _view.state.events.size()

	if target_id < 0:
		printerr("FlashShot: no melee blow found; nothing to draw")
		await _teardown()
		return

	var body: Node2D = _view._unit_views[target_id]
	var centre: Vector2 = body.get_global_transform_with_canvas().origin
	var panels: Array[Image] = []
	var lit: Array[int] = []
	var strength: Array[String] = []
	var previous: Image = null
	for i in FRAMES:
		if not ring:
			_drop_rings()
		await RenderingServer.frame_post_draw
		strength.append("%.2f" % UnitView.flash_strength(body._flash_age))
		var full := get_viewport().get_texture().get_image()
		var origin := Vector2i(centre) - CROP / 2
		origin = origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
		var panel := full.get_region(Rect2i(origin, CROP))
		lit.append(0 if previous == null else _changed(previous, panel))
		previous = panel.duplicate()
		panel.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
		panels.append(panel)
	print("FlashShot %s: unit %d, tick %d" % [stem, target_id, _view.state.tick])
	print("    changed pixels %s" % str(lit.slice(1)))
	print("    flash strength %s" % str(strength))
	_save(panels, stem)
	DisplayOptions.reset()
	UnitView.reset_flash_tint()
	await _teardown()

## Copied from `Tools/BurstShot.gd` unchanged. See the header.
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

## A vertical ruler down the middle of every panel, so a body that shifts a pixel
## between frames can be told from one that only changed colour.
func _save(panels: Array[Image], stem: String) -> void:
	var w := CROP.x * ZOOM
	var h := CROP.y * ZOOM
	var strip := Image.create(w * panels.size(), h, false, panels[0].get_format())
	for i in panels.size():
		strip.blit_rect(panels[i], Rect2i(Vector2i.ZERO, panels[i].get_size()), Vector2i(i * w, 0))
		strip.fill_rect(Rect2i(i * w + w / 2, 0, RULER_WIDTH, h), RULER)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s.png" % [OUT_DIR, stem]
	strip.save_png(path)
	print("FlashShot: %s" % path)

## Fabricated bodies for a cost measurement only. Copied from `ImpactShot`, which
## is where the 14/100-unit numbers this has to be comparable to came from.
func _clone(src: CombatUnit, id: int) -> CombatUnit:
	var out := CombatUnit.new()
	for p in src.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.set(p.name, src.get(p.name))
	out.id = id
	out.position = Vector2(
		randf_range(-CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_WIDTH),
		randf_range(-CG.ARENA_HALF_HEIGHT, CG.ARENA_HALF_HEIGHT))
	return out

## `storm` lights every body on the screen every frame: a real fight lands a
## handful of blows a second, so without it a hundred-unit row measures a
## hundred bodies at rest. With it, it measures the ceiling nothing can exceed.
func _cost(units: int, on: bool, storm: bool) -> void:
	seed(SEED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"hit_stop", false)
	DisplayOptions.set_enabled(&"impact_squash", false)
	DisplayOptions.set_enabled(&"impact_particles", false)
	DisplayOptions.set_enabled(&"hit_flash", on)
	var party_ids: Array = ScreenSweepScript.sweep_parties(Registry.all_class_ids())[0]
	await _build(party_ids)
	_view.set_process(false)
	var state: CombatState = _view.state
	var source: Array = state.units.duplicate()
	while state.units.size() < units:
		state.units.append(_clone(source[state.units.size() % source.size()], state.units.size()))
	_view._ensure_unit_views()
	await RenderingServer.frame_post_draw

	var frames := 0
	var slice := CG.TICK_SECONDS / 4.0
	var t0 := Time.get_ticks_usec()
	for i in COST_FRAMES:
		if state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		if storm:
			for id in _view._unit_views:
				_view._unit_views[id].struck(CG.DamageType.PHYSICAL)
		_view._process(slice)
		await RenderingServer.frame_post_draw
		frames += 1
	var spent := Time.get_ticks_usec() - t0
	print("FlashShot cost, %d units, flash %s, storm %s: %d us per rendered frame (n=%d)" % [
		state.units.size(), on, storm, 0 if frames == 0 else spent / frames, frames])
	DisplayOptions.reset()
	await _teardown()

func _teardown() -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	await get_tree().process_frame
