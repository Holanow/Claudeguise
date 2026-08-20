extends Resource
class_name ActionDef


## Something a unit can do that takes time and may cost resource. Attacks,
## spells, blocks, and the plain move are all actions, so the simulation has one

@export var id: StringName = &""
@export var display_name: String = ""

## One or two sentences a player reads on the inspect screen, in their language
## rather than ours: what this does and when it is worth using. Not the numbers ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â
## the screen can read those off the fields below and they change every time
@export var description: String = ""

## Ticks between the unit committing and the effect landing. The unit is
## interruptible here and its intent cannot change. This is what makes reading
## a fight possible, so an action with wind_up_ticks == 0 should be rare.
@export var wind_up_ticks: int = 0

## Ticks after the effect lands before the unit may act again.
@export var recover_ticks: int = 0

## Ticks before this action may be used again by the same unit. 0 means never
## gated. Measured from the tick the effect lands.
@export var cooldown_ticks: int = 0

@export var resource_cost: int = 0

## World units. Measured centre to centre at the moment the effect lands, not at
## the moment the unit commits: a target that walks out is a miss, and that is
## deliberate.
@export var range_units: float = 0.0

## World units. 0.0 means the effect hits only the focused target.
@export var splash_radius: float = 0.0

## Whether this action needs an unobstructed line to its target. A wall or a
## pillar between the two stops it; a pit does not, since a pit blocks feet
## rather than sight.
@export var requires_line_of_sight: bool = false

@export var damage_type: CG.DamageType = CG.DamageType.PHYSICAL

## Multiplier on the wielder's derived attack power for this damage type.
## Balance.gd owns what that power is; this owns how hard this particular
## action leans on it.
@export var power_scale: float = 1.0

## Negative heals. Positive damages. Keeps one resolution path.
@export var heals: bool = false

@export var applies_status: CG.Status = CG.Status.SHIELD
@export var applies_status_enabled: bool = false
@export var status_duration_ticks: int = 0

## A status this action strips off its target for a bonus, scaled by what that
## status was carrying. Disabled on every action that exists today.
@export var consumes_status: CG.Status = CG.Status.SHIELD
@export var consumes_status_enabled: bool = false
@export var consumed_power_scale: float = 0.0

## An `EnemyDef` id this action builds, on the caster's own team. Empty means
## the action summons nothing, which is every action that exists today, so
## adding this changes no behaviour and invalidates no measurement.
@export var summons_unit_id: StringName = &""

## The most summons from this action that may be alive at once. Zero means no
## limit, which is every action that existed before the Siege Engine.
@export var max_active_summons: int = 0

## How many units one cast of this action summons. One for every action that
## existed before the Rat King.
@export var summon_count: int = 1

## This action may only be used against a target carrying `CG.Status.MARKED`.
## False for every action that existed before the Siege Engine.
@export var requires_marked_target: bool = false

## Resource this action's wielder gains when it lands. Zero for every action
## that existed before it, so nothing changes until content sets it.
@export var restores_resource: int = 0

## How far this action drags its target toward the caster, in arena units. Zero
## means it does not pull, which is every action that exists today.
@export var pull_distance: float = 0.0

## Strips every harmful status from this action's targets, per `CG.is_harmful`.
## False for every action that exists today.
@export var cleanses_harmful: bool = false

## World units per tick a shot from this action travels before its effect
## lands. 0.0 means instant -- every action that exists today, unchanged --
## same inert-by-default pattern as pull_distance and summons_unit_id before
@export var projectile_speed: float = 0.0

## How far this action's TAUNTING status reaches, in world units. 0.0 means the
## action does not taunt, which is every action today.
@export var taunt_radius: float = 0.0

## Issue 150. This action is cast on its caster, whoever that is.
##
## **A marker rather than an inference, and the inference is the trap.**
@export var targets_self: bool = false

## Issue 61. Resource charged to the caster on every tick this action is held.
## 0 means the action is not sustained, which is every action that exists today,
## so adding this changes no behaviour and invalidates no measurement -- the same
@export var sustain_cost_per_tick: int = 0

## World units around the caster a held effect reaches on each tick. Every
## living enemy inside it takes the action's effect, the same
@export var sustain_radius: float = 0.0
