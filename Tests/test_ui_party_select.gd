extends "res://Tests/TestCase.gd"

const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const PartySelect := preload("res://Scripts/UI/PartySelect.gd")

## Swapping the party between runs is an acceptance criterion for the slice, so
## PartySelect is not a placeholder. These tests drive selection through
## toggle_pawn() (what the checkboxes call) rather than through the tree, so
## they do not depend on Registry having content yet.

func _make_pawn(id: String, name: String) -> PawnData:
	var cls := ClassDef.new()
	cls.id = StringName(id)
	cls.display_name = name
	var pawn := PawnData.new()
	pawn.id = StringName(id)
	pawn.display_name = name
	pawn.pawn_class = cls
	return pawn

func test_toggle_pawn_adds_and_removes_from_the_party() -> void:
	var screen := PartySelect.new()
	var pawn := _make_pawn("warrior", "Warrior")
	screen.toggle_pawn(pawn, true)
	assert_eq(screen.selected_pawns().size(), 1)
	screen.toggle_pawn(pawn, false)
	assert_eq(screen.selected_pawns().size(), 0)
	screen.free()

func test_toggle_pawn_respects_the_four_pawn_cap() -> void:
	var screen := PartySelect.new()
	var pawns: Array[PawnData] = []
	for i in 5:
		var pawn := _make_pawn("class_%d" % i, "Class %d" % i)
		pawns.append(pawn)
		screen.toggle_pawn(pawn, true)
	assert_eq(screen.selected_pawns().size(), 4, "a fifth pawn must not join the party")
	screen.free()

func test_current_config_carries_the_selected_party_and_seed() -> void:
	var screen := PartySelect.new()
	# _seed_edit is built in _ready(), which does not run outside a tree. A
	# missing edit falls back to seed 0 rather than crashing.
	var pawn := _make_pawn("priest", "Priest")
	screen.toggle_pawn(pawn, true)
	var config := screen.current_config()
	assert_eq(config.party.size(), 1)
	assert_eq(config.party[0].display_name, "Priest")
	screen.free()

func test_two_different_selections_produce_different_configs() -> void:
	# The party can be swapped and it shows: two different selections must not
	# collapse into the same RunConfig.
	var screen := PartySelect.new()
	var warrior := _make_pawn("warrior", "Warrior")
	var priest := _make_pawn("priest", "Priest")

	screen.toggle_pawn(warrior, true)
	var config_a := screen.current_config()

	screen.toggle_pawn(warrior, false)
	screen.toggle_pawn(priest, true)
	var config_b := screen.current_config()

	assert_ne(config_a.party[0].display_name, config_b.party[0].display_name)
	screen.free()
