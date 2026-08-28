extends Node

## Issue 696, tier 1. One impact frame per melee action in a real BattleView,
## cropped and zoomed like `Tools/SellswordShot.gd`, tiled into a strip with
## no filler cell. Each fight is a solo room, one starter (plan-less) pawn and
## one enemy, so `DefaultBehavior` fires the action under test and draws
## nothing a plan would (icon columns, block arcs).
##
## `warrior_execute` and `abomination_claw` are not here: neither is on any
## live class' or enemy's action list (checked `Scripts/Content/Classes` and
## `Scripts/Content/Enemies`), so no fight can reach them -- see the PR body.

const OUT := "res://Screenshots/linnet_696_tier1_contact_sheet.png"
const CROP := Vector2i(420, 280)
const ZOOM := 2
const SEED := 11

## action_id, party class id, enemy id, gap.
const ENTRIES := [
	[&"warrior_strike", &"warrior", &"rat", 30.0],
	[&"goblin_stab", &"warrior", &"goblin", 30.0],
	[&"rat_bite", &"warrior", &"rat", 30.0],
	[&"ghoul_maul", &"warrior", &"ghoul", 34.0],
	[&"warden_axe", &"warrior", &"the_warden", 44.0],
	[&"brute_slam", &"warrior", &"brute", 40.0],
	[&"sellsword_strike", &"warrior", &"sellsword", 30.0],
]

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _solo_room(enemy_id: StringName, gap: float) -> RoomData:
	var room := RoomData.new()
	room.id = &"vfx_probe"
	room.party_spawns = [Vector2(-gap * 0.5, 0.0)]
	room.enemy_spawns = [{"enemy_id": enemy_id, "position": Vector2(gap * 0.5, 0.0)}]
	return room

## `make_starter_pawn`, not `make_preset_pawn`: a preset pawn carries every
## plan row for its class, which draws as a permanent icon column beside it
## and, for the Warrior, an automatic Block that fills the frame with a
## "Directional Block" arc and label. A starter pawn has no plan at all, so
## `DefaultBehavior` decides and the frame shows only the action under test.
func _build(party_class: StringName, room: RoomData) -> void:
	var cfg := RunConfig.new()
	cfg.party = [PawnFactory.make_starter_pawn(party_class, &"p0", "P0")]
	cfg.encounter_id = &"vfx_probe"
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, room)
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

## Ticks between an action's `ACTION_FIRE` and its `IMPACT`-cue layers
## actually starting, read off the action's own `vfx` rather than guessed, so
## the captured frame is the moment the glow appears, not before or after.
## A layer's `delay` schedules through `get_tree().create_timer`, real wall
## seconds, not simulated ticks. Every tier-1 delay is 0 today, but waiting on
## the same clock the layer uses is what makes this correct if that changes.
func _impact_delay_seconds(action_id: StringName) -> float:
	var action := ActionLibrary.get_action(action_id)
	if action == null or action.vfx == null:
		return 0.0
	var max_delay := 0.0
	for layer in action.vfx.for_cue(VFXLayer.Cue.IMPACT):
		max_delay = maxf(max_delay, layer.delay)
	return max_delay

func _wait_real_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		_frame()
		await get_tree().process_frame

func _to_impact(action_id: StringName) -> Vector2:
	for _i in 4000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == action_id and e.kind == CG.EventKind.ACTION_FIRE:
				await _wait_real_seconds(_impact_delay_seconds(action_id))
				var v: Node2D = _view._unit_views.get(e.target_id)
				print("Tier1ContactSheet: %s at tick %d" % [action_id, e.tick])
				return Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	printerr("Tier1ContactSheet: no %s in this fight" % action_id)
	return Vector2.INF

## A small opaque label reading `text`, rendered off the main viewport so it
## can be stamped onto a corner of a cropped, zoomed cell without competing
## with the battle's own HUD for space.
func _label_stamp(text: String) -> Image:
	var sub := SubViewport.new()
	sub.size = Vector2i(CROP.x * ZOOM, 28)
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	var bg := ColorRect.new()
	bg.size = Vector2(sub.size)
	bg.color = Color(0, 0, 0, 0.8)
	sub.add_child(bg)
	var label := Label.new()
	label.text = text
	label.position = Vector2(6, 4)
	label.add_theme_color_override("font_color", Color.WHITE)
	sub.add_child(label)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	sub.queue_free()
	return img

func _capture_one(action_id: StringName) -> Image:
	var at := await _to_impact(action_id)
	if at == Vector2.INF:
		return null
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
	var shot := full.get_region(Rect2i(origin, CROP))
	shot.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	var label := await _label_stamp(String(action_id))
	shot.blit_rect(label, Rect2i(Vector2i.ZERO, label.get_size()),
		Vector2i(0, shot.get_height() - label.get_height()))
	_view.queue_free()
	_view = null
	await get_tree().process_frame
	return shot

func _run() -> void:
	var shots: Array[Image] = []
	for entry in ENTRIES:
		await _build(entry[1], _solo_room(entry[2], entry[3]))
		var shot := await _capture_one(entry[0])
		if shot != null:
			shots.append(shot)
	if shots.is_empty():
		printerr("Tier1ContactSheet: nothing captured")
		return
	var cell := Vector2i(CROP.x * ZOOM, CROP.y * ZOOM)
	var sheet := Image.create(cell.x * shots.size(), cell.y, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	sheet.save_png(OUT)
	print("Tier1ContactSheet: %s (%d shots)" % [OUT, shots.size()])
