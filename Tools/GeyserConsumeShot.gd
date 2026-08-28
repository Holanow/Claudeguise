extends Node

## Issue 657. One frame of a `geyser_blast` landing: on a target already
## burning (steam) or on one that is not (water). Per #280, the proof is
## pixels, not the `when` field parsing. One process per shot -- a scheduled
## `after()` layer lives on the tree, not on the view, so a second build in the
## same process calls into a director the first one already freed.
##
##   godot --path . res://Tools/GeyserConsumeShot.tscn -- consume
##   godot --path . res://Tools/GeyserConsumeShot.tscn -- no_consume

const OUT_CONSUME := "res://Screenshots/curlew_657_geyser_consume.png"
const OUT_NO_CONSUME := "res://Screenshots/curlew_657_geyser_no_consume.png"
const CROP := Vector2i(200, 160)
const ZOOM := 3
const SEED := 7

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	var burning := OS.get_cmdline_user_args().has("consume")
	await _run(burning, OUT_CONSUME if burning else OUT_NO_CONSUME)
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in 4:
		out.append(PawnFactory.make_preset_pawn(&"geysermancer", StringName("g%d" % i), "G%d" % i))
	return out

func _build() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = CG.DEFAULT_ENCOUNTER
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, RoomLibrary.get_room(CG.DEFAULT_ENCOUNTER))
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

## Steps until a `geyser_blast` lands. If `burning`, forces BURN onto its
## target the instant the cast commits (and raises its hp so the DOT cannot
## kill it first) so the shot has something to consume when it lands.
func _to_the_hit(burning: bool) -> Vector2:
	var target_id := -1
	for _i in 6000:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 12)):
			if target_id == -1 and e.action_id == &"geyser_blast" and e.kind == CG.EventKind.ACTION_START:
				target_id = e.target_id
				# Raised on BOTH branches: the shot takes ~34 ticks (wind-up plus
				# travel) to land, and only `burning` should decide the look --
				# not whether the rest of the party kills this target first.
				var t: CombatUnit = _view.state.unit(target_id)
				t.hp_max = 999999
				t.hp = t.hp_max
				if burning:
					t.statuses[CG.Status.BURN] = _view.state.tick + 200
					t.status_magnitude[CG.Status.BURN] = 40.0
			if target_id != -1 and e.action_id == &"geyser_blast" \
					and e.kind == CG.EventKind.DAMAGE and e.target_id == target_id:
				var v: Node2D = _view._unit_views.get(target_id)
				print("GeyserConsumeShot: landed on %d at tick %d, burning=%s" % [target_id, e.tick, burning])
				return Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	printerr("GeyserConsumeShot: no geyser_blast landed in this fight (tick %d outcome %d target_id %d)" \
		% [_view.state.tick, _view.state.outcome, target_id])
	return Vector2.INF

func _run(burning: bool, out_path: String) -> void:
	await _build()
	var at := await _to_the_hit(burning)
	if at == Vector2.INF:
		return
	# Let the delayed IMPACT layers (arrival 0.07s) start, then let gravity pull
	# the two bursts apart -- steam rises, water falls -- before the capture.
	for _i in 26:
		_frame()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
	var shot := full.get_region(Rect2i(origin, CROP))
	shot.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	shot.save_png(out_path)
	print("GeyserConsumeShot: %s" % out_path)
