extends RefCounted

const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PresetPlans := preload("res://Scripts/Content/PresetPlans.gd")

## Builds a starter PawnData for a class: the class definition plus its two
## preset plans, no equipment and no attribute bonuses. Equipment generation is
## out of scope for this slice per issue 2, so this is the only way a
## fightable pawn gets made right now.
##
## Not part of the Registry module contract (Registry composes content
## definitions, not live pawn instances), but lives under Scripts/Content/
## because it is content, and both this issue's tests and whatever builds the
## party-select roster need it.
##
## OWNER: teal.

static func make_starter_pawn(class_id: StringName, pawn_id: StringName, display_name: String) -> PawnData:
	var pawn := PawnData.new()
	pawn.id = pawn_id
	pawn.display_name = display_name
	pawn.pawn_class = Registry.get_class_def(class_id)
	pawn.plans = PresetPlans.for_class(class_id)
	return pawn
