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
var _lifetime: float = LIFETIME_SECONDS
var _font_size: int = Palette.FONT_SIZE_FLOATER

func show_amount(amount: int, color: Color, font_size: int = Palette.FONT_SIZE_FLOATER) -> void:
	show_text(str(amount), color, LIFETIME_SECONDS, font_size)

## A death marker uses this directly: longer on screen than a damage number
## and its own font size, so "someone just died" reads as a distinct kind of
## event rather than another floating number.
func show_text(text: String, color: Color, lifetime: float = LIFETIME_SECONDS, font_size: int = Palette.FONT_SIZE_FLOATER) -> void:
	_text = text
	_color = color
	_age = 0.0
	_lifetime = lifetime
	_font_size = font_size
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	position.y -= RISE_SPEED * delta
	if _age >= _lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _text == "":
		return
	var alpha := clampf(1.0 - _age / _lifetime, 0.0, 1.0)
	var c := _color
	c.a = alpha
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
	draw_string(font, Vector2(-text_size.x * 0.5, 0.0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, c)
