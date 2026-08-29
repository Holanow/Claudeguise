extends Node

## Issue 755: the standing-preferences section, narrow and wide, and the dead-
## ally fallback made visible. Same rig as `PlanScaleShot.gd`.

const OUT := "res://Screenshots/pipit_755_globals"

func _party() -> Array[PawnData]:
	var warrior := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	var priest := PawnFactory.make_starter_pawn(&"priest", &"priest", "Priest")
	return [warrior, priest]

func _run(tag: String, panel_width: int, ally_id: StringName) -> void:
	var party := _party()
	var priest := party[1]
	priest.posture = UnitGlobals.POSTURE_STAND_NEAR_ALLY
	priest.stand_near_ally_id = ally_id
	var panel := InspectPanel.create()
	add_child(panel)
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = float(panel_width)
	panel.offset_bottom = 720.0
	await get_tree().process_frame
	panel.embed()
	panel.set_party_roster(party)
	panel.show_pawn(priest)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	get_viewport().get_texture().get_image().save_png("%s_%s_%dpx.png" % [OUT, tag, panel_width])
	print("wrote ", "%s_%s_%dpx.png" % [OUT, tag, panel_width])
	panel.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run("named", 340, &"warrior")
	await _run("named", 240, &"warrior")
	await _run("named", 480, &"warrior")
	await _run("dangling", 340, &"nobody_in_the_party")
	get_tree().quit(0)
