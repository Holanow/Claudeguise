extends Node

## Issue 256: how much of the fix can a player ever SEE?
##
##   godot --path . --headless res://Tools/FacingVisible.tscn
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## Drawing the real facing is worth doing whatever this says -- the simulation
## decides the Warrior's guard on it. But "the units now face the right way" is a
## claim about the picture, and a left-right symmetric silhouette looks identical
## mirrored. So: for every shape the game fields, how many of its points move when
## it is flipped, and how far.
##
## Points rather than pixels because `build_parts` is what `draw_unit` draws and
## comparing its output asks the drawing itself rather than a rasterisation of it.

const CG := preload("res://Scripts/Core/CG.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")

func _ready() -> void:
	var ids: Array[StringName] = []
	for id in Registry.all_class_ids():
		ids.append(id)
	for id in Registry.all_enemy_ids():
		ids.append(id)
	var symmetric: Array[String] = []
	for id in ids:
		var a := Silhouettes.build_parts(id, 33.0, CG.Team.PLAYER, CG.DamageType.PHYSICAL, false)
		var b := Silhouettes.build_parts(id, 33.0, CG.Team.PLAYER, CG.DamageType.PHYSICAL, true)
		var moved := 0
		var total := 0
		var worst := 0.0
		for i in mini(a.size(), b.size()):
			# **The SET of points, not point i against point i.** Mirroring
			# reflects every x, so index-by-index every coordinate changes even
			# for a shape that maps exactly onto itself -- the first version of
			# this tool measured that and reported all fifteen shapes as fully
			# asymmetric, which is the "one degree off" failure this project
			# keeps paying for. What a player sees is whether the drawn shape
			# differs, so each mirrored point is matched to its nearest partner
			# in the unmirrored part.
			var pa: PackedVector2Array = a[i]["points"]
			var pb: PackedVector2Array = b[i]["points"]
			for j in pb.size():
				total += 1
				var nearest := 1000000.0
				for k in pa.size():
					nearest = minf(nearest, pa[k].distance_to(pb[j]))
				if nearest > 0.5:
					moved += 1
					worst = maxf(worst, nearest)
		if moved == 0:
			symmetric.append(String(id))
		print("FacingVisible %-16s %d of %d points land somewhere new when mirrored, furthest %.1f px at radius 33" % [
			id, moved, total, worst])
	print("FacingVisible: %d of %d shapes are left-right identical: %s" % [
		symmetric.size(), ids.size(), ", ".join(symmetric)])
	get_tree().quit(0)
