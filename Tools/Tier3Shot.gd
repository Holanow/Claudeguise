extends Node

## Issue 696, tier 3. One frame strip per action, `Tools/SellswordShot.gd`'s
## pattern generalised to twelve actions across two real fights rather than
## one: `floor1_hazard` carries the Brute (`brute_roar`), `floor1_cover`
## carries the Stalker (`stalker_mark`), and both carry a full player party so
## the other ten -- all preset-plan actions -- can fire in either.

const CROP := Vector2i(420, 280)
const COLS := 5
const ZOOM := 2
const FRAMES := 10
const MAX_TICKS := 2400

const RUNS := [
	{"encounter": &"floor1_hazard", "seeds": [1, 2, 3, 4, 5, 6],
		"want": [&"warrior_guard", &"warrior_taunt", &"warrior_block", &"warrior_second_wind",
			&"priest_haste", &"priest_ward", &"priest_heal", &"geyser_cleanse",
			&"channel_mana", &"spotter_mark", &"brute_roar"]},
	{"encounter": &"floor1_cover", "seeds": [1, 2, 3, 4, 5, 6], "want": [&"stalker_mark"]},
]

var _view: Node2D = null
var _found: Dictionary = {}

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	out.append(PawnFactory.make_preset_pawn(&"warrior", &"g0", "Warrior"))
	out.append(PawnFactory.make_preset_pawn(&"priest", &"g1", "Priest"))
	out.append(PawnFactory.make_preset_pawn(&"geysermancer", &"g2", "Geysermancer"))
	out.append(PawnFactory.make_preset_pawn(&"siege_master", &"g3", "Siege Master"))
	return out

func _build(encounter_id: StringName, fight_seed: int) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = encounter_id
	cfg.seed = fight_seed
	if _view != null and is_instance_valid(_view):
		_view.queue_free()
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, RoomLibrary.get_room(encounter_id))
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

func _capture(action_id: StringName, e: CombatEvent, wind_up: int, recover: int) -> void:
	var span_ticks := wind_up + recover + 8
	var step := maxi(1, int(ceil(float(span_ticks) / float(FRAMES))))
	var shots: Array[Image] = []
	for _i in FRAMES:
		var v: Node2D = _view._unit_views.get(e.source_id)
		var at := Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
		await RenderingServer.frame_post_draw
		var full := get_viewport().get_texture().get_image()
		var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
		var reg := full.get_region(Rect2i(origin, CROP))
		reg.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
		shots.append(reg)
		for _t in step:
			for _q in 4:
				_frame()
				await get_tree().process_frame
	var rows := int(ceil(float(shots.size()) / float(COLS)))
	var sheet := Image.create(CROP.x * ZOOM * COLS, CROP.y * ZOOM * rows, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP * ZOOM),
			Vector2i((i % COLS) * CROP.x * ZOOM, (i / COLS) * CROP.y * ZOOM))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	var out := "res://Screenshots/sable_696_tier3_%s.png" % action_id
	sheet.save_png(out)
	print("Tier3Shot: %s at tick %d" % [out, e.tick])

func _play_one(encounter_id: StringName, want: Array, fight_seed: int) -> void:
	await _build(encounter_id, fight_seed)
	for _i in MAX_TICKS:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.kind != CG.EventKind.ACTION_START:
				continue
			if not want.has(e.action_id) or _found.has(e.action_id):
				continue
			var action: ActionDef = ActionLibrary.get_action(e.action_id)
			if action == null:
				continue
			_found[e.action_id] = true
			await _capture(e.action_id, e, action.wind_up_ticks, action.recover_ticks)
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		var all_found := true
		for a in want:
			if not _found.has(a):
				all_found = false
				break
		if all_found:
			break

func _run() -> void:
	for run in RUNS:
		var want: Array = run["want"]
		for s in run["seeds"]:
			var remaining: Array = want.filter(func(a): return not _found.has(a))
			if remaining.is_empty():
				break
			await _play_one(run["encounter"], remaining, s)
	for a in RUNS[0]["want"] + RUNS[1]["want"]:
		if not _found.has(a):
			printerr("Tier3Shot: %s never fired across the seed sweep" % a)
