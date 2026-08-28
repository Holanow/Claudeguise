extends Node

## Issue 703. Two units, one forced action -- `DummyRoom`'s staging, not a live
## fight -- rendered through a real `BattleView` the way `SellswordShot.gd`
## captures frames. One crop per beat: the small reversed opener with its
## step back, the unchanged signature, the larger reversed finisher.

const OUT := "res://Screenshots/wren_703_crescent_beats.png"
const CROP := Vector2i(520, 320)
const ZOOM := 2
const FRAMES_PER_TICK := 4
## How many sub-tick frames to let a beat's sweep animate before the capture,
## so the shot lands mid-swing rather than on the tween's very first frame.
const SETTLE_FRAMES := 4

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("SellswordBeatsShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	await _run()
	get_tree().quit(0)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))

## The caster's own `intent` is forced once, on `ForceOnce`'s own principle:
## nothing decides for it, so nothing but the beat mechanic can fire here.
func _build_state() -> CombatState:
	var state := CombatState.new(703)
	var caster := CombatSim._build_enemy_unit(0, EnemyLibrary.get_enemy(&"sellsword"), &"sellsword", Vector2(-154, 0))
	## Issue 642: point-sized, so the two bodies never drift toward each
	## other's contact radius through `_separate_phase` before the combo
	## fires -- the same reason `Tools/DummyRoom.gd` zeroes both radii.
	caster.radius = 0.0
	var target := CombatUnit.new()
	target.id = 1
	target.team = CG.Team.PLAYER
	target.radius = 0.0
	target.hp_max = 999999
	target.hp = target.hp_max
	target.resource_max = 999999
	target.resource = 999999
	## Close enough that the opener's own -40 step back still leaves the
	## finisher's gap under every beat's range_units, the same margin
	## `Tools/DummyRoom.gd::_placement_distance` derives for the same reason.
	target.position = Vector2(-140, 0)
	state.units = [caster, target]
	caster.facing = (target.position - caster.position).normalized()
	caster.intent = Intent.use_action(&"sellsword_crescent", target.id)
	return state

func _run() -> void:
	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_view = packed.instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.set_process(false)
	_view.state = _build_state()
	_view.event_cursor = 0
	_view._rebuild_units()
	_view._arena.grid = _view.state.grid
	_view._arena.projectiles = []
	_view._arena.shot_positions = {}
	_view._arena.units = _view.state.units
	_view._arena.queue_redraw()

	var labels := ["1 opener (backstep, reversed)", "2 signature (unchanged)", "3 finisher (larger, reversed)"]
	var shots: Array[Image] = []
	var seen := {}

	for _i in 400:
		_frame()
		await get_tree().process_frame
		for e in _view.state.events_since(maxi(0, _view.event_cursor - 6)):
			if e.action_id != &"sellsword_crescent" or e.kind != CG.EventKind.ACTION_FIRE:
				continue
			if e.beat_index < 0 or seen.has(e.beat_index):
				continue
			seen[e.beat_index] = true
			for _s in SETTLE_FRAMES:
				_frame()
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var full := get_viewport().get_texture().get_image()
			var v: Node2D = _view._unit_views.get(e.source_id)
			var at: Vector2 = Vector2.ZERO if v == null else v.get_global_transform_with_canvas().origin
			var origin := (Vector2i(at) - CROP / 2).clamp(Vector2i.ZERO, full.get_size() - CROP)
			shots.append(full.get_region(Rect2i(origin, CROP)))
			print("SellswordBeatsShot: beat %d (%s) fired at tick %d" % [e.beat_index, labels[e.beat_index], e.tick])
		if seen.size() >= 3 or _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break

	if shots.size() < 3:
		printerr("SellswordBeatsShot: only captured %d of 3 beats; nothing to write" % shots.size())
		return

	var sheet := Image.create(CROP.x * ZOOM * shots.size(), CROP.y * ZOOM, false, shots[0].get_format())
	for i in shots.size():
		var reg := shots[i]
		reg.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(reg, Rect2i(Vector2i.ZERO, CROP * ZOOM), Vector2i(i * CROP.x * ZOOM, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	sheet.save_png(OUT)
	print("SellswordBeatsShot: %s" % OUT)
