extends Node2D
class_name DeathExplosion

## Issue 589. A dead unit's own head, body and hands, thrown.
##
## The player: "Units should explode violently when they die". #566 made a unit
## a stack of parts and #583 cut that stack at the parts that move; this cuts it
## again, into chunks, and the chunks are what fly. So an exploding goblin
## scatters a goblin rather than a generic puff.
##
## One pool, one canvas item, and `advance` is spent by `BattleView._render` for
## the same reason #516's decay is: a frozen frame never reaches that line.

const OPTION := &"death_explosion"

## How many deaths may be in the air at once. Measured, not guessed:
## `Tools/GibCost.gd` reports the worst overlap a real fight produces and this
## is set above it. Past the cap the oldest explosion is recycled, so a scrum
## cannot grow the live count however many bodies drop into it.
const POOL := 12

## How long a chunk flies, and when it starts going. Longer than #517's 0.35 s
## debris on purpose: debris marks a moment, and this one has to be followed.
const LIFETIME := 0.85
const FADE_AFTER := 0.45

## Arena pixels a second at the instant of the death, across the fan.
const LAUNCH_MIN := 190.0
const LAUNCH_MAX := 340.0

## How wide the chunks fan out, in radians, centred straight up.
const FAN := 2.2

## Extra throw a chunk gets for sitting high on the body, per pixel of height
## above the body's centre. A head leaves faster than a foot.
const PIVOT_THROW := 2.4

const GRAVITY := 780.0

## Air, as a share of speed shed each second. Under 1.0 the launch reads as a
## burst rather than as a constant slide.
const DRAG := 1.9

## Turns a second at the fastest. Signed per chunk, so they do not all spin the
## same way.
const SPIN := 2.6

var _slots: Array = []
var _next: int = 0

func _ready() -> void:
	for i in POOL:
		_slots.append({"age": INF, "fresh": false, "origin": Vector2.ZERO,
			"radius": 0.0, "facing": false, "pieces": []})

## Throws `fragments` -- `UnitArt.fragments_for`'s output, one entry per slot --
## apart from `at`.
## Refused while the option is off, the same gate `UnitView.struck` applies, so
## nothing can start an effect that will never be drawn.
func explode(at: Vector2, radius: float, facing_left: bool, fragments: Array, unit_id: int) -> void:
	if not DisplayOptions.enabled(OPTION) or fragments.is_empty():
		return
	var slot: Dictionary = _slots[_next]
	_next = (_next + 1) % _slots.size()
	slot["age"] = 0.0
	# Frame 0 is the body exactly where it stood. The 0.10 s hit stop a death
	# already fires (#515) then holds THAT rather than the hole it used to hold,
	# and the chunks leave on the frame the freeze lifts.
	slot["fresh"] = true
	slot["origin"] = at
	slot["radius"] = radius
	slot["facing"] = facing_left
	slot["pieces"] = _pieces(radius, facing_left, fragments, unit_id)
	queue_redraw()

func _pieces(radius: float, facing_left: bool, fragments: Array, unit_id: int) -> Array:
	var out: Array = []
	var jitter := PartAnimation.phase_for(unit_id)
	for i in fragments.size():
		var parts: Array = fragments[i]["pieces"]
		var pivot := _ink_center(radius, parts)
		if facing_left:
			pivot.x = -pivot.x
		# Fanned rather than thrown along the chunk's own offset: the Hands slot
		# holds a hand each side, so its ink is centred on the body and has no
		# direction of its own to be thrown along.
		var t := (float(i) + 0.5) / float(fragments.size())
		var angle := -PI * 0.5 + (t - 0.5) * FAN + sin(jitter + float(i)) * 0.22
		if facing_left:
			angle = -PI - angle
		var speed := lerpf(LAUNCH_MIN, LAUNCH_MAX, fposmod(jitter * 0.37 + float(i) * 0.41, 1.0))
		out.append({
			"parts": parts,
			"pivot": pivot,
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(angle), sin(angle)) * speed + Vector2(0.0, pivot.y * PIVOT_THROW),
			"angle": 0.0,
			"spin": SPIN * TAU * (fposmod(jitter + float(i) * 0.7, 2.0) - 1.0),
		})
	return out

## Where a chunk's ink sits, in the space it is drawn into: the union of the
## parts in it. A slot holding a head and its eyes tumbles about the head rather
## than about the canvas the parts share.
static func _ink_center(radius: float, parts: Array) -> Vector2:
	var box := Rect2()
	var any := false
	for part in parts:
		var r := UnitArt.opaque_rect(radius, part["tex"])
		box = r if not any else box.merge(r)
		any = true
	return box.get_center()

## Spent by `BattleView._render`, never by a `_process` of this node's own. The
## guard is here as well because this is the fifth effect to have to honour it
## and the check is one line: #528 and #535 closed the class for the floaters,
## the flashes, the debris and the death markers.
func advance(delta: float) -> void:
	if ViewClock.frozen:
		return
	var moved := false
	for slot in _slots:
		if slot["age"] >= LIFETIME:
			continue
		if slot["fresh"]:
			slot["fresh"] = false
			moved = true
			continue
		slot["age"] += delta
		for piece in slot["pieces"]:
			piece["vel"] += Vector2(0.0, GRAVITY) * delta
			piece["vel"] -= piece["vel"] * minf(1.0, DRAG * delta)
			piece["pos"] += piece["vel"] * delta
			piece["angle"] += piece["spin"] * delta
		moved = true
	if moved:
		queue_redraw()

## Everything drops at once. A restart reuses unit ids, so an explosion left
## running would be a body from the last fight.
func clear() -> void:
	for slot in _slots:
		slot["age"] = INF
		slot["fresh"] = false
		slot["pieces"] = []
	_next = 0
	queue_redraw()

## How many chunks are in the air. The instruments read this; nothing in the
## view does.
func live_pieces() -> int:
	var n := 0
	for slot in _slots:
		if slot["age"] < LIFETIME:
			n += slot["pieces"].size()
	return n

func live_explosions() -> int:
	var n := 0
	for slot in _slots:
		if slot["age"] < LIFETIME:
			n += 1
	return n

static func alpha_at(age: float) -> float:
	if age < FADE_AFTER:
		return 1.0
	return clampf(1.0 - (age - FADE_AFTER) / (LIFETIME - FADE_AFTER), 0.0, 1.0)

## How dark a chunk goes once it is in the air, and how fast it gets there. It
## LEAVES at full colour, so the frozen frame the death holds is the body
## exactly; it darkens as it flies.
##
## Measured against the picture rather than chosen: on `sable_589_..._scrum.png`
## a goblin's head tumbles through a crowd of goblins, and the two cues that
## separate wreckage from a unit are that wreckage carries no bar and that it is
## not the colour a live goblin is.
const DIM := 0.55
const DIM_SECONDS := 0.14

static func tint_at(age: float) -> Color:
	var k := lerpf(1.0, DIM, clampf(age / DIM_SECONDS, 0.0, 1.0))
	return Color(k, k, k, alpha_at(age))

func _draw() -> void:
	# The same filter `UnitArt.draw` sets, and for the same reason: these are the
	# body's own textures and linear filtering smudges them at the size a unit
	# is actually drawn.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for slot in _slots:
		var age: float = slot["age"]
		if age >= LIFETIME:
			continue
		var tint := tint_at(age)
		for piece in slot["pieces"]:
			var pivot: Vector2 = piece["pivot"]
			# Rotated about the chunk's own ink, not about the canvas its parts
			# were authored on: a head is nowhere near the middle of that canvas,
			# and spinning the canvas makes it orbit rather than tumble.
			draw_set_transform(slot["origin"] + piece["pos"] + pivot, piece["angle"], Vector2.ONE)
			for part in piece["parts"]:
				var tex: Texture2D = part["tex"]
				var rect := UnitArt.signed_rect(tex, slot["radius"], slot["facing"])
				draw_texture_rect(tex, Rect2(rect.position - pivot, rect.size), false,
					(part["color"] as Color) * tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
