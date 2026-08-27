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

## What this looks like when it fires. Null means the view's own defaults, which
## is every action that has not been given one yet.
@export var vfx: AbilityVFX

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
# The flat field names, and they READ ONLY. Everything that looks at an action
# without caring how it is composed -- the UI, the tests, the instruments --
# still says `action.range_units`. Nothing writes one: content is authored as
# a `.tres` and a fixture composes the parts itself.
# ---------------------------------------------------------------------------

var range_units: float:
	get: return targeting.range_units if targeting != null else 0.0
var splash_radius: float:
	get: return targeting.splash_radius if targeting != null else 0.0
var requires_line_of_sight: bool:
	get: return targeting.requires_line_of_sight if targeting != null else false
var targets_self: bool:
	get: return targeting.targets_self if targeting != null else false
var covers_target: bool:
	get: return targeting.covers_target if targeting != null else false
var requires_marked_target: bool:
	get: return targeting.requires_marked_target if targeting != null else false
var arc_degrees: float:
	get: return targeting.arc_degrees if targeting != null else 0.0

var projectile_speed: float:
	get: return delivery.speed if delivery != null else 0.0

var sustain_cost_per_tick: int:
	get: return sustain.cost_per_tick if sustain != null else 0
var sustain_radius: float:
	get: return sustain.radius if sustain != null else 0.0

var damage_type: CG.DamageType:
	get:
		var h := hit()
		return h.damage_type if h != null else CG.DamageType.PHYSICAL
var power_scale: float:
	get:
		var h := hit()
		return h.power_scale if h != null else 0.0
var heals: bool:
	get:
		var h := hit()
		return h.heals if h != null else false
var consumes_status_enabled: bool:
	get:
		var h := hit()
		return h.consumes_status_enabled if h != null else false
var consumes_status: CG.Status:
	get:
		var h := hit()
		return h.consumes_status if h != null else CG.Status.SHIELD
var consumed_power_scale: float:
	get:
		var h := hit()
		return h.consumed_power_scale if h != null else 0.0

var applies_status_enabled: bool:
	get: return status_effect() != null
var applies_status: CG.Status:
	get:
		var s := status_effect()
		return s.status if s != null else CG.Status.SHIELD
var status_duration_ticks: int:
	get:
		var s := status_effect()
		return s.duration_ticks if s != null else 0
var status_magnitude: float:
	get:
		var s := status_effect()
		return s.magnitude if s != null else 0.0
var taunt_radius: float:
	get:
		var s := status_effect()
		return s.taunt_radius if s != null else 0.0

var pull_distance: float:
	get:
		var p := pull_effect()
		return p.distance if p != null else 0.0

var cleanses_harmful: bool:
	get: return has_cleanse()

var summons_unit_id: StringName:
	get:
		var s := summon_effect()
		return s.unit_id if s != null else &""
var max_active_summons: int:
	get:
		var s := summon_effect()
		return s.max_active if s != null else 0

var leaves_pool_radius: float:
	get:
		var p := pool_effect()
		return p.radius if p != null else 0.0

var restores_resource: int:
	get:
		var r := restore_effect()
		return r.amount if r != null else 0
