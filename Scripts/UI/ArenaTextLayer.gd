extends Node2D
class_name ArenaTextLayer

## Issue 321: every word drawn over the arena, and every node that draws one,
## lives here -- the last child of the arena, so nothing a unit wears can be
## painted over a name.

var state: CombatState = null

## Issue 511: where each body sat at the tick the layout was solved at, and
## where it is drawn this frame. The rows themselves are still decided once per
## tick, against the simulated positions; only the chip and its tether slide.
var tick_at: Dictionary = {}
var frame_at: Dictionary = {}

func sync(s: CombatState) -> void:
	state = s
	queue_redraw()

func set_positions(was: Dictionary, now: Dictionary) -> void:
	tick_at = was
	frame_at = now
	queue_redraw()

func _draw() -> void:
	if state == null or not DisplayOptions.enabled(&"name_plates"):
		return
	var layout := UnitView.plate_layout(state)
	for id in layout:
		var u := state.unit(int(id))
		if u == null or not u.alive:
			continue
		var chip: Rect2 = layout[id]
		var body = frame_at.get(id)
		var was = tick_at.get(id)
		if body != null and was != null:
			chip.position += body - was
			# The layout clamped this chip into the arena; sliding it can push it
			# back out, and issue 378 is that nothing drawn may leave the arena.
			chip.position += UnitView.into_arena(chip)
		UnitView.draw_plate_tether(self, u, state.units, chip,
			body if body != null else UnitView.RECOMPUTE_AT)
		UnitView.draw_label_chip(self, chip.position, u.display_name, Palette.TEXT,
			UnitView.label_font_size())
