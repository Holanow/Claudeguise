extends Resource
class_name ActionDef

## An action, composed on three axes plus a sustain profile. Authored as a
## `.tres` under `Scripts/Content/Actions/`, not built by a constructor call.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## Ticks between the unit committing and the effects landing. The unit is
## interruptible here and its intent cannot change. This is what makes reading
## a fight possible, so an action with wind_up_ticks == 0 should be rare.
@export var wind_up_ticks: int = 0

## Ticks after the effects land before the unit may act again.
@export var recover_ticks: int = 0

## Ticks before this action may be used again by the same unit. 0 means never
## gated. Measured from the tick the effects land.
@export var cooldown_ticks: int = 0

@export var resource_cost: int = 0

## Who this reaches. Null means the defaults on `ActionTargeting`.
@export var targeting: ActionTargeting

## How the effects travel. Null means instant, which is most actions.
@export var delivery: ActionDelivery

## What happens on arrival, in resolution order. An action that does three
## things lists three of them.
@export var effects: Array[AbilityEffect] = []

## A state the caster enters instead of arriving anywhere. Null on all but
## `abomination_immolate`.
@export var sustain: ActionSustain

## Issue 621: a bare `ActionDef.new()` carries one `HitEffect`, so it still
## behaves as it did before -- power scale 1.0, physical, no heal. Loading a
## `.tres` replaces the whole array, so nothing pays for this twice.
func _init() -> void:
	var seed: Array[AbilityEffect] = [HitEffect.new()]
	effects = seed

## The first effect of each kind. Actions carry at most one of any of these, so
## a linear walk over a list of three is the whole lookup.
func hit() -> HitEffect:
	for fx in effects:
		if fx is HitEffect:
			return fx
	return null

func status_effect() -> StatusEffect:
	for fx in effects:
		if fx is StatusEffect:
			return fx
	return null

func pull_effect() -> PullEffect:
	for fx in effects:
		if fx is PullEffect:
			return fx
	return null

func summon_effect() -> SummonEffect:
	for fx in effects:
		if fx is SummonEffect:
			return fx
	return null

func pool_effect() -> PoolEffect:
	for fx in effects:
		if fx is PoolEffect:
			return fx
	return null

func restore_effect() -> RestoreEffect:
	for fx in effects:
		if fx is RestoreEffect:
			return fx
	return null

func has_cleanse() -> bool:
	for fx in effects:
		if fx is CleanseEffect:
			return true
	return false


# ---------------------------------------------------------------------------
# The flat field names. Reads are for everything that looks at an action without
# caring how it is composed -- the UI, the tests, the instruments. Writes are a
# BRIDGE for the 37 test fixtures that still build actions field by field, and
# issue 622 removes them. Content is authored as `.tres`, not through these.
# ---------------------------------------------------------------------------

## Where each kind of effect sits in the list. The sim runs `effects` in order,
## so a fixture assigning fields in any order still gets one canonical order.
const _RANKS := {
	&"HitEffect": 0, &"StatusEffect": 1, &"PullEffect": 2, &"CleanseEffect": 3,
	&"SummonEffect": 4, &"PoolEffect": 5, &"RestoreEffect": 6,
}

## A `.tres` loaded twice is the SAME instance, so writing to one would change
## the action for every unit in the game. Refuse loudly rather than drift.
func _authorable() -> bool:
	if resource_path == "":
		return true
	push_error("ActionDef '%s' was loaded from %s and is shared by reference; it may not be mutated." % [id, resource_path])
	return false

func _rank_of(fx: AbilityEffect) -> int:
	return _RANKS.get(fx.get_script().get_global_name(), 99)

func _insert_effect(fx: AbilityEffect) -> void:
	var r := _rank_of(fx)
	var i := 0
	while i < effects.size() and _rank_of(effects[i]) <= r:
		i += 1
	effects.insert(i, fx)

func _drop_effect(rank: int) -> void:
	for i in range(effects.size() - 1, -1, -1):
		if _rank_of(effects[i]) == rank:
			effects.remove_at(i)

func _ensure_hit() -> HitEffect:
	var h := hit()
	if h == null:
		h = HitEffect.new()
		_insert_effect(h)
	return h

## The status fields exist whether or not the action applies one, exactly as
## they did when they were four flat fields behind an enabled flag. So writes
## land here and the flag alone decides whether it is in `effects`.
var _held_status: StatusEffect = null

func _status_slot() -> StatusEffect:
	var s := status_effect()
	if s != null:
		return s
	if _held_status == null:
		_held_status = StatusEffect.new()
	return _held_status

func _ensure_targeting() -> ActionTargeting:
	if targeting == null:
		targeting = ActionTargeting.new()
	return targeting

func _ensure_sustain() -> ActionSustain:
	if sustain == null:
		sustain = ActionSustain.new()
	return sustain

var range_units: float:
	get: return targeting.range_units if targeting != null else 0.0
	set(v):
		if _authorable(): _ensure_targeting().range_units = v
var splash_radius: float:
	get: return targeting.splash_radius if targeting != null else 0.0
	set(v):
		if _authorable(): _ensure_targeting().splash_radius = v
var requires_line_of_sight: bool:
	get: return targeting.requires_line_of_sight if targeting != null else false
	set(v):
		if _authorable(): _ensure_targeting().requires_line_of_sight = v
var targets_self: bool:
	get: return targeting.targets_self if targeting != null else false
	set(v):
		if _authorable(): _ensure_targeting().targets_self = v
var covers_target: bool:
	get: return targeting.covers_target if targeting != null else false
	set(v):
		if _authorable(): _ensure_targeting().covers_target = v
var requires_marked_target: bool:
	get: return targeting.requires_marked_target if targeting != null else false
	set(v):
		if _authorable(): _ensure_targeting().requires_marked_target = v

## 0.0 removes the delivery outright. A delivery whose speed is zero would
## launch a shot that never arrives; the old field was value-gated and this
## keeps it so.
var projectile_speed: float:
	get: return delivery.speed if delivery != null else 0.0
	set(v):
		if not _authorable(): return
		if v <= 0.0:
			delivery = null
		else:
			if delivery == null: delivery = ActionDelivery.new()
			delivery.speed = v

var sustain_cost_per_tick: int:
	get: return sustain.cost_per_tick if sustain != null else 0
	set(v):
		if _authorable(): _ensure_sustain().cost_per_tick = v
var sustain_radius: float:
	get: return sustain.radius if sustain != null else 0.0
	set(v):
		if _authorable(): _ensure_sustain().radius = v

var damage_type: CG.DamageType:
	get:
		var h := hit()
		return h.damage_type if h != null else CG.DamageType.PHYSICAL
	set(v):
		if _authorable(): _ensure_hit().damage_type = v
var power_scale: float:
	get:
		var h := hit()
		return h.power_scale if h != null else 0.0
	set(v):
		if _authorable(): _ensure_hit().power_scale = v
var heals: bool:
	get:
		var h := hit()
		return h.heals if h != null else false
	set(v):
		if _authorable(): _ensure_hit().heals = v
var consumes_status_enabled: bool:
	get:
		var h := hit()
		return h.consumes_status_enabled if h != null else false
	set(v):
		if _authorable(): _ensure_hit().consumes_status_enabled = v
var consumes_status: CG.Status:
	get:
		var h := hit()
		return h.consumes_status if h != null else CG.Status.SHIELD
	set(v):
		if _authorable(): _ensure_hit().consumes_status = v
var consumed_power_scale: float:
	get:
		var h := hit()
		return h.consumed_power_scale if h != null else 0.0
	set(v):
		if _authorable(): _ensure_hit().consumed_power_scale = v

var applies_status_enabled: bool:
	get: return status_effect() != null
	set(v):
		if not _authorable(): return
		if v:
			if status_effect() == null: _insert_effect(_status_slot())
		else:
			_drop_effect(_RANKS[&"StatusEffect"])
var applies_status: CG.Status:
	get:
		var s := status_effect()
		return s.status if s != null else CG.Status.SHIELD
	set(v):
		if _authorable(): _status_slot().status = v
var status_duration_ticks: int:
	get:
		var s := status_effect()
		return s.duration_ticks if s != null else 0
	set(v):
		if _authorable(): _status_slot().duration_ticks = v
var status_magnitude: float:
	get:
		var s := status_effect()
		return s.magnitude if s != null else 0.0
	set(v):
		if _authorable(): _status_slot().magnitude = v
var taunt_radius: float:
	get:
		var s := status_effect()
		return s.taunt_radius if s != null else 0.0
	set(v):
		if _authorable(): _status_slot().taunt_radius = v

var pull_distance: float:
	get:
		var p := pull_effect()
		return p.distance if p != null else 0.0
	set(v):
		if not _authorable(): return
		_drop_effect(_RANKS[&"PullEffect"])
		if v > 0.0:
			var p := PullEffect.new()
			p.distance = v
			_insert_effect(p)

var cleanses_harmful: bool:
	get: return has_cleanse()
	set(v):
		if not _authorable(): return
		_drop_effect(_RANKS[&"CleanseEffect"])
		if v: _insert_effect(CleanseEffect.new())

var summons_unit_id: StringName:
	get:
		var s := summon_effect()
		return s.unit_id if s != null else &""
	set(v):
		if not _authorable(): return
		if v == &"":
			_drop_effect(_RANKS[&"SummonEffect"])
			return
		var s := summon_effect()
		if s == null:
			s = SummonEffect.new()
			_insert_effect(s)
		s.unit_id = v
var max_active_summons: int:
	get:
		var s := summon_effect()
		return s.max_active if s != null else 0
	set(v):
		if not _authorable(): return
		var s := summon_effect()
		if s == null:
			s = SummonEffect.new()
			_insert_effect(s)
		s.max_active = v

var leaves_pool_radius: float:
	get:
		var p := pool_effect()
		return p.radius if p != null else 0.0
	set(v):
		if not _authorable(): return
		_drop_effect(_RANKS[&"PoolEffect"])
		if v > 0.0:
			var p := PoolEffect.new()
			p.radius = v
			_insert_effect(p)

var restores_resource: int:
	get:
		var r := restore_effect()
		return r.amount if r != null else 0
	set(v):
		if not _authorable(): return
		_drop_effect(_RANKS[&"RestoreEffect"])
		if v > 0:
			var r := RestoreEffect.new()
			r.amount = v
			_insert_effect(r)
