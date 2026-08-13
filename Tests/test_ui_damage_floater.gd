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
