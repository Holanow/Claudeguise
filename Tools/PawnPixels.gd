extends Node

## How 22 world units of radius become a body a few pixels tall: every
## multiplication between `CombatUnit.radius` and a screen pixel, named, for
## real pawns in a real room at the window this runs at.

## SAMPLING MOMENT: the fight is paused before anything is read, and nothing
## here touches `state.rng` or steps `CombatSim`.

const OUT_DIR := "res://Screenshots"
const ENCOUNTER := &"floor1_warden"
const SEED := 0x2A
const PARTY := ["warrior", "priest", "geysermancer", "siege_master"]

## Ticks let past before reading, so pawns have left their spawn column and the
## room looks like a fight rather than a line-up.
const SETTLE_TICKS := 40

var _battle: Node = null

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _run() -> void:
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_battle = packed.instantiate()
	add_child(_battle)
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = ENCOUNTER
	cfg.seed = SEED
	_battle.begin(cfg)
	print("PawnPixels: begun, %d units" % _battle.state.units.size())
	var frames := 0
	while _battle.state.tick < SETTLE_TICKS and _battle.state.outcome == CombatState.Outcome.UNRESOLVED:
		await get_tree().process_frame
		frames += 1
		if frames > 60 * 60:
			print("PawnPixels: gave up settling at tick %d" % _battle.state.tick)
			break
	print("PawnPixels: settled at tick %d after %d frames" % [_battle.state.tick, frames])
	_battle.set_paused(true)
	for i in 4:
		await get_tree().process_frame

	var size := Vector2(DisplayServer.window_get_size())
	var layout: Dictionary = BattleView.compute_layout(size)
	var arena_scale: float = layout["scale"].x
	_report_layout(size, arena_scale)
	_report_units(arena_scale)
	_report_plates(arena_scale)
	_report_screen_rects(layout["position"], arena_scale)
	await _report_raster(arena_scale)
	await _shot(size)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in PARTY:
		out.append(PawnFactory.make_starter_pawn(
			StringName(cid), StringName("%s_%d" % [cid, out.size()]),
			ClassLibrary.get_class_def(StringName(cid)).display_name))
	return out

# --- the three multiplications --------------------------------------------

func _report_layout(size: Vector2, arena_scale: float) -> void:
	print("window %.0f x %.0f, room %s" % [size.x, size.y, ENCOUNTER])
	print("")
	print("MULTIPLICATION 1  DISPLAY_SCALE = %.2f  (view only)" % UnitView.DISPLAY_SCALE)
	print("MULTIPLICATION 3  arena fit scale")
	var fit_w := (CG.ARENA_HALF_WIDTH + 45.0 * UnitView.DISPLAY_SCALE) * 2.0
	var fit_h := (CG.ARENA_HALF_HEIGHT + 150.0 * UnitView.DISPLAY_SCALE) \
		+ (CG.ARENA_HALF_HEIGHT + 70.0 * UnitView.DISPLAY_SCALE)
	print("  arena %.0f x %.0f + margins -> fit box %.0f x %.0f world units"
		% [CG.ARENA_HALF_WIDTH * 2.0, CG.ARENA_HALF_HEIGHT * 2.0, fit_w, fit_h])
	print("  usable %.0f x %.0f px (log takes %.0f)"
		% [size.x - CombatLogView.LOG_WIDTH, size.y, CombatLogView.LOG_WIDTH])
	print("  scale = min(%.4f, %.4f) = %.4f, and the HEIGHT is what binds"
		% [(size.x - CombatLogView.LOG_WIDTH) / fit_w, size.y / fit_h, arena_scale])
	print("  plate text: FONT_SIZE_SMALL %d * %.2f * %.4f = %.1f px"
		% [Palette.FONT_SIZE_SMALL, UnitView.DISPLAY_SCALE, arena_scale,
			Palette.FONT_SIZE_SMALL * UnitView.DISPLAY_SCALE * arena_scale])
	print("")

func _report_units(arena_scale: float) -> void:
	print("MULTIPLICATION 2  the sprite's own fill of the box it is given")
	print("%-14s %6s %8s %9s %9s %11s %13s" % [
		"unit", "radius", "box(wu)", "file(px)", "ink(px)", "fill w x h", "SCREEN px"])
	for u: CombatUnit in _battle.state.units:
		if not u.alive:
			continue
		var shape := UnitView.shape_id(u)
		var box := UnitView.display_radius(u) * 2.0
		var ink := UnitView.drawn_box(shape, u.team, UnitView.display_radius(u))
		var n := UnitArt.canvas_size(shape, u.team)
		var file := Vector2(n, n)
		var tex_ink := Vector2(UnitArt.body_used_rect(shape, u.team).size)
		print("%-14s %6.0f %8.0f %9s %9s %11s %13s" % [
			String(u.display_name).substr(0, 14), u.radius, box,
			"%.0fx%.0f" % [file.x, file.y],
			"%.0fx%.0f" % [tex_ink.x, tex_ink.y],
			"%.2f x %.2f" % [ink.size.x / box, ink.size.y / box],
			"%.1f x %.1f" % [ink.size.x * arena_scale, ink.size.y * arena_scale]])
	print("")

## Where each body lands in the saved PNG, so the ink can be re-measured out of
## the screenshot rather than out of this tool's own arithmetic.
func _report_screen_rects(origin: Vector2, arena_scale: float) -> void:
	print("BODY RECTS IN THE SAVED SHOT (x y w h, screen px)")
	for u: CombatUnit in _battle.state.units:
		if not u.alive:
			continue
		var shape := UnitView.shape_id(u)
		var centre := origin + UnitView.drawn_position(u, _battle.state.units) * arena_scale
		var box := UnitView.drawn_box(shape, u.team, UnitView.display_radius(u))
		var rect := Rect2(centre + box.position * arena_scale, box.size * arena_scale)
		print("%-14s %.0f %.0f %.0f %.0f" % [
			String(u.display_name).substr(0, 14), rect.position.x, rect.position.y,
			rect.size.x, rect.size.y])
	print("")

## The playtester's claim, in numbers: the name plate against the body it names.
func _report_plates(arena_scale: float) -> void:
	print("PLATE vs BODY, both in screen pixels")
	print("%-14s %13s %13s %10s" % ["unit", "body", "plate", "plate/body"])
	var layout: Dictionary = UnitView.plate_layout(_battle.state)
	for u: CombatUnit in _battle.state.units:
		if not u.alive or not layout.has(u.id):
			continue
		var plate: Rect2 = layout[u.id]
		var body := UnitView.drawn_box(UnitView.shape_id(u), u.team, UnitView.display_radius(u))
		print("%-14s %13s %13s %9.2fx" % [
			String(u.display_name).substr(0, 14),
			"%.0f x %.0f" % [body.size.x * arena_scale, body.size.y * arena_scale],
			"%.0f x %.0f" % [plate.size.x * arena_scale, plate.size.y * arena_scale],
			(plate.size.x * plate.size.y) / maxf(body.size.x * body.size.y, 1.0)])
	print("")

# --- rasterised check ------------------------------------------------------

## Draws each body alone, at the size the arithmetic above says it lands at, and
## counts the opaque pixels. Same `Silhouettes.draw_unit` the battle screen uses.
func _report_raster(arena_scale: float) -> void:
	print("RASTERISED CHECK -- each body drawn alone at its on-screen size")
	print("%-14s %13s %13s %8s" % ["unit", "predicted", "rasterised", "ink px"])
	for u: CombatUnit in _battle.state.units:
		if not u.alive:
			continue
		var shape := UnitView.shape_id(u)
		var radius := UnitView.display_radius(u) * arena_scale
		var vp := SubViewport.new()
		vp.size = Vector2i(256, 256)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var canvas := _BodyCanvas.new()
		canvas.shape = shape
		canvas.radius = radius
		canvas.team = u.team
		canvas.position = Vector2(128, 128)
		vp.add_child(canvas)
		add_child(vp)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := vp.get_texture().get_image()
		var used := image.get_used_rect()
		var opaque := 0
		for y in range(used.position.y, used.end.y):
			for x in range(used.position.x, used.end.x):
				if image.get_pixel(x, y).a > 0.0:
					opaque += 1
		var box := UnitView.drawn_box(shape, u.team, UnitView.display_radius(u))
		print("%-14s %13s %13s %8d" % [
			String(u.display_name).substr(0, 14),
			"%.1f x %.1f" % [box.size.x * arena_scale, box.size.y * arena_scale],
			"%d x %d" % [used.size.x, used.size.y], opaque])
		vp.queue_free()
	print("")

class _BodyCanvas extends Node2D:
	var shape: StringName = &""
	var radius: float = 0.0
	var team: CG.Team = CG.Team.PLAYER

	func _draw() -> void:
		Silhouettes.draw_unit(self, shape, radius, team, CG.DamageType.PHYSICAL)

func _shot(size: Vector2) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/sable_pawn_scale_before_%dx%d.png" % [OUT_DIR, int(size.x), int(size.y)]
	image.save_png(path)
	print("shot: %s" % path)
