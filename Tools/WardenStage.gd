extends Node

## Issue 830. `Tools/Tier3Stage.gd`'s shape, widened from two units to five,
## because a throw needs somewhere to land: the whole point of the ability is
## the spot it picks, and a two-unit rig cannot photograph a choice between
## targets. Same bargain otherwise -- no `Battle.tscn`, bare `UnitView`s and a
## bare `VFXDirector`, nobody deciding anything except through `ForceOnce`.
##
## The flight is a MOVEMENT, so this shoots a frame every tick across the whole
## of it rather than one still: `ENGINEER.md` records two features that read
## identically in a pair of screenshots and correctly in a strip.

const OUT_DIR := "res://Screenshots/"
const CROP := Vector2i(520, 360)
const ZOOM := 1

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
	await _capture(&"warden_throw")
	await _capture(&"warden_chain_toss")
	await _capture_combo()
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------

func _rebuild_scene() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = Node2D.new()
	add_child(_arena)
	_arena.position = get_viewport().get_visible_rect().size * 0.5
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
	_caption.add_theme_font_size_override("font_size", 15)
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

## `pawn` stays null for Tier3Stage's reason: a real `PawnData` reaches
## `_decide_phase` ahead of `default_decide`, so `ForceOnce` would never be
## asked. Health is huge so nobody dies and ends the fight mid-strip.
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

# ---------------------------------------------------------------------------
# One ability, one strip
# ---------------------------------------------------------------------------

## The Warden on the left, a loner within reach of it, and a knot of three off
## to the right. The loner is nearest so it is what gets grabbed; the knot is
## the only spot worth aiming at, so a correct landing is unmistakable and a
## lazy one (drop it where it stood) is too.
func _capture(action_id: StringName) -> void:
	_rebuild_scene()
	var warden := _bare_unit(0, &"the_warden", CG.Team.ENEMY, Vector2(-220.0, 0.0),
		EnemyLibrary.get_enemy(&"the_warden").radius)
	warden.move_speed = 0.0
	warden.actions = [action_id]
	var loner := _bare_unit(1, &"warrior", CG.Team.PLAYER, Vector2(-170.0, 0.0), 14.0)
	var knot: Array[CombatUnit] = [
		_bare_unit(2, &"priest", CG.Team.PLAYER, Vector2(30.0, -34.0), 14.0),
		_bare_unit(3, &"geysermancer", CG.Team.PLAYER, Vector2(58.0, 30.0), 14.0),
		_bare_unit(4, &"siege_master", CG.Team.PLAYER, Vector2(4.0, 26.0), 14.0),
	]
	warden.facing = Vector2.RIGHT

	_state = CombatState.new(1)
	var units: Array[CombatUnit] = [warden, loner]
	for k in knot:
		units.append(k)
	_state.units = units
	_cursor = 0

	## The chain reaches past the loner on purpose: `warden_chain_toss`'s own
	## row aims at the FARTHEST enemy, so the strip must show it skip the one
	## standing next to the Warden.
	var subject := loner if action_id == &"warden_throw" else _state.unit(4)
	var once := ForceOnce.new()
	once.caster_id = warden.id
	once.action_id = action_id
	once.target_id = subject.id
	var deps := SimDeps.new()
	deps.default_decide = Callable(once, "decide")

	for u in _state.units:
		_add_view(u)

	var shots: Array[Image] = []
	shots.append(await _shot("%s  BEFORE  everyone at rest" % action_id))

	var fired := false
	var travelling := false
	for t in 400:
		CombatSim.step(_state, deps)
		_consume_events()
		for id in _views:
			_views[id].sync(_state)
		for _q in 3:
			await get_tree().process_frame

		for e in _state.events_since(maxi(0, _cursor - 8)):
			if e.action_id == action_id and e.kind == CG.EventKind.ACTION_FIRE and not fired:
				fired = true
				shots.append(await _shot("%s  CAST  tick %d" % [action_id, t]))

		var moving: bool = subject.throw_ticks_left > 0 or subject.pull_ticks_left > 0
		if moving:
			travelling = true
			shots.append(await _shot("%s  %s  %d left  at %d,%d" % [
				action_id,
				"AIRBORNE" if subject.has_status(CG.Status.AIRBORNE) else "CHAINED",
				maxi(subject.throw_ticks_left, subject.pull_ticks_left),
				int(subject.position.x), int(subject.position.y)]))
		elif travelling:
			shots.append(await _shot("%s  LANDED  at %d,%d" % [
				action_id, int(subject.position.x), int(subject.position.y)]))
			break
		if shots.size() > 20:
			break

	if not travelling:
		printerr("WardenStage: %s never moved anybody" % action_id)
	_save(action_id, shots)

## Issue 836: the three-beat axe. A different shape from the two above -- there
## is no travelling subject to follow, so this shoots one frame per tick from
## the first beat to past the last, and reads the victim's BLEED stack count
## into the caption. Stacks are what make the number of beats that connected
## legible on the target rather than only in a log.
##
## The bleed is a 35% chance per beat, so this searches seeds for one where all
## three land and NAMES it in the caption. Picking the seed is legitimate for a
## demonstration and dishonest if unstated, so it is stated.
func _capture_combo() -> void:
	var action_id := &"warden_axe"
	var beats: int = ActionLibrary.get_action(action_id).beats.size()
	var seed_used := _seed_that_bleeds_most(action_id, beats)
	_rebuild_scene()

	var warden := _bare_unit(0, &"the_warden", CG.Team.ENEMY, Vector2(-60.0, 0.0),
		EnemyLibrary.get_enemy(&"the_warden").radius)
	warden.move_speed = 0.0
	warden.actions = [action_id]
	warden.facing = Vector2.RIGHT
	var victim := _bare_unit(1, &"warrior", CG.Team.PLAYER, Vector2(-10.0, 0.0), 14.0)
	_state = CombatState.new(seed_used)
	var units: Array[CombatUnit] = [warden, victim]
	_state.units = units
	_cursor = 0

	var once := ForceOnce.new()
	once.caster_id = warden.id
	once.action_id = action_id
	once.target_id = victim.id
	var deps := SimDeps.new()
	deps.default_decide = Callable(once, "decide")
	for u in _state.units:
		_add_view(u)

	var shots: Array[Image] = []
	shots.append(await _shot("%s  BEFORE  seed %d  no bleed" % [action_id, seed_used]))
	var landed := 0
	var since_first := -1
	## My own cursor, advanced once per tick and never rewound. `_consume_events`
	## looks BACK over a window so the VFX director cannot miss a cue, and
	## counting beats off that window counted every beat several times: the
	## first strip captioned three beats as "beat 3 of 3" from tick two onward.
	var seen := _state.events.size()
	for t in 400:
		CombatSim.step(_state, deps)
		for i in range(seen, _state.events.size()):
			var e := _state.events[i]
			if e.action_id == action_id and e.kind == CG.EventKind.ACTION_FIRE:
				landed += 1
				## Only the FIRST beat starts the clock. Restarting it on every
				## beat ran the strip to 55 frames instead of 15.
				if since_first < 0:
					since_first = 0
		seen = _state.events.size()
		_consume_events()
		for id in _views:
			_views[id].sync(_state)
		for _q in 3:
			await get_tree().process_frame
		if since_first < 0:
			continue
		shots.append(await _shot("%s  beat %d of %d  +%dt  %d bleed stack(s)" % [
			action_id, mini(landed, beats), beats, since_first,
			int(victim.status_magnitude.get(CG.Status.BLEED, 0.0))]))
		since_first += 1
		if since_first > ActionLibrary.get_action(action_id).beats[-1].delay_ticks + 2:
			break
	if landed == 0:
		printerr("WardenStage: %s never fired" % action_id)
	_save(action_id, shots)

## The first seed whose combo lands the most bleeds, searched headlessly on a
## bare fixture so the strip above spends no frames on rejected seeds.
func _seed_that_bleeds_most(action_id: StringName, beats: int) -> int:
	var best_seed := 1
	var best := -1
	for s in range(1, 60):
		var probe := CombatState.new(s)
		var w := _bare_unit(0, &"the_warden", CG.Team.ENEMY, Vector2(-60.0, 0.0), 33.0)
		w.move_speed = 0.0
		w.actions = [action_id]
		w.facing = Vector2.RIGHT
		var v := _bare_unit(1, &"warrior", CG.Team.PLAYER, Vector2(-10.0, 0.0), 14.0)
		var units: Array[CombatUnit] = [w, v]
		probe.units = units
		var once := ForceOnce.new()
		once.caster_id = w.id
		once.action_id = action_id
		once.target_id = v.id
		var deps := SimDeps.new()
		deps.default_decide = Callable(once, "decide")
		for _t in 60:
			CombatSim.step(probe, deps)
		var stacks := int(v.status_magnitude.get(CG.Status.BLEED, 0.0))
		if stacks > best:
			best = stacks
			best_seed = s
		if best >= beats:
			break
	print("WardenStage: seed %d lands %d bleed stack(s)" % [best_seed, best])
	return best_seed

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

## The whole arena every frame, not a crop that follows the subject: where the
## body goes RELATIVE to the knot is the thing being photographed, and a crop
## centred on the body hides exactly that.
func _shot(text: String) -> Image:
	var full_size := Vector2i(get_viewport().get_visible_rect().size)
	## Inside the crop, not at the viewport's own corner. The first strip put
	## it at (8, 8) and every caption landed outside the region taken.
	var origin := ((full_size - CROP) / 2).clamp(Vector2i.ZERO, full_size - CROP)
	_caption.text = text
	_caption.global_position = Vector2(origin) + Vector2(8, 6)
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var reg := full.get_region(Rect2i(origin, CROP))
	if ZOOM != 1:
		reg.resize(CROP.x * ZOOM, CROP.y * ZOOM, Image.INTERPOLATE_NEAREST)
	return reg

## Wrapped to five per row: a twenty-frame flight in one line is 10,400 pixels
## wide and nobody opens it.
func _save(action_id: StringName, shots: Array[Image]) -> void:
	if shots.is_empty():
		return
	var per_row := 5
	var rows := int(ceil(float(shots.size()) / float(per_row)))
	var w := CROP.x * ZOOM
	var h := CROP.y * ZOOM
	var sheet := Image.create(w * per_row, h * rows, false, shots[0].get_format())
	## A short last row leaves cells nobody wrote, and an uninitialised cell
	## renders WHITE beside a black arena, which reads as part of the evidence.
	sheet.fill(Color.BLACK)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, Vector2i(w, h)),
			Vector2i((i % per_row) * w, (i / per_row) * h))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	## #830 shot the throw and the chain; #836 added the axe combo. The
	## filename carries the issue that produced the strip.
	var issue := "836" if action_id == &"warden_axe" else "830"
	var out := OUT_DIR + "teal_%s_%s.png" % [issue, action_id]
	sheet.save_png(out)
	print("WardenStage: %s (%d frames)" % [out, shots.size()])
