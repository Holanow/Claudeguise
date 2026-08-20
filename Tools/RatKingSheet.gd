extends Node2D

const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")

## The Rat King and its rats, at the size a fight actually draws them.
##
##   godot --path . --resolution 1280x820 res://Tools/RatKingSheet.tscn
##
## No --headless. `get_viewport().get_texture()` never populates under --headless
## on this machine; a real window works.
##
## OWNED BY sable (`Scripts/Art/**`).
##
## WHY A SECOND PREVIEW TOOL RATHER THAN A ROW IN ArtPreview
##
## `ArtPreview` answers "does this shape read", one shape per cell. The Rat King
## poses a question that has no cell: **does the pile read as many, and do the
## rats it spawns read as the same animal at a third of the size and in a
## crowd?** That is a question about a group, so the sheet has to draw the group.
##
## The Rat King is also not in any encounter yet, and the existing art test walks
## encounter spawn lists. That is exactly how the Siege Master's engine shipped
## invisible: a summoned unit appears in no spawn list, so nothing looked at it.
##
## THE TRUE SIZE IS COMPUTED, NOT TYPED
##
## `ArtPreview` types its own scale factor and gets it slightly wrong -- it uses
## the viewport width over the arena width and never applies
## `UnitView.DISPLAY_SCALE`. This asks `BattleView.compute_layout`, which is the
## function the real screen uses, so the "true size" row is the real number and
## not a second opinion about it. Same discipline as measuring the sound rate off
## a real fight: the thing that decides it is the thing to ask.

const CAPTURE_PATH := "res://Screenshots/rat_king.png"

## World radii. The Warden is 22.0 in `floor1_enemies.gd` and is the only boss in
## the game, so a miniboss sits just under it. The rat is chaff and is drawn at
## the goblin's 11.0, which is the smallest thing currently fielded.
const KING_RADIUS := 20.0
const RAT_RADIUS := 9.0
const WARDEN_RADIUS := 22.0
const GHOUL_RADIUS := 16.0
const GOBLIN_RADIUS := 11.0

const _DESIGN_RADIUS := 78.0

var _font: Font = null
var _screen_scale := 1.0

func _ready() -> void:
	# The scale the real battle screen would use at 1280x720, asked of the real
	# function rather than reproduced here.
	var layout := BattleView.compute_layout(Vector2(1280.0, 720.0))
	_screen_scale = layout["scale"].x * UnitViewScript.DISPLAY_SCALE
	print("RatKingSheet: battle scale %.4f, DISPLAY_SCALE %.2f" % [
		layout["scale"].x, UnitViewScript.DISPLAY_SCALE])
	print("  rat_king  world r=%.1f -> %.1f px radius, %.0f px ACROSS" % [
		KING_RADIUS, KING_RADIUS * _screen_scale, KING_RADIUS * _screen_scale * 2.0])
	print("  rat       world r=%.1f -> %.1f px radius, %.0f px ACROSS" % [
		RAT_RADIUS, RAT_RADIUS * _screen_scale, RAT_RADIUS * _screen_scale * 2.0])
	print("  the_warden world r=%.1f -> %.0f px ACROSS  (the existing boss, for scale)" % [
		WARDEN_RADIUS, WARDEN_RADIUS * _screen_scale * 2.0])
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_width() != int(get_viewport_rect().size.x):
		printerr("RatKingSheet: laid out at logical width %d, captured at %d -- CROPPED." % [
			int(get_viewport_rect().size.x), image.get_width()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	var err := image.save_png(CAPTURE_PATH)
	if err != OK:
		printerr("RatKingSheet: could not save %s (%d)" % [CAPTURE_PATH, err])
	else:
		print("RatKingSheet: wrote ", CAPTURE_PATH)
	get_tree().quit(0)

func _label(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _enemy(shape: StringName, radius: float, at: Vector2, facing_left: bool = false) -> void:
	Silhouettes.draw_unit(self, shape, radius, CG.Team.ENEMY, CG.DamageType.PHYSICAL, facing_left, at)

func _draw() -> void:
	_font = ThemeDB.fallback_font
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BACKGROUND)

	_label(Vector2(30.0, 40.0), "The Rat King, and the rats it leaves behind",
		Palette.FONT_SIZE_HEADING, Palette.TEXT)
	_label(Vector2(30.0, 64.0),
		"README: \"Big collection of rats joined at the tail. Ranged attacker, all attacks leave behind rats.\"",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	# --- design size, where the shapes are authored ------------------------
	_label(Vector2(30.0, 108.0), "At design size. Nobody ever sees this.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	_enemy(&"rat_king", _DESIGN_RADIUS, Vector2(140.0, 230.0))
	_label(Vector2(70.0, 336.0), "rat_king", Palette.FONT_SIZE_BODY, Palette.TEXT)
	_enemy(&"rat", _DESIGN_RADIUS * 0.5, Vector2(320.0, 250.0))
	_label(Vector2(282.0, 336.0), "rat", Palette.FONT_SIZE_BODY, Palette.TEXT)

	# --- true size, which is the only row that decides anything ------------
	var true_y := 230.0
	_label(Vector2(430.0, 108.0), "TRUE SIZE, computed from BattleView.compute_layout at 1280x720.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
	_label(Vector2(430.0, 128.0), "This row is the one that decides whether the art works.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var contrast := [
		[&"rat_king", KING_RADIUS, "rat_king"],
		[&"the_warden", WARDEN_RADIUS, "the_warden"],
		[&"ghoul", GHOUL_RADIUS, "ghoul"],
		[&"goblin", GOBLIN_RADIUS, "goblin"],
		[&"rat", RAT_RADIUS, "rat"],
	]
	var x := 470.0
	for row in contrast:
		var r: float = float(row[1]) * _screen_scale
		_enemy(row[0], r, Vector2(x, true_y))
		# The circle a unit's radius actually describes, so the pile can be
		# checked against the space it is allowed to occupy rather than against
		# how big it happens to look.
		draw_arc(Vector2(x, true_y), r, 0.0, TAU, 48, Palette.ARENA_EDGE, 1.0)
		_label(Vector2(x - 34.0, true_y + r + 22.0), String(row[2]), Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
		x += 150.0

	# --- the actual scene --------------------------------------------------
	# The king mid-fight with the chaff it has spawned. This is the picture that
	# answers the real question, because "reads as many" and "the rats read as
	# the same animal" are both properties of the group and neither is visible
	# one cell at a time.
	var band_y := 420.0
	draw_rect(Rect2(Vector2(30.0, band_y), Vector2(size.x - 60.0, 340.0)), Palette.ARENA_FLOOR)
	_label(Vector2(44.0, band_y + 26.0),
		"The fight, at true size on the arena floor: the pile, and six of what it spawns.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)

	var king_at := Vector2(300.0, band_y + 190.0)
	_enemy(&"rat_king", KING_RADIUS * _screen_scale, king_at)
	var rr := RAT_RADIUS * _screen_scale
	# Scattered by hand rather than on a ring: a ring reads as a formation and
	# chaff does not form up.
	for offset in [Vector2(120.0, -34.0), Vector2(186.0, 30.0), Vector2(96.0, 62.0),
			Vector2(252.0, -12.0), Vector2(300.0, 54.0), Vector2(170.0, -78.0)]:
		_enemy(&"rat", rr, king_at + offset)
	# The party's side of it, for contrast in the same picture: what the player
	# is looking at when they have to tell the miniboss from its chaff.
	for i in 3:
		Silhouettes.draw_unit(self, [&"warrior", &"priest", &"siege_master"][i],
			12.0 * _screen_scale, CG.Team.PLAYER,
			[CG.DamageType.EARTH, CG.DamageType.DIVINE, CG.DamageType.RAW][i],
			true, Vector2(880.0 + float(i) * 80.0, band_y + 150.0 + float(i % 2) * 60.0))

	_label(Vector2(44.0, band_y + 318.0),
		"Squint. The pile should read as several animals and the chaff as one each.",
		Palette.FONT_SIZE_SMALL, Palette.TEXT_DIM)
