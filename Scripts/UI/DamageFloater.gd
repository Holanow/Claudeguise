extends Node2D

const Palette := preload("res://Scripts/Core/Palette.gd")

## A number that rises off a unit and fades. Coloured by damage type through
## Palette.damage_color.
##
## OWNER: pike.
##
## Purely cosmetic and driven by wall clock, not by ticks. It must never feed
## anything back into the simulation.

const LIFETIME_SECONDS := 0.9
const RISE_SPEED := 40.0

var _text: String = ""
var _color: Color = Palette.TEXT
var _age: float = 0.0

func show_amount(amount: int, color: Color) -> void:
	_text = str(amount)
	_color = color
	_age = 0.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	position.y -= RISE_SPEED * delta
	if _age >= LIFETIME_SECONDS:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _text == "":
		return
	var alpha := clampf(1.0 - _age / LIFETIME_SECONDS, 0.0, 1.0)
	var c := _color
	c.a = alpha
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-10.0, 0.0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SIZE_FLOATER, c)
