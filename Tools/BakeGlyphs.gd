extends Node2D


## Bakes every generated glyph to a PNG, so the drawing code can be deleted.
##
##   godot --path . --resolution 640x400 res://Tools/BakeGlyphs.tscn
##
## OWNER: sable. Not part of the game and not part of the gate. It is committed
## because the geometry it reads is deleted in the same change: this file plus
## git history is the only way to regenerate the assets it writes.
##
## It renders the SAME draw calls the game made, into a transparent SubViewport,
## and writes the readback. Nothing is redrawn by hand, so the assets are today's
## look by construction rather than by somebody's judgement.
##
## Run it with a real renderer. `--headless` uses the dummy driver, which draws
## nothing and reads back an empty image -- and an empty PNG is indistinguishable
## from a working one until the fallback is gone.
##
## Widths that are a FRACTION of the icon (a status rim, an item plate) need no
## help: they scale with the bake. Widths that are a fixed number of PIXELS (an
## ability plate's outline, a silhouette's edge) are multiplied by the bake
## factor, because "render at 4x" means the whole picture at 4x and a 1px line
## left at 1px would vanish on the way back down.

const PAD := 8
const ICON := 128
const ICON_SCALE := 4.0
const UNIT := 128
const UNIT_RADIUS := 64.0
const UNIT_OUTLINE := 4.0

## Silhouettes with no file in `Assets/Units/` today. Everything else there is
## hand-drawn pixel art and baking over it would replace real art with the
## placeholder it already beat.
const UNBAKED_UNITS := [
	&"dungeon_grunt", &"dungeon_archer", &"dungeon_cultist",
	&"grub", &"brute", &"stalker", &"siege_engine",
]

var _viewport: SubViewport
var _painter: Painter
var _written := 0


class Painter extends Node2D:
	var job: Callable

	func _draw() -> void:
		if job.is_valid():
			job.call(self)


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(ICON + PAD * 2, ICON + PAD * 2)
	_painter = Painter.new()
	_viewport.add_child(_painter)
	add_child(_viewport)
	await _bake_all()
	print("BakeGlyphs: wrote %d files" % _written)
	get_tree().quit(0)


func _bake_all() -> void:
	var icon := Rect2(Vector2(PAD, PAD), Vector2(ICON, ICON))

	for s in CG.Status.values():
		await _bake("res://Assets/UI/status/%s.png" % String(CG.Status.keys()[s]).to_lower(), ICON,
			func(c: CanvasItem) -> void:
				var plate := UIArt.glyph_points({"poly": StatusIcons.plate_points(s)}, icon)
				UIArt.draw_outlined_polygon(c, plate, Palette.HP_BACK, StatusIcons.rim_color(s),
					maxf(1.0, ICON * 0.5 * 0.12))
				UIArt.draw_glyph(c, StatusIcons.GLYPHS[s], StatusIcons.glyph_rect(icon, s), Palette.TEXT))

	for id in ActionIcons.GLYPHS.keys():
		var action := Registry.get_action(id)
		var dt: CG.DamageType = action.damage_type if action != null else CG.DamageType.RAW
		await _bake("res://Assets/UI/action/%s.png" % id, ICON,
			func(c: CanvasItem) -> void:
				var plate := UIArt.glyph_points({"poly": ActionIcons.PLATE}, icon)
				UIArt.draw_outlined_polygon(c, plate, Palette.HP_BACK, Palette.ARENA_EDGE, ICON_SCALE)
				var inner := Rect2(icon.position + icon.size * 0.16, icon.size * 0.68)
				UIArt.draw_glyph(c, ActionIcons.glyph_for(id), inner, Palette.damage_color(dt)))

	for id in EquipmentIcons.known_ids():
		var item := Registry.get_equipment(id)
		if item == null:
			continue
		await _bake("res://Assets/UI/item/%s.png" % id, ICON,
			func(c: CanvasItem) -> void:
				EquipmentIcons._draw_plate(c, item.slot, icon, EquipmentIcons.slot_color(item.slot))
				var color := EquipmentIcons.gem_color(id) if EquipmentIcons.RING_GEMS.has(id) else Palette.TEXT
				UIArt.draw_glyph(c, EquipmentIcons.glyph_for(id), EquipmentIcons._inner(item.slot, icon), color))

	var center := Vector2(PAD + UNIT * 0.5, PAD + UNIT * 0.5)
	for id in UNBAKED_UNITS:
		await _bake_unit(id, center)


## One unit silhouette, drawn from the polygons about to be deleted.
##
## Twice, one file per side, because the polygons take the TEAM COLOUR and a
## single shared file would throw it away. That is not decoration: team colour is
## how the player tells whose unit it is, and `siege_engine` is a player summon
## while the other six are enemies. `UnitArt.texture_for` reads
## `<id>.player.png` and `<id>.enemy.png` before the shared name for exactly this.
##
## PHYSICAL accent because `UnitView._accent` gives every unit without a pawn
## class exactly that, and none of these has one.
func _bake_unit(id: StringName, center: Vector2) -> void:
	for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
		var side := "player" if team == CG.Team.PLAYER else "enemy"
		await _bake("res://Assets/Units/%s.%s.png" % [id, side], UNIT,
			func(c: CanvasItem) -> void:
				for part in Silhouettes.build_parts(id, UNIT_RADIUS, team,
						CG.DamageType.PHYSICAL, false, center):
					var fill: Color = part["fill"] if part["filled"] else Color(0, 0, 0, 0)
					UIArt.draw_outlined_polygon(c, part["points"], fill, part["outline"], UNIT_OUTLINE))


func _bake(path: String, side: int, job: Callable) -> void:
	_viewport.size = Vector2i(side + PAD * 2, side + PAD * 2)
	_painter.job = job
	_painter.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	# Crop the pad back off. The pad exists only so a stroke straddling the
	# outer edge is rendered rather than clipped by the viewport; the file has
	# to be exactly the box the code drew into, or every icon comes back a few
	# percent small once `draw_fit` scales the padding too.
	image = image.get_region(Rect2i(PAD, PAD, side, side))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	if image.save_png(path) != OK:
		push_error("BakeGlyphs: could not write %s" % path)
		return
	_written += 1
