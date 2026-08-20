extends Node2D

const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")

## Issue #197's live options, drawn at the size a fight draws them.
##
##   godot --path . --resolution 1280x1110 res://Tools/ImpactMarkSheet.tscn
##
## That resolution is not a taste call. The project stretches a 1280-wide canvas
## to fill the window, so any wider window captures the same canvas UPSCALED --
## a 1500x1300 run writes a PNG 1.17x larger than life, which is the one thing a
## sheet about legibility at true size must not do. At 1280 the capture is 1:1.
##
## No --headless: `get_viewport().get_texture()` never populates under
## --headless on this machine, same note AttackFXPreview.gd and RatKingSheet.gd
## both carry. A real window works.
##
## OWNED BY sable. **Nothing here is in the shipped path.** The candidate
## geometry for options B and D lives in this file and not in
## `Scripts/Art/AttackFX.gd` on purpose: the issue is labelled `for-owner` and
## the choice is the player's, so shipping the function ahead of the decision
## would be implementing an option while claiming to render one. What the game
## draws today comes from the real `AttackFX.draw_impact_flash`, so the
## "CURRENT" column is the live code and not a reproduction of it.
##
## WHY THIS SHEET EXISTS
##
## I wrote in #197: *"at goblin size (15px body) a 120-degree arc is a short
## stroke. Needs rendering before anyone believes it. I would render it before
## recommending it."* That is a claim about pixels and it cannot be settled by
## reading coordinates. Every size below is asked of `BattleView.compute_layout`
## and `Silhouettes.drawn_extent` -- the functions the real screen uses -- rather
## than typed, because `ArtPreview` types its own scale factor and gets it wrong.

## Two pages, captured from one run: the option grid, and the scrum. They are
## split because the canvas is only ~1110 tall at 1:1 and both do not fit.
const CAPTURE_PATH := "res://Screenshots/impact_mark_options.png"
const SCRUM_PATH := "res://Screenshots/impact_mark_scrum.png"

## The arc's span. 120 degrees is the figure #197 names.
const ARC_DEGREES := 120.0

## The one colour options A and D would use. `d8d3c4` is what PHYSICAL already
## is, which makes it the cheapest constant to adopt -- and see the interrupt
## cell at the bottom of the sheet for the reason that choice is not free.
const FIXED_COLOR := Color("d8d3c4")

## The moment sampled in the grid. Mid-life: the ring is near its final size and
## still has most of its alpha, which is the frame a viewer actually registers.
const SAMPLE_PROGRESS := 0.4

## Where the attacker stands, relative to the target. Down-left, so the mark is
## nowhere near an axis and cannot flatter itself by lining up with the grid.
const BEARING_DEGREES := 205.0

var _font: Font = null
var _scale := 1.0
var _page := 0

func _ready() -> void:
	var layout := BattleView.compute_layout(Vector2(1280.0, 720.0))
	_scale = layout["scale"].x
	# The window is DPI-scaled on this machine: a --resolution of 1500x1300
	# gives a 1280x1109 viewport upscaled into a 1500x1300 capture. Everything
	# below lays out in VIEWPORT space, so print it rather than assume it -- the
	# first version of the scrum panel ran off the right edge for exactly this
	# reason and the capture's own width did not show it.
	print("ImpactMarkSheet: viewport %s, battle scale %.4f" % [get_viewport_rect().size, _scale])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CAPTURE_PATH)
	_page = 1
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(SCRUM_PATH)
	get_tree().quit(0)

func _capture(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	var err := image.save_png(path)
	if err != OK:
		printerr("ImpactMarkSheet: could not save %s (error %d)" % [path, err])
		return
	print("ImpactMarkSheet: wrote ", path)

## The radius the live code hands `ImpactFlash`, in screen pixels: a unit's
## world radius through `display_radius` and then through the battle scale.
func _flash_radius(world_radius: float) -> float:
	return world_radius * UnitViewScript.DISPLAY_SCALE * _scale

func _drawn_body_px(shape_id: StringName, world_radius: float, team: CG.Team) -> float:
	var box := Silhouettes.drawn_extent(shape_id, world_radius * UnitViewScript.DISPLAY_SCALE, team)
	return box.size.x * _scale

# ---------------------------------------------------------------------------
# The candidate marks. Only `_ring` is the shipped one.

## What the game draws today: `AttackFX.draw_impact_flash`, called directly.
func _ring(at: Vector2, radius: float, dt: CG.DamageType, progress: float) -> void:
	AttackFX.draw_impact_flash(self, at, radius, dt, progress)

## Option A: the same ring in one constant colour. Alpha and radius still come
## from the live functions, so only the colour differs.
func _ring_fixed(at: Vector2, radius: float, progress: float) -> void:
	var alpha := AttackFX.impact_flash_alpha(progress)
	if alpha <= 0.0:
		return
	var c := FIXED_COLOR
	c.a = alpha
	draw_arc(at, AttackFX.impact_flash_radius(radius, progress), 0.0, TAU, 20, c, 3.0, true)

## Option B: the same expanding, fading circle cut down to a `ARC_DEGREES` arc
## centred on the bearing to the attacker. Nothing else changes -- growth and
## fade are still `AttackFX`'s, so this is the shipped animation with most of
## its circumference removed.
func _arc(at: Vector2, radius: float, color: Color, progress: float, bearing: float) -> void:
	var alpha := AttackFX.impact_flash_alpha(progress)
	if alpha <= 0.0:
		return
	var c := color
	c.a = alpha
	var half := deg_to_rad(ARC_DEGREES) * 0.5
	draw_arc(at, AttackFX.impact_flash_radius(radius, progress), bearing - half, bearing + half, 14, c, 3.0, true)

## Option B, second reading: a chevron pointing inward at the contact point
## rather than an arc lying along it. #197 lists both; at the sizes below they
## are not the same picture and only one of them survives the goblin.
func _chevron(at: Vector2, radius: float, color: Color, progress: float, bearing: float) -> void:
	var alpha := AttackFX.impact_flash_alpha(progress)
	if alpha <= 0.0:
		return
	var c := color
	c.a = alpha
	var r := AttackFX.impact_flash_radius(radius, progress)
	var tip := at + Vector2(r, 0.0).rotated(bearing)
	var arm := maxf(r * 0.55, 5.0)
	var back := bearing + PI
	var a := tip + Vector2(arm, 0.0).rotated(back + deg_to_rad(38.0))
	var b := tip + Vector2(arm, 0.0).rotated(back - deg_to_rad(38.0))
	draw_line(a, tip, c, 3.0, true)
	draw_line(b, tip, c, 3.0, true)

# ---------------------------------------------------------------------------

## Smallest fielded unit, the case #197 names, and the largest. Radii are read
## off the registry so this cannot drift from the content.
func _cases() -> Array:
	return [
		{"id": &"rat", "label": "rat (smallest)", "team": CG.Team.ENEMY},
		{"id": &"goblin", "label": "goblin (#197 case)", "team": CG.Team.ENEMY},
		{"id": &"rat_king", "label": "rat king (largest)", "team": CG.Team.ENEMY},
	]

func _radius_of(id: StringName) -> float:
	var e = Registry.get_enemy(id)
	return e.radius if e != null else 12.0

const _COLUMNS := [
	"CURRENT\nring, damage colour",
	"A\nring, one colour",
	"B arc\ndamage colour",
	"B chevron\ndamage colour",
	"D\narc, one colour",
]

func _draw() -> void:
	_font = ThemeDB.fallback_font
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKGROUND)
	if _page == 1:
		_crowd(Vector2(40.0, 40.0))
		return

	draw_string(_font, Vector2(40.0, 34.0),
		"Issue #197 -- impact mark options, at the size a 1280x720 fight draws them",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_HEADING, Palette.TEXT)
	draw_string(_font, Vector2(40.0, 56.0),
		"Every mark grows and fades with the shipped AttackFX functions. The dim unit down-left of each target is the attacker the hit came from.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	draw_string(_font, Vector2(40.0, 74.0),
		"Sampled at t=%.2f of the 0.35s life. Damage type is PROFANE -- the purple PLAYTEST-FRESH-2 could not read." % SAMPLE_PROGRESS,
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var bearing := deg_to_rad(BEARING_DEGREES)
	var col_w := 212.0
	var row_h := 160.0
	var origin := Vector2(212.0, 132.0)

	for c in _COLUMNS.size():
		var head: String = _COLUMNS[c]
		var lines := head.split("\n")
		draw_string(_font, origin + Vector2(float(c) * col_w - 6.0, -34.0), lines[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)
		draw_string(_font, origin + Vector2(float(c) * col_w - 6.0, -16.0), lines[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var cases := _cases()
	for r in cases.size():
		var case: Dictionary = cases[r]
		var world_radius := _radius_of(case["id"])
		var flash_radius := _flash_radius(world_radius)
		var body_px := _drawn_body_px(case["id"], world_radius, case["team"])
		var y := origin.y + float(r) * row_h

		draw_string(_font, Vector2(40.0, y + 52.0), case["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)
		draw_string(_font, Vector2(40.0, y + 70.0), "body %.0f px across" % body_px,
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
		draw_string(_font, Vector2(40.0, y + 88.0), "arc runs %.0f px" % _arc_length_px(flash_radius),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

		for c in _COLUMNS.size():
			var at := Vector2(origin.x + float(c) * col_w + 100.0, y + 68.0)
			_cell(at, case, world_radius, flash_radius, bearing, c)

	_lifetime_strip(Vector2(40.0, origin.y + float(cases.size()) * row_h + 40.0), bearing)
	_magnified(Vector2(40.0, origin.y + float(cases.size()) * row_h + 280.0), bearing)

func _arc_length_px(flash_radius: float) -> float:
	return AttackFX.impact_flash_radius(flash_radius, SAMPLE_PROGRESS) * deg_to_rad(ARC_DEGREES)

## One cell: a patch of arena floor, the attacker, the unit that was hit, and
## one of the five marks on it.
func _cell(at: Vector2, case: Dictionary, world_radius: float, flash_radius: float, bearing: float, column: int) -> void:
	draw_rect(Rect2(at - Vector2(100.0, 66.0), Vector2(200.0, 132.0)), Palette.ARENA_FLOOR)
	var draw_radius := world_radius * UnitViewScript.DISPLAY_SCALE * _scale

	# The attacker: a goblin standing at contact range on the bearing, drawn
	# dim so it does not compete with the mark under judgement.
	var attacker_r := _radius_of(&"goblin") * UnitViewScript.DISPLAY_SCALE * _scale
	var attacker_at := at + Vector2(draw_radius + attacker_r + 6.0, 0.0).rotated(bearing)
	Silhouettes.draw_unit(self, &"goblin", attacker_r, CG.Team.ENEMY, CG.DamageType.PHYSICAL, false, attacker_at)

	Silhouettes.draw_unit(self, case["id"], draw_radius, CG.Team.PLAYER, CG.DamageType.PHYSICAL, false, at)

	# PROFANE on purpose: it is the colour PLAYTEST-FRESH-2 could not read, and
	# the whole first half of #197 is about it.
	var dt := CG.DamageType.PROFANE
	match column:
		0: _ring(at, flash_radius, dt, SAMPLE_PROGRESS)
		1: _ring_fixed(at, flash_radius, SAMPLE_PROGRESS)
		2: _arc(at, flash_radius, Palette.damage_color(dt), SAMPLE_PROGRESS, bearing)
		3: _chevron(at, flash_radius, Palette.damage_color(dt), SAMPLE_PROGRESS, bearing)
		4: _arc(at, flash_radius, FIXED_COLOR, SAMPLE_PROGRESS, bearing)

## The whole life of the mark for the goblin, four stops, so the grid's single
## frame is not the only evidence. Same trick AttackFXPreview uses: growing
## radius and falling alpha means later stops do not hide earlier ones.
func _lifetime_strip(at: Vector2, bearing: float) -> void:
	draw_string(_font, at, "Whole life overlaid (t=0 brightest and smallest .. t=1), goblin, arc vs ring",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)
	var flash_radius := _flash_radius(_radius_of(&"goblin"))
	var draw_radius := _radius_of(&"goblin") * UnitViewScript.DISPLAY_SCALE * _scale
	var stops := [0.9, 0.6, 0.3, 0.0]
	var arc_at := at + Vector2(110.0, 110.0)
	var ring_at := at + Vector2(330.0, 110.0)
	for p in [arc_at, ring_at]:
		draw_rect(Rect2(p - Vector2(96.0, 82.0), Vector2(192.0, 164.0)), Palette.ARENA_FLOOR)
		Silhouettes.draw_unit(self, &"goblin", draw_radius, CG.Team.PLAYER, CG.DamageType.PHYSICAL, false, p)
	for s in stops:
		_arc(arc_at, flash_radius, FIXED_COLOR, s, bearing)
		_ring(ring_at, flash_radius, CG.DamageType.PROFANE, s)
	draw_string(_font, arc_at + Vector2(-40.0, 100.0), "D (arc)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	draw_string(_font, ring_at + Vector2(-50.0, 100.0), "current (ring)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

## Two things the grid cannot show at true size, magnified 3x and labelled as
## magnified so nobody reads them as evidence about legibility:
## the goblin cells side by side, and the interrupt flash the game already
## draws in `Palette.TEXT` -- which is the collision option A walks into.
func _magnified(at: Vector2, bearing: float) -> void:
	draw_string(_font, at, "3x MAGNIFIED (shape detail only -- judge legibility from the grid above)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)
	var flash_radius := _flash_radius(_radius_of(&"goblin")) * 3.0
	var draw_radius := _radius_of(&"goblin") * UnitViewScript.DISPLAY_SCALE * _scale * 3.0
	var labels := ["current ring", "B arc", "B chevron", "interrupt (already white)"]
	for i in labels.size():
		var p := at + Vector2(90.0 + float(i) * 172.0, 110.0)
		draw_rect(Rect2(p - Vector2(84.0, 82.0), Vector2(168.0, 164.0)), Palette.ARENA_FLOOR)
		Silhouettes.draw_unit(self, &"goblin", draw_radius, CG.Team.PLAYER, CG.DamageType.PHYSICAL, false, p)
		match i:
			0: _ring(p, flash_radius, CG.DamageType.PROFANE, SAMPLE_PROGRESS)
			1: _arc(p, flash_radius, FIXED_COLOR, SAMPLE_PROGRESS, bearing)
			2: _chevron(p, flash_radius, FIXED_COLOR, SAMPLE_PROGRESS, bearing)
			3: _ring_white(p, flash_radius, SAMPLE_PROGRESS)
		draw_string(_font, p + Vector2(-78.0, 100.0), labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

## `BattleView._spawn_interrupt_flash` passes `Palette.TEXT` to the same
## geometry. Reproduced here rather than called, because that call site is
## wren's file and this sheet does not touch it.
func _ring_white(at: Vector2, radius: float, progress: float) -> void:
	var alpha := AttackFX.impact_flash_alpha(progress)
	if alpha <= 0.0:
		return
	var c := Palette.TEXT
	c.a = alpha
	draw_arc(at, AttackFX.impact_flash_radius(radius, progress), 0.0, TAU, 20, c, 3.0, true)

## The condition the mark has to survive, which no isolated cell tests: three
## hits landing at once inside a scrum, at true size.
##
## A single unit on an empty floor flatters every option here. The playtest note
## that produced #197 was written about a fight, and the question it asks --
## "whose event is this?" -- only exists when there is more than one unit the
## mark could belong to.
##
## Hand-placed, not simulated: this is a still, and the positions come from what
## a melee scrum looks like in `Tools/preview/fight_*.png`. It is the weakest
## evidence on the sheet for that reason and it is labelled as a mock-up.
const _SCRUM := [
	# id, offset from panel centre in world units, team, hit-by (index) or -1
	[&"goblin", Vector2(-46.0, -18.0), CG.Team.ENEMY, -1],
	[&"warrior", Vector2(-4.0, -6.0), CG.Team.PLAYER, 0],
	[&"cultist", Vector2(40.0, -30.0), CG.Team.ENEMY, -1],
	[&"priest", Vector2(30.0, 34.0), CG.Team.PLAYER, 2],
	[&"goblin", Vector2(-52.0, 30.0), CG.Team.ENEMY, 3],
	[&"rat", Vector2(4.0, 44.0), CG.Team.ENEMY, -1],
]

func _crowd(at: Vector2) -> void:
	draw_string(_font, at, "SCRUM, true size, three hits landing at once -- a mock-up of a real frame, not a captured one",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)
	var labels := ["current: ring, damage colour", "A: ring, one colour", "D: arc, one colour"]
	for i in labels.size():
		var centre := at + Vector2(180.0 + float(i) * 352.0, 130.0)
		draw_rect(Rect2(centre - Vector2(170.0, 108.0), Vector2(340.0, 216.0)), Palette.ARENA_FLOOR)
		_scrum_panel(centre, i, SAMPLE_PROGRESS)
		draw_string(_font, centre + Vector2(-166.0, 128.0), labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	# The same scrum at three points in the mark's life, option D only. The row
	# above is one frame, and a mark a viewer never catches at its best frame is
	# not legible in the sense the finish line asks for: "without pausing".
	var second := at + Vector2(0.0, 290.0)
	draw_string(_font, second, "The same three hits under option D at three points in the 0.35s life -- what a viewer who does not pause actually sees",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)
	var stops := [0.1, 0.45, 0.8]
	for i in stops.size():
		var centre := second + Vector2(180.0 + float(i) * 352.0, 130.0)
		draw_rect(Rect2(centre - Vector2(170.0, 108.0), Vector2(340.0, 216.0)), Palette.ARENA_FLOOR)
		_scrum_panel(centre, 2, stops[i])
		draw_string(_font, centre + Vector2(-166.0, 128.0), "t = %.2f" % stops[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

func _scrum_panel(centre: Vector2, variant: int, progress: float) -> void:
	var points := []
	for row in _SCRUM:
		var id: StringName = row[0]
		var r := _unit_radius(id) * UnitViewScript.DISPLAY_SCALE * _scale
		var offset: Vector2 = row[1]
		var p := centre + offset * _scale * UnitViewScript.DISPLAY_SCALE
		points.append(p)
		var team: CG.Team = row[2]
		Silhouettes.draw_unit(self, id, r, team, CG.DamageType.PHYSICAL, false, p)
	for i in _SCRUM.size():
		var hit_by: int = _SCRUM[i][3]
		if hit_by < 0:
			continue
		var shape: StringName = _SCRUM[i][0]
		var flash_radius := _flash_radius(_unit_radius(shape))
		var here: Vector2 = points[i]
		var from: Vector2 = points[hit_by]
		var bearing := here.angle_to_point(from)
		match variant:
			0: _ring(here, flash_radius, CG.DamageType.PROFANE, progress)
			1: _ring_fixed(here, flash_radius, progress)
			2: _arc(here, flash_radius, FIXED_COLOR, progress, bearing)

## Player classes are not in the enemy registry, so the scrum needs both.
## `CombatUnit`'s default radius is what `CombatSim` gives every pawn.
func _unit_radius(id: StringName) -> float:
	var e = Registry.get_enemy(id)
	if e != null:
		return e.radius
	return 22.0
