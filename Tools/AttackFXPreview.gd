extends Node2D


## Draws AttackFX's two pieces standalone -- readable size and true on-screen
## size, side by side -- and saves a screenshot. Same reasoning as
## Tools/ArtPreview.gd: "the shapes are fine" is not something to conclude
## from reading a coordinate table, and both pieces are small and brief enough
## in a live fight that a still sheet is the only place to judge them.
##
## It drew three. The wind-up ring row went with the ring in issue #85 -- the
## progress bar in `UnitView` replaced it and this file was its last caller.
##
##   godot --path . --resolution 1280x900 Tools/AttackFXPreview.tscn
##
## Lives in Tools/, not Scenes/, for the same reason ArtPreview does: a
## look-at-it harness, not part of the game.
##
## No --headless: get_viewport().get_texture() never populated under
## --headless on this machine (RenderingServer.frame_post_draw fired but the
## captured image stayed blank / the process hung waiting on it, unlike a
## script-mode run through Tests/run_tests.gd). A real window with a GL
## context, same as ContactSheet.gd's own documented invocation, works.

const CAPTURE_PATH := "res://Tools/preview/attack_fx.png"

const _ALL_TYPES := [
	CG.DamageType.PHYSICAL, CG.DamageType.FIRE, CG.DamageType.WATER,
	CG.DamageType.AIR, CG.DamageType.EARTH, CG.DamageType.DIVINE,
	CG.DamageType.PROFANE, CG.DamageType.RAW,
]

# True on-screen sizes, matched to the live code: ArenaFloor._PROJECTILE_RADIUS
# (5.0 world units) times the same viewport-fit scale ArtPreview derives, and
# UnitView.display_radius's own real-unit output.
const _PROJECTILE_WORLD_RADIUS := 5.0
const _UNIT_WORLD_RADIUS := 12.0 * 1.5 # CombatUnit.radius default * UnitView.DISPLAY_SCALE

const _COL_WIDTH := 150.0
const _MARGIN := Vector2(60.0, 100.0)

func _screen_scale() -> float:
	return get_viewport_rect().size.x / (CG.ARENA_HALF_WIDTH * 2.0)

func _ready() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture()
	get_tree().quit(0)

func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Tools/preview"))
	var err := image.save_png(CAPTURE_PATH)
	if err != OK:
		printerr("AttackFXPreview: could not save %s (error %d)" % [CAPTURE_PATH, err])
		return
	print("AttackFXPreview: wrote ", CAPTURE_PATH)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Palette.BACKGROUND)
	draw_string(font, Vector2(_MARGIN.x, 30.0), "AttackFX -- per-damage-type attack visuals",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_HEADING, Palette.TEXT)
	draw_string(font, Vector2(_MARGIN.x, 52.0),
		"row 1: projectile, readable size (30px)  ·  row 2: true on-screen size (~5-10px)  ·  row 3: impact flash, one snapshot at t=0.4",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var scale := _screen_scale()
	var true_projectile_size := _PROJECTILE_WORLD_RADIUS * scale
	var true_unit_radius := _UNIT_WORLD_RADIUS * scale

	var row1_y := _MARGIN.y + 40.0
	var row2_y := row1_y + 110.0
	var row3_y := row2_y + 90.0

	for i in _ALL_TYPES.size():
		var dt: CG.DamageType = _ALL_TYPES[i]
		var x := _MARGIN.x + float(i) * _COL_WIDTH + 60.0
		var name := CG.damage_type_name(dt)

		# Row 1: readable-size projectile, travelling up-right, with a patch
		# of arena floor under it same as ArtPreview does for silhouettes.
		var row1 := Vector2(x, row1_y)
		draw_rect(Rect2(row1 - Vector2(45.0, 45.0), Vector2(90.0, 90.0)), Palette.ARENA_FLOOR)
		AttackFX.draw_projectile(self, row1, Vector2(1.0, -0.4), dt, 30.0)
		draw_string(font, row1 + Vector2(-40.0, 55.0), name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)

		# Row 2: true size, same shot.
		var row2 := Vector2(x, row2_y)
		draw_rect(Rect2(row2 - Vector2(45.0, 25.0), Vector2(90.0, 50.0)), Palette.ARENA_FLOOR)
		AttackFX.draw_projectile(self, row2, Vector2(1.0, -0.4), dt, true_projectile_size)

		# Row 3: one impact-flash snapshot, mid-lifetime.
		var row3 := Vector2(x, row3_y)
		AttackFX.draw_impact_flash(self, row3, true_unit_radius, dt, 0.4)

	var flash_y := row3_y + 130.0
	draw_string(font, Vector2(_MARGIN.x, flash_y - 30.0),
		"Impact flash growing and fading, overlaid (Fire, then Water) -- t=0 (brightest, smallest) to t=1 (faintest, largest):",
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	_flash_overlay(CG.DamageType.FIRE, Vector2(_MARGIN.x + 100.0, flash_y + 50.0), true_unit_radius)
	_flash_overlay(CG.DamageType.WATER, Vector2(_MARGIN.x + 320.0, flash_y + 50.0), true_unit_radius)

func _flash_overlay(dt: CG.DamageType, at: Vector2, radius: float) -> void:
	# All four stops drawn at the same centre on purpose: growing radius and
	# falling alpha means later stops don't hide earlier ones, so a single
	# glance shows the whole life of the flash rather than four separate
	# frames.
	for p in [1.0, 0.6, 0.3, 0.0]:
		AttackFX.draw_impact_flash(self, at, radius, dt, p)
