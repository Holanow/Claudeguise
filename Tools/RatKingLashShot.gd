extends Node

## Issue 757 evidence, staged the way `Tools/Tier3Stage.gd` stages every
## action shot: two units, nobody else, `ForceOnce` through
## `SimDeps.default_decide`, no `Battle.tscn`. Shows the Rat King's crown at
## rest, then the wind-up, cast, three summons and the stun landing.

const OUT_DIR := "res://Screenshots/"
const CROP := Vector2i(420, 320)
const ZOOM := 2
const RUN_TICKS := 200

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
	await _run()
	get_tree().quit(0)

func _run() -> void:
	_arena = Node2D.new()
	add_child(_arena)
	var vp := get_viewport().get_visible_rect().size
	_arena.position = vp * 0.5
	_vfx = VFXDirector.new()
	_vfx.position_of_fn = func(id: int) -> Vector2:
		var v: Node2D = _views.get(id)
		return Vector2.ZERO if v == null else v.position
	_vfx.hand_of_fn = func(id: int) -> Vector2:
		var v = _views.get(id)
		return Vector2.ZERO if v == null else v.hand_anchor()
	_vfx.hands_of_fn = func(id: int) -> PackedVector2Array:
		var v = _views.get(id)
		return PackedVector2Array() if v == null else v.hand_anchors()
	_vfx.facing_of_fn = func(id: int) -> Vector2:
		var u := _state.unit(id) if _state != null else null
		return Vector2.RIGHT if u == null else u.facing
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

	var action: ActionDef = ActionLibrary.get_action(&"rat_king_lash")
	var king := _bare_unit(0, &"rat_king", CG.Team.ENEMY, Vector2(-CG.ARENA_HALF_WIDTH + 100.0, 0.0))
	var dummy := _bare_unit(1, &"warrior", CG.Team.PLAYER, king.position + Vector2(150.0, 0.0))
	king.facing = (dummy.position - king.position).normalized()
	king.actions = [action.id]

	_state = CombatState.new(1)
	var units: Array[CombatUnit] = [king, dummy]
	_state.units = units
	_cursor = 0

	var rig := ForceOnce.new()
	rig.caster_id = king.id
	rig.action_id = action.id
	rig.target_id = dummy.id
	var deps := SimDeps.new()
	deps.default_decide = Callable(rig, "decide")

	_add_view(king)
	_add_view(dummy)

	var shots: Array[Image] = []
	shots.append(await _shot(king.id, "rat_king_lash  BEFORE (crown)"))

	var fired := false
	var fire_tick := -1
	for t in RUN_TICKS:
		CombatSim.step(_state, deps)
		_consume_events()
		for id in _views:
			_views[id].sync(_state)
		for _q in 4:
			await get_tree().process_frame
		if t == 10:
			shots.append(await _shot(king.id, "rat_king_lash  WIND-UP"))
		if not fired:
			for e in _state.events_since(maxi(0, _cursor - 6)):
				if e.action_id == action.id and e.kind == CG.EventKind.ACTION_FIRE:
					fired = true
					fire_tick = t
					break
		if fired and t == fire_tick:
			shots.append(await _shot(king.id, "rat_king_lash  CAST"))
		if fired and t == fire_tick + 5:
			shots.append(await _shot(king.id, "rat_king_lash  +5t (rats + hit)"))
		if fired and t == fire_tick + 20:
			shots.append(await _shot(king.id, "rat_king_lash  +20t (3 rats alive)"))
			break

	var stunned := dummy.has_status(CG.Status.STUN)
	print("RatKingLashShot: fired=%s dummy stunned=%s dummy hp=%d/%d" % [
		fired, stunned, dummy.hp, dummy.hp_max,
	])
	var summons := 0
	for e in _state.events:
		if e.kind == CG.EventKind.SUMMONED and e.source_id == king.id:
			summons += 1
	print("RatKingLashShot: summons fired = %d" % summons)

	_save(shots)

func _bare_unit(id: int, shape: StringName, team: CG.Team, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.enemy_id = shape
	u.display_name = String(shape).capitalize()
	u.position = pos
	var edef := EnemyLibrary.get_enemy(shape)
	u.radius = edef.radius if edef != null else 33.0
	u.hp_max = 999999
	u.hp = u.hp_max
	u.resource_max = 999999
	u.resource = 999999
	return u

func _add_view(u: CombatUnit) -> void:
	var view := Node2D.new()
	view.set_script(load("res://Scripts/UI/UnitView.gd"))
	_arena.add_child(view)
	view.bind(_state, u.id)
	_views[u.id] = view

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
	var out := OUT_DIR + "kestrel_757_rat_king_lash.png"
	sheet.save_png(out)
	print("RatKingLashShot: wrote ", out, " (%d frames)" % shots.size())
