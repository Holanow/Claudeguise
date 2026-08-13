extends "res://Tests/TestCase.gd"

const DamageFloater := preload("res://Scripts/UI/DamageFloater.gd")

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

func test_show_amount_still_uses_the_default_lifetime() -> void:
	var f := DamageFloater.new()
	f.show_amount(7, Color.WHITE)
	f._process(0.9)
	assert_true(f.is_queued_for_deletion(), "show_amount must not have inherited a stale custom lifetime")
