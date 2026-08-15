extends Node
const UnitView := preload("res://Scripts/UI/UnitView.gd")
func _ready() -> void:
	for pair in [[&"goblin", 11.0], [&"goblin_archer", 11.0], [&"ghoul", 11.0], [&"rat", 9.0], [&"warrior", 22.0], [&"abomination", 22.0]]:
		var id: StringName = pair[0]
		var r: float = pair[1] * UnitView.DISPLAY_SCALE
		var box := UnitView.drawn_extent(id)
		print("%-14s footprint %5.1f wide | drawn %5.1f wide | bar was %5.1f now %5.1f | top was %5.1f now %5.1f" % [
			id, r * 2.0, UnitView.drawn_half_width(id, r) * 2.0,
			clampf(r * 2.0, UnitView.MIN_BAR_WIDTH, UnitView.BAR_WIDTH * UnitView.DISPLAY_SCALE),
			UnitView.bar_width(r, id), r, UnitView.drawn_top(id, r)])
	get_tree().quit(0)
