extends Node2D

const Palette := preload("res://Scripts/Core/Palette.gd")

## A number that rises off a unit and fades. Coloured by damage type through
## Palette.damage_color.
##
## OWNER: pike.
##
## Purely cosmetic and driven by wall clock, not by ticks. It must never feed
## anything back into the simulation.

func show_amount(amount: int, color: Color) -> void:
	push_error("DamageFloater.show_amount is not implemented yet (issue 3, owner pike)")
