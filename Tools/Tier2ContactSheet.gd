extends Node

## Issue 696, tier 2. One impact frame per bolt action, in a real BattleView,
## tiled into a contact sheet. Same solo-room trick as Tier1ContactSheet.
## Five of the nine are not here -- see the PR body for why each one.

const OUT := "res://Screenshots/linnet_696_tier2_contact_sheet.png"
const CROP := Vector2i(300, 240)
const COLS := 4
const SEED := 13

## action id, party class, enemy id, gap, disarm the party pawn.
const ENTRIES := [
	[&"goblin_arrow", &"warrior", &"goblin_archer", 150.0, true],
	[&"cultist_bolt", &"warrior", &"cultist", 150.0, true],
	[&"priest_smite", &"priest", &"rat", 150.0, false],
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

## `disarm_party` strips the party pawn's own actions after the fight starts,
## so it cannot kill an enemy whose SECOND action is the one under test
## (stalker fires `stalker_mark` before `stalker_dart`; a live Warrior across
## the table sometimes finished it off first).
func _build(party_class: StringName, room: RoomData, disarm_party: bool = true) -> void:
	var cfg := RunConfig.new()
	cfg.party = [PawnFactory.make_preset_pawn(party_class, &"p0", "P0")]
	cfg.encounter_id = &"vfx_probe"
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, room)
	_view.set_process(false)
	if disarm_party:
		for u in _view.state.units:
			if u.team == CG.Team.PLAYER:
				u.actions = []

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

func _shoot(at: Vector2) -> Image:
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
	return full.get_region(Rect2i(origin, CROP))

func _to_impact(action_id: StringName) -> Vector2:
	for _i in 4000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == action_id and e.kind == CG.EventKind.ACTION_FIRE:
				for _settle in 3 * 4:
					_frame()
					await get_tree().process_frame
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
			## Speed 13 units/tick over the gap: mid-flight sits around half
			## the travel ticks after the loose. Centred on the bolt itself,
			## not the target -- at the midpoint it is nowhere near either
			## body, and the trail is what this frame exists to show.
			for _mid in 5 * 4:
				_frame()
				await get_tree().process_frame
			var mid_at := Vector2.ZERO
			for p in _view.state.projectiles:
				if not p.resolved and p.action_id == &"sellsword_seeker_bolts":
					mid_at = _view._arena.get_global_transform_with_canvas() * p.position
					break
			out.append(await _shoot(mid_at))
			for _rest in 12 * 4:
				_frame()
				await get_tree().process_frame
			var v: Node2D = _view._unit_views.get(1)
			out.append(await _shoot(Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin))
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
	await _build(&"warrior", _solo_room(&"sellsword", SEEKER_GAP), true)
	shots.append_array(await _capture_seeker())
	if shots.is_empty():
		printerr("Tier2ContactSheet: nothing captured")
		return
	var rows := int(ceil(float(shots.size()) / float(COLS)))
	var sheet := Image.create(CROP.x * COLS, CROP.y * rows, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP),
			Vector2i((i % COLS) * CROP.x, (i / COLS) * CROP.y))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	sheet.save_png(OUT)
	print("Tier2ContactSheet: %s (%d shots)" % [OUT, shots.size()])
