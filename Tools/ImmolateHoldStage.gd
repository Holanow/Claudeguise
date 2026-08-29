extends Node

## Issue 772. `Tools/Tier3Stage.gd` samples a punctual action or a status's
## own duration; Immolate is neither -- it is the one sustained action in the
## game, and its "still on" signal is `unit.sustaining`, not a status. Same
## staging shape (two bare units, `VFXDirector`, `ForceOnce` to ignite), with
## a second decide callable that keeps re-choosing the aura so the strip can
## show the hold rather than one instant of it.

const OUT_DIR := "res://Screenshots/"
const CROP := Vector2i(420, 320)
const ZOOM := 2
const RUN_TICKS := 400

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

## Re-affirms the aura every tick while `active`, then stops asking for it --
## the off switch `CombatSim._reaffirm_sustain` is built around.
class Hold:
	var caster_id: int
	var action_id: StringName
	var target_id: int
	var active := true

	func decide(_state: CombatState, unit: CombatUnit) -> Intent:
		if unit.id != caster_id:
			return null
		if active:
			return Intent.use_action(action_id, target_id)
		return Intent.move_to(Vector2(9999.0, 9999.0))

var _arena: Node2D = null
var _caption: Label = null
var _vfx: VFXDirector = null
var _views: Dictionary = {}
var _state: CombatState = null
var _cursor := 0

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _run() -> void:
	_rebuild_scene()
	var action_id := &"abomination_immolate"
	var action: ActionDef = ActionLibrary.get_action(action_id)
	if action == null:
		printerr("ImmolateHoldStage: unknown action %s" % action_id)
		return

	var caster := _bare_unit(0, &"abomination", CG.Team.PLAYER, Vector2(-120.0, 0.0), 33.0)
	var enemy := _bare_unit(1, &"goblin", CG.Team.ENEMY, Vector2(60.0, 0.0), 33.0)
	caster.facing = (enemy.position - caster.position).normalized()
	caster.actions = [action_id]

	_state = CombatState.new(1)
	_state.units = [caster, enemy] as Array[CombatUnit]
	_cursor = 0

	var deps := SimDeps.new()
	var once := ForceOnce.new()
	once.caster_id = caster.id
	once.action_id = action_id
	once.target_id = caster.id
	deps.default_decide = Callable(once, "decide")

	_add_view(caster)
	_add_view(enemy)

	var shots: Array[Image] = []
	shots.append(await _shot(caster.id, "Immolate  BEFORE"))

	var hold := Hold.new()
	hold.caster_id = caster.id
	hold.action_id = action_id
	hold.target_id = caster.id

	var ignited := false
	for t in RUN_TICKS:
		CombatSim.step(_state, deps)
		_consume_events()
		for id in _views:
			_views[id].sync(_state)
		for _q in 4:
			await get_tree().process_frame
		if not ignited and caster.sustaining == action_id:
			ignited = true
			deps.default_decide = Callable(hold, "decide")
			shots.append(await _shot(caster.id, "Immolate  IGNITE  t%d" % t))
		if _state.outcome != CombatState.Outcome.UNRESOLVED:
			break

	if not ignited:
		printerr("ImmolateHoldStage: never ignited")
		_save(shots)
		return

	## Spread across the hold, then drop it and show the frame after.
	var offsets_s: Array[float] = [0.5, 1.5, 3.0]
	for off in offsets_s:
		var want := int(off * CG.TICKS_PER_SECOND)
		while _state.tick < want and _state.outcome == CombatState.Outcome.UNRESOLVED:
			CombatSim.step(_state, deps)
			_consume_events()
			for id in _views:
				_views[id].sync(_state)
			for _q in 4:
				await get_tree().process_frame
		var still: bool = caster.sustaining == action_id
		shots.append(await _shot(caster.id, "Immolate  +%.1fs  %s" % [off, "ON" if still else "OFF"]))
		if not still:
			break

	if caster.sustaining == action_id:
		hold.active = false
		for _t in CG.TICKS_PER_SECOND:
			CombatSim.step(_state, deps)
			_consume_events()
			for id in _views:
				_views[id].sync(_state)
			for _q in 4:
				await get_tree().process_frame
			if caster.sustaining != action_id:
				break
		shots.append(await _shot(caster.id, "Immolate  DROPPED"))

	_save(shots)

func _rebuild_scene() -> void:
	_arena = Node2D.new()
	add_child(_arena)
	var vp := get_viewport().get_visible_rect().size
	_arena.position = vp * 0.5
	_views.clear()
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

func _bare_unit(id: int, shape: StringName, team: CG.Team, pos: Vector2, radius: float) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.enemy_id = shape
	u.display_name = String(shape).capitalize()
	u.position = pos
	u.radius = radius
	u.hp_max = 250
	u.hp = 250
	u.resource_max = 999999
	u.resource = 999999
	return u

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

func _save(shots: Array[Image]) -> void:
	if shots.is_empty():
		return
	var sheet := Image.create(CROP.x * ZOOM * shots.size(), CROP.y * ZOOM, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP * ZOOM), Vector2i(i * CROP.x * ZOOM, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	sheet.save_png(OUT_DIR + "curlew_772_immolate_hold.png")
