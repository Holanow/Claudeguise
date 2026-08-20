extends "res://Tests/TestCase.gd"


## Cosmetic and wall-clock driven. It must never feed anything back into the
## simulation, so these tests only check its own rise-and-fade lifecycle.

func test_show_amount_starts_processing() -> void:
	var f := DamageFloater.new()
	assert_false(f.is_processing())
	f.show_amount(7, Color.WHITE)
	assert_true(f.is_processing())
	f.free()

func test_process_rises_and_ages() -> void:
	var f := DamageFloater.new()
	f.show_amount(7, Color.WHITE)
	var start_y := f.position.y
	f._process(0.1)
	assert_true(f.position.y < start_y, "a floater must rise, not fall")
	f.free()

func test_floater_frees_itself_after_its_lifetime() -> void:
	var f := DamageFloater.new()
	f.show_amount(7, Color.WHITE)
	f._process(10.0)
	assert_true(f.is_queued_for_deletion())

func test_show_text_respects_a_longer_custom_lifetime() -> void:
	# A death marker asks for more time on screen than a damage number. It
	# must still be alive after the default lifetime has passed.
	var f := DamageFloater.new()
	f.show_text("Rat dies", Color.WHITE, 1.8)
	f._process(0.9)
	assert_false(f.is_queued_for_deletion(), "a 1.8s marker must outlive the 0.9s default lifetime")
	f._process(1.0)
	assert_true(f.is_queued_for_deletion())
	f.free()

## Issue 320. The one death the playtester caught on screen was "mid-grey at
## about 40% opacity": the old fade started at frame one, so a marker was
## already half gone by the time an eye reached it.
func test_a_death_marker_holds_full_opacity_before_it_fades() -> void:
	var f := DamageFloater.new()
	f.show_death("Warrior dies", Color.WHITE, 20)
	assert_true(f.death_marker, "BattleView stacks deaths by this flag")
	f._process(DamageFloater.DEATH_LIFETIME * 0.5)
	assert_eq(f.modulate.a, 1.0, "half way through its life a death must still be fully opaque")
	f._process(DamageFloater.DEATH_LIFETIME * 0.4)
	assert_true(f.modulate.a < 1.0, "it must still fade out rather than vanishing")
	assert_true(f.modulate.a > 0.0)
	f.free()

func test_a_damage_number_still_fades_from_the_first_frame() -> void:
	var f := DamageFloater.new()
	f.show_amount(7, Color.WHITE)
	f._process(DamageFloater.LIFETIME_SECONDS * 0.5)
	assert_true(f.modulate.a < 1.0, "show_death's hold must not have leaked onto damage numbers")
	f.free()

func test_alpha_at_holds_then_falls_to_zero() -> void:
	assert_eq(DamageFloater.alpha_at(0.0, 2.0, 0.0), 1.0)
	assert_eq(DamageFloater.alpha_at(1.0, 2.0, 0.0), 0.5)
	assert_eq(DamageFloater.alpha_at(1.4, 2.0, 0.7), 1.0)
	assert_eq(DamageFloater.alpha_at(2.0, 2.0, 0.7), 0.0)

## A death outlives a damage number by enough to be noticed at all.
func test_a_death_marker_outlives_a_damage_number() -> void:
	assert_true(DamageFloater.DEATH_LIFETIME > DamageFloater.LIFETIME_SECONDS * 2.0)

func test_show_amount_still_uses_the_default_lifetime() -> void:
	var f := DamageFloater.new()
	f.show_amount(7, Color.WHITE)
	f._process(0.9)
	assert_true(f.is_queued_for_deletion(), "show_amount must not have inherited a stale custom lifetime")
