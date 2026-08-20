extends RefCounted


## **A DURATION IN A DESCRIPTION IS PLAYER-FACING COPY AND IT IS DERIVED FROM A
## TICK COUNT. Ten of them said exactly half the truth for sixty-odd merges.**
## Issue 77 halved `CG.TICKS_PER_SECOND` from 30 to 15 and deliberately left

## Every ActionDef in the slice: the five classes' actions and the enemies'.
## Kept in one module rather than split per class because Registry only cares
## about ids, and a reviewer checking "what can this class actually do" reads
## faster from one file than five. See Registry.gd for the module contract.
## OWNER: teal.

## Travel speed, in world units per tick, for every real ranged action on either
## side. One constant rather than the literal repeated at twelve call sites: it
## was already the same number everywhere, and the player has now asked for it to
const RANGED_PROJECTILE_SPEED := 32.5

## Issue 132: *"The default attack of any magic class should restore a small
## amount of mana."*
const MAGIC_BASIC_ATTACK_MANA := 3

## "Reaches anywhere in the room", expressed as a real number.
##
## Issue 93, the player's spec for the Siege Engine: unlimited range. A literal
const ARENA_SPAN := 1200.0

## `abomination_grapple`'s own three numbers, named because
## `IMMOLATE_TICK_POWER_SCALE` below is derived from them and a literal repeated
## in two places is a literal that drifts.
const GRAPPLE_POWER_SCALE := 2.8
const GRAPPLE_WIND_UP := 8
const GRAPPLE_RECOVER := 10

## Issue 219: what one tick of `abomination_immolate` does to one enemy.
##
## **Derived: a tick of channel is worth a tick of Grapple.** Grapple is the most
const IMMOLATE_TICK_POWER_SCALE := GRAPPLE_POWER_SCALE / float(GRAPPLE_WIND_UP + GRAPPLE_RECOVER)

static func classes() -> Array[ClassDef]:
	return []

## Issue 28b: which actions declare `requires_line_of_sight`. Every ranged
## attack, whichever side fires it -- a wall denying a shot is the point of
## the field, and letting an enemy's own arrows and bolts ignore it would
static func actions() -> Array[ActionDef]:
	return [
		_action(&"warrior_strike", "Strike", "A reliable melee swing that costs nothing.", CG.DamageType.PHYSICAL, 40.0, 6, 8, 1.0, 0, 0),
		# Issue 150: `_targets_self`, because Guard is built through
		_targets_self(_action_status(&"warrior_guard", "Guard", "Raises a block that reduces damage taken by 25% for 6 seconds. Costs 20 Rage.", CG.DamageType.EARTH, 0.0, 4, 10, 0.0, 20, CG.Status.BLOCK, 90)),
		# Issue 79: cost 60 -> 25. This action fired zero times across 210
		_action(&"warrior_execute", "Execute", "A heavy melee blow that deals twice the damage of a Strike. Costs 20 Rage.", CG.DamageType.PHYSICAL, 40.0, 8, 10, 2.0, 20, 40),
		# Issue 30/TAUNTING: self-targeted (target_self, same pattern
		_action_taunt(&"warrior_taunt", "Taunt", "Forces every enemy within 350 units to attack the caster for 16 seconds.", 6, 10, 350.0, 240),
		# Issue 52: the directional block the player asked for and found
		_action_self_buff(&"warrior_block", "Directional Block", "Raises a shield that stops a travelling shot aimed at an ally standing behind it, for 10 seconds.", CG.DamageType.EARTH, 6, 10, CG.Status.SHIELDING, 150),

		# Issue 99: the Warrior's self-sustain, replacing Directional Block in
		_action_self_heal(&"warrior_second_wind", "Second Wind", "Draws on a reserve of stamina to heal the Warrior for a moderate amount. Can only be done occasionally. Costs 15 Rage.", CG.DamageType.PHYSICAL, 15, 12, 2.2, 15, 450),

		_action_heal(&"priest_heal", "Heal", "Restores health to an ally within 220 units.", CG.DamageType.DIVINE, 220.0, 8, 10, 1.4, 25),
		# Issue 62: the Priest's no-cost basic attack. Same range and travel
		_restores(_projectile(_action(&"priest_bolt", "Bolt", "A ranged bolt of divine light dealing damage at up to 220 units. Costs nothing and returns 3 Mana when it lands.", CG.DamageType.DIVINE, 220.0, 8, 10, 0.5, 0, 0, true), RANGED_PROJECTILE_SPEED), MAGIC_BASIC_ATTACK_MANA),
		_projectile(_action(&"priest_smite", "Smite", "A ranged bolt of divine light dealing damage at up to 220 units.", CG.DamageType.DIVINE, 220.0, 10, 10, 0.9, 15, 0, true), RANGED_PROJECTILE_SPEED),
		# The Priest's two buff spells, per the player's own direction ("one
		_action_ally_buff(&"priest_haste", "Haste", "Speeds up an ally's actions by 30% for 10 seconds. Costs 15 Mana.", CG.DamageType.DIVINE, 220.0, 8, 10, 15, CG.Status.HASTE, 150),
		# priest_ward: SHIELD, Balance.damage_reduction already reads it
		_action_ally_buff(&"priest_ward", "Ward", "Reduces damage taken by an ally by 25% for 10 seconds. Costs 15 Mana.", CG.DamageType.DIVINE, 220.0, 8, 10, 15, CG.Status.SHIELD, 150),

		# Issue 79: the Geysermancer's no-cost basic attack, the third and last
		_restores(_projectile(_action(&"geyser_spout", "Spout", "A jet of scalding water dealing damage at up to 200 units. Costs nothing and returns 3 Mana when it lands.", CG.DamageType.WATER, 200.0, 8, 10, 0.5, 0, 0, true), RANGED_PROJECTILE_SPEED), MAGIC_BASIC_ATTACK_MANA),
		_consumes(_projectile(_action_splash(&"geyser_blast", "Geyser Blast", "A splash of scalding water that damages every enemy within 50 units of the impact point, up to 200 units away. Against a burning target it snuffs the flames and hits far harder. Costs 20 Mana.", CG.DamageType.WATER, 200.0, 50.0, 12, 12, 0.8, 20, true), RANGED_PROJECTILE_SPEED), CG.Status.BURN, BURN_CONSUME_POWER_SCALE),
		# Issue 79: numbers unchanged. This action also fired zero times in 210
		_projectile(_action_status(&"geyser_scald", "Scald", "A focused burst of fire at a single target up to 200 units away, setting it alight for 6 seconds. Costs 15 Mana.", CG.DamageType.FIRE, 200.0, 8, 8, 1.0, 15, CG.Status.BURN, BURN_DURATION_TICKS, true), RANGED_PROJECTILE_SPEED),
		# Issue 87: the player's own "Geysermancer can do debuff removal", and
		_action_cleanse(&"geyser_cleanse", "Scour", "Boils every harmful effect off an ally within 200 units. Costs 10 Mana.", 200.0, 8, 10, 10, 60),

		# Issue 12: siege_shot and siege_barrage retired along with the range
		_projectile(_action(&"siege_master_shot", "Shot", "A ranged shot dealing damage at up to 200 units. Costs nothing.", CG.DamageType.PHYSICAL, 200.0, 8, 10, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),
		# spotter_mark: a light ranged hit that leaves MARKED for 5s
		_projectile(_action_status(&"spotter_mark", "Spotter's Mark", "Marks a target within 220 units, reducing its damage reduction by 25 percentage points for 10 seconds.", CG.DamageType.PHYSICAL, 220.0, 10, 10, 1.0, 15, CG.Status.MARKED, 150, true), RANGED_PROJECTILE_SPEED),
		# build_siege_engine: self-targeted (range 0, no line-of-sight
		_summon_cap(_action_summon(&"build_siege_engine", "Build Siege Engine", "Spends 6 seconds building a Siege Engine with 140 health. It cannot move and only fires at enemies you have marked. Two at most. Costs 20 Mana.", 90, 20, 20, &"siege_engine"), 2),

		# Issue 62: abomination_claw, restored. The player's own direction --
		_action_status(&"abomination_claw", "Claw", "A melee strike that poisons the target for 4.5% of its max health per second, for 6 seconds. Costs nothing.", CG.DamageType.PROFANE, 45.0, 7, 9, 1.0, 0, CG.Status.POISON, 90),
		# Issue 52: the Abomination's hook and grapple, per the player's own
		_projectile(_pull(_action(&"abomination_hook", "Hook", "A profane tendril that deals damage and pulls the target 100 units toward the caster. Reaches 140 units. Costs 15 Rage.", CG.DamageType.PROFANE, 140.0, 10, 12, 1.4, 15, 0, true), 100.0), RANGED_PROJECTILE_SPEED),
		# abomination_grapple: melee range (45, matching this bestiary's
		_action_status(&"abomination_grapple", "Grapple", "A crushing melee grip that deals damage and slows the target's movement by 50% for 10 seconds. Costs 20 Rage.", CG.DamageType.PROFANE, 45.0, GRAPPLE_WIND_UP, GRAPPLE_RECOVER, GRAPPLE_POWER_SCALE, 20, CG.Status.SLOWED, 150),
		# Issue 219: Immolate, restored, and it is the ONLY thing in the game
		_sustained(&"abomination_immolate", "Immolate", "Sets the Abomination alight. Every enemy within 90 units burns for as long as it is held, taking a Grapple's worth of damage each second. Costs 1 Rage to light and 15 Rage a second to hold.", CG.DamageType.FIRE, 15, IMMOLATE_TICK_POWER_SCALE, 1, 1, 90.0),

		_action(&"goblin_stab", "Stab", "A melee jab dealing damage at up to 40 units.", CG.DamageType.PHYSICAL, 40.0, 6, 6, 1.0, 0, 0),
		_projectile(_action(&"goblin_arrow", "Arrow", "A ranged shot dealing damage at up to 200 units.", CG.DamageType.PHYSICAL, 200.0, 8, 8, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),
		_action(&"ghoul_maul", "Maul", "A melee blow at up to 45 units, with a 0.5-second wind-up.", CG.DamageType.PHYSICAL, 45.0, 14, 14, 1.0, 0, 0),
		# Issue 23: the bestiary's status user. Profane -> POISON per README.md.
		_projectile(_action_status(&"cultist_bolt", "Dark Bolt", "A ranged bolt at up to 200 units that poisons the target for 4.5% of its max health per second, for 6 seconds.", CG.DamageType.PROFANE, 200.0, 10, 10, 0.7, 0, CG.Status.POISON, 90, true), RANGED_PROJECTILE_SPEED),

		# Issue 44: The Warden, floor 1's boss (README's own name and flavour
		_action(&"warden_axe", "Executioner's Axe", "A melee swing at up to 55 units, with a 0.7-second wind-up.", CG.DamageType.PHYSICAL, 55.0, 20, 22, 2.4, 0, 0),
		_projectile(_action(&"warden_chain_toss", "Chain Toss", "A ranged attack at up to 270 units.", CG.DamageType.PHYSICAL, 270.0, 16, 18, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),

		# Issue 93: the siege engine's own attack, rebuilt as artillery at the
		_projectile(_marked_only(_action(&"siege_engine_bolt", "Engine Bolt", "A ranged attack that reaches anywhere in the arena, but only at an enemy the Siege Master has marked. Fires once every 4 seconds.", CG.DamageType.PHYSICAL, ARENA_SPAN, 45, 15, 1.0, 0, 0, true)), RANGED_PROJECTILE_SPEED),

		## Issue 12 retired dungeon_grunt/dungeon_archer/dungeon_cultist from
		_action(&"grunt_smash", "Smash", "Retired from the bestiary; kept only so an older test fixture referencing it by name still resolves.", CG.DamageType.PHYSICAL, 40.0, 10, 10, 1.0, 0, 0),
		_action(&"archer_shot", "Arrow", "Retired from the bestiary; kept only so an older test fixture referencing it by name still resolves.", CG.DamageType.PHYSICAL, 220.0, 12, 10, 0.8, 0, 0),
	]

static func enemies() -> Array[EnemyDef]:
	return [
		# Issue 12: the Siege Master's engineer half. `EnemyDef` reused rather
		_enemy(&"siege_engine", "Siege Engine", 140, 0, CG.ResourceKind.ENERGY, 0.0, 20.0, {CG.DamageType.PHYSICAL: 16}, 0.0, [&"siege_engine_bolt"], ["Ranged", "Construct"], 0.0),
	]

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return []

static func _action(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int, requires_los: bool = false) -> ActionDef:
	var a := ActionDef.new()
	a.id = id
	a.display_name = display_name
	a.description = description
	a.damage_type = damage_type
	a.range_units = range_units
	a.wind_up_ticks = wind_up
	a.recover_ticks = recover
	a.power_scale = power_scale
	a.resource_cost = resource_cost
	a.cooldown_ticks = cooldown_ticks
	a.requires_line_of_sight = requires_los
	return a

## Issue 99: a heal a unit casts on itself, with a real cooldown.
##
## `_action_heal` does not cover this and wrapping it would be worse: it takes a
static func _action_self_heal(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, 0.0, wind_up, recover, power_scale, resource_cost, 0)
	a.heals = true
	a.targets_self = true
	a.cooldown_ticks = cooldown_ticks
	return a

static func _action_heal(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0)
	a.heals = true
	return a

static func _action_splash(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, splash_radius: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, requires_los: bool = false) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0, requires_los)
	a.splash_radius = splash_radius
	return a

static func _action_splash_cd(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, splash_radius: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int, requires_los: bool = false) -> ActionDef:
	var a := _action_splash(id, display_name, description, damage_type, range_units, splash_radius, wind_up, recover, power_scale, resource_cost, requires_los)
	a.cooldown_ticks = cooldown_ticks
	return a

static func _action_status(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, status: CG.Status, duration_ticks: int, requires_los: bool = false) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0, requires_los)
	a.applies_status_enabled = true
	a.applies_status = status
	a.status_duration_ticks = duration_ticks
	return a

## Issue 30: self-targeted (range 0.0, no line-of-sight check, no damage --
## same "the status is the whole effect" shape _action_summon already uses)
## application of TAUNTING, with a real taunt_radius and a cooldown so it
static func _targets_self(a: ActionDef) -> ActionDef:
	a.targets_self = true
	return a

static func _projectile(a: ActionDef, speed: float) -> ActionDef:
	a.projectile_speed = speed
	return a

## Issue 121: how long `geyser_scald`'s BURN lasts. **Paired with
## `Balance.BURN_FRACTION_OF_HIT_PER_TICK` and the two must move together** --
## burn's whole output is the fraction times this number times the applying hit,
const BURN_DURATION_TICKS := 90

## Issue 121: what `geyser_blast` gets for eating a BURN, as a multiple of the
## burn's own stored magnitude -- the mitigated damage of the hit that lit it.
const BURN_CONSUME_POWER_SCALE := 1.0

## Issue 132: the mana a magic class's default attack returns when it lands.
## Same inert-by-default shape as `_projectile` and `_marked_only` -- the field
## is 0 on every other action.
static func _restores(a: ActionDef, amount: int) -> ActionDef:
	a.restores_resource = amount
	return a

## Issue 121: strips a status off the target and adds `scale` times its stored
## magnitude to this hit. The first consume in the game; every other action
## leaves `consumes_status_enabled` false and is untouched.
static func _consumes(a: ActionDef, status: CG.Status, scale: float) -> ActionDef:
	a.consumes_status_enabled = true
	a.consumes_status = status
	a.consumed_power_scale = scale
	return a

## Issue 93: wraps an ActionDef so it may only be aimed at an enemy carrying
## MARKED. Same inert-by-default, content-decides-who-uses-it shape as
## `_projectile` and `_pull`: the field is false on every other action, so this
static func _marked_only(a: ActionDef) -> ActionDef:
	a.requires_marked_target = true
	return a

## Issue 93: caps how many live summons this action may have on the field at
## once. Built as a property of the summoning action rather than a special case
## for the Siege Master, because `summons_unit_id` is generic on either team and
## the next summoner will want the same thing -- there was no cap mechanism
## anywhere before this (`grep max_summon|summon_limit` returned nothing).
##
## 0 means uncapped, which is every other action, so this is additive.
static func _summon_cap(a: ActionDef, cap: int) -> ActionDef:
	a.max_active_summons = cap
	return a

## Issue 219: the first authored channel. Self-targeted (range 0.0, no
## line-of-sight of its own -- the aura checks it per target inside
## `CombatSim._sustain_targets`), no cooldown, and both halves of the price
static func _sustained(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, wind_up: int, tick_power_scale: float, resource_cost: int, sustain_cost_per_tick: int, sustain_radius: float) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, 0.0, wind_up, 0, tick_power_scale, resource_cost, 0)
	a.targets_self = true
	a.sustain_cost_per_tick = sustain_cost_per_tick
	a.sustain_radius = sustain_radius
	return a

## Issue 52/14: wraps an ActionDef with a real pull, same "the mechanism was
## always inert-by-default, content decides who uses it" pattern _projectile
## established for issue 18. `distance` is how far the target is dragged
## toward the caster, in world units -- see ActionDef.pull_distance's own
## doc comment for why the simulation (not content) does the dragging.
static func _pull(a: ActionDef, distance: float) -> ActionDef:
	a.pull_distance = distance
	return a

## Issue 52: a self-targeted status application whose cooldown genuinely
## matches its own duration, the same shape `_action_taunt` already uses --
## pulled out as its own helper rather than copied a second time. Deliberately
static func _action_self_buff(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, wind_up: int, recover: int, status: CG.Status, duration_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, 0.0, wind_up, recover, 0.0, 0, duration_ticks)
	a.targets_self = true
	a.applies_status_enabled = true
	a.applies_status = status
	a.status_duration_ticks = duration_ticks
	return a

## Same reasoning as `_action_self_buff` (cooldown matches duration, not
## `_action_status`'s hardcoded 0), for an ally-targeted buff instead of a
## self-targeted one: range_units and resource_cost are real here, since an
static func _action_ally_buff(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, resource_cost: int, status: CG.Status, duration_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, 0.0, resource_cost, duration_ticks)
	a.applies_status_enabled = true
	a.applies_status = status
	a.status_duration_ticks = duration_ticks
	return a

## Issue 87: an ally-targeted action whose entire effect is
## `cleanses_harmful` -- no damage, no heal, no status of its own. Same
## "the mechanism is the whole effect" shape `_action_summon` already uses for
static func _action_cleanse(id: StringName, display_name: String, description: String, range_units: float, wind_up: int, recover: int, resource_cost: int, cooldown_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, CG.DamageType.WATER, range_units, wind_up, recover, 0.0, resource_cost, cooldown_ticks)
	a.heals = true
	a.cleanses_harmful = true
	return a

static func _action_taunt(id: StringName, display_name: String, description: String, wind_up: int, recover: int, taunt_radius: float, duration_ticks: int) -> ActionDef:
	var a := _action(id, display_name, description, CG.DamageType.PHYSICAL, 0.0, wind_up, recover, 0.0, 0, duration_ticks)
	a.targets_self = true
	a.applies_status_enabled = true
	a.applies_status = CG.Status.TAUNTING
	a.status_duration_ticks = duration_ticks
	a.taunt_radius = taunt_radius
	return a

## Issue 12: self-targeted (range 0.0, no line-of-sight check), deals no
## damage of its own (power_scale 0.0) -- summons_unit_id is the entire
## effect. `_action` already covers everything else this needs.
static func _action_summon(id: StringName, display_name: String, description: String, wind_up: int, recover: int, resource_cost: int, summons_unit_id: StringName) -> ActionDef:
	var a := _action(id, display_name, description, CG.DamageType.PHYSICAL, 0.0, wind_up, recover, 0.0, resource_cost, 0)
	a.targets_self = true
	a.summons_unit_id = summons_unit_id
	return a

static func _enemy(id: StringName, display_name: String, hp_max: int, resource_max: int, resource_kind: CG.ResourceKind, move_speed: float, radius: float, attack_power: Dictionary, damage_reduction: float, actions: Array[StringName], display_tags: Array[String], focus_bias: float = 0.0) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.display_name = display_name
	e.hp_max = hp_max
	e.resource_max = resource_max
	e.resource_kind = resource_kind
	e.move_speed = move_speed
	e.radius = radius
	e.attack_power = attack_power
	e.damage_reduction = damage_reduction
	e.actions = actions
	e.display_tags = display_tags
	e.focus_bias = focus_bias
	return e
