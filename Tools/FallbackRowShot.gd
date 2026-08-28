extends Node

## Issue 719: what the InspectPanel shows for a planless pawn's fallback row,
## after the fallback became two rules -- nearest enemy, weapon's basic attack.

const OUT := "res://Screenshots/issue719_fallback_row.png"

func _ready() -> void:
	Offscreen.hide_window(self)
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	pawn.plans = []
	var panel := InspectPanel.create()
	add_child(panel)
	panel.open([pawn])
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll := panel.find_child("DetailScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 100000
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	get_viewport().get_texture().get_image().save_png(OUT)
	print("wrote ", OUT)
	get_tree().quit(0)
