extends SceneTree

## Issue 671: the Sellsword's look, baked once as AbilityVFX resources.
##
##   godot --headless --path . --script res://Tools/BakeSellswordVFX.gd
##
## He is a floor-1 ELITE, not a boss: polished, not loud. A professional
## soldier rather than a spellcaster finale. Strike deliberately gets almost
## nothing, because that contrast is what makes Crescent land.

const OUT := "res://Scripts/Content/VFX"

## Cold steel and a little arcane blue. Deliberately not the Geysermancer's
## water and not Immolate's fire -- an elite should read as its own thing.
const STEEL := Color(0.86, 0.90, 0.98)
const ARCANE := Color(0.40, 0.58, 0.92)

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
	_strike()
	_seeker_bolts()
	_crescent()
	quit(0)

## Almost nothing, on purpose.
func _strike() -> void:
	var glow := GlowPulseLayer.new()
	glow.cue = VFXLayer.Cue.IMPACT
	glow.colour = STEEL
	glow.size = 60.0
	glow.seconds = 0.10

	var nudge := ScreenShakeLayer.new()
	nudge.cue = VFXLayer.Cue.IMPACT
	nudge.pixels = 3.0

	var vfx := AbilityVFX.new()
	vfx.display_name = "Strike"
	vfx.layers = [glow, nudge] as Array[VFXLayer]
	_save(vfx, "%s/sellsword_strike.tres" % OUT)

## The bolts are drawn by the projectile layer already. What VFX adds is the
## arrival: a small cool bloom and a few sparks per bolt, so two hits read as
## two events rather than one number changing twice.
func _seeker_bolts() -> void:
	var glow := GlowPulseLayer.new()
	glow.cue = VFXLayer.Cue.IMPACT
	glow.colour = ARCANE
	glow.size = 54.0
	glow.seconds = 0.12

	var sparks := EmberBurstLayer.new()
	sparks.cue = VFXLayer.Cue.IMPACT
	sparks.colour_hot = STEEL
	sparks.colour_cool = ARCANE
	sparks.amount = 14
	sparks.speed = 150.0
	sparks.lifetime = 0.4
	sparks.gravity = Vector2(0, 90)

	# No shake and no hit stop. A bolt is a plink; spending the heavy cues here
	# would leave nothing for Crescent.
	var vfx := AbilityVFX.new()
	vfx.display_name = "Seeker Bolts"
	vfx.layers = [glow, sparks] as Array[VFXLayer]
	_save(vfx, "%s/sellsword_seeker_bolts.tres" % OUT)

## The signature. The arc is drawn at the action's own numbers -- 65 units and
## 65 degrees either side -- so what is drawn is what is hit.
func _crescent() -> void:
	var charge := ChargeOrbLayer.new()
	charge.cue = VFXLayer.Cue.WIND_UP
	charge.inner_colour = STEEL
	charge.outer_colour = ARCANE
	charge.size = 74.0

	var arc := ArcSweepLayer.new()
	arc.cue = VFXLayer.Cue.RELEASE
	arc.edge_colour = Color(0.52, 0.72, 1.0)
	arc.core_colour = Color(1.0, 1.0, 1.0)
	arc.radius = 65.0
	arc.half_arc_degrees = 65.0

	# The sweep takes this long to cross the arc, so what happens to the
	# targets waits for the blade to reach them.
	var arrival := 0.09

	# Small, and it lands ON the struck body rather than over the whole arc.
	# At 72 it washed the sweep out completely -- the skill's own warning that
	# additive over a large area blows out to white and loses all shape.
	var glow := GlowPulseLayer.new()
	glow.cue = VFXLayer.Cue.IMPACT
	glow.delay = arrival
	glow.colour = STEEL
	glow.size = 40.0
	glow.seconds = 0.12

	var sparks := EmberBurstLayer.new()
	sparks.cue = VFXLayer.Cue.IMPACT
	sparks.delay = arrival
	sparks.colour_hot = STEEL
	sparks.colour_cool = ARCANE
	sparks.amount = 26
	sparks.speed = 240.0
	sparks.lifetime = 0.55
	sparks.gravity = Vector2(0, 200)

	var shake := ScreenShakeLayer.new()
	shake.cue = VFXLayer.Cue.IMPACT
	shake.delay = arrival
	shake.pixels = 9.0

	var stop := HitStopLayer.new()
	stop.cue = VFXLayer.Cue.IMPACT
	stop.delay = arrival

	var vfx := AbilityVFX.new()
	vfx.display_name = "Crescent"
	vfx.layers = [charge, arc, glow, sparks, shake, stop] as Array[VFXLayer]
	_save(vfx, "%s/sellsword_crescent.tres" % OUT)
