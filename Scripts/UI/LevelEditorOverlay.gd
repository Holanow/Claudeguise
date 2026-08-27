extends Node2D

const LevelEditorCanvasScript := preload("res://Scripts/UI/LevelEditorCanvas.gd")

## The level editor's own drawing on top of ArenaFloor: the party deploy
## zone, every placed enemy, and the rectangle being dragged out right now.

var canvas = null

func _draw() -> void:
	if canvas == null:
		return
	_draw_deploy_zone()
	for i in canvas.party_spawns.size():
		_draw_party_spawn(i, canvas.party_spawns[i])
	for spawn in canvas.enemy_spawns:
		_draw_enemy(spawn)
	_draw_labels()
	if canvas._dragging and canvas.mode == LevelEditorCanvasScript.Mode.PLACE_TERRAIN:
		var rect: Rect2 = LevelEditorCanvasScript._rect_from_corners(canvas._drag_start_world, canvas._drag_current_world)
		draw_rect(rect, Palette.TEXT_DIM, false, 2.0)

## Issue 145. The level editor passes no labels and keeps `party_radius` at 6.0,
## so it draws exactly the pin it always drew. The deploy screen passes the real
## unit radius and the pawns' names, which is what turns four identical dots
## into a decision -- the held one is outlined so the player can see what they
## have picked up.
func _draw_party_spawn(index: int, at: Vector2) -> void:
	var radius: float = canvas.party_radius
	draw_circle(at, radius, Palette.TEAM_PLAYER)
	if index == canvas.held_party_spawn():
		draw_arc(at, radius + 2.0, 0.0, TAU, 24, Palette.TEXT, 2.0, true)

## Every name on this screen, laid out against each other before any of it is
## drawn. Issue 321: each label used to draw itself at its own marker with no
## knowledge of the others, so on the deploy screen `Ghoul` printed over
## `Cultist` and read as `ltist` every single time.
func _draw_labels() -> void:
	var font := ThemeDB.fallback_font
	var ascent := font.get_ascent(Palette.FONT_SIZE_SMALL)
	for entry in label_layout(_labels()):
		var chip: Rect2 = entry["rect"]
		draw_string(font, Vector2(chip.position.x, chip.position.y + ascent), String(entry["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)

## Each label on the first row free of every label already placed. Markers are
## taken in the order `_labels` gives them, so the layout is the same every
## time the same screen is drawn.
static func label_layout(labels: Array) -> Array:
	var placed: Array[Rect2] = []
	var out: Array = []
	for entry in labels:
		var text := String(entry["text"])
		var at: Vector2 = entry["at"]
		var radius := float(entry["radius"])
		var chip := label_rect(text, at, radius, 0)
		var row := 0
		while row < LABEL_ROWS and _hits_any(chip, placed):
			row += 1
			chip = label_rect(text, at, radius, row)
		placed.append(chip)
		out.append({"text": text, "rect": chip, "row": row})
	return out

## Enough rows for every marker on the screen to get its own, so the search can
## never run out and overprint the way it used to by construction.
const LABEL_ROWS := 32

## The ink one name covers, lifted `row` whole rows clear of its marker. The
## one place this geometry exists: `_draw_labels` renders it and the row search
## de-collides against it, so a shifted label cannot drift from its own box.
## Row 0 is exactly where every label was drawn before there was a search.
static func label_rect(text: String, at: Vector2, radius: float, row: int) -> Rect2:
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL)
	var ascent := font.get_ascent(Palette.FONT_SIZE_SMALL)
	var baseline := at.y - radius - 4.0 - float(row) * (size.y + 2.0)
	return Rect2(Vector2(at.x - size.x * 0.5, baseline - ascent), size)

static func _hits_any(chip: Rect2, placed: Array[Rect2]) -> bool:
	for p in placed:
		if chip.intersects(p):
			return true
	return false

## Marker order decides who keeps the row nearest its own body, so it is fixed:
## the party first in list order, then the enemies in list order.
func _labels() -> Array:
	var out: Array = []
	for i in canvas.party_spawns.size():
		if i >= canvas.party_labels.size() or canvas.party_labels[i] == "":
			continue
		out.append({"text": String(canvas.party_labels[i]),
			"at": canvas.party_spawns[i], "radius": canvas.party_radius})
	for spawn in canvas.enemy_spawns:
		var text := enemy_label(spawn)
		if text == "":
			continue
		out.append({"text": text, "at": spawn.position,
			"radius": float(spawn.get("radius", 22.0))})
	return out

## Registry.get_enemy for a display name rather than the raw id reaching the
## screen -- the same rule InspectPanel's own tests hold every label on this
## project to.
static func enemy_label(spawn: Dictionary) -> String:
	var enemy_def := Registry.get_enemy(spawn.enemy_id)
	return enemy_def.display_name if enemy_def != null else String(spawn.enemy_id)

func _draw_deploy_zone() -> void:
	var top_left := Vector2(-CG.ARENA_HALF_WIDTH, -CG.ARENA_HALF_HEIGHT)
	var bottom_right := Vector2(CG.party_deploy_max_x(), CG.ARENA_HALF_HEIGHT)
	var color := Palette.TEAM_PLAYER
	color.a = 0.14
	draw_rect(Rect2(top_left, bottom_right - top_left), color)

## Blocked enemies (the same check `has_blocked_enemy` uses to refuse a
## save) draw in HP_LOW rather than the normal enemy colour — visible on the
## editor itself, not only as a refusal message once Save is pressed.
func _draw_enemy(spawn: Dictionary) -> void:
	var pos: Vector2 = spawn.position
	var radius: float = float(spawn.get("radius", 22.0))
	## A throwaway grid rather than the rectangles: the editor should refuse
	## exactly the spawns the fight would, and the fight asks cells.
	var blocked: bool = TerrainGrid.from_features(canvas.terrain).move_blocked(pos, radius)
	draw_circle(pos, radius, Palette.HP_LOW if blocked else Palette.TEAM_ENEMY)
