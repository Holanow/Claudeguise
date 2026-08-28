extends Node

## Issue 742: proof that the embedded plan editor scales its content down as
## the panel narrows rather than clipping it off the left edge. Same rig as
## `NarrowPlanShot.gd` -- a fixed-width column inside a taller window -- run
## across the widths the issue names plus one below the readability floor.

const OUT := "res://Screenshots/pipit_742_scale"

func _run(panel_width: int) -> void:
	var pawn := PawnFactory.make_starter_pawn(&"abomination", &"abomination", "Abomination")
	for plan in PresetPlans.for_class(&"abomination"):
		pawn.plans.append(plan)
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
	panel.show_pawn(pawn)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	get_viewport().get_texture().get_image().save_png("%s_%dpx.png" % [OUT, panel_width])
	print("wrote ", "%s_%dpx.png" % [OUT, panel_width], " panel.size=", panel.size)
	panel.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run(240)
	await _run(320)
	await _run(480)
	await _run(1200)
	get_tree().quit(0)
