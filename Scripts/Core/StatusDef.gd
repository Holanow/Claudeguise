extends Resource
class_name StatusDef

## What one `CG.Status` IS, in one place. Authored as a `.tres` under
## `Scripts/Core/Statuses/`, one file per enum member. Issue 627.

## Every field is a plain `@export var`. Nothing here is computed: a write to a
## getter-only property in GDScript silently does nothing.

## The enum member this file describes. `CG.Status` stays the key; this is the
## back-reference, held to the file's own name by the transcription test.
@export var status: CG.Status = CG.Status.SHIELD

## Whether a unit would want this removed. Read through `CG.is_harmful`.
@export var harmful: bool = false

## Duration is deliberately NOT here: it is authored per application, on
## `StatusEffect.duration_ticks` and on a hazard, and two casters may apply the
## same status for different lengths.

## Applying this again adds a stack instead of refreshing what was there.
@export var stacks: bool = false

## The magnitude is the damage of the hit that applied it.
@export var hit_scaled: bool = false

## Whether this deals damage on a tick at all. A bool rather than a sentinel
## damage type, because `CG.DamageType.PHYSICAL` is 0.
@export var deals_damage_over_time: bool = false

@export var dot_damage_type: CG.DamageType = CG.DamageType.PHYSICAL

## Percent of the victim's own max hp per tick, in the unit its old constant
## used, so the move cannot round anything.
@export var damage_percent_of_max_hp_per_tick: float = 0.0

## Damage per tick per unit of stored magnitude, on top of the percent above.
@export var damage_per_magnitude_per_tick: float = 0.0

## Ticks between damage ticks. 1 is every tick.
@export var tick_interval: int = 1

## How long a stacking status holds on past its expiry, per stack still left.
@export var stack_decay_ticks: int = 0

## Fraction of incoming damage removed while carried.
@export var damage_reduction: float = 0.0

## Fraction of the unit's damage reduction removed while carried.
@export var vulnerability: float = 0.0

## Multiplier on wind-up and recovery ticks. 1.0 changes nothing.
@export var tick_scale: float = 1.0

## Multiplier on move speed. 1.0 changes nothing.
@export var speed_scale: float = 1.0

## The badge art, looked up through `UIArt`. The rim colour is deliberately not
## here: it is one rule off `harmful`, so a red rim can never appear on a
## helpful badge, and thirteen authored colours could.
@export var icon_name: StringName = &""
