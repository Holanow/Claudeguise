extends Node

## Issue 749 proof, recovery half, staged the way `Tools/Tier3Stage.gd` is
## (#752): one caster, one target, nobody else, forced through
## `SimDeps.default_decide`, on a bare `UnitView` pair -- no `Battle.tscn` and
## no scrum to hide the one swing this is meant to show. One frame per tick
## from a provably-at-rest BEFORE through wind-up, recover and a settled tail.

const OUT_DIR := "res://Screenshots/"
const CROP := Vector2i(300, 260)
const ZOOM := 3
const ACTION_ID := &"warrior_strike"
const CASTER_CLASS := &"warrior"
const SETTLE_TAIL_TICKS := 12

class ForceOnce:
	var caster_id: int
	var action_id: StringName
	var target_id: int
	var used := false

	func decide(_state: CombatState, unit: CombatUnit) -> Intent:
		if unit.id == caster_id and not used:
			used = true
			return Intent.use_action(action_id, target_id)
		return null

var _arena: Node2D = null
var _caption: Label = null
var _vfx: VFXDirector = null
var _views: Dictionary = {}
var _state: CombatState = null
var _cursor := 0

func _ready() -> void:
	Offscreen.hide_window(self)
	await _capture()
	get_tree().quit(0)

func _rebuild_scene() -> void:
	_arena = Node2D.new()
	add_child(_arena)
	var vp := get_viewport().get_visible_rect().size
	_arena.position = vp * 0.5
	_vfx = VFXDirector.new()
	_vfx.position_of_fn = _pos_of
	_vfx.hand_of_fn = _hand_of
	_vfx.hands_of_fn = _hands_of
	_vfx.facing_of_fn = _facing_of
	_arena.add_child(_vfx)
	var layer := CanvasLayer.new()
	layer.layer = 100
	_arena.add_child(layer)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 14)
	_caption.add_theme_color_override("font_color", Color(1, 1, 0.4))
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 4)
	layer.add_child(_caption)

func _pos_of(id: int) -> Vector2:
	var v: Node2D = _views.get(id)
	return Vector2.ZERO if v == null else v.position

func _hand_of(id: int) -> Vector2:
	var v = _views.get(id)
	return Vector2.ZERO if v == null else v.hand_anchor()

func _hands_of(id: int) -> PackedVector2Array:
	var v = _views.get(id)
	return PackedVector2Array() if v == null else v.hand_anchors()

func _facing_of(id: int) -> Vector2:
	var u := _state.unit(id) if _state != null else null
	return Vector2.RIGHT if u == null else u.facing

func _add_view(u: CombatUnit) -> void:
	var view := Node2D.new()
	view.set_script(load("res://Scripts/UI/UnitView.gd"))
	_arena.add_child(view)
	view.bind(_state, u.id)
	_views[u.id] = view

## Same choice `Tools/DummyRoom.gd` and `Tools/Tier3Stage.gd` make: `pawn`
## stays null so `default_decide` (the `ForceOnce` rig) answers instead of
## `PlanInterpreter` ever being asked.
func _bare_unit(id: int, shape: StringName, team: CG.Team, pos: Vector2, radius: float) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.enemy_id = shape
	u.display_name = String(shape).capitalize()
	u.position = pos
	u.radius = radius
	u.hp_max = 999999
	u.hp = u.hp_max
	u.resource_max = 999999
	u.resource = 999999
	return u

func _capture() -> void:
	_rebuild_scene()
	var action: ActionDef = ActionLibrary.get_action(ACTION_ID)

	var caster := _bare_unit(0, CASTER_CLASS, CG.Team.PLAYER,
		Vector2(-CG.ARENA_HALF_WIDTH + 100.0, 0.0), 33.0)
	var dist: float = clampf(action.range_units - 1.0, 40.0, 300.0) if action.range_units > 0.0 else 160.0
	var target := _bare_unit(1, &"goblin", CG.Team.ENEMY, caster.position + Vector2(dist, 0.0), 27.0)
	caster.facing = (target.position - caster.position).normalized()
	caster.actions = [ACTION_ID]

	_state = CombatState.new(1)
	var units: Array[CombatUnit] = [caster, target]
	_state.units = units
	_cursor = 0

	var deps := SimDeps.new()
	var rig := ForceOnce.new()
	rig.caster_id = caster.id
	rig.action_id = ACTION_ID
	rig.target_id = target.id
	deps.default_decide = Callable(rig, "decide")

	_add_view(caster)
	_add_view(target)

	var shots: Array[Image] = []
	shots.append(await _shot(caster.id, "%s  BEFORE (rest)" % ACTION_ID))

	var t := 0
	var settled := false
	while t < 4000:
		CombatSim.step(_state, deps)
		_consume_events()
		for id in _views:
			_views[id].sync(_state)
		for _q in 4:
			await get_tree().process_frame
		var u := _state.unit(caster.id)
		shots.append(await _shot(caster.id, "%s  t+%d" % [ACTION_ID, t + 1]))
		t += 1
		if u.action_ticks_left <= 0 and u.recover_ticks_left <= 0 and u.current_action == &"":
			settled = true
			break
		if _state.outcome != CombatState.Outcome.UNRESOLVED:
			break

	## One more sample, `SETTLE_TAIL_TICKS` later, so the pose is caught fully
	## at rest rather than on the exact tick recovery cleared -- the same
	## caution `Tier3Stage._sample_status`'s trailing sample takes.
	if settled:
		for _s in SETTLE_TAIL_TICKS:
			CombatSim.step(_state, deps)
			_consume_events()
			for id in _views:
				_views[id].sync(_state)
			for _q in 4:
				await get_tree().process_frame
	shots.append(await _shot(caster.id, "%s  SETTLED" % ACTION_ID))
	_save(shots)

func _consume_events() -> void:
	var events := _state.events_since(_cursor)
	_cursor = _state.events.size()
	for e in events:
		if _vfx == null or e.action_id == &"":
			continue
		var action: ActionDef = ActionLibrary.get_action(e.action_id)
		if action == null or action.vfx == null:
			continue
		if e.kind == CG.EventKind.ACTION_START:
			_vfx.play(action.vfx, VFXLayer.Cue.WIND_UP, e.source_id, e.target_id,
				float(action.wind_up_ticks) * CG.TICK_SECONDS)
		elif e.kind == CG.EventKind.ACTION_FIRE:
			_vfx.play(action.vfx, VFXLayer.Cue.RELEASE, e.source_id, e.target_id, 0.0)
			_vfx.play(action.vfx, VFXLayer.Cue.IMPACT, e.source_id, e.target_id, 0.0)

func _shot(unit_id: int, text: String) -> Image:
	var v: Node2D = _views.get(unit_id)
	var at := Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
	var origin := Vector2i(at) - CROP / 2
	_caption.text = text
	_caption.global_position = Vector2(origin) + Vector2(4, 4)
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var clamped := origin.clamp(Vector2i.ZERO, full.get_size() - CROP)
	var reg := full.get_region(Rect2i(clamped, CROP))
	reg.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return reg

## One row, exactly as wide as the frames taken, same reasoning
## `Tier3Stage._save` uses: a strip sized to what it holds carries no filler.
func _save(shots: Array[Image]) -> void:
	if shots.is_empty():
		return
	var sheet := Image.create(CROP.x * ZOOM * shots.size(), CROP.y * ZOOM, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP * ZOOM), Vector2i(i * CROP.x * ZOOM, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var out := OUT_DIR + "linnet_749_recover_%s_staged.png" % ACTION_ID
	sheet.save_png(out)
	print("Linnet749Recover: %s (%d frames)" % [out, shots.size()])
