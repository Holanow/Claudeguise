extends Node2D
class_name UnitView


## One combatant on screen: body, health bar, resource bar, name, tags, and the
## wind-up indicator that says an action is coming.

## Scaled for CombatUnit.radius's phone-legibility pass (12.0 -> 22.0) and
## Palette.FONT_SIZE_SMALL going 11 -> 16 alongside it.
const BAR_WIDTH := 60.0
const BAR_HEIGHT := 7.0
const BAR_GAP := 3.0

## The bar is tied to the drawn body, not to a fixed width. At
## `BAR_WIDTH * DISPLAY_SCALE` every unit got 90 while a goblin is 33 across,
## and a bar three times the width of its body reads as a floating object
## rather than as that body's health.
const MIN_BAR_WIDTH := 20.0

## Everything a unit wears -- bar width, the bar stack's anchor, the badge row
## -- measures from the **drawn** body, not from `CombatUnit.radius`.
static var _extents := {}
const _EXTENT_REFERENCE_RADIUS := 100.0

static func drawn_box(shape_id: StringName, team: CG.Team, radius: float) -> Rect2:
	var key := "%s|%d" % [shape_id, int(team)]
	if not _extents.has(key):
		_extents[key] = Silhouettes.drawn_extent(shape_id, _EXTENT_REFERENCE_RADIUS, team)
	var box: Rect2 = _extents[key]
	var scale := radius / _EXTENT_REFERENCE_RADIUS
	return Rect2(box.position * scale, box.size * scale)

## Half the drawn body's width in pixels. Falls back to the footprint when a
## shape measures empty, so an unknown id keeps the decoration it always had.
static func drawn_half_width(shape_id: StringName, team: CG.Team, radius: float) -> float:
	var box := drawn_box(shape_id, team, radius)
	return radius if box.size.x <= 0.0 else box.size.x * 0.5

## How far above centre the drawn body actually reaches. Read off the box's top
## edge rather than assumed symmetric: art that sits low in its canvas has a top
## edge nowhere near `-radius`, which is the `siege_master` case.
static func drawn_top(shape_id: StringName, team: CG.Team, radius: float) -> float:
	var box := drawn_box(shape_id, team, radius)
	return radius if box.size.y <= 0.0 else absf(box.position.y)

static func drawn_bottom(shape_id: StringName, team: CG.Team, radius: float) -> float:
	var box := drawn_box(shape_id, team, radius)
	return radius if box.size.y <= 0.0 else box.end.y

## Sized to the drawn body, floored so a bar stays a bar. The floor is small
## because the point of the issue is that a bar much wider than its creature
## reads as the main object.
static func bar_width(radius: float, shape_id: StringName = &"", team: CG.Team = CG.Team.PLAYER) -> float:
	var body := radius * 2.0 if shape_id == &"" else drawn_half_width(shape_id, team, radius) * 2.0
	return clampf(body, MIN_BAR_WIDTH, BAR_WIDTH * DISPLAY_SCALE)

## The screen scale: margins, shake, floaters and font sizes read it. Issue
## 642 took the body out of it -- `CombatUnit.radius` is now the drawn size.
const DISPLAY_SCALE := 1.5

static func display_radius(u: CombatUnit) -> float:
	return u.radius

var unit_id: int = -1
var _state: CombatState = null

## `should_show_label`'s trigger, plus a hold: once true, stays true for
## LABEL_HOLD_TICKS more, so the name does not blink out the instant the
## trigger flickers. An attacker refocuses or finishes winding up several
## times a second, which is what made the name blink.
const LABEL_HOLD_TICKS := int(CG.TICKS_PER_SECOND * 1.5)

## The hold, and the hp/resource watch that also arms it, keyed by unit id
## rather than held per view. Issue 378 needs plate *visibility* to be a shared
## fact: the row a plate lands on is decided against every other visible plate
## at once, which one view's private timer cannot answer.
## The hp/resource half is why "some enemies never get names" -- a fodder unit
## standing in melee range is hit without ever focusing or winding up itself.
static var _hold_tick := {}
static var _last_hp := {}
static var _last_resource := {}
static var _hold_epoch := -1

## A fight restarts at tick 0 and reuses unit ids, so the holds are dropped
## whenever the clock goes backwards.
static func _watch_holds(state: CombatState) -> void:
	if state.tick == _hold_epoch:
		return
	if state.tick < _hold_epoch:
		_hold_tick.clear()
		_last_hp.clear()
		_last_resource.clear()
	_hold_epoch = state.tick
	for u in state.units:
		if _last_hp.has(u.id) and (u.hp != _last_hp[u.id] or u.resource != _last_resource[u.id]):
			_hold_tick[u.id] = state.tick
		_last_hp[u.id] = u.hp
		_last_resource[u.id] = u.resource

func bind(state: CombatState, id: int) -> void:
	unit_id = id
	sync(state)

## Issue 501: `at` is the drawn position when the caller has already computed it
## for the whole fight, so a hundred bodies do not each walk the array twice.
const RECOMPUTE_AT := Vector2.INF

func sync(state: CombatState, at: Vector2 = RECOMPUTE_AT) -> void:
	_state = state
	_watch_holds(state)
	var u := _unit()
	if u == null:
		return
	position = drawn_position(u, state.units) if at == RECOMPUTE_AT else at
	visible = u.alive
	queue_redraw()
	# Issue 449. Attached from here rather than from the battle screen, the way
	# `PopoutLayer.of` already attaches itself: the arena's hover targets are this
	# file's geometry, and a screen that draws units gets the glossary for free.
	# `load` rather than the class name, so the two files are not a parse cycle.
	var hover = load("res://Scripts/UI/HoverLayer.gd").of(self)
	if hover != null:
		hover.bind(state, get_parent())

## The arena's own rectangle, in the local space every UnitView and floater is
## a child of. Issue 378: nothing the arena draws may leave it.
const ARENA_BOUNDS := Rect2(
	Vector2(-CG.ARENA_HALF_WIDTH, -CG.ARENA_HALF_HEIGHT),
	Vector2(CG.ARENA_HALF_WIDTH * 2.0, CG.ARENA_HALF_HEIGHT * 2.0))

## The shift that brings `rect` back inside the arena, zero when it already is.
## Something wider than the arena is pinned to the left/top edge rather than
## fought over.
static func into_arena(rect: Rect2) -> Vector2:
	return Vector2(
		maxf(0.0, ARENA_BOUNDS.position.x - rect.position.x) - maxf(0.0, rect.end.x - ARENA_BOUNDS.end.x),
		maxf(0.0, ARENA_BOUNDS.position.y - rect.position.y) - maxf(0.0, rect.end.y - ARENA_BOUNDS.end.y))

## Where the body is drawn: the simulated position, and whatever it takes to
## keep the drawn body inside the arena. The playtester measured a Siege Engine
## at y=550-645 against a border at y=633 -- the simulation clamps a unit's
## centre, and a body has a radius.
static func drawn_position(u: CombatUnit, _units: Array = []) -> Vector2:
	var at := u.position
	var body := drawn_box(shape_id(u), u.team, display_radius(u))
	return at + into_arena(Rect2(at + body.position, body.size))

## should_show_label's immediate trigger, plus a hold: once true, stays true
## for LABEL_HOLD_TICKS more so the name does not blink out the instant the
## trigger condition itself flickers.
static func label_visible(u: CombatUnit, state: CombatState) -> bool:
	if should_show_label(u, state.units):
		_hold_tick[u.id] = state.tick
		return true
	return state.tick - int(_hold_tick.get(u.id, -1000000000)) <= LABEL_HOLD_TICKS

## Which way the body is drawn, from `CombatUnit.facing` -- the same quantity
## `_shot_is_blocked` reads to decide whether the Warrior's guard stops a shot,
## so drawing anything else decides an outcome on a fact it refuses to show.
static func facing_left(u: CombatUnit) -> bool:
	if u.facing.x != 0.0:
		return u.facing.x < 0.0
	return u.team == CG.Team.ENEMY

func _unit() -> CombatUnit:
	if _state == null:
		return null
	return _state.unit(unit_id)

## Class id for a pawn, enemy id for an enemy. Silhouettes.draw_unit falls
## back to a hollow diamond for any id it does not know, so this is safe to
## call before teal's content registers real classes or enemies.
static func shape_id(u: CombatUnit) -> StringName:
	if u.pawn != null and u.pawn.pawn_class != null:
		return u.pawn.pawn_class.id
	return u.enemy_id

func _shape_id(u: CombatUnit) -> StringName:
	return shape_id(u)

## The class's first damage type colours its accent shapes. Enemies have no
## class to read one from, so they fall back to physical until there is a
## reason to look one up on EnemyDef instead.
func _accent(u: CombatUnit) -> int:
	if u.pawn != null and u.pawn.pawn_class != null and not u.pawn.pawn_class.damage_types.is_empty():
		return u.pawn.pawn_class.damage_types[0]
	return CG.DamageType.PHYSICAL

## Issue 516. Both halves of the impact under one id: they are one effect, and
## what the player A/Bs is the feel rather than the parts.
const IMPACT_OPTION := &"impact_squash"

## How long each half lasts. Short on purpose: the simulation lands blows 15
## times a second, and a decay longer than a tick is still running when the
## next one arrives.
const SQUASH_SECONDS := 0.22
const RECOIL_SECONDS := 0.18

## How far the struck body compresses, as a fraction of its drawn size. It
## widens by the same amount, so the silhouette keeps roughly its area.
const SQUASH_AMOUNT := 0.22

## How far the attacker is thrown back, in arena pixels.
const RECOIL_PIXELS := 7.0 * DISPLAY_SCALE

## Issue 531. How far a ranged attacker kicks back at the moment it looses.
## Smaller than a melee recoil on purpose: nothing was struck, and a full impact
## kick reads as the archer being hit rather than as the archer firing.
const LOOSE_PIXELS := 4.0 * DISPLAY_SCALE

## Fast in, slow out: full at the moment of the blow, easing to nothing. Cubic
## rather than linear because a linear return reads as a slide rather than as a
## body springing back.
static func impact_decay(age: float, span: float) -> float:
	if span <= 0.0 or age < 0.0 or age >= span:
		return 0.0
	var left := 1.0 - age / span
	return left * left * left

static func squash_scale(age: float) -> Vector2:
	var k := SQUASH_AMOUNT * impact_decay(age, SQUASH_SECONDS)
	return Vector2(1.0 + k, 1.0 - k)

static func recoil_offset(age: float, direction: Vector2, pixels: float = RECOIL_PIXELS) -> Vector2:
	return direction * (pixels * impact_decay(age, RECOIL_SECONDS))

## Issue 553. The struck body goes white for a moment. Its own toggle rather
## than a part of `impact_squash`: one is a shape and one is a colour, and the
## player asked to see this one on its own.
const FLASH_OPTION := &"hit_flash"

## Shorter than the squash on purpose. A flash that outlasts a blow reads as a
## status the unit is carrying rather than as the blow landing.
const FLASH_SECONDS := 0.12

## How white the body goes at the moment of the blow. Short of 1.0 so the
## silhouette still reads as itself rather than as a blank plate.
const FLASH_STRENGTH := 0.85

## How far the flash leans toward the damage type's own colour: 0.0 is white,
## 1.0 is the colour itself. White is what ships -- the floater, the ring and
## the debris already carry the type, and this is the one mark whose whole job
## is "that body, right now".
const FLASH_TINT := 0.0

## The live value, so `Tools/FlashShot.gd` can photograph both treatments in one
## run without a rebuild. Reset with `reset_flash_tint`.
static var flash_tint: float = FLASH_TINT

static func reset_flash_tint() -> void:
	flash_tint = FLASH_TINT

static func flash_strength(age: float) -> float:
	return FLASH_STRENGTH * impact_decay(age, FLASH_SECONDS)

static func flash_color(damage_type: int) -> Color:
	if flash_tint <= 0.0 or damage_type < 0:
		return Color.WHITE
	return Color.WHITE.lerp(Palette.damage_color(damage_type), clampf(flash_tint, 0.0, 1.0))

## `INF` is "not running": adding a delta to it leaves it not running.
var _squash_age: float = INF
var _flash_age: float = INF
## The damage type the live flash was told to lean toward. `-1` is "none given",
## which stays white whatever `flash_tint` is.
var _flash_type: int = -1
var _recoil_age: float = INF
var _recoil_direction: Vector2 = Vector2.ZERO
## How far the live recoil throws this body: a melee blow and a loose differ in
## distance only, so they share one age, one decay and one draw.
var _recoil_pixels: float = RECOIL_PIXELS

## Refused while the option is off, so nothing can start an effect that will
## never be drawn and nothing can leave a body scaled when it is turned off.
## Two independent toggles: the shape and the colour each answer for themselves.
func struck(damage_type: int = -1) -> void:
	if DisplayOptions.enabled(IMPACT_OPTION):
		_squash_age = 0.0
	if DisplayOptions.enabled(FLASH_OPTION):
		_flash_age = 0.0
		_flash_type = damage_type
	queue_redraw()

func recoiled(direction: Vector2, pixels: float = RECOIL_PIXELS) -> void:
	if not DisplayOptions.enabled(IMPACT_OPTION) or direction == Vector2.ZERO:
		return
	_recoil_age = 0.0
	_recoil_direction = direction.normalized()
	_recoil_pixels = pixels
	queue_redraw()

## The flash is in here because `BattleView._render` only spends a delta on a
## view this says is busy. Left out, a flash shorter than the squash would stop
## decaying the moment the squash expired and stay half-white for good.
func impact_active() -> bool:
	return _squash_age < SQUASH_SECONDS or _recoil_age < RECOIL_SECONDS \
		or _flash_age < FLASH_SECONDS

## Spent on rendered frames rather than on ticks, because a tick-driven recovery
## is three or four steps long and reads as a stutter rather than as a spring --
## but spent by `BattleView._render` rather than by a `_process` of this view's
## own, so that a hit stop (#515) holds the decay along with everything else.
func advance_impact(delta: float) -> void:
	_squash_age += delta
	_recoil_age += delta
	_flash_age += delta
	if not impact_active():
		_squash_age = INF
		_recoil_age = INF
		_flash_age = INF
		_flash_type = -1
		_recoil_direction = Vector2.ZERO
		_recoil_pixels = RECOIL_PIXELS
	queue_redraw()

## Issue 583. Hands that bob, thrust, draw and cast. One toggle for the whole
## system rather than one per motion: what the player A/Bs is whether bodies
## move at all.
const ANIM_OPTION := &"part_animation"

## View seconds this body has been alive for, and the render alpha of the frame
## being drawn. Both are spent by `BattleView._render`, which is what makes a
## pause and a hit stop hold the animation: `_process` returns above `_render`
## while `ViewClock.frozen`, so nothing here is ever advanced through a freeze.
var _anim_seconds: float = 0.0
var _anim_alpha: float = 0.0

static func animating() -> bool:
	return DisplayOptions.enabled(ANIM_OPTION)

func advance_anim(delta: float, alpha: float) -> void:
	_anim_seconds += delta
	_anim_alpha = alpha
	queue_redraw()

## `recover_ticks_left`'s own total, since `CombatUnit` stores only the
## countdown. Captured the first tick it is seen (always its max, counting
## down from there) and dropped back to 0 once recovery clears, so a fresh
## action always starts from a clean total rather than one left over.
var _recover_total: int = 0

func _track_recover(u: CombatUnit) -> void:
	if u.recover_ticks_left <= 0:
		_recover_total = 0
	elif u.recover_ticks_left > _recover_total:
		_recover_total = u.recover_ticks_left

## `progress` through the current wind-up or recover phase, which of the three
## shared motions it is, and whether this is the recover half -- or IDLE with
## `progress` 0 while nothing is winding up or recovering. Both hands and the
## weapon derive their pose from this one triple, which is what keeps them
## moving as one thing rather than three separately-timed ones.
func _action_progress(u: CombatUnit) -> Array:
	_track_recover(u)
	if u.action_ticks_total > 0 and u.action_ticks_left > 0:
		var done := float(u.action_ticks_total - u.action_ticks_left) + _anim_alpha
		var kind := PartAnimation.kind_for(ActionLibrary.get_action(u.current_action))
		return [kind, done / float(u.action_ticks_total), false]
	if u.recover_ticks_left > 0 and u.current_action != &"" and _recover_total > 0:
		var kind := PartAnimation.kind_for(ActionLibrary.get_action(u.current_action))
		var done := float(_recover_total - u.recover_ticks_left) + _anim_alpha
		return [kind, clampf(done / float(_recover_total), 0.0, 1.0), true]
	return [PartAnimation.Kind.IDLE, 0.0, false]

## Where the main hand and the weapon it holds sit this frame, in the body's
## own draw space. The idle bob runs underneath the action pose rather than
## being replaced by it, so a body mid-wind-up is still breathing.
##
## Not turned round for facing the way it used to be: the mirror is a scale on
## `UnitVisual`'s own node now, so a child offset is mirrored with the body.
func _part_offset(u: CombatUnit, radius: float) -> Vector2:
	var off := PartAnimation.idle_offset(_anim_seconds, PartAnimation.phase_for(u.id), radius)
	var kp := _action_progress(u)
	if kp[0] != PartAnimation.Kind.IDLE:
		off += PartAnimation.recover_offset(kp[0], kp[1], radius) if kp[2] \
			else PartAnimation.action_offset(kp[0], kp[1], radius)
	return off

## The off hand's own quieter echo: same idle, a fraction of the main hand's
## action pose. One arm swings, the other counterbalances.
func _off_hand_offset(u: CombatUnit, radius: float) -> Vector2:
	var off := PartAnimation.idle_offset(_anim_seconds, PartAnimation.phase_for(u.id), radius)
	var kp := _action_progress(u)
	if kp[0] != PartAnimation.Kind.IDLE:
		off += PartAnimation.recover_offset(kp[0], kp[1], radius) * PartAnimation.OFF_HAND_SHARE if kp[2] \
			else PartAnimation.off_hand_offset(kp[0], kp[1], radius)
	return off

## How far the main hand and its weapon are turned this frame. Only a melee
## wind-up turns at all; a draw and a cast hold the weapon steady.
func _part_angle(u: CombatUnit) -> float:
	var kp := _action_progress(u)
	return PartAnimation.recover_angle(kp[0], kp[1]) if kp[2] else PartAnimation.action_angle(kp[0], kp[1])

func _off_hand_angle(u: CombatUnit) -> float:
	var kp := _action_progress(u)
	if kp[2]:
		return -PartAnimation.recover_angle(kp[0], kp[1]) * PartAnimation.OFF_HAND_SHARE
	return PartAnimation.off_hand_angle(kp[0], kp[1])

## The part this unit's weapon draws in the `Weapon` slot. Falls back to
## `EnemyDef.weapon_part` for a unit with no `pawn` at all.
func _weapon_part(u: CombatUnit) -> StringName:
	if u.pawn != null:
		return &"" if u.pawn.main_hand == null else u.pawn.main_hand.part
	var enemy_def := EnemyLibrary.get_enemy(u.enemy_id)
	return &"" if enemy_def == null else enemy_def.weapon_part

## Whether this body has anything to animate at all. False means the toggle is
## off or this recipe puts nothing in its `HandMain`/`HandOff` slots, and
## either way the body is posed exactly as it was baked.
## Where this body's main hand is drawn, in arena space. A cast leaves the
## hand, and the hand moves through the whole wind-up, so a beam anchored to
## the body centre visibly detaches from the pose that is throwing it.
## Every hand this body has, in arena space, tracked separately, main hand
## first. Empty when the recipe puts nothing in its hand slots.
func hand_anchors() -> PackedVector2Array:
	var out := PackedVector2Array()
	if _visual == null:
		return out
	for p in _visual.slot_points(&"HandMain"):
		out.append(position + p)
	for p in _visual.slot_points(&"HandOff"):
		out.append(position + p)
	return out

func hand_anchor() -> Vector2:
	if _visual == null:
		return position
	return position + _visual.slot_offset(&"HandMain")

func can_animate(u: CombatUnit) -> bool:
	return animating() and UnitRecipes.has_animated_part(_shape_id(u))

## The sprite tree, built once per body and re-posed every frame. Everything that
## moves a body -- facing, the impact squash, the recoil, the hands -- is a
## transform on a node in here, and nothing under it is redrawn to do it.
var _visual: UnitVisual = null

func _sync_visual(u: CombatUnit, radius: float) -> void:
	if _visual == null:
		_visual = UnitVisual.new()
		add_child(_visual)
	_visual.build(_shape_id(u), u.team, radius, _weapon_part(u))
	_visual.pose(facing_left(u), squash_scale(_squash_age),
		recoil_offset(_recoil_age, _recoil_direction, _recoil_pixels),
		drawn_bottom(_shape_id(u), u.team, radius))
	var animate := can_animate(u)
	var full_offset := _part_offset(u, radius) if animate else Vector2.ZERO
	var full_angle := _part_angle(u) if animate else 0.0
	var share_offset := _off_hand_offset(u, radius) if animate else Vector2.ZERO
	var share_angle := _off_hand_angle(u) if animate else 0.0
	## Issue 747: on a dual-wielder's off-hand swing, the full motion moves to
	## HandOff and HandMain takes the quieter share instead -- everyone else
	## takes the branch below unchanged, since `dual_wields` is false for them.
	var off_hand_swings := animate and DefaultPlan.dual_wields(u.pawn) \
		and u.last_attack_hand == EquipmentDef.Slot.OFF_HAND
	var main_offset := share_offset if off_hand_swings else full_offset
	var main_angle := share_angle if off_hand_swings else full_angle
	_visual.offset_slot(&"HandMain", main_offset)
	_visual.offset_slot(&"Weapon", main_offset)
	_visual.rotate_slot(&"HandMain", main_angle)
	_visual.rotate_slot(&"Weapon", main_angle)
	_visual.offset_slot(&"HandOff", full_offset if off_hand_swings else share_offset)
	_visual.rotate_slot(&"HandOff", full_angle if off_hand_swings else share_angle)
	_visual.flash(flash_color(_flash_type), flash_strength(_flash_age))
	_visual.set_focus_line(_focus_line_to(u))

## Who is this unit currently after. Answers "why is that side winning" by itself,
## before a single number changes: a target being focused by three units at once
## reads differently from one being ignored. `INF` is no line, and `UnitVisual`
## draws it under the body.
func _focus_line_to(u: CombatUnit) -> Vector2:
	if u.focus_id < 0 or u.current_action == &"":
		return Vector2.INF
	if _has_active_projectile(u):
		return Vector2.INF
	var target := _state.unit(u.focus_id)
	if target == null or not target.alive:
		return Vector2.INF
	return target.position - u.position

func _draw() -> void:
	var u := _unit()
	if u == null:
		return

	var radius := display_radius(u)

	_sync_visual(u, radius)

	_draw_concentration_badge(u, radius)

	# The wind-up bar and the badge row hang under the body, so a
	# unit on the bottom edge drew them past the border (issue 378). The block
	# is measured first and lifted as one, rather than the body moving whenever
	# a status lands.
	_draw_wind_up(u, radius, below_block_top(u, _state.units))
	_draw_below_block(u)

	var width := bar_width(radius, _shape_id(u), u.team)
	var bar_height := BAR_HEIGHT * DISPLAY_SCALE
	var bar_gap := BAR_GAP * DISPLAY_SCALE
	var y := -drawn_top(_shape_id(u), u.team, radius) - bar_gap
	var stack_bottom := y

	if u.resource_max > 0:
		y -= bar_height
		var res_pos := Vector2(-width * 0.5, y)
		var res_fraction := float(u.resource) / float(u.resource_max)
		draw_rect(Rect2(res_pos, Vector2(width, bar_height)), Palette.HP_BACK)
		draw_rect(Rect2(res_pos, Vector2(width * res_fraction, bar_height)), Palette.resource_color(u.resource_kind))
		y -= bar_gap

	y -= bar_height
	var hp_pos := Vector2(-width * 0.5, y)
	draw_rect(Rect2(hp_pos, Vector2(width, bar_height)), Palette.HP_BACK)
	draw_rect(Rect2(hp_pos, Vector2(width * u.hp_fraction(), bar_height)), hp_fill_color(u))
	_draw_bar_tether(u, stack_bottom)

## Issue 440: the line that says which pawn this name belongs to. Same device
## as the bar tether below, for the same reason -- measured over 24,735 drawn
## plate-ticks, a plate reads as the wrong pawn 45.7% of the time and as nobody
## 10.5%, and 52.7% of that is already true at the un-moved home row, so
## nearness to a body cannot be the cue that ties a name to its owner.
## Issue 321: drawn by `ArenaTextLayer` onto its canvas rather than by the unit
## it belongs to, so no other unit's bars can land on top of it.
static func draw_plate_tether(ci: CanvasItem, u: CombatUnit, units: Array, chip: Rect2,
		body_at: Vector2 = RECOMPUTE_AT) -> void:
	var points := plate_tether(u, units, chip, body_at)
	var color := Palette.team_color(u.team)
	color.a = TETHER_ALPHA
	# Backed, the way the focus line is: the bar tether is ten pixels
	# long and this one crosses the scrum, so it needs the same dark stroke
	# under it to stay a line over a body.
	ci.draw_line(points[0], points[1], Color(Palette.BACKGROUND, 0.5), TETHER_WIDTH * 3.0)
	ci.draw_line(points[0], points[1], color, TETHER_WIDTH)

## The tether's two ends in ARENA-local pixels: the middle of the plate's
## bottom edge, and the top of its own unit's bar stack.
## Issue 511: `body_at` is the interpolated position when the caller has one, so
## the tether ends on the bar stack the player is looking at rather than on the
## one the last tick left behind.
static func plate_tether(u: CombatUnit, units: Array, chip: Rect2,
		body_at: Vector2 = RECOMPUTE_AT) -> PackedVector2Array:
	var at := drawn_position(u, units) if body_at == RECOMPUTE_AT else body_at
	return PackedVector2Array([
		Vector2(chip.get_center().x, chip.end.y),
		at + Vector2(0.0, bar_stack_top(u))])

## The box the bar stack covers, in ARENA-local pixels. The one place that
## geometry is readable from outside `_draw`, so a test can ask what a name
## would be drawn under.
static func bar_stack_rect(u: CombatUnit, units: Array) -> Rect2:
	var radius := display_radius(u)
	var shape := shape_id(u)
	var width := bar_width(radius, shape, u.team)
	var bar_height := BAR_HEIGHT * DISPLAY_SCALE
	var bottom := -drawn_top(shape, u.team, radius) - BAR_GAP * DISPLAY_SCALE
	var top := bottom - bar_height
	if u.resource_max > 0:
		top -= bar_height + BAR_GAP * DISPLAY_SCALE
	return Rect2(drawn_position(u, units) + Vector2(-width * 0.5, top),
		Vector2(width, bottom - top))

## Where the bars end and the plate's gap begins, read back out of
## `label_baseline` so the two cannot drift apart.
static func bar_stack_top(u: CombatUnit) -> float:
	return label_baseline(u) + BAR_GAP * DISPLAY_SCALE + float(label_font_size())

## The baseline the name plate's text sits on, in this view's local space:
## clear of the body, the resource bar and the hp bar. Split out because
## `plate_rect` and `_draw` must agree.
static func label_baseline(u: CombatUnit) -> float:
	var radius := display_radius(u)
	var shape := shape_id(u)
	var bar_height := BAR_HEIGHT * DISPLAY_SCALE
	var bar_gap := BAR_GAP * DISPLAY_SCALE
	var y := -drawn_top(shape, u.team, radius) - bar_gap
	if u.resource_max > 0:
		y -= bar_height + bar_gap
	y -= bar_height
	return y - bar_gap - float(label_font_size())

## The chip a name plate occupies, in ARENA-local pixels, clamped into the
## arena. This is the one place the plate's geometry exists: `_draw` renders
## it, `plate_ranks` de-collides against it and `Tools/ArenaSpill.gd` measures
## it, so an instrument cannot drift from what ships.
static func plate_rect(u: CombatUnit, units: Array, row: int = -1) -> Rect2:
	var which := row if row >= 0 else crowd_rank(u, units)
	var step: Vector2 = PLATE_ROWS[clampi(which, 0, PLATE_ROWS.size() - 1)]
	var text_size := _measure(u.display_name, label_font_size())
	var pad := Vector2(3.0, 2.0) * DISPLAY_SCALE
	# Sideways in units of this plate's own width: a fixed step cannot move
	# "Goblin Archer" clear of "Goblin Archer".
	var nudge := Vector2(
		step.x * maxf(CROWD_STEP, (text_size.x + pad.x * 2.0) * 0.6),
		step.y * plate_row_height())
	var at := drawn_position(u, units) + nudge
	var chip := Rect2(
		at + Vector2(-text_size.x * 0.5 - pad.x, label_baseline(u) - text_size.y),
		text_size + pad * 2.0)
	chip.position += into_arena(chip)
	# `into_arena` is a subtraction, and subtracting a float from itself lands
	# a plate pushed off the right edge at 480.00006 against a border at 480.
	chip.position.x = clampf(chip.position.x, ARENA_BOUNDS.position.x,
		maxf(ARENA_BOUNDS.position.x, ARENA_BOUNDS.end.x - chip.size.x))
	chip.position.y = clampf(chip.position.y, ARENA_BOUNDS.position.y,
		maxf(ARENA_BOUNDS.position.y, ARENA_BOUNDS.end.y - chip.size.y))
	return chip

## Where a plate goes when the row under it is taken: x in CROWD_STEP, y in
## whole rows.
## The last four step sideways on purpose: near the arena's ceiling every
## upward row clamps back to the same y, so lifting alone stops separating
## anything and only a horizontal move does.
const PLATE_ROWS := [
	Vector2(0.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, -2.0), Vector2(0.0, -3.0),
	Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0),
	Vector2(1.0, -2.0), Vector2(-1.0, -2.0), Vector2(0.0, -4.0), Vector2(0.0, -5.0),
	Vector2(2.0, 0.0), Vector2(-2.0, 0.0), Vector2(2.0, -2.0), Vector2(-2.0, -2.0),
	Vector2(3.0, 0.0), Vector2(-3.0, 0.0), Vector2(3.0, -1.0), Vector2(-3.0, -1.0),
	Vector2(4.0, 0.0), Vector2(-4.0, 0.0), Vector2(4.0, -1.0), Vector2(-4.0, -1.0),
]

## `get_string_size` is called once per plate per candidate row per unit per
## frame; there are a handful of distinct names in a fight.
static var _text_sizes := {}

static func _measure(text: String, size: int) -> Vector2:
	var key := "%s|%d" % [text, size]
	if not _text_sizes.has(key):
		_text_sizes[key] = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	return _text_sizes[key]

## Issue 187, and TWO independent cold readers reported it before it was filed:
const TETHER_WIDTH := 1.0 * DISPLAY_SCALE
const TETHER_ALPHA := 0.55

func _draw_bar_tether(u: CombatUnit, stack_bottom: float) -> void:
	var color := Palette.team_color(u.team)
	color.a = TETHER_ALPHA
	draw_line(Vector2(0.0, stack_bottom), Vector2.ZERO, color, TETHER_WIDTH)

## Issue 82, and the finding that forced it: **`Palette.HP_LOW` and
## `Palette.TEAM_ENEMY` are the same colour, `e0705f`.** So every unit's bar ran
## the same red-to-green ramp regardless of side, a hurt party pawn was drawn in
## the enemy's own colour, and a fresh reader reported the field as "green
## dashes" that never answered *am I ahead* -- the first question a spectator
## has.
static func hp_fill_color(u: CombatUnit) -> Color:
	var team := Palette.team_color(u.team)
	# Floored well above zero so a nearly-dead unit is still legibly its own
	# side rather than fading into the trough it sits in.
	return Palette.HP_BACK.lerp(team, clampf(0.45 + u.hp_fraction() * 0.55, 0.0, 1.0))

## Palette.FONT_SIZE_SMALL is shared with screens that have nothing to do
## with the arena (InspectPanel's attribute chips, PartySelect), so it is
## not something this file can change -- scaled locally instead, the same
## reasoning DISPLAY_SCALE itself exists for.
static func label_font_size() -> int:
	return int(round(Palette.FONT_SIZE_SMALL * DISPLAY_SCALE))

## One sideways step of crowding nudge.
const CROWD_STEP := 20.0 * DISPLAY_SCALE

## One row of upward lift. Derived from the font rather than fixed: a step
## shorter than a chip cannot clear the chip below it, which is how a 30-pixel
## step under a 40-pixel plate sent every crowded name two rows up instead of
## one.
static func plate_row_height() -> float:
	return _measure("X", label_font_size()).y + 4.0 * DISPLAY_SCALE + 2.0

## Issue 41: a dense room (floor1_room1, 10 enemies) piled every enemy's name
## into the top-middle of the screen at once, and no amount of vertical
## stagger reads as separate names once four labels share the same few rows
## -- see Screenshots/label_crowd_before_1280x720.png. Raising DISPLAY_SCALE
## further (2.0x, tried in issue 31) made it worse, not better: this is a
## count problem, not a spacing constant to retune again.
static func should_show_label(u: CombatUnit, units: Array) -> bool:
	if u.team == CG.Team.PLAYER:
		return true
	if concentration_count(u, units) > 0:
		return true
	return u.action_ticks_left > 0 and u.current_action != &""

## Which row this unit's plate sits on. Issue 378, and it is the same defect
## #367 fixed for death plates: this compared two POINTS against a 105-unit
## radius, and what collides is a chip as wide as the name. That radius could
## not see two Goblins 120 apart whose 110-pixel plates overlap by 81, which is
## where `AbRatnation` and `SiegSiege Engine` came from.
static func crowd_rank(u: CombatUnit, units: Array) -> int:
	return int(plate_ranks(units).get(u.id, 0))

## The first free row for every plate that could be up, assigned in id order so
## two views of the same fight agree on where a name lands. Rows are tested as
## rectangles, which is the whole point.
##
## `state` restricts the search to the plates that are actually drawn: without
## it a plate gives way to a name nobody can see, and a row spent on an unseen
## plate is a row the next visible one cannot have.
static func plate_ranks(units: Array, state: CombatState = null) -> Dictionary:
	var candidates: Array = []
	for u in units:
		if u.alive and (state == null or label_visible(u, state)):
			candidates.append(u)
	candidates.sort_custom(func(a, b): return a.id < b.id)

	var placed: Array[Rect2] = []
	var ranks := {}
	for u in candidates:
		var best_row := 0
		var best_area := INF
		for row in PLATE_ROWS.size():
			var chip := plate_rect(u, units, row)
			var area := overlap_area(chip, placed)
			if area < best_area:
				best_area = area
				best_row = row
			if area <= 0.0:
				break
		placed.append(plate_rect(u, units, best_row))
		ranks[u.id] = best_row
	return ranks

## Total area this chip loses to what is already placed. Zero is a free row;
## past that the least-bad row wins, because a fourteen-unit scrum can exhaust
## every row and falling off the end onto the last one is the worst of them.
static func overlap_area(chip: Rect2, placed: Array[Rect2]) -> float:
	var area := 0.0
	for p in placed:
		var hit := chip.intersection(p)
		if hit.size.x > 0.0 and hit.size.y > 0.0:
			area += hit.size.x * hit.size.y
	return area

## Every plate's final chip, laid out against each other and clamped into the
## arena. Cached: `_draw` asks once per unit per frame and the layout is O(n^2)
## in a fourteen-unit scrum, so it is computed once per distinct world state.
static var _layout_key := ""
static var _layout := {}

static func plate_layout(state: CombatState) -> Dictionary:
	var key := _layout_key_for(state)
	if key != _layout_key:
		_layout_key = key
		_layout = {}
		var ranks := plate_ranks(state.units, state)
		for u in state.units:
			if ranks.has(u.id):
				_layout[u.id] = plate_rect(u, state.units, int(ranks[u.id]))
	return _layout

## Everything the layout reads: who is alive, where they are standing, and
## which names are up.
static func _layout_key_for(state: CombatState) -> String:
	var h := 17
	for u in state.units:
		h = h * 31 + hash([u.id, u.alive, roundi(u.position.x), roundi(u.position.y),
			u.alive and label_visible(u, state)])
	return "%d|%d|%d" % [state.units.size(), h, state.tick]

func _has_active_projectile(u: CombatUnit) -> bool:
	if _state == null:
		return false
	for p in _state.projectiles:
		if p.source_id == u.id and not p.resolved:
			return true
	return false

## How many other living units currently have this one as their focus --
## "is this unit under fire from more than one thing at once", which issue 15
## found was completely invisible: a scrum of three attackers on one pawn
## looked identical to three attackers merely standing near it. Split out for
## testing without a live canvas, same reasoning as status_badges.
static func concentration_count(u: CombatUnit, units: Array) -> int:
	var count := 0
	for other in units:
		if other.id == u.id or not other.alive:
			continue
		if other.focus_id == u.id:
			count += 1
	return count

const CONCENTRATION_THRESHOLD := 2

## Issue 198: 8, not 11, and drawn as an arc rather than a filled disc.
const CONCENTRATION_BADGE_RADIUS := 8.0 * DISPLAY_SCALE
const CONCENTRATION_BADGE_WIDTH := 2.0

## Only drawn once concentration is actually worth flagging (2+): a badge on
## every unit all the time would be noise, and the issue this answers is
## specifically "three attackers on one pawn read as nothing at all", not
## "who has a target".
func _draw_concentration_badge(u: CombatUnit, radius: float) -> void:
	if _state == null:
		return
	var count := concentration_count(u, _state.units)
	if count < CONCENTRATION_THRESHOLD:
		return
	var shape := _shape_id(u)
	var half := drawn_half_width(shape, u.team, radius)
	var badge_radius := clampf(half * 0.45, 5.0 * DISPLAY_SCALE, CONCENTRATION_BADGE_RADIUS)
	var badge_center := Vector2(half, -drawn_top(shape, u.team, radius) + badge_radius)
	draw_arc(badge_center, badge_radius, 0.0, TAU, 20, _concentration_color(u), CONCENTRATION_BADGE_WIDTH, true)
	var font := ThemeDB.fallback_font
	var text := str(count)
	var size := int(round(Palette.FONT_SIZE_SMALL * DISPLAY_SCALE * 0.8))
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	draw_string(font, badge_center - text_size * 0.5 + Vector2(0.0, text_size.y * 0.75),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.TEXT)

## The team of whoever is focusing this unit. Read off the real focusers rather
## than assumed to be the opposite team, so a badge never claims a side that is
## not actually attacking.
func _concentration_color(u: CombatUnit) -> Color:
	for other in _state.units:
		if other.id != u.id and other.alive and other.focus_id == u.id:
			return Palette.team_color(other.team)
	return Palette.TEXT_DIM

## PLAYTEST-NOTES-2 item 3: "countdowns should be progress bars, with an icon
## at the end showing what is coming", and the note's own reading of it --
## "the icon is the better half: a ring says something is coming, an icon says
## what."
const WIND_UP_ICON_SIZE := 16.0 * DISPLAY_SCALE
const WIND_UP_TOP_GAP := 4.0 * DISPLAY_SCALE
const WIND_UP_ICON_GAP := 3.0 * DISPLAY_SCALE

## Takes a radius since issue 82: the whole block is still exactly as wide as
## the hp bar above it, but that width now depends on the body.
static func wind_up_icon_size(radius: float, shape_id: StringName = &"", team: CG.Team = CG.Team.PLAYER) -> float:
	return clampf(bar_width(radius, shape_id, team) * 0.34, 7.0 * DISPLAY_SCALE, WIND_UP_ICON_SIZE)

static func wind_up_bar_width(radius: float, shape_id: StringName = &"", team: CG.Team = CG.Team.PLAYER) -> float:
	return bar_width(radius, shape_id, team) - wind_up_icon_size(radius, shape_id, team) - WIND_UP_ICON_GAP

## How full the bar is, 0..1. Its own function so it can be checked without a
## canvas, same split as wind_up_elapsed_ticks. A total of 0 means the action
## has no wind-up at all and fires the tick it commits: full, not empty, since
## nothing is being waited for.
static func wind_up_fraction(u: CombatUnit) -> float:
	if u.action_ticks_total <= 0:
		return 1.0
	return clampf(float(wind_up_elapsed_ticks(u)) / float(u.action_ticks_total), 0.0, 1.0)

## The damage type the icon is coloured by. The *action's* own type, not
## `_accent(u)`'s class-level one, even though sable's own signature note
## offers `_accent` as the cheap answer. The point of the icon is that the
## player sees the thing coming and then sees the same thing land, and what
## lands is coloured by the action: `ArenaFloor._draw_projectile` (PR #71) and
## the floating number both already read `ActionDef.damage_type`. A Priest
## whose class accent is Divine also casts Physical actions, and the telegraph
## disagreeing with its own projectile is worse than one Registry lookup.
func _wind_up_damage_type(u: CombatUnit) -> int:
	var action = ActionLibrary.get_action(u.current_action)
	return action.damage_type if action != null else _accent(u)

## Everything drawn under the body, as one height. Each part is measured by
## the same function that draws it, so the two cannot drift.
static func below_block_height(u: CombatUnit, radius: float) -> float:
	return wind_up_height(u, radius) + status_badge_row_height(u, radius)

static func wind_up_height(u: CombatUnit, radius: float) -> float:
	if u.action_ticks_left <= 0 or u.current_action == &"":
		return 0.0
	return WIND_UP_TOP_GAP + wind_up_icon_size(radius, shape_id(u), u.team)

static func status_badge_row_height(u: CombatUnit, radius: float) -> float:
	if status_badges(u).is_empty() and hidden_status_count(u) == 0:
		return 0.0
	return STATUS_BADGE_TOP_GAP + status_badge_size(shape_id(u), u.team, radius)

## Silent when nothing is winding up. How much room it takes is
## `wind_up_height`, which `below_block_rects` reads to stack the badges under it.
func _draw_wind_up(u: CombatUnit, radius: float, top_offset: float) -> void:
	if u.action_ticks_left <= 0 or u.current_action == &"":
		return

	var shape := _shape_id(u)
	var width := wind_up_bar_width(radius, shape, u.team)
	var icon_size := wind_up_icon_size(radius, shape, u.team)
	var bar_height := BAR_HEIGHT * DISPLAY_SCALE
	var block_left := -bar_width(radius, shape, u.team) * 0.5
	var top := top_offset + WIND_UP_TOP_GAP
	var damage_type := _wind_up_damage_type(u)

	# Vertically centred on the icon, not on the bar: the icon is the taller of
	# the two and the pair has to read as one object.
	var bar_top := top + (icon_size - bar_height) * 0.5
	var bar_pos := Vector2(block_left, bar_top)
	draw_rect(Rect2(bar_pos, Vector2(width, bar_height)), Palette.HP_BACK)
	draw_rect(Rect2(bar_pos, Vector2(width * wind_up_fraction(u), bar_height)),
		Palette.damage_color(damage_type))

	ActionIcons.draw_action(self, u.current_action, damage_type,
		Rect2(Vector2(block_left + width + WIND_UP_ICON_GAP, top),
			Vector2(icon_size, icon_size)))

## PLAYTEST-NOTES-2 item 2: "no clear visual for who is afflicted with what."
const STATUS_BADGE_SIZE := 14.0 * DISPLAY_SCALE
const STATUS_BADGE_GAP := Palette.SPACE_XS * DISPLAY_SCALE

## Clearance from whatever is above the row -- the body, or the wind-up bar
## when the unit is mid-action. Deliberately larger than the gap between
## badges: two badges of the same unit belong together and should read as one
## row, and the row belongs to the unit rather than to the thing above it.
const STATUS_BADGE_TOP_GAP := 6.0 * DISPLAY_SCALE

## A unit can in principle carry every status at once. Two are shown.
const MAX_STATUS_BADGES := 2

## Which badges this unit gets, in draw order. Split out from the drawing for
## the same reason status_badges is: Godot refuses draw_* outside _draw(), so a
## test that can only call the drawing wrapper logs errors and asserts nothing.
static func status_badges(u: CombatUnit) -> Array:
	var all := ordered_statuses(u)
	if all.size() <= MAX_STATUS_BADGES:
		return all
	# One slot is given up to the "+N" chip, so the row still occupies at most
	# MAX_STATUS_BADGES slots and never grows wider than the unit.
	return all.slice(0, MAX_STATUS_BADGES - 1)

## Every status on the unit, in draw order, with nothing dropped. Split out so
## the overflow count is derived from the same ordering the drawn badges are --
## two independent orderings would let the "+N" disagree with what is shown.
static func ordered_statuses(u: CombatUnit) -> Array:
	var harmful: Array = []
	var beneficial: Array = []
	for s in CG.Status.values():
		if not u.has_status(s):
			continue
		if CG.is_harmful(s):
			harmful.append(s)
		else:
			beneficial.append(s)
	return harmful + beneficial

## Issue 161, sable's measurement: `MAX_STATUS_BADGES` is 4 and **a fifth status
## was dropped with nothing on screen saying so.** With bleed stacking and burn,
## five is reachable now.
static func hidden_status_count(u: CombatUnit) -> int:
	var total := ordered_statuses(u).size()
	if total <= MAX_STATUS_BADGES:
		return 0
	return total - (MAX_STATUS_BADGES - 1)

## The floor. Expressed the same way as the ceiling two constants up, so the
## two move together.
const STATUS_BADGE_MIN := 13.0 * DISPLAY_SCALE

## Issue 190: sable measured a row of four badges at 84px against a 27px goblin,
## 3.1x the unit. The row scales with the drawn body for the same reason the bar
## does -- and the gap scales with it, or three badges of 9px sit in 12px of air.
static func status_badge_size(shape_id: StringName, team: CG.Team, radius: float) -> float:
	return clampf(drawn_half_width(shape_id, team, radius) * 0.7, STATUS_BADGE_MIN, STATUS_BADGE_SIZE)

## Where the block under the body starts, in this view's local space: the drawn
## body's bottom edge, plus whatever lift keeps the whole block inside the arena.
static func below_block_top(u: CombatUnit, units: Array) -> float:
	var radius := display_radius(u)
	var shape := shape_id(u)
	var bottom := drawn_bottom(shape, u.team, radius)
	var width := bar_width(radius, shape, u.team)
	return bottom + into_arena(Rect2(
		drawn_position(u, units) + Vector2(-width * 0.5, bottom),
		Vector2(width, below_block_height(u, radius)))).y

## Issue 449: every mark under the body that answers a hover, in ARENA-local
## pixels, in the order they are drawn. `_draw` lays the row out from this same
## list, so a hover target cannot drift from the glyph the player is pointing at.
static func below_block_rects(u: CombatUnit, units: Array) -> Array:
	var out: Array = []
	var radius := display_radius(u)
	var shape := shape_id(u)
	var at := drawn_position(u, units)
	var top := below_block_top(u, units) + wind_up_height(u, radius)

	var badges := status_badges(u)
	var hidden := hidden_status_count(u)
	if not badges.is_empty() or hidden > 0:
		var size := status_badge_size(shape, u.team, radius)
		var gap := STATUS_BADGE_GAP * (size / STATUS_BADGE_SIZE)
		var slots := badges.size() + (1 if hidden > 0 else 0)
		var row_width := StatusIcons.row_width(slots, size, gap)
		var rects := StatusIcons.layout_row(
			at + Vector2(-row_width * 0.5, top + STATUS_BADGE_TOP_GAP), slots, size, gap)
		for i in badges.size():
			out.append({"kind": &"status", "rect": rects[i], "status": badges[i]})
		if hidden > 0:
			out.append({"kind": &"overflow", "rect": rects[slots - 1], "count": hidden})
	top += status_badge_row_height(u, radius)
	return out

## How far off a mark a pointer may be and still hit it. A badge is 20 arena
## pixels and the arena is drawn at about 0.83, so the glyph alone is a smaller
## target on screen than anything else the player is asked to point at.
const HOVER_SLOP := 4.0

## Which mark the pointer is over, or {} for none. Marks answer before bodies
## because they are small and sit on top of one.
static func hover_at(state: CombatState, point: Vector2) -> Dictionary:
	for u in state.units:
		if not u.alive:
			continue
		for entry in below_block_rects(u, state.units):
			if (entry["rect"] as Rect2).grow(HOVER_SLOP).has_point(point):
				return {"unit": u, "mark": entry}
	return {}

func _draw_below_block(u: CombatUnit) -> void:
	for entry in below_block_rects(u, _state.units):
		var rect: Rect2 = entry["rect"]
		rect.position -= position
		match entry["kind"]:
			&"status":
				StatusIcons.draw_status(self, entry["status"], rect)
			&"overflow":
				_draw_overflow_chip(rect, int(entry["count"]))

## Deliberately not a glyph. Every plate in `StatusIcons` means "this specific
## status is on this unit", and a plate meaning "there are more" would be the
## first one that is not a status -- exactly the ambiguity sable measured, where
## badges in a category already share ~84% of their pixels. Text cannot be
## mistaken for a status.
func _draw_overflow_chip(rect: Rect2, count: int) -> void:
	var font := ThemeDB.fallback_font
	var text := "+%d" % count
	var size := int(round(Palette.FONT_SIZE_SMALL * DISPLAY_SCALE))
	var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var at := rect.get_center() + Vector2(-measured.x * 0.5, measured.y * 0.35)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.TEXT_DIM)

## Renders text centred on its own width with a small backdrop chip behind it,
## rather than a fixed draw width that truncates. `at` is the chip's top-left
## in this view's local space: the caller decides where it goes, because issue
## 378 needs that decision made against every other plate at once.
static func draw_label_chip(ci: CanvasItem, at: Vector2, text: String, color: Color, font_size: int) -> void:
	var pad := Vector2(3.0, 2.0) * DISPLAY_SCALE
	var text_size := _measure(text, font_size)
	ci.draw_rect(Rect2(at, text_size + pad * 2.0), Color(Palette.BACKGROUND, 0.65))
	ci.draw_string(ThemeDB.fallback_font, at + Vector2(pad.x, text_size.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## Split out for testing, same reasoning as status_badges below: the part of
## the wind-up draw call that is pure arithmetic rather than a draw_* call.
static func wind_up_elapsed_ticks(u: CombatUnit) -> int:
	return u.action_ticks_total - u.action_ticks_left

