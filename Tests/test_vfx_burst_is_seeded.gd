extends "res://Tests/TestCase.gd"


## Issue 907: `VFXDirector.burst` builds a `CPUParticles2D`, which picks its seed
## from the wall clock unless `use_fixed_seed` is set -- the defect #713 fixed
## for `ImpactBurst`'s `GPUParticles2D`. Rendered output is not testable here
## (the suite is headless and `frame_post_draw` never fires, #897), so this
## asserts the seed is fixed and repeats, not the pixels.

func _ember_vfx() -> AbilityVFX:
	var layer := EmberBurstLayer.new()
	layer.cue = VFXLayer.Cue.IMPACT
	var vfx := AbilityVFX.new()
	vfx.layers = [layer] as Array[VFXLayer]
	return vfx

## Every burst of one director, in order, as `use_fixed_seed` and `seed` pairs.
func _seeds_of(vfx: AbilityVFX, plays: Array) -> Array:
	var director: VFXDirector = in_tree(VFXDirector.new())
	for p in plays:
		director.play(vfx, VFXLayer.Cue.IMPACT, p[0], p[1], 0.0)
	var out := []
	for child in director.get_children():
		var particles := child as CPUParticles2D
		if particles != null:
			out.append([particles.use_fixed_seed, particles.seed])
	return out


func test_a_burst_is_seeded_and_two_directors_agree() -> void:
	var vfx := _ember_vfx()
	var plays := [[1, 2], [1, 3], [2, 1]]
	var first := _seeds_of(vfx, plays)
	var second := _seeds_of(vfx, plays)
	assert_eq(first.size(), 3, "one CPUParticles2D per play")
	for pair in first:
		assert_true(pair[0], "every burst must set use_fixed_seed")
	assert_eq(first, second,
		"two directors played the same sequence must seed their particles the same")

func test_two_bursts_in_one_fight_do_not_share_a_seed() -> void:
	var seeds := []
	for pair in _seeds_of(_ember_vfx(), [[1, 2], [1, 2], [1, 2]]):
		seeds.append(pair[1])
	assert_eq(seeds.size(), 3, "one CPUParticles2D per play")
	var unique := {}
	for s in seeds:
		unique[s] = true
	assert_eq(unique.size(), 3,
		"the same pair hitting three times must not throw identical debris")
