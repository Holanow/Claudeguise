extends Node

## Issue 685. The Mercenary Sellsword mid-Crescent, cropped tight -- proof
## `EnemyDef.weapon_part` puts a sword in an enemy's hand, where before this
## issue `UnitView._weapon_part` returned "" for anything with no `pawn`.

const OUT := "res://Screenshots/sable_685_sellsword_crescent.png"
const CROP := Vector2i(150, 130)
const ZOOM := 4
const SEED := 7

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

## A starter pawn (no plan rows) rather than a preset one: `DefaultBehavior`
## decides for it, and never uses Block, so no "Directional Block" status
## badge lands on top of the Sellsword at melee range and hides it.
func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	out.append(PawnFactory.make_starter_pawn(&"warrior", &"g0", "G0"))
	return out

func _build() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = &"floor1_sellsword"
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, Registry.get_encounter(&"floor1_sellsword"))
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

## Steps until sellsword_crescent lands, then holds 10 more ticks -- past the
## wind-up's release point -- and returns the caster.
func _to_the_swing() -> CombatUnit:
	for _i in 6000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if e.action_id == &"sellsword_crescent" and e.kind == CG.EventKind.ACTION_START:
				for _skip in 10 * 4:
					_frame()
					await get_tree().process_frame
				for u in _view.state.units:
					if u.id == e.source_id:
						return u
				return null
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	return null

func _run() -> void:
	await _build()
	var u := await _to_the_swing()
	if u == null:
		printerr("SellswordSwingShot: no sellsword_crescent in this fight")
		return
	var v: Node2D = _view._unit_views.get(u.id)
	if v == null:
		printerr("SellswordSwingShot: no view for unit %d" % u.id)
		return
	## The ally's own view and card, hidden for the capture only, so nothing
	## of its stands between the camera and the Sellsword's sword.
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
	print("SellswordSwingShot: %s" % OUT)
