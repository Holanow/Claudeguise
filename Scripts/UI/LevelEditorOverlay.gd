extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const LevelEditorCanvasScript := preload("res://Scripts/UI/LevelEditorCanvas.gd")

## The level editor's own drawing on top of ArenaFloor: the party deploy
## zone, every placed enemy, and the rectangle being dragged out right now.
##
## OWNER: kite.
##
## A child of the same ArenaFloor-scripted node the editor's terrain draws
## on, not a sibling of it — the same reason UnitView is a child of
## BattleView's Arena rather than a sibling: a CanvasItem's children draw
## after its own _draw() call, so this is what keeps ArenaFloor's opaque
## floor fill from painting over everything placed on it. Found on a real
## launch: the first version drew enemies from the Control's own _draw(),
## with ArenaFloor added as a later sibling — every enemy vanished under the
## floor the instant a real screenshot was taken, invisible in the gate
## because no test asserted draw order, only that the data was there.
##
## Reads the canvas's live state directly rather than owning a duplicate of
## it — this node exists only to draw. `LevelEditorCanvas` still owns
## everything and is the only thing anyone outside this file talks to.

var canvas = null

func _draw() -> void:
	if canvas == null:
		return
	_draw_deploy_zone()
	for p in canvas.party_spawns:
		draw_circle(p, 6.0, Palette.TEAM_PLAYER)
	for spawn in canvas.enemy_spawns:
		_draw_enemy(spawn)
	if canvas._dragging and canvas.mode == LevelEditorCanvasScript.Mode.PLACE_TERRAIN:
		var rect: Rect2 = LevelEditorCanvasScript._rect_from_corners(canvas._drag_start_world, canvas._drag_current_world)
		draw_rect(rect, Palette.TEXT_DIM, false, 2.0)

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
	var blocked: bool = Terrain.point_is_blocked(canvas.terrain, pos, radius)
	draw_circle(pos, radius, Palette.HP_LOW if blocked else Palette.TEAM_ENEMY)
	var font := ThemeDB.fallback_font
	# Registry.get_enemy for a display name rather than the raw id reaching
	# the screen — the same rule InspectPanel's own tests hold every label
	# on this project to.
	var enemy_def := Registry.get_enemy(spawn.enemy_id)
	var text := enemy_def.display_name if enemy_def != null else String(spawn.enemy_id)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL)
	draw_string(font, pos + Vector2(-text_size.x * 0.5, -radius - 4.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_SMALL, Palette.TEXT)
