extends Node

## Issue 723: a photograph of the new `inert` gutter mark (⊘) -- a row past
## the pawn's block budget, which never renders anywhere else in the repo
## before this capture. Same fixture shape as `Tools/FallbackRowShot.gd`: a
## real starter pawn, real class, `InspectPanel` built directly.

const OUT := "res://Screenshots/sable_723_inert_verdict"

func _ready() -> void:
	Offscreen.hide_window(self)
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	var panel := InspectPanel.create()
	add_child(panel)
	panel.open([pawn])
	# Real library rows, real cost -- taken until adding one more would fit,
	# then the WIS budget is cut so the last row(s) taken land past it. This
	# is the real over-budget path (equipment coming off costs WIS), not a
	# synthetic fixture.
	for plan in PresetPlans.for_class(&"warrior"):
		panel._add_preset(pawn, plan)
	pawn.pawn_class.base_attributes["WIS"] = 2
	panel._build_detail(pawn)
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := panel.find_child("DetailScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	var tag := "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("wrote ", "%s_%s.png" % [OUT, tag])
	get_tree().quit(0)
