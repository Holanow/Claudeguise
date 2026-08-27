extends Node

## Issue 685. A real fight, stepped until the Warrior is mid-swing on a melee
## action, cropped tight -- proof the sword rotates with the hand and the
## off-hand counterbalances, not just that a weapon is drawn at rest.

const OUT := "res://Screenshots/sable_685_weapon_swing.png"
const CROP := Vector2i(120, 120)
const ZOOM := 4
const SEED := 0

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	get_viewport().warp_mouse(Vector2(-5000, -5000))
	await _run()
	get_tree().quit(0)

## Starter pawns, not preset: `DefaultBehavior` decides for them and never
## uses Block, so no "Directional Block" status badge covers the swing.
func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in 2:
		out.append(PawnFactory.make_starter_pawn(&"warrior", StringName("w%d" % i), "Warrior %d" % i))
	return out

func _build() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = &"floor1_warden"
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin(cfg)
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

## Steps until a Warrior is roughly two-thirds through a melee wind-up, past
## the release point where the swing-through starts, and returns that unit.
func _to_the_swing() -> CombatUnit:
	for _i in 6000:
		_frame()
		await get_tree().process_frame
		for u in _view.state.units:
			if u.team != CG.Team.PLAYER or u.pawn == null or u.pawn.weapon == null:
				continue
			if u.action_ticks_total <= 0 or u.action_ticks_left <= 0:
				continue
			var action := ActionLibrary.get_action(u.current_action)
			if PartAnimation.kind_for(action) != PartAnimation.Kind.MELEE:
				continue
			var progress := float(u.action_ticks_total - u.action_ticks_left) / float(u.action_ticks_total)
			if progress >= 0.75:
				return u
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	return null

func _run() -> void:
	await _build()
	var u := await _to_the_swing()
	if u == null:
		printerr("WeaponSwingShot: no melee swing found")
		return
	var v: Node2D = _view._unit_views.get(u.id)
	if v == null:
		printerr("WeaponSwingShot: no view for unit %d" % u.id)
		return
	for other in _view.state.units:
		if other.id != u.id:
			var ov: Node2D = _view._unit_views.get(other.id)
			if ov != null:
				ov.visible = false
	if _view._unit_card != null:
		_view._unit_card.dismiss()
	await RenderingServer.frame_post_draw
	var at := v.get_global_transform_with_canvas().origin
	var full := get_viewport().get_texture().get_image()
	var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
	var reg := full.get_region(Rect2i(origin, CROP))
	reg.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	reg.save_png(OUT)
	print("WeaponSwingShot: %s (unit %d, action %s)" % [OUT, u.id, u.current_action])
