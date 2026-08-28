extends Node

## Issue 696, tier 3. A guard, a taunt or a mark has no impact flash to point
## at -- the whole effect is a persistent state on a body -- so this does not
## copy `Tools/SellswordShot.gd`'s single-impact-window pattern for the eight
## actions that apply a real status. For those it shoots the AFFECTED unit,
## one frame before application (the unaffected baseline) and several more
## spread across the status's real lifetime, each burned-in labelled with the
## action id and elapsed time. The four punctual actions (a heal, a resource
## cast) have no lifetime to spread across and keep one impact-window strip.
## HUD chrome is hidden so nothing sits on top of the struck pawn.

const OUT_DIR := "res://Screenshots/"
const CROP := Vector2i(360, 280)
const COLS := 5
const ZOOM := 2
const MAX_TICKS := 2400

class StatusCfg:
	var action_id: StringName
	var status: CG.Status

	func _init(a: StringName, s: CG.Status) -> void:
		action_id = a
		status = s

## Which status each of these actually applies -- read off the shipped
## `StatusEffect` on each action's own `.tres`, not guessed from its name.
static var STATUS_ACTIONS: Array[StatusCfg] = [
	StatusCfg.new(&"warrior_guard", CG.Status.BLOCK),
	StatusCfg.new(&"warrior_taunt", CG.Status.TAUNTING),
	StatusCfg.new(&"warrior_block", CG.Status.SHIELDING),
	StatusCfg.new(&"priest_haste", CG.Status.HASTE),
	StatusCfg.new(&"priest_ward", CG.Status.SHIELD),
	StatusCfg.new(&"brute_roar", CG.Status.TAUNTING),
	StatusCfg.new(&"spotter_mark", CG.Status.MARKED),
	StatusCfg.new(&"stalker_mark", CG.Status.MARKED),
]

const RUNS := [
	{"encounter": &"floor1_hazard", "seeds": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
		16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30],
		"want": [&"warrior_guard", &"warrior_taunt", &"warrior_block", &"warrior_second_wind",
			&"priest_haste", &"priest_ward", &"priest_heal", &"geyser_cleanse",
			&"channel_mana", &"spotter_mark", &"brute_roar"]},
	{"encounter": &"floor1_cover", "seeds": [1, 2, 3, 4, 5, 6], "want": [&"stalker_mark"]},
]

var _view: Node2D = null
var _caption: Label = null
var _found: Dictionary = {}

func _ready() -> void:
	Offscreen.hide_window(self)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 14)
	_caption.add_theme_color_override("font_color", Color(1, 1, 0.4))
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 4)
	layer.add_child(_caption)
	await _run()
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	out.append(PawnFactory.make_preset_pawn(&"warrior", &"g0", "Warrior"))
	out.append(PawnFactory.make_preset_pawn(&"priest", &"g1", "Priest"))
	out.append(PawnFactory.make_preset_pawn(&"geysermancer", &"g2", "Geysermancer"))
	out.append(PawnFactory.make_preset_pawn(&"siege_master", &"g3", "Siege Master"))
	return out

func _unit(id: int) -> CombatUnit:
	for u in _view.state.units:
		if u.id == id:
			return u
	return null

## Screen-space chrome only. World-space badges over a unit's own head stay --
## they are what the fight already looks like, not an instrument overlay.
func _hide_hud() -> void:
	for n in [_view._party_label, _view._encounter_label, _view._seed_label,
			_view._outcome_label, _view._team_status, _view._combat_log,
			_view._end_banner, _view._end_dim, _view._pause_dim,
			_view._click_hint, _view._display_options, _view._pause_button,
			_view._setup_hint, _view._reset_button]:
		if n != null:
			n.visible = false

func _build(encounter_id: StringName, fight_seed: int) -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = encounter_id
	cfg.seed = fight_seed
	if _view != null and is_instance_valid(_view):
		_view.set_process(false)
		remove_child(_view)
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, RoomLibrary.get_room(encounter_id))
	_view.set_process(false)
	_hide_hud()

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

func _advance_ticks(n: int) -> void:
	for _t in n:
		for _q in 4:
			_frame()
			await get_tree().process_frame

## One capture: crop tight on `unit_id`, caption burned in at the crop's own
## top-left so it survives the crop rather than sitting outside it.
func _shot(unit_id: int, text: String) -> Image:
	var v: Node2D = _view._unit_views.get(unit_id)
	var at := Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
	var origin := (Vector2i(at) - CROP / 2)
	_caption.text = text
	_caption.global_position = Vector2(origin) + Vector2(4, 4)
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var clamped := origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
	var reg := full.get_region(Rect2i(clamped, CROP))
	reg.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return reg

func _save(action_id: StringName, shots: Array[Image]) -> void:
	if shots.is_empty():
		return
	var rows := int(ceil(float(shots.size()) / float(COLS)))
	var sheet := Image.create(CROP.x * ZOOM * COLS, CROP.y * ZOOM * rows, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP * ZOOM),
			Vector2i((i % COLS) * CROP.x * ZOOM, (i / COLS) * CROP.y * ZOOM))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var out := OUT_DIR + "sable_696_tier3_%s.png" % action_id
	sheet.save_png(out)
	print("Tier3Shot: %s" % out)

## One frame before wind-up starts (baseline, unaffected), one at application,
## then more spread across the status's real duration -- clamped to whatever
## the fight actually gives it, which is itself the honest answer for
## `warrior_block` (soaks out on damage, does not run a timer).
## Minimum lifetime samples (past BEFORE/CAST) to count as a real capture,
## rather than one truncated by the target dying or the fight ending a beat
## after the cast -- that outcome is real but proves nothing about legibility
## and the seed sweep should keep looking instead of accepting it.
const MIN_LIFETIME_SAMPLES := 3

func _capture_status(cfg: StatusCfg, e: CombatEvent, wind_up: int, duration_ticks: int) -> bool:
	var target: int = e.target_id
	var shots: Array[Image] = []
	shots.append(await _shot(target, "%s  BEFORE" % cfg.action_id))
	await _advance_ticks(wind_up + 2)
	shots.append(await _shot(target, "%s  CAST" % cfg.action_id))
	var offsets_s: Array[float] = [0.3, 1.0, 2.5, 5.0, 8.0, 12.0]
	var last_ticks := wind_up + 2
	var on_samples := 0
	for off in offsets_s:
		var cap_ticks: int = duration_ticks - 1 if duration_ticks > 0 else 999999
		var target_ticks: int = mini(int(off * CG.TICKS_PER_SECOND), cap_ticks)
		var step := target_ticks - last_ticks
		if step <= 0:
			continue
		await _advance_ticks(step)
		last_ticks = target_ticks
		var u := _unit(target)
		var still: bool = u != null and u.has_status(cfg.status)
		shots.append(await _shot(target, "%s  +%.1fs  %s" % [cfg.action_id, off, "ON" if still else "OFF"]))
		if still:
			on_samples += 1
		## The target dying clears its statuses -- a real fight outcome, not a
		## VFX defect, but it proves nothing about whether the status reads
		## while it is actually up. Keep sweeping seeds instead of accepting
		## a strip that is all OFF because the target did not live to show it.
		if shots.size() >= 8 or u == null or _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	if on_samples < MIN_LIFETIME_SAMPLES:
		return false
	_save(cfg.action_id, shots)
	return true

func _capture_punctual(action_id: StringName, e: CombatEvent, wind_up: int, recover: int) -> bool:
	var span_ticks := wind_up + recover + 8
	var step := maxi(1, int(ceil(float(span_ticks) / 8.0)))
	var follow: int = e.target_id if e.target_id != e.source_id else e.source_id
	var shots: Array[Image] = []
	for i in 8:
		shots.append(await _shot(follow, "%s  t+%dt" % [action_id, i * step]))
		await _advance_ticks(step)
	_save(action_id, shots)
	return true

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
			var status_cfg: StatusCfg = null
			for c in STATUS_ACTIONS:
				if c.action_id == e.action_id:
					status_cfg = c
					break
			var duration := 0
			for eff in action.effects:
				if eff is StatusEffect:
					duration = eff.duration_ticks
			var ok: bool
			if status_cfg != null:
				ok = await _capture_status(status_cfg, e, action.wind_up_ticks, duration)
			else:
				ok = await _capture_punctual(e.action_id, e, action.wind_up_ticks, action.recover_ticks)
			if ok:
				_found[e.action_id] = true
			## Not `return`: a fight this long can carry several of the
			## actions still being hunted, and a failed attempt (target died
			## too soon to sample) should not cost the rest of it. The event
			## list just read is now stale after the ticks the capture
			## advanced -- break rather than keep reading it, and let the
			## next outer tick fetch a fresh one.
			break
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break

func _run() -> void:
	for run in RUNS:
		var want: Array = run["want"]
		for s in run["seeds"]:
			var remaining: Array = want.filter(func(a): return not _found.has(a))
			if remaining.is_empty():
				break
			await _play_one(run["encounter"], remaining, s)
	for run in RUNS:
		for a in run["want"]:
			if not _found.has(a):
				printerr("Tier3Shot: %s never fired across the seed sweep" % a)
