extends AbilityEffect
class_name ConsumeGroundEffect

## Eats the ground of `kind` under the caster and heals a fraction of its max
## hp. General on purpose -- not `EatBloodEffect` -- so any unit that can stand
## on the right terrain can carry this. Issue 759.

@export var kind: Terrain.Kind = Terrain.Kind.BLOOD
@export var heal_fraction_of_max_hp: float = 0.0
