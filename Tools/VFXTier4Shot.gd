extends Node

## Issue 696, tier 4. Frames of each theatrics action, in a real BattleView,
## tiled into a strip. Copies the pattern of `Tools/SellswordShot.gd` -- wait
## for the action's own `ACTION_START` in a real fight, then capture across
## its wind-up, release and impact -- generalised to run over every action in
## `_CONFIGS` in one process instead of one hand-written script per action.

const OUT_DIR := "res://Screenshots/"
const CROP := Vector2i(480, 320)
const COLS := 4
const ZOOM := 2
const FRAMES := 12
const SEED := 7

class Config:
	var label: String
	var action_id: StringName
	var party_ids: Array[StringName]
	var room_id: StringName

	func _init(l: String, a: StringName, p: Array[StringName], r: StringName) -> void:
		label = l
		action_id = a
		party_ids = p
		room_id = r

## Player-cast actions use `floor1_room1` (plenty of enemy targets, no
## dependence on any other tier's content). Boss actions use their own room so
## the caster is the enemy who actually owns the action.
static var _CONFIGS: Array[Config] = [
	Config.new("geyser_blast", &"geyser_blast", [&"geysermancer"], &"floor1_room1"),
	Config.new("geyser_spout", &"geyser_spout", [&"geysermancer"], &"floor1_room1"),
	Config.new("geyser_scald", &"geyser_scald", [&"geysermancer"], &"floor1_room1"),
	Config.new("abomination_immolate", &"abomination_immolate", [&"abomination"], &"floor1_room1"),
	Config.new("abomination_hook", &"abomination_hook", [&"abomination"], &"floor1_room1"),
	Config.new("abomination_grapple", &"abomination_grapple", [&"abomination"], &"floor1_room1"),
	Config.new("build_siege_engine", &"build_siege_engine", [&"siege_master"], &"floor1_room1"),
	Config.new("sellsword_crescent", &"sellsword_crescent", [&"sellsword"], &"floor1_room1"),
	Config.new("warden_chain_toss", &"warden_chain_toss", [&"warrior", &"warrior"], &"floor1_warden"),
	Config.new("rat_king_lash", &"rat_king_lash", [&"warrior", &"warrior"], &"floor1_rat_king"),
]

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run_all()
	get_tree().quit(0)

func _party(ids: Array[StringName]) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_preset_pawn(ids[i], StringName("g%d" % i), "G%d" % i))
	return out

func _build(cfg: Config) -> void:
	var run := RunConfig.new()
	run.party = _party(cfg.party_ids)
	run.encounter_id = cfg.room_id
	run.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(run, RoomLibrary.get_room(cfg.room_id))
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

## Steps until `action_id` fires (`ACTION_START`), then returns the tick it
## fired on and where the caster was standing. `Vector2.INF` means it never
## fired in the budget.
func _to_the_cast(action_id: StringName) -> Dictionary:
	for _i in 12000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == action_id and e.kind == CG.EventKind.ACTION_START:
				print("VFXTier4Shot: %s at tick %d, unit %d" % [action_id, e.tick, e.source_id])
				return {"tick": e.tick, "source_id": e.source_id}
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	printerr("VFXTier4Shot: no %s in this fight" % action_id)
	return {}

func _shoot(cfg: Config) -> void:
	await _build(cfg)
	var found := await _to_the_cast(cfg.action_id)
	if found.is_empty():
		return
	var action: ActionDef = ActionLibrary.get_action(cfg.action_id)
	## Lead into the wind-up so the tell is on the strip, then run past
	## recover long enough for a beam's hold and fade to finish reading.
	var lead_ticks: int = mini(action.wind_up_ticks, 8)
	var tail_ticks: int = action.recover_ticks + 12
	var total_ticks: int = lead_ticks + tail_ticks
	var step_frames: int = maxi(1, roundi(float(total_ticks * 4) / float(FRAMES)))
	var v: Node2D = _view._unit_views.get(found["source_id"])
	var at: Vector2 = Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
	var shots: Array[Image] = []
	for _i in FRAMES:
		await RenderingServer.frame_post_draw
		var full := get_viewport().get_texture().get_image()
		var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
		var reg := full.get_region(Rect2i(origin, CROP))
		reg.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
		shots.append(reg)
		for _s in step_frames:
			_frame()
			await get_tree().process_frame
	var rows := int(ceil(float(shots.size()) / float(COLS)))
	var sheet := Image.create(CROP.x * ZOOM * COLS, CROP.y * ZOOM * rows, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP * ZOOM),
			Vector2i((i % COLS) * CROP.x * ZOOM, (i / COLS) * CROP.y * ZOOM))
	var out := OUT_DIR + "kestrel_696_%s.png" % cfg.label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	sheet.save_png(out)
	print("VFXTier4Shot: %s" % out)

func _run_all() -> void:
	for cfg in _CONFIGS:
		await _shoot(cfg)
		if is_instance_valid(_view):
			_view.queue_free()
			_view = null
			await get_tree().process_frame
