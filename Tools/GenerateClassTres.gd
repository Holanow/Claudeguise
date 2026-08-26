extends SceneTree

## Scratch, issue 628: writes each ClassDef built by `starting_classes.gd` out
## as a `.tres`, so that the fifty values move themselves rather than by hand.

const OUT_DIR := "res://Scripts/Content/Classes"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var mod := load("res://Scripts/Content/Modules/starting_classes.gd")
	for c in mod.classes():
		var path := "%s/%s.tres" % [OUT_DIR, c.id]
		var err := ResourceSaver.save(c, path)
		print("%s  %s" % ["ok " if err == OK else "FAIL", path])
	quit()
