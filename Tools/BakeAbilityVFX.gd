extends SceneTree

## Authors the AbilityVFX resources. One shot, the way BakeParts is: run it
## once, then edit the `.tres` in the inspector like any other resource.
##
##   godot --headless --path . --script res://Tools/BakeAbilityVFX.gd

const OUT_DIR := "res://Scripts/Content/VFX"

func _save(res: Resource, path: String) -> Resource:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(res, path)
	if err != OK:
		printerr("could not save %s (%d)" % [path, err])
	else:
		print("wrote %s" % path)
	res.take_over_path(path)
	return res

func _initialize() -> void:
	_geyser_blast()
	_geyser_scald()
	quit(0)

## The player's framing, 2026-08-24: "Imagine that the root of the geyser is the
## caster's chest. Think Kamehameha."
func _geyser_blast() -> void:
	var core := Color(0.88, 0.98, 1.0)
	var deep := Color(0.13, 0.44, 0.85)

	var orb := ChargeOrbLayer.new()
	orb.cue = VFXLayer.Cue.WIND_UP
	orb.inner_colour = core
	orb.outer_colour = deep
	orb.size = 118.0

	# One beam per hand, each tracking its own. They converge on the target, so
	# the cast reads as two hands throwing it rather than one point on a chest.
	var left := BeamLayer.new()
	left.cue = VFXLayer.Cue.RELEASE
	left.core_colour = core
	left.edge_colour = deep
	left.width = 52.0
	left.hand_index = 0

	var right := BeamLayer.new()
	right.cue = VFXLayer.Cue.RELEASE
	right.core_colour = core
	right.edge_colour = deep
	right.width = 52.0
	right.hand_index = 1

	# The beam takes this long to arrive, so everything that happens ON the
	# target waits. Without it the goblin flinches before it is hit.
	var arrival := 0.07

	var glow := GlowPulseLayer.new()
	glow.cue = VFXLayer.Cue.IMPACT
	glow.delay = arrival
	glow.colour = core

	var ring := ShockRingLayer.new()
	ring.cue = VFXLayer.Cue.IMPACT
	ring.delay = arrival
	ring.ring_colour = Color(0.62, 0.9, 1.0)

	# Water falls. Fire's embers rise, and reusing them here read as steam.
	var spray := EmberBurstLayer.new()
	spray.cue = VFXLayer.Cue.IMPACT
	spray.delay = arrival
	spray.colour_hot = core
	spray.colour_cool = deep
	spray.gravity = Vector2(0, 420)
	spray.speed = 300.0
	spray.lifetime = 0.7

	var shake := ScreenShakeLayer.new()
	shake.cue = VFXLayer.Cue.IMPACT
	shake.delay = arrival
	shake.pixels = 13.0

	var stop := HitStopLayer.new()
	stop.cue = VFXLayer.Cue.IMPACT
	stop.delay = arrival

	var vfx := AbilityVFX.new()
	vfx.display_name = "Geyser Blast"
	vfx.layers = [orb, left, right, glow, ring, spray, shake, stop] as Array[VFXLayer]
	_save(vfx, "%s/geyser_blast.tres" % OUT_DIR)

## The cheap one, and the point of it: a second look reuses the same layers at
## different numbers. Scald is a jet, not a column, so it gets no ring and no
## hit stop -- those belong to the ability that is meant to feel heavy.
func _geyser_scald() -> void:
	var core := Color(0.95, 0.99, 1.0)
	var deep := Color(0.25, 0.62, 0.9)

	var beam := BeamLayer.new()
	beam.cue = VFXLayer.Cue.RELEASE
	beam.core_colour = core
	beam.edge_colour = deep
	beam.width = 40.0
	beam.hold_seconds = 0.05
	beam.fade_seconds = 0.14

	var glow := GlowPulseLayer.new()
	glow.cue = VFXLayer.Cue.IMPACT
	glow.delay = 0.05
	glow.colour = core
	glow.size = 66.0
	glow.seconds = 0.12

	var spray := EmberBurstLayer.new()
	spray.cue = VFXLayer.Cue.IMPACT
	spray.delay = 0.05
	spray.colour_hot = core
	spray.colour_cool = deep
	spray.amount = 18
	spray.speed = 170.0
	spray.lifetime = 0.5
	spray.gravity = Vector2(0, 380)

	var vfx := AbilityVFX.new()
	vfx.display_name = "Scald"
	vfx.layers = [beam, glow, spray] as Array[VFXLayer]
	_save(vfx, "%s/geyser_scald.tres" % OUT_DIR)
