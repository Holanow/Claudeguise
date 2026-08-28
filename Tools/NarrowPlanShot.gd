extends Node

## rook's ruling on #723's follow-up (the plan editor moves into a popout tab,
## separate issue): the embedded layout has to hold well below the current
## ~480px party-screen column. Pins the embedded panel to a fixed-width
## column inside a taller window, so the rest of the frame stays visible and
## the column's own clearance is easy to read off the screenshot.

const OUT := "res://Screenshots/sable_723_narrow"

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
	get_viewport().get_texture().get_image().save_png("%s_%dpx_column.png" % [OUT, panel_width])
	print("wrote ", "%s_%dpx_column.png" % [OUT, panel_width])
	panel.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run(320)
	await _run(240)
	get_tree().quit(0)
