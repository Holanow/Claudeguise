extends Node

## Issue 749 proof, trail half. A still cannot judge motion (#707), so this
## shoots a strip across a seeker bolt's flight in a real BattleView. Copies
## `Tools/VFXTier4Shot.gd`'s pattern -- wait for the action's own
## `ACTION_START`, then capture across wind-up + recover + a tail.
##
## The recovery half of #749 is staged separately, in `Tools/Linnet749Recover.gd`
## -- rook rejected a live-fight strip for it (#752): other pawns casting,
## dying and missing in the frame make the one swing this is meant to prove
## unreadable. A trail is visible against a scrum in a way a returning pose is
## not, so this tool stays live-fight for that half only.

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

static var _CONFIGS: Array[Config] = [
	## `sellsword_seeker_bolts` is the Mercenary Sellsword's own action, not a
	## player class's -- two Warriors as the party mirrors
	## `VFXTier4Shot`'s own `sellsword_crescent` config for the same reason.
	Config.new("trail_seeker_bolts", &"sellsword_seeker_bolts", [&"warrior", &"warrior"], &"floor1_sellsword"),
]

var _view: Node2D = null
var _retired: Array[Node2D] = []

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run_all()
	get_tree().quit(0)

func _party(cfg: Config) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in cfg.party_ids.size():
		out.append(PawnFactory.make_preset_pawn(cfg.party_ids[i], StringName("g%d" % i), "G%d" % i))
	var action: ActionDef = ActionLibrary.get_action(cfg.action_id)
	if not out.is_empty():
		var blocks: Array[PlanBlock] = [TargetSelfBlock.new() if action.targets_self
			else TargetNearestEnemyBlock.new()]
		var use := UseActionBlock.new()
		use.action = action
		blocks.append(use)
		var forced := Plan.new()
		forced.id = StringName("linnet749_force_%s" % cfg.action_id)
		forced.display_name = "Filming: " + cfg.action_id
		forced.blocks = blocks
		out[0].plans.push_front(forced)
	return out

func _build(cfg: Config) -> void:
	var run := RunConfig.new()
	run.party = _party(cfg)
	run.encounter_id = cfg.room_id
	run.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(run, RoomLibrary.get_room(cfg.room_id))
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

func _to_the_cast(action_id: StringName) -> Dictionary:
	for _i in 12000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == action_id and e.kind == CG.EventKind.ACTION_START:
				print("Linnet749Shot: %s at tick %d, unit %d" % [action_id, e.tick, e.source_id])
				return {"tick": e.tick, "source_id": e.source_id}
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	printerr("Linnet749Shot: no %s in this fight" % action_id)
	return {}

func _shoot(cfg: Config) -> void:
	await _build(cfg)
	var found := await _to_the_cast(cfg.action_id)
	if found.is_empty():
		return
	var action: ActionDef = ActionLibrary.get_action(cfg.action_id)
	var total_ticks: int = action.wind_up_ticks + action.recover_ticks + 12
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
	var out := OUT_DIR + "linnet_749_%s.png" % cfg.label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	sheet.save_png(out)
	print("Linnet749Shot: %s" % out)

func _run_all() -> void:
	for cfg in _CONFIGS:
		await _shoot(cfg)
		if is_instance_valid(_view):
			_view.set_process(false)
			remove_child(_view)
			_retired.append(_view)
			_view = null
