extends Node2D
class_name DamageFloater


## A number that rises off a unit and fades. Coloured by damage type through
## Palette.damage_color.

const LIFETIME_SECONDS := 0.9
const RISE_SPEED := 40.0

## Issue 320. A death used to fade from the first frame, so the playtester's one
## sighting was "mid-grey at about 40% opacity" over a hatched hazard floor.
const DEATH_LIFETIME := 2.4
const DEATH_HOLD := 0.7
const PLATE_PAD := Vector2(10.0, 5.0)

var _text: String = ""
var _color: Color = Palette.TEXT
var _age: float = 0.0
var _lifetime: float = LIFETIME_SECONDS
var _font_size: int = Palette.FONT_SIZE_FLOATER
## Fraction of the lifetime spent fully opaque before the fade begins.
var _hold: float = 0.0
var _plate: StyleBox = null

## True on a marker announcing a death, so BattleView can stack this frame's
## deaths into a column instead of printing them over each other.
var death_marker: bool = false

func show_amount(amount: int, color: Color, font_size: int = Palette.FONT_SIZE_FLOATER) -> void:
	show_text(str(amount), color, LIFETIME_SECONDS, font_size)

## A death, on an opaque plate and held at full opacity for most of its life.
## `Assets/UI/panel/death.png` replaces the plate; without it the plate is a
## `StyleBoxFlat` in the background colour, which is what neutralises the floor.
func show_death(text: String, color: Color, font_size: int) -> void:
	death_marker = true
	_plate = UIArt.panel_style(&"death", Palette.BACKGROUND, color, 2)
	_hold = DEATH_HOLD
	show_text(text, color, DEATH_LIFETIME, font_size)

## A death marker uses this directly: longer on screen than a damage number
## and its own font size, so "someone just died" reads as a distinct kind of
## event rather than another floating number.
func show_text(text: String, color: Color, lifetime: float = LIFETIME_SECONDS, font_size: int = Palette.FONT_SIZE_FLOATER) -> void:
	_text = text
	_color = color
	_age = 0.0
	_lifetime = lifetime
	_font_size = font_size
	modulate.a = 1.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	position.y -= RISE_SPEED * delta
	if _age >= _lifetime:
		queue_free()
		return
	modulate.a = alpha_at(_age, _lifetime, _hold)
	queue_redraw()

## Full opacity until `hold` of the lifetime has passed, then linear to zero.
## `hold` of 0 is the plain fade a damage number has always had.
static func alpha_at(age: float, lifetime: float, hold: float) -> float:
	if lifetime <= 0.0:
		return 0.0
	return clampf((1.0 - age / lifetime) / (1.0 - hold), 0.0, 1.0)

func _draw() -> void:
	if _text == "":
		return
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
	var origin := Vector2(-text_size.x * 0.5, 0.0)
	if _plate != null:
		var ascent := font.get_ascent(_font_size)
		var descent := font.get_descent(_font_size)
		_plate.draw(get_canvas_item(), Rect2(
			origin.x - PLATE_PAD.x, origin.y - ascent - PLATE_PAD.y,
			text_size.x + PLATE_PAD.x * 2.0, ascent + descent + PLATE_PAD.y * 2.0))
	draw_string(font, origin, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, _color)
