extends SceneTree

## Writes the ledger's page grounds, panels and rules to `Assets/UI/`; run once
## and commit the output, the same relationship `BakeProjectiles.gd` has with
## the projectile marks. Issue 807.

const W := 1280
const H := 720

## Nine-slice source size. `UIArt` takes the corner as a third of the shorter
## side, so 48 gives 16px corners and every rule below is authored inside them.
const N := 48
const C := N / 3

## Paper is quantised so a full-screen grain field still compresses, and it is
## DITHERED by half a step before rounding. Quantising alone drew visible
## contour rings across the page -- a topographic map, not paper.
const STEPS := 40.0

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Assets/UI/background"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Assets/UI/border"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Assets/UI/panel"))
	_write("res://Assets/UI/background.png", _paper(W, H, Palette.PAPER_LEAF, 1))
	_write("res://Assets/UI/background/battle.png", _paper(W, H, Palette.PAPER_LEAF.darkened(0.05), 2))
	_write("res://Assets/UI/background/arena.png", _slate())
	_write("res://Assets/UI/border/arena.png", _board())
	_write("res://Assets/UI/panel.png", _card(false))
	_write("res://Assets/UI/panel/inspect.png", _card(true))
	_write("res://Assets/UI/panel_border.png", _rule_frame())
	quit(0)

func _write(path: String, img: Image) -> void:
	if img.save_png(path) != OK:
		printerr("BakeLedgerArt: could not write ", path)
		return
	print("  %-40s %d x %d" % [path, img.get_width(), img.get_height()])

## ---------------------------------------------------------------------------
## PAPER
##
## Not a gradient. Three separate things at three scales -- an uneven blotch,
## the mould's laid lines, and fibre -- because a single smooth ramp is the
## thing that reads as a texture pack.
func _paper(w: int, h: int, base: Color, seed: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + seed
	var fx := float(w)
	var fy := float(h)
	for y in h:
		var v := float(y)
		# Laid lines: the close-set impression of the paper mould, with a
		# heavier chain line every fifth.
		var laid := 0.008 if int(y) % 7 == 0 else 0.0
		if int(y) % 35 == 0:
			laid = 0.016
		for x in w:
			var u := float(x)
			# Four octaves rather than two. Two put one obvious disc in the
			# middle of the page.
			var blotch := (
				sin(u / fx * 5.3 + 0.7) * cos(v / fy * 3.1 + 1.9) * 0.45
				+ sin(u / fx * 11.0 - 2.2) * cos(v / fy * 7.4) * 0.30
				+ sin(u / fx * 23.0 + 4.1) * cos(v / fy * 17.0 - 0.6) * 0.16
				+ sin(u / fx * 47.0) * cos(v / fy * 39.0 + 2.5) * 0.09)
			var lift := blotch * 0.014 - laid
			# Age at the margins, over a falloff wide enough that no edge reads
			# as a drawn border.
			var edge := minf(minf(u, fx - 1.0 - u) / (fx * 0.40), minf(v, fy - 1.0 - v) / (fy * 0.40))
			lift -= (1.0 - clampf(edge, 0.0, 1.0)) * 0.045
			if rng.randf() < 0.09:
				lift += rng.randf_range(-0.030, 0.030)
			img.set_pixel(x, y, _quantise(base, lift, rng))
	return img

## Lightness only. Shifting hue as well is what turns paper orange.
func _quantise(base: Color, lift: float, rng: RandomNumberGenerator = null) -> Color:
	var c := base.lightened(lift) if lift > 0.0 else base.darkened(-lift)
	var d := rng.randf_range(-0.5, 0.5) if rng != null else 0.0
	return Color(
		clampf(roundf(c.r * STEPS + d) / STEPS, 0.0, 1.0),
		clampf(roundf(c.g * STEPS + d) / STEPS, 0.0, 1.0),
		clampf(roundf(c.b * STEPS + d) / STEPS, 0.0, 1.0),
		1.0)

## The arena's ground. Deliberately almost flat: this file exists so the
## general parchment `background.png` cannot reach the arena through `UIArt`'s
## fallback, and an arena that changed legibility would be a behaviour change
## wearing a theme's clothes.
func _slate() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	for y in H:
		for x in W:
			var lift := 0.0
			if rng.randf() < 0.04:
				lift = rng.randf_range(-0.02, 0.03)
			img.set_pixel(x, y, _quantise(Palette.ARENA_FLOOR, lift, rng))
	return img

## ---------------------------------------------------------------------------
## THE BOOK'S FURNITURE
##
## The frame the arena is mounted in: the book's board, with a keyline inside
## it, so a dark rectangle on a light page reads as a plate pasted in rather
## than as a hole cut out.
func _board() -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in N:
		for x in N:
			var d := mini(mini(x, N - 1 - x), mini(y, N - 1 - y))
			if d >= 7:
				continue
			var c := Palette.BINDING
			if d == 0:
				c = Palette.BINDING_DEEP
			elif d == 5:
				c = Palette.PAPER_SHADE
			elif d == 6:
				c = Palette.BINDING_DEEP
			elif d <= 2:
				c = Palette.BINDING.lightened(0.10)
			img.set_pixel(x, y, c)
	return img

## A card laid on the leaf. Lighter than the page so it lifts; a hairline ink
## rule; the doubled rule under the head that every ruled account book has; and
## on the worked page, the red vertical money-column rule inset from the right.
func _card(worked: bool) -> Image:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Palette.PAPER_FIELD)
	_hline(img, 0, Palette.INK_DIM)
	_hline(img, N - 1, Palette.INK_DIM)
	_vline(img, 0, Palette.INK_DIM)
	_vline(img, N - 1, Palette.INK_DIM)
	# The doubled head rule: the first line closes the border, the second sits
	# three below it. Red on the worked page, ink on a plain card.
	_hline(img, 4, Palette.RULE_RED if worked else Palette.INK_DIM)
	if worked:
		_hline(img, 6, Palette.RULE_RED)
		_vline(img, N - 6, Palette.RULE_RED)
		_hline(img, N - 5, Palette.RULE_FEINT)
	# Register ticks: a short heavier stroke into each corner, the printer's
	# mark that tells you the rules were meant rather than left over.
	for i in 5:
		for p in [Vector2i(i, 2), Vector2i(2, i), Vector2i(N - 1 - i, 2), Vector2i(N - 3, i),
				Vector2i(i, N - 3), Vector2i(2, N - 1 - i), Vector2i(N - 1 - i, N - 3), Vector2i(N - 3, N - 1 - i)]:
			img.set_pixel(p.x, p.y, Palette.INK)
	return img

## The same furniture with nothing behind it, for callers that want a rule
## around something they have already filled.
func _rule_frame() -> Image:
	var img := _card(false)
	for y in range(C, N - C):
		for x in range(C, N - C):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img

func _hline(img: Image, y: int, c: Color) -> void:
	for x in img.get_width():
		img.set_pixel(x, y, c)

func _vline(img: Image, x: int, c: Color) -> void:
	for y in img.get_height():
		img.set_pixel(x, y, c)
