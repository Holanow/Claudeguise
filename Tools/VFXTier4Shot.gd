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
	## Prepends an unconditioned top-priority plan row for `action_id` on the
	## first party pawn. `floor1_room1` has ten enemies, so a class's OWN
	## preset library (its real, shipped plan) rarely reaches its lower rows
	## before the fight is decided -- this is a filming aid only, on top of
	## the library the class actually ships with, never a substitute for it.
	var force: bool

	func _init(l: String, a: StringName, p: Array[StringName], r: StringName, f: bool = false) -> void:
		label = l
		action_id = a
		party_ids = p
		room_id = r
		force = f

## Player-cast actions use `floor1_room1` (plenty of enemy targets, no
## dependence on any other tier's content). Boss actions use their own room so
## the caster is the enemy who actually owns the action.
static var _CONFIGS: Array[Config] = [
	Config.new("geyser_blast", &"geyser_blast", [&"geysermancer"], &"floor1_room1"),
	Config.new("geyser_spout", &"geyser_spout", [&"geysermancer"], &"floor1_room1", true),
	Config.new("geyser_scald", &"geyser_scald", [&"geysermancer"], &"floor1_room1"),
	Config.new("abomination_immolate", &"abomination_immolate", [&"abomination"], &"floor1_room1", true),
	Config.new("abomination_hook", &"abomination_hook", [&"abomination"], &"floor1_room1", true),
	Config.new("abomination_grapple", &"abomination_grapple", [&"abomination"], &"floor1_room1"),
	## `build_siege_engine`'s wind-up is 90 ticks (six seconds). `floor1_room1`
	## has ten enemies, so this needs two Warriors holding the line for the
	## Siege Master to survive it; `floor1_sellsword`'s three enemies fold to
	## three party pawns almost immediately and end the fight before frame one.
	Config.new("build_siege_engine", &"build_siege_engine", [&"siege_master", &"warrior", &"warrior"], &"floor1_room1"),
	## The Mercenary Sellsword is `floor1_sellsword`'s own enemy, not a player
	## class -- `Tools/SellswordShot.gd`'s party is two Warriors for exactly
	## this reason, so this copies that setup rather than the guess this file
	## started with (a player-side "sellsword", which does not exist).
	Config.new("sellsword_crescent", &"sellsword_crescent", [&"warrior", &"warrior"], &"floor1_sellsword"),
	Config.new("warden_chain_toss", &"warden_chain_toss", [&"warrior", &"warrior"], &"floor1_warden"),
	Config.new("rat_king_lash", &"rat_king_lash", [&"warrior", &"warrior"], &"floor1_rat_king"),
]

var _view: Node2D = null
## Kept alive, off-tree, so a still-armed `SceneTreeTimer` from a hidden
## fight's own delayed VFX layer has a valid `self` to call into (see
## `_run_all`) without that fight's own `CanvasLayer` UI -- the end-of-fight
## banner in particular -- bleeding through on top of the next one.
## `Node2D.visible = false` does not hide a `CanvasLayer` child; it draws on
## its own layer regardless of its parent's visibility.
var _retired: Array[Node2D] = []

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run_all()
	get_tree().quit(0)

func _party(cfg: Config) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in cfg.party_ids.size():
		out.append(PawnFactory.make_preset_pawn(cfg.party_ids[i], StringName("g%d" % i), "G%d" % i))
	if cfg.force and not out.is_empty():
		var action: ActionDef = ActionLibrary.get_action(cfg.action_id)
		var blocks: Array[PlanBlock] = [TargetSelfBlock.new() if action.targets_self
			else TargetNearestEnemyBlock.new()]
		var use := UseActionBlock.new()
		use.action = action
		blocks.append(use)
		var forced := Plan.new()
		forced.id = StringName("vfxshot_force_%s" % cfg.action_id)
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
	## Capture starts at `ACTION_START` (the beginning of the wind-up, already
	## detected), so the window has to reach past release: the whole wind-up,
	## plus recover, plus a tail for a beam's hold and fade to finish reading.
	## An earlier cap on this ended `build_siege_engine`'s capture 38 ticks
	## before its 90-tick wind-up ever released.
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
	var out := OUT_DIR + "kestrel_696_%s.png" % cfg.label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	sheet.save_png(out)
	print("VFXTier4Shot: %s" % out)

func _run_all() -> void:
	for cfg in _CONFIGS:
		await _shoot(cfg)
		## Not freed: a delayed layer's `SceneTreeTimer` can still be armed
		## when a capture window ends, and firing it against a freed
		## `VFXDirector` crashes. Removed from the tree instead, so nothing of
		## it draws (see `_retired`'s comment), and kept referenced so it is
		## not garbage-collected out from under that timer either.
		if is_instance_valid(_view):
			_view.set_process(false)
			remove_child(_view)
			_retired.append(_view)
			_view = null
