extends Node
const UnitView := preload("res://Scripts/UI/UnitView.gd")
const Silhouettes := preload("res://Scripts/Art/Silhouettes.gd")
const CG := preload("res://Scripts/Core/CG.gd")
## Issue 190: the ratio between decoration and unit, per shape, both axes.
func _ready() -> void:
	print("shape           fill_w fill_h | footprint | bar  | top  | badge")
	for row in [[&"goblin", 11.0, CG.Team.ENEMY], [&"goblin_archer", 11.0, CG.Team.ENEMY],
			[&"ghoul", 11.0, CG.Team.ENEMY], [&"rat", 9.0, CG.Team.ENEMY],
			[&"the_warden", 26.0, CG.Team.ENEMY],
			[&"warrior", 22.0, CG.Team.PLAYER], [&"priest", 22.0, CG.Team.PLAYER],
			[&"geysermancer", 22.0, CG.Team.PLAYER], [&"siege_master", 22.0, CG.Team.PLAYER],
			[&"abomination", 22.0, CG.Team.PLAYER]]:
		var id: StringName = row[0]
		var r: float = row[1] * UnitView.DISPLAY_SCALE
		var team: CG.Team = row[2]
		var fill := Silhouettes.fill_ratio(id, team)
		print("%-14s %.2f  %.2f  | %5.1f     | %4.1f | %4.1f | %4.1f" % [
			id, fill.x, fill.y, r * 2.0,
			UnitView.bar_width(r, id, team),
			UnitView.drawn_top(id, team, r),
			UnitView.status_badge_size(id, team, r)])
	get_tree().quit(0)
