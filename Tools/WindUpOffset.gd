extends Node


const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")

## Issue 241, wren's half: WHERE the wind-up bar sits relative to the body it
## belongs to, measured, for every shape in the game and for the Warden in a
## real fight.
##
##   godot --path . --resolution 1280x720 res://Tools/WindUpOffset.tscn
##
## Two halves, and the first is the one that answers the issue.
##
## **The arithmetic pass** reproduces `_draw_wind_up`'s geometry from the same
## public statics it uses, per shape, with no fight running. That is what makes
## the number reproducible: a pixel read off a screenshot depends on where the
## unit happened to stand.
##
## **The fight pass** then photographs the Warden mid-Axe so the arithmetic can
## be checked against something drawn. `floor1_warden` is the only room that
## fields it. Nothing is written onto the state.
##
## No --headless for the capture: `get_viewport().get_texture()` never
## populates under --headless on this machine (RoarShot's finding).
##
## It writes `Screenshots/wren_241_warden_windup.png`. The two files committed
## beside it, `_before` and `_after`, are that capture taken with and without
## the `UnitArt.draw` fix, renamed by hand so the pair survives the next run.
##
## Not part of the game and not part of the gate.

const OUT_DIR := "res://Screenshots"
const SETTLE_FRAMES := 4

## radius, team: the values `CombatSim` really builds these with, times
## DISPLAY_SCALE, which is what `UnitView` draws at.
const SHAPES := [
	[&"the_warden", 22.0, CG.Team.ENEMY],
	[&"rat_king", 20.0, CG.Team.ENEMY],
	[&"brute", 16.0, CG.Team.ENEMY],
	[&"goblin", 11.0, CG.Team.ENEMY],
	[&"goblin_archer", 11.0, CG.Team.ENEMY],
	[&"ghoul", 11.0, CG.Team.ENEMY],
	[&"rat", 9.0, CG.Team.ENEMY],
	[&"warrior", 22.0, CG.Team.PLAYER],
	[&"priest", 22.0, CG.Team.PLAYER],
	[&"geysermancer", 22.0, CG.Team.PLAYER],
	[&"siege_master", 22.0, CG.Team.PLAYER],
	[&"abomination", 22.0, CG.Team.PLAYER],
]

var _battle: Node = null
var _settle := -1
var _done := false
var _warden_id := -1

func _ready() -> void:
	_report()
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = &"floor1_warden"
	cfg.seed = 7
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ["warrior", "geysermancer", "priest", "siege_master"]:
		var c := StringName(cid)
		out.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, out.size()]), Registry.get_class_def(c).display_name
		))
	return out

## The wind-up block's own geometry in a unit's local space, origin at the
## unit's centre, positive x right and positive y down -- exactly the space
## `_draw_wind_up` draws into.
func _report() -> void:
	print("WindUpOffset: local space, origin = unit centre, +y down.")
	print("%-14s %6s %6s %7s | %7s %7s | %7s %7s %7s" % [
		"shape", "bodyW", "bodyH", "bodyCx", "barL", "barR", "barCx", "blockCx", "barTop"])
	for row in SHAPES:
		var id: StringName = row[0]
		var r: float = float(row[1]) * UnitView.DISPLAY_SCALE
		var team: CG.Team = row[2]
		var box := UnitView.drawn_box(id, team, r)
		var block_w := UnitView.bar_width(r, id, team)
		var icon := UnitView.wind_up_icon_size(r, id, team)
		var bar_w := UnitView.wind_up_bar_width(r, id, team)
		var block_left := -block_w * 0.5
		var bar_h := UnitView.BAR_HEIGHT * UnitView.DISPLAY_SCALE
		var top := UnitView.drawn_bottom(id, team, r) + UnitView.WIND_UP_TOP_GAP
		var bar_top := top + (icon - bar_h) * 0.5
		print("%-14s %6.1f %6.1f %7.1f | %7.1f %7.1f | %7.1f %7.1f %7.1f" % [
			id, box.size.x, box.size.y, box.get_center().x,
			block_left, block_left + bar_w,
			block_left + bar_w * 0.5, block_left + block_w * 0.5, bar_top])
	print("WindUpOffset: barCx is the cream bar's own centre. The player sees a")
	print("  bar, and the icon beside it is a different colour and shape.")

func _process(_delta: float) -> void:
	if _battle == null or _done:
		return
	var state = _battle.state
	if state == null:
		return
	if _settle < 0:
		for u in state.units:
			if u.alive and u.enemy_id == &"the_warden" and u.action_ticks_left > 0 \
					and u.current_action == &"warden_axe":
				_warden_id = u.id
				_settle = 0
				break
		return
	if _settle < SETTLE_FRAMES:
		_settle += 1
		return
	var w = state.unit(_warden_id)
	if w == null or w.action_ticks_left <= 0 or w.current_action != &"warden_axe":
		_settle = -1
		return
	_done = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/wren_241_warden_windup.png" % OUT_DIR
	image.save_png(path)
	print("WindUpOffset: %s at tick %d, wind-up %.2f" % [
		path, state.tick, UnitView.wind_up_fraction(w)])
	var view := _view_for(_warden_id)
	if view != null:
		var o: Vector2 = view.global_position
		var r := UnitView.display_radius(w)
		var box := UnitView.drawn_box(&"the_warden", w.team, r)
		var block_w := UnitView.bar_width(r, &"the_warden", w.team)
		print("  view origin on screen: %s  facing_left=%s" % [o, UnitView.facing_left(w)])
		print("  drawn body on screen:  x %.1f .. %.1f" % [
			o.x + box.position.x, o.x + box.end.x])
		print("  chrome column screen:  x %.1f .. %.1f" % [
			o.x - block_w * 0.5, o.x + block_w * 0.5])
	get_tree().quit(0)

func _view_for(id: int) -> Node2D:
	for n in _battle.find_children("*", "Node2D", true, false):
		if n.get("unit_id") == id:
			return n
	return null
