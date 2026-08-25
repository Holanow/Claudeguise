extends SceneTree

## Issue 566. How much of its own canvas each unit's art fills, recipe and
## drawing side by side. I reported the composed units as drawing SMALLER than
## the hand-drawn ones off a glance at a contact sheet; this asks the question
## of the pixels instead.

func _init() -> void:
	var radius := 40.0
	print("  %-18s %-7s %6s %6s   %s" % ["shape", "source", "fillX", "fillY", "extent at r=40"])
	for id in Silhouettes.shape_ids():
		for team in [CG.Team.PLAYER, CG.Team.ENEMY]:
			var tex := UnitArt.texture_for(id, team)
			if tex == null:
				continue
			var frac := UnitArt.opaque_fraction(tex)
			var box := Silhouettes.drawn_extent(id, radius, team)
			print("  %-18s %-7s %6.2f %6.2f   %5.1f x %5.1f" % [
				id, "recipe" if UnitRecipes.has_recipe(id) else "png",
				frac.x, frac.y, box.size.x, box.size.y])
			break
	quit(0)
