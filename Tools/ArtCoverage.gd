extends SceneTree

## Issue 280. **Are `Silhouettes.build_parts` polygons dead everywhere, or only
## for the shapes that have a PNG?**
##
##     godot --headless --path . --script res://Tools/ArtCoverage.gd
##
## sable. Measurement only, never gated. `draw_unit` takes the PNG when
## `UnitArt.texture_for` returns one and the polygons otherwise, so the question
## is answered by asking `texture_for` for every id the game can put on screen:
## every class id, every enemy id (including summons, which are enemy defs), and
## every `_PARTS` key. An id with no PNG and no polygon draws the unknown
## diamond, which is a third path and is also not dead.

const CG := preload("res://Scripts/Core/CG.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")
const UnitArt := preload("res://Scripts/Art/UnitArt.gd")

func _init() -> void:
	var poly_ids := {}
	for id in Silhouettes.shape_ids():
		poly_ids[id] = true

	var spawnable := {}
	for id in Registry.all_class_ids():
		spawnable[id] = "class"
	for id in Registry.all_enemy_ids():
		spawnable[id] = "enemy"

	var png_only: Array[String] = []
	var poly_drawn: Array[String] = []
	var unknown_drawn: Array[String] = []

	var ids := spawnable.keys()
	ids.sort()
	for id in ids:
		var player := UnitArt.has_art(id, CG.Team.PLAYER)
		var enemy := UnitArt.has_art(id, CG.Team.ENEMY)
		var line := "%-18s %-6s png(player)=%s png(enemy)=%s polygons=%s" % [
			id, spawnable[id], player, enemy, poly_ids.has(id)]
		if player and enemy:
			png_only.append(line)
		elif poly_ids.has(id):
			poly_drawn.append(line)
		else:
			unknown_drawn.append(line)

	print("=== spawnable ids drawn from a PNG on both sides (polygons dead) ===")
	for l in png_only:
		print("  " + l)
	print("=== spawnable ids drawn from build_parts polygons (LIVE) ===")
	for l in poly_drawn:
		print("  " + l)
	print("=== spawnable ids with neither: _unknown_parts diamond ===")
	for l in unknown_drawn:
		print("  " + l)

	var unused: Array[String] = []
	for id in Silhouettes.shape_ids():
		if not spawnable.has(id):
			unused.append(str(id))
	unused.sort()
	print("=== _PARTS keys nothing can spawn: %s ===" % str(unused))
	print("totals: spawnable=%d png=%d polygon=%d diamond=%d parts_keys=%d" % [
		ids.size(), png_only.size(), poly_drawn.size(), unknown_drawn.size(),
		Silhouettes.shape_ids().size()])
	quit(0)
