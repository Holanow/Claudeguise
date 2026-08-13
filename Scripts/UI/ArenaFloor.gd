extends Node2D

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")

## The ground a fight happens on: a floor filling the play area, a boundary at
## the simulated bounds, and a faint grid for a sense of scale.
##
## OWNER: pike.
##
## Attached to the Arena node itself, so it is drawn in the same local space
## that _layout_arena positions and scales — the drawn rectangle is
## CG.ARENA_HALF_WIDTH/HEIGHT, the same constants the simulation places units
## within, not a second guess at the same numbers.
##
## Kept quieter than the units on purpose: low alpha on the grid and centre
## lines, and the boundary is a thin outline rather than a filled shape.

const GRID_SPACING := 60.0
const BOUNDARY_WIDTH := 2.0
const GRID_ALPHA := 0.16
const CENTER_LINE_ALPHA := 0.3

func _draw() -> void:
	var hw := CG.ARENA_HALF_WIDTH
	var hh := CG.ARENA_HALF_HEIGHT

	draw_rect(Rect2(Vector2(-hw, -hh), Vector2(hw * 2.0, hh * 2.0)), Palette.ARENA_FLOOR)

	var grid_color := Palette.ARENA_EDGE
	grid_color.a = GRID_ALPHA
	var gx := -hw
	while gx <= hw:
		draw_line(Vector2(gx, -hh), Vector2(gx, hh), grid_color, 1.0)
		gx += GRID_SPACING
	var gy := -hh
	while gy <= hh:
		draw_line(Vector2(-hw, gy), Vector2(hw, gy), grid_color, 1.0)
		gy += GRID_SPACING

	var center_color := Palette.ARENA_EDGE
	center_color.a = CENTER_LINE_ALPHA
	draw_line(Vector2(-hw, 0.0), Vector2(hw, 0.0), center_color, 1.0)
	draw_line(Vector2(0.0, -hh), Vector2(0.0, hh), center_color, 1.0)

	draw_rect(Rect2(Vector2(-hw, -hh), Vector2(hw * 2.0, hh * 2.0)), Palette.ARENA_EDGE, false, BOUNDARY_WIDTH)
