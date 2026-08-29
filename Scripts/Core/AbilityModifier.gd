extends Resource
class_name AbilityModifier

## Issue 632: an item changing an ability's SHAPE, for abilities it does not
## author. Equipment could already grant actions and move attributes; it could
## not make every projectile spell throw an extra bolt.
##
## `pierce_bonus`, the other of #632's six fields, is still absent: nothing in
## the game pierces, so it would be an exported field that does nothing.

@export var display_name: String = ""

@export_group("Which abilities")
## Matches on STRUCTURE rather than on a label: an action is a projectile
## because it has a delivery, not because somebody tagged it one.
@export var only_projectiles: bool = false
## Null matches every damage type. Otherwise this matches the damage the action
## actually deals, read off its own HitEffect -- never a tag beside it. Matching
## a label while damage routes through a resource is two spellings of one idea,
## and only one of them is true.
@export var only_damage_type: CG.DamageType = CG.DamageType.PHYSICAL
@export var any_damage_type: bool = true

@export_group("What it changes")
## Added to `delivery.count`. Every projectile spell throws this many more.
@export var target_count_bonus: int = 0
## Multiplies the caster's attack power for matching actions.
@export var power_multiplier: float = 1.0
## Applied on a landed hit, in addition to whatever the action already applies.
@export var adds_status: CG.Status = CG.Status.SHIELD
@export var adds_status_enabled: bool = false
@export var adds_status_ticks: int = 0
## Issue 746: chance the added status actually lands, drawn from `state.rng`
## once per landed hit. Defaults to 1.0 so every modifier authored before this
## field existed still applies unconditionally.
@export_range(0.0, 1.0) var adds_status_chance: float = 1.0

func matches(action: ActionDef) -> bool:
	if only_projectiles and action.delivery == null:
		return false
	if any_damage_type:
		return true
	return action.damage_type == only_damage_type
