extends Node

## Issue 696 tier 3, evidence rebuilt: rook held PR #702 because the first
## strips were filmed inside a real fight, so other pawns cast, died and
## missed in every frame. This stages instead: exactly two units, caster and
## subject, nobody else, forced through `SimDeps.default_decide` with a
## `ForceOnce` rig (`Tools/DummyRoom.gd`'s own pattern, proven at 40/40). No
## `Battle.tscn` -- a bare `UnitView` pair plus a bare `VFXDirector`, wired the
## way `BattleView` wires them. BEFORE is taken before `CombatSim.step` ever
## runs, so the subject is provably at rest.

const OUT_DIR := "res://Screenshots/"
const CROP := Vector2i(420, 320)
const ZOOM := 2
const RUN_TICKS := 600

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

## Which class or enemy casts each action, and whether the second unit's
## SHAPE should read as an ally or a foe. Its TEAM is always the caster's
## opposite regardless of this flag -- `CombatSim._check_outcome` ends the
## fight the instant one team has no living member, and a fight that ends
## after tick 1 freezes `action_ticks_left` forever (issue found staging this
## rig: every self- and ally-target action stalled at wind-up, only the two
## enemy-target marks ever fired). Which unit gets PHOTOGRAPHED is decided
## separately, from `targets_self` / `covers_target`, the same fields
## `Tools/DummyRoom.gd` already reads for the identical reason.
class Rig:
	var action_id: StringName
	var caster_class: StringName = &""
	var caster_enemy: StringName = &""

	func _init(a: StringName, cls: StringName, enemy: StringName) -> void:
		action_id = a
		caster_class = cls
		caster_enemy = enemy

func _build_rigs() -> Array[Rig]:
	var out: Array[Rig] = []
	out.append(Rig.new(&"warrior_guard", &"warrior", &""))
	out.append(Rig.new(&"warrior_taunt", &"warrior", &""))
	out.append(Rig.new(&"warrior_block", &"warrior", &""))
	out.append(Rig.new(&"warrior_second_wind", &"warrior", &""))
	out.append(Rig.new(&"priest_haste", &"priest", &""))
	out.append(Rig.new(&"priest_ward", &"priest", &""))
	out.append(Rig.new(&"priest_heal", &"priest", &""))
	out.append(Rig.new(&"brute_roar", &"", &"brute"))
	out.append(Rig.new(&"spotter_mark", &"siege_master", &""))
	out.append(Rig.new(&"stalker_mark", &"", &"stalker"))
	out.append(Rig.new(&"geyser_cleanse", &"geysermancer", &""))
	out.append(Rig.new(&"channel_mana", &"siege_master", &""))
	return out

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
	for rig in _build_rigs():
		await _capture(rig)

# ---------------------------------------------------------------------------
# Scene: two units, a VFX director, nothing else.
# ---------------------------------------------------------------------------

func _rebuild_scene() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
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

# ---------------------------------------------------------------------------
# Units: real class/enemy shapes, exactly two, placed in range.
# ---------------------------------------------------------------------------

## `pawn` is deliberately left null on every unit here, the same choice
## `Tools/DummyRoom.gd` makes and for the same reason: a real `PawnData`
## reaches `_decide_phase` before `default_decide` does, so `PlanInterpreter`
## would answer for a planless starter pawn instead of `ForceOnce` ever being
## asked. `shape_id()` only wants a string key, and a class id and an enemy id
## are both just that -- `enemy_id` carries either.
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

func _shape_radius(shape: StringName, is_enemy: bool) -> float:
	if is_enemy:
		var edef := EnemyLibrary.get_enemy(shape)
		if edef != null:
			return edef.radius
	return 33.0

func _make_caster(rig: Rig, id: int, pos: Vector2) -> CombatUnit:
	if rig.caster_class != &"":
		return _bare_unit(id, rig.caster_class, CG.Team.PLAYER, pos, _shape_radius(rig.caster_class, false))
	return _bare_unit(id, rig.caster_enemy, CG.Team.ENEMY, pos, _shape_radius(rig.caster_enemy, true))

func _make_second(_rig: Rig, id: int, pos: Vector2, caster_team: CG.Team) -> CombatUnit:
	## Always the caster's opposite team -- see the Rig doc comment.
	var team := _enemy_team(caster_team)
	var shape: StringName = &"goblin" if team == CG.Team.ENEMY else &"warrior"
	return _bare_unit(id, shape, team, pos, _shape_radius(shape, team == CG.Team.ENEMY))

func _enemy_team(team: CG.Team) -> CG.Team:
	return CG.Team.ENEMY if team == CG.Team.PLAYER else CG.Team.PLAYER

# ---------------------------------------------------------------------------
# One action, one strip.
# ---------------------------------------------------------------------------

func _capture(rig: Rig) -> void:
	_rebuild_scene()
	var action: ActionDef = ActionLibrary.get_action(rig.action_id)
	if action == null:
		printerr("Tier3Stage: unknown action %s" % rig.action_id)
		return

	var self_targeted := action.targeting != null and action.targeting.targets_self
	var deps := SimDeps.new()

	var caster := _make_caster(rig, 0, Vector2(-CG.ARENA_HALF_WIDTH + 100.0, 0.0))
	var dist: float = clampf(action.range_units - 1.0, 40.0, 300.0) if action.range_units > 0.0 else 160.0
	var second := _make_second(rig, 1, caster.position + Vector2(dist, 0), caster.team)
	caster.facing = (second.position - caster.position).normalized()
	caster.actions = [rig.action_id]

	## Same budget `Tools/DummyRoom.gd` gives a caster: near-infinite unless
	## the action itself restores the resource, in which case a real ceiling
	## is what makes the gain visible.
	var restore := action.restore_effect()
	if restore != null:
		caster.resource_max = maxi(action.resource_cost, 1) + 1000
		caster.resource = action.resource_cost

	var hit := action.hit()
	if hit != null and hit.heals:
		var wounded := caster if self_targeted else second
		wounded.hp = int(wounded.hp_max / 2)
	if action.has_cleanse():
		second.statuses[CG.Status.BURN] = 999999
		second.status_magnitude[CG.Status.BURN] = 10.0

	_state = CombatState.new(1)
	var units: Array[CombatUnit] = [caster, second]
	_state.units = units
	_cursor = 0

	var rig_once := ForceOnce.new()
	rig_once.caster_id = caster.id
	rig_once.action_id = rig.action_id
	rig_once.target_id = caster.id if self_targeted else second.id
	deps.default_decide = Callable(rig_once, "decide")

	_add_view(caster)
	_add_view(second)

	var subject_id := caster.id if (self_targeted or action.covers_target) else second.id

	var shots: Array[Image] = []
	shots.append(await _shot(subject_id, "%s  BEFORE" % rig.action_id))

	var wind_up := action.wind_up_ticks
	var started := false
	var start_tick := -1
	var wind_up_shot_taken := wind_up <= 2
	var fired := false
	var fire_tick := -1
	var status: CG.Status = -1
	var duration := 0
	for eff in action.effects:
		if eff is StatusEffect:
			status = eff.status
			duration = eff.duration_ticks

	for t in RUN_TICKS:
		CombatSim.step(_state, deps)
		_consume_events()
		for id in _views:
			_views[id].sync(_state)
		for _q in 4:
			await get_tree().process_frame
		if not started:
			for e in _state.events_since(maxi(0, _cursor - 6)):
				if e.action_id == rig.action_id and e.kind == CG.EventKind.ACTION_START:
					started = true
					start_tick = t
					break
		## A wind-up cue (`channel_mana`'s charging orb) plays and can fade
		## entirely between ACTION_START and ACTION_FIRE on a long wind-up, so
		## BEFORE-then-CAST alone would skip over it. One sample at the
		## midpoint catches it without adding a frame to the short wind-ups
		## that do not need one.
		if started and not wind_up_shot_taken and t >= start_tick + maxi(1, wind_up / 2):
			wind_up_shot_taken = true
			shots.append(await _shot(subject_id, "%s  WIND-UP" % rig.action_id))
		if not fired:
			for e in _state.events_since(maxi(0, _cursor - 6)):
				if e.action_id == rig.action_id and e.kind == CG.EventKind.ACTION_FIRE:
					fired = true
					fire_tick = t
					break
		if fired and t == fire_tick:
			shots.append(await _shot(subject_id, "%s  CAST" % rig.action_id))
			break
		if _state.outcome != CombatState.Outcome.UNRESOLVED:
			break

	if not fired:
		printerr("Tier3Stage: %s never fired" % rig.action_id)
		_save(rig.action_id, shots)
		return

	if status != -1 and duration > 0:
		await _sample_status(rig.action_id, subject_id, status, duration, deps, shots)
	else:
		await _sample_punctual(rig.action_id, subject_id, action.wind_up_ticks, action.recover_ticks, deps, shots)

	_save(rig.action_id, shots)

## Spread across the status's own real duration -- offsets clamped to
## `duration - 1` so the last sample lands while it is still up, plus one
## sample past the end to show it drop.
func _sample_status(action_id: StringName, subject_id: int, status: CG.Status, duration: int,
		deps: SimDeps, shots: Array[Image]) -> void:
	var offsets_s: Array[float] = [0.3, 1.0, 2.5, 5.0, 8.0, 12.0]
	var elapsed := 0
	for off in offsets_s:
		var want: int = mini(int(off * CG.TICKS_PER_SECOND), duration + int(CG.TICKS_PER_SECOND * 0.5))
		var step := want - elapsed
		if step <= 0:
			continue
		for _t in step:
			CombatSim.step(_state, deps)
			_consume_events()
			for id in _views:
				_views[id].sync(_state)
			for _q in 4:
				await get_tree().process_frame
			if _state.outcome != CombatState.Outcome.UNRESOLVED:
				break
		elapsed = want
		var u := _state.unit(subject_id)
		var still: bool = u != null and u.has_status(status)
		shots.append(await _shot(subject_id, "%s  +%.1fs  %s" % [action_id, off, "ON" if still else "OFF"]))
		if shots.size() >= 8 or u == null or _state.outcome != CombatState.Outcome.UNRESOLVED:
			break

## A punctual action (heal, restore, cleanse) has no lifetime to spread
## across; sample evenly through wind-up and recover instead.
func _sample_punctual(action_id: StringName, subject_id: int, wind_up: int, recover: int,
		deps: SimDeps, shots: Array[Image]) -> void:
	var span := maxi(4, recover + 6)
	var step := maxi(1, int(ceil(float(span) / 5.0)))
	for _i in 5:
		for _t in step:
			CombatSim.step(_state, deps)
			_consume_events()
			for id in _views:
				_views[id].sync(_state)
			for _q in 4:
				await get_tree().process_frame
			if _state.outcome != CombatState.Outcome.UNRESOLVED:
				break
		shots.append(await _shot(subject_id, "%s  +%dt" % [action_id, (shots.size()) * step]))
		if _state.outcome != CombatState.Outcome.UNRESOLVED:
			break

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

## One row, exactly as wide as the frames taken -- no cell goes unfilled,
## because a strip sized to what it holds cannot carry filler.
func _save(action_id: StringName, shots: Array[Image]) -> void:
	if shots.is_empty():
		return
	var sheet := Image.create(CROP.x * ZOOM * shots.size(), CROP.y * ZOOM, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP * ZOOM), Vector2i(i * CROP.x * ZOOM, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var out := OUT_DIR + "pipit_696_tier3_%s.png" % action_id
	sheet.save_png(out)
	print("Tier3Stage: %s (%d frames)" % [out, shots.size()])
