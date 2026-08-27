extends Node

## Issue 696, tier 1. One impact frame per melee action, in a real BattleView,
## tiled into a contact sheet. Each fight is a minimal solo room -- one party
## pawn, one enemy -- so the actual class' DefaultBehavior fires the action
## under test without a plan.
##
## `warrior_execute` and `abomination_claw` are not here: neither is on any
## live class' or enemy's action list today (`warrior_execute`'s own
## description says retired; nothing in `Scripts/Content/Classes` or
## `Scripts/Content/Enemies` names `abomination_claw`), so no fight can reach
## them. Their `.tres` exists and matches the shared table; unverified live.

const OUT := "res://Screenshots/linnet_696_tier1_contact_sheet.png"
const CROP := Vector2i(300, 240)
const COLS := 4
const SEED := 11

## action_id, party class id (or "" to reuse the enemy room), enemy id, gap.
const ENTRIES := [
	[&"warrior_strike", &"warrior", &"rat", 30.0],
	[&"goblin_stab", &"warrior", &"goblin", 30.0],
	[&"rat_bite", &"warrior", &"rat", 30.0],
	[&"ghoul_maul", &"warrior", &"ghoul", 34.0],
	[&"warden_axe", &"warrior", &"the_warden", 44.0],
	[&"brute_slam", &"warrior", &"brute", 40.0],
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

func _build(party_class: StringName, room: RoomData) -> void:
	var cfg := RunConfig.new()
	cfg.party = [PawnFactory.make_preset_pawn(party_class, &"p0", "P0")]
	cfg.encounter_id = &"vfx_probe"
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, room)
	_view.set_process(false)

func _build_sellsword() -> void:
	var cfg := RunConfig.new()
	var party: Array[PawnData] = []
	for i in 2:
		party.append(PawnFactory.make_preset_pawn(&"warrior", StringName("g%d" % i), "G%d" % i))
	cfg.party = party
	cfg.encounter_id = &"floor1_sellsword"
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, RoomLibrary.get_room(&"floor1_sellsword"))
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

## Steps until `action_id` fires, then a short settle so the impact VFX shows,
## and returns where the struck body is.
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
				print("Tier1ContactSheet: %s at tick %d" % [action_id, e.tick])
				return Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	printerr("Tier1ContactSheet: no %s in this fight" % action_id)
	return Vector2.INF

func _capture_one(action_id: StringName) -> Image:
	var at := await _to_impact(action_id)
	if at == Vector2.INF:
		return null
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
	var shot := full.get_region(Rect2i(origin, CROP))
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
	await _build_sellsword()
	var sell_shot := await _capture_one(&"sellsword_strike")
	if sell_shot != null:
		shots.append(sell_shot)
	if shots.is_empty():
		printerr("Tier1ContactSheet: nothing captured")
		return
	var rows := int(ceil(float(shots.size()) / float(COLS)))
	var sheet := Image.create(CROP.x * COLS, CROP.y * rows, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP),
			Vector2i((i % COLS) * CROP.x, (i / COLS) * CROP.y))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	sheet.save_png(OUT)
	print("Tier1ContactSheet: %s (%d shots)" % [OUT, shots.size()])
