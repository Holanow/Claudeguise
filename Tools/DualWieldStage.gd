extends Node

## Issue 747: two consecutive `warrior_strike` swings from a dual-wielding
## Warrior, staged the way `Tools/Tier3Stage.gd` stages everything else --
## two units, nobody else, no `Battle.tscn`, a bare `UnitView` pair and a bare
## `VFXDirector`. Unlike `Tier3Stage`, the caster carries a real `PawnData`
## (empty `plans`, so `PlanInterpreter.decide` falls through to the forced
## rig exactly as it does for a starter pawn) because the alternation only
## exists off `pawn.main_hand`/`pawn.off_hand`.
##
##   godot --headless --path . --script res://Tools/DualWieldStage.gd

const OUT_DIR := "res://Screenshots/"
const CROP := Vector2i(420, 320)
const ZOOM := 2
const ACTION_ID := &"warrior_strike"

class ForceRepeat:
	var caster_id: int
	var action_id: StringName
	var target_id: int

	func decide(_state: CombatState, unit: CombatUnit) -> Intent:
		return Intent.use_action(action_id, target_id) if unit.id == caster_id else null

var _arena: Node2D = null
var _caption: Label = null
var _vfx: VFXDirector = null
var _views: Dictionary = {}
var _state: CombatState = null
var _cursor := 0
var _caster: CombatUnit = null

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
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

func _run() -> void:
	_rebuild_scene()

	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"w", "Warrior")
	pawn.off_hand = ItemLibrary.get_equipment(&"wrench")

	_caster = CombatUnit.new()
	_caster.id = 0
	_caster.team = CG.Team.PLAYER
	_caster.hp_max = 999999
	_caster.hp = _caster.hp_max
	_caster.resource_max = 999999
	_caster.resource = 999999
	_caster.pawn = pawn
	_caster.actions = [ACTION_ID]
	_caster.position = Vector2(-CG.ARENA_HALF_WIDTH + 100.0, 0.0)

	## A real shape (`enemy_id`), not a bare dummy -- the first capture had no
	## `enemy_id` here, drew as a black square right beside the caster at
	## melee range, and was mistaken for the weapon.
	var target := CombatUnit.new()
	target.id = 1
	target.team = CG.Team.ENEMY
	target.enemy_id = &"goblin"
	target.radius = 33.0
	target.hp_max = 999999999
	target.hp = target.hp_max
	target.resource_max = 999999
	target.resource = 999999
	target.position = _caster.position + Vector2(35.0, 0.0)
	_caster.facing = (target.position - _caster.position).normalized()

	_state = CombatState.new(1)
	_state.units = [_caster, target]
	_cursor = 0

	var rig := ForceRepeat.new()
	rig.caster_id = _caster.id
	rig.action_id = ACTION_ID
	rig.target_id = target.id
	var deps := SimDeps.new()
	deps.default_decide = Callable(rig, "decide")

	_add_view(_caster)
	_add_view(target)

	var shots: Array[Image] = []
	shots.append(await _shot("BEFORE  last_attack_hand=%d" % _caster.last_attack_hand))

	var swings_seen := 0
	for _t in 600:
		CombatSim.step(_state, deps)
		var fired := _consume_events()
		for id in _views:
			_views[id].sync(_state)
		for _q in 2:
			await get_tree().process_frame
		## Captured at ACTION_FIRE -- the swing's own peak -- rather than a
		## fixed frame count after commit, which put two different swings at
		## two different points in their motion and read as noise, not signal.
		if fired:
			swings_seen += 1
			var hand_name := "MAIN" if _caster.last_attack_hand == EquipmentDef.Slot.MAIN_HAND else "OFF"
			shots.append(await _shot("swing %d  hand=%s  FIRE" % [swings_seen, hand_name]))
		if swings_seen >= 4:
			break

	_save(shots)

func _consume_events() -> bool:
	var events := _state.events_since(_cursor)
	_cursor = _state.events.size()
	var fired := false
	for e in events:
		if e.action_id == ACTION_ID and e.kind == CG.EventKind.ACTION_FIRE:
			fired = true
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
	return fired

func _shot(text: String) -> Image:
	var v: Node2D = _views.get(_caster.id)
	var at := Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
	var origin := Vector2i(at) - CROP / 2
	_caption.text = text
	_caption.global_position = Vector2(origin) + Vector2(4, 4)
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var img := full.get_region(Rect2i(origin, CROP))
	img.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return img

func _save(shots: Array[Image]) -> void:
	if shots.is_empty():
		printerr("DualWieldStage: no frames captured")
		return
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var strip := Image.create(w * shots.size(), h, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		strip.blit_rect(shots[i], Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(w * i, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%sheron_747_dual_wield_strip.png" % OUT_DIR
	strip.save_png(path)
	print("DualWieldStage: %s (%d frames)" % [path, shots.size()])
