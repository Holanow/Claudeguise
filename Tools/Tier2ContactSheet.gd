extends Node

## Issue 696, tier 2. One impact frame per bolt action, in a real BattleView,
## cropped and zoomed the way `Tools/SellswordShot.gd` is, tiled into a strip
## with no filler cell. Same starter-pawn solo room as Tier1ContactSheet, so
## the frame shows only the action under test and no plan chrome.
## Five of the nine are not here -- see the PR body for why each one.

const OUT := "res://Screenshots/linnet_696_tier2_contact_sheet.png"
const CROP := Vector2i(420, 280)
const ZOOM := 2
const SEED := 13

## action id, party class, enemy id, gap, which team to disarm so it cannot
## land its own hit and clutter the frame (or divert the side under test into
## healing itself, which is what a live Rat chipping a Priest below half HP
## did before this was ENEMY here).
const ENTRIES := [
	[&"goblin_arrow", &"warrior", &"goblin_archer", 150.0, CG.Team.PLAYER],
	[&"cultist_bolt", &"warrior", &"cultist", 150.0, CG.Team.PLAYER],
	[&"priest_bolt", &"priest", &"rat", 150.0, CG.Team.ENEMY],
]

const SEEKER_GAP := 150.0

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

## Strips `disarm_team`'s own actions after the fight starts, so it cannot
## land its own hit (or heal itself out of the fight it is losing) and
## clutter the frame with a second event. `CG.Team.PLAYER + 1` (out of the
## two-value enum) disarms nobody. `make_starter_pawn`, not
## `make_preset_pawn`: no plan, no icon column.
func _build(party_class: StringName, room: RoomData, disarm_team: CG.Team) -> void:
	var cfg := RunConfig.new()
	cfg.party = [PawnFactory.make_starter_pawn(party_class, &"p0", "P0")]
	cfg.encounter_id = &"vfx_probe"
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, room)
	_view.set_process(false)
	var none: Array[StringName] = []
	for u in _view.state.units:
		if u.team == disarm_team:
			u.actions = none

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

## A layer's `delay` schedules through `get_tree().create_timer`, real wall
## seconds, same as this waits in -- NOT simulated ticks. `run.ps1` does not
## fix the frame rate here, so a tick count converted from `delay` drifts
## against the timer that actually gates the glow; waiting on the same clock
## the layer itself uses is the only way this lands ON the glow instead of
## before or after it.
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

func _shoot(at: Vector2) -> Image:
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
	var shot := full.get_region(Rect2i(origin, CROP))
	shot.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return shot

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

func _stamped(shot: Image, text: String) -> Image:
	var label := await _label_stamp(text)
	shot.blit_rect(label, Rect2i(Vector2i.ZERO, label.get_size()),
		Vector2i(0, shot.get_height() - label.get_height()))
	return shot

func _to_impact(action_id: StringName) -> Vector2:
	for _i in 4000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == action_id and e.kind == CG.EventKind.ACTION_FIRE:
				await _wait_real_seconds(_impact_delay_seconds(action_id))
				var v: Node2D = _view._unit_views.get(e.target_id)
				print("Tier2ContactSheet: %s at tick %d" % [action_id, e.tick])
				return Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	printerr("Tier2ContactSheet: no %s in this fight" % action_id)
	return Vector2.INF

func _capture_one(action_id: StringName) -> Image:
	var at := await _to_impact(action_id)
	if at == Vector2.INF:
		return null
	var shot := await _shoot(at)
	shot = await _stamped(shot, String(action_id))
	_view.queue_free()
	_view = null
	await get_tree().process_frame
	return shot

## Fires `sellsword_seeker_bolts` at range, grabs one frame mid-flight (the
## trail is invisible at impact) and one at impact.
func _capture_seeker() -> Array[Image]:
	var out: Array[Image] = []
	for _i in 4000:
		_frame()
		await get_tree().process_frame
		var fired := false
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == &"sellsword_seeker_bolts" and e.kind == CG.EventKind.ACTION_FIRE:
				fired = true
		if fired:
			## Mid-flight has to be TICK-based, not real-seconds: the
			## projectile's own position only moves on a tick, and this
			## render loop's real frame rate is not fixed to 15/s, so a
			## real-time wait long enough to be "half the flight" in nominal
			## terms had already resolved the shot in practice -- the actual
			## bug this replaced. Ticks to cross `SEEKER_GAP` at this
			## delivery's speed, halved, so the projectile is still airborne.
			var delivery_speed: float = ActionLibrary.get_action(&"sellsword_seeker_bolts").projectile_speed
			var half_ticks := int(ceil(SEEKER_GAP / delivery_speed * 0.5))
			for _mid in half_ticks * 4:
				_frame()
				await get_tree().process_frame
			var mid_at := Vector2.ZERO
			for p in _view.state.projectiles:
				if not p.resolved and p.action_id == &"sellsword_seeker_bolts":
					mid_at = _view._arena.get_global_transform_with_canvas() * p.position
					break
			out.append(await _stamped(await _shoot(mid_at), "sellsword_seeker_bolts (mid-flight)"))
			## The glow itself is still real-time scheduled (see
			## `_impact_delay_seconds`), so waiting for it stays real-seconds.
			await _wait_real_seconds(_impact_delay_seconds(&"sellsword_seeker_bolts"))
			var v: Node2D = _view._unit_views.get(1)
			var impact_at := Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
			out.append(await _stamped(await _shoot(impact_at), "sellsword_seeker_bolts (impact)"))
			print("Tier2ContactSheet: sellsword_seeker_bolts captured (mid-flight + impact)")
			break
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	if out.is_empty():
		printerr("Tier2ContactSheet: no sellsword_seeker_bolts in this fight")
	_view.queue_free()
	_view = null
	return out

func _run() -> void:
	var shots: Array[Image] = []
	for entry in ENTRIES:
		await _build(entry[1], _solo_room(entry[2], entry[3]), entry[4])
		var shot := await _capture_one(entry[0])
		if shot != null:
			shots.append(shot)
	await _build(&"warrior", _solo_room(&"sellsword", SEEKER_GAP), CG.Team.PLAYER)
	shots.append_array(await _capture_seeker())
	if shots.is_empty():
		printerr("Tier2ContactSheet: nothing captured")
		return
	var cell := Vector2i(CROP.x * ZOOM, CROP.y * ZOOM)
	var sheet := Image.create(cell.x * shots.size(), cell.y, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	sheet.save_png(OUT)
	print("Tier2ContactSheet: %s (%d shots)" % [OUT, shots.size()])
