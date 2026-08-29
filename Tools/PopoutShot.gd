extends Node

## Issue 741: the narrow tabbed popout, mid-fight, at whatever window size
## `--resolution` sets. Stages a real fight through `Battle.tscn` -- the
## popout only exists once a fight is running -- opens it, switches to the
## Equipment tab, and shoots both. Run once per size named in the PR.

const BattleScene := preload("res://Scenes/Battle.tscn")
const OUT := "res://Screenshots/pipit_741_popout"

func _make_party() -> Array[PawnData]:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	for plan in PresetPlans.for_class(&"warrior"):
		pawn.plans.append(plan)
	return [pawn]

func _make_encounter() -> RoomData:
	var e := RoomData.new()
	e.enemy_spawns = [{"enemy_id": &"goblin", "position": Vector2(300.0, 0.0)}]
	e.party_spawns = [Vector2(-300.0, 0.0)]
	return e

func _ready() -> void:
	Offscreen.hide_window(self)
	var tag := "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	var view = BattleScene.instantiate()
	add_child(view)
	var config := RunConfig.new()
	config.seed = 1
	config.party = _make_party()
	view.config = config
	view.begin_with_encounter(config, _make_encounter())
	view.start_fight()
	for i in 10:
		await get_tree().process_frame
	view._open_plans(config.party[0])
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	get_viewport().get_texture().get_image().save_png("%s_plans_%s.png" % [OUT, tag])
	print("wrote plans shot at ", tag)

	view._inspect_panel._show_tab(1)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_equip_%s.png" % [OUT, tag])
	print("wrote equipment shot at ", tag)

	## A real edit mid-fight -- swap the first two rows -- so the staged state
	## the issue asks to make visible is what a player would actually see.
	view._inspect_panel._show_tab(0)
	var inspector = view._inspect_panel._inspect
	inspector._move_plan(config.party[0], 0, 1)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_staged_%s.png" % [OUT, tag])
	print("wrote staged shot at ", tag)
	get_tree().quit(0)
