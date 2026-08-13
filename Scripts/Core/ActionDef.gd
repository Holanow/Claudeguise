extends Resource

const CG := preload("res://Scripts/Core/CG.gd")

## Something a unit can do that takes time and may cost resource. Attacks,
## spells, blocks, and the plain move are all actions, so the simulation has one
## code path for "unit is busy doing a thing" rather than several.
##
## MANAGER-OWNED SHAPE. Instances live in Scripts/Content/ and belong to the
## content session.

@export var id: StringName = &""
@export var display_name: String = ""

## One or two sentences a player reads on the inspect screen, in their language
## rather than ours: what this does and when it is worth using. Not the numbers —
## the screen can read those off the fields below and they change every time
## anyone tunes.
##
## Empty is a defect rather than a default. An action with no description is one
## the player is asked to plan around with no information, and the inspect screen
## is the only place the game ever explains itself.
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
