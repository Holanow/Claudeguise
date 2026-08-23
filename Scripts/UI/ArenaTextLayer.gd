extends Node2D
class_name ArenaTextLayer

## Issue 321: every word drawn over the arena, and every node that draws one,
## lives here -- the last child of the arena, so nothing a unit wears can be
## painted over a name.

var state: CombatState = null

func sync(s: CombatState) -> void:
	state = s
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
		UnitView.draw_plate_tether(self, u, state.units, chip)
		UnitView.draw_label_chip(self, chip.position, u.display_name, Palette.TEXT,
			UnitView.label_font_size())
