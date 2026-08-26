extends RefCounted
class_name LegacyActions621



## Every ActionDef in the slice: the five classes' actions and the enemies'.

const RANGED_PROJECTILE_SPEED := 32.5

const MAGIC_BASIC_ATTACK_MANA := 3

## Issue 166: the Mana one Channel returns, and how long the caster stands still
## for it. 45 ticks is 3 seconds; the cooldown stops it replacing the fight.
const CHANNEL_MANA := 25
const CHANNEL_WIND_UP := 45
const CHANNEL_COOLDOWN := 150

## "Reaches anywhere in the room", expressed as a real number.
##
const ARENA_SPAN := 1200.0

## Issue 593: the Warrior's directional block. It is spent by damage rather than
## by time, so the duration is a BACKSTOP against an unbounded status rather
## than the thing that ends it -- `CG.MAX_TICKS` is the fight's own budget, so
## the block lasts the whole fight or until it breaks, whichever comes first.
## The cooldown is what stops the pool being free: without it an `always` row
## re-raises a broken shield the same tick and the Warrior is invulnerable. It
## kept its old 150, which the old version carried as both cooldown and timer.
const BLOCK_HEALTH := 40.0
const BLOCK_BACKSTOP_TICKS := CG.MAX_TICKS
## Any ally in the room. The nomination decides which way the Warrior TURNS,
## and you do not have to stand next to somebody to point a shield at what is
## shooting them -- what the shield actually covers is still only the 220-unit
## frontage `SHIELD_WIDTH` gives it, wherever the Warrior happens to be.
const BLOCK_REACH := ARENA_SPAN
const BLOCK_COOLDOWN := 150

## Issue 592: how far the Geysermancer and the Siege Master operate. It is well
## past the 200 every other ranged attack sits at, and past the Warden's 270,
## so the two long-range classes reach across a room a Goblin has to cross.
const CASTER_REACH := 350.0

## `abomination_grapple`'s own three numbers, named because
## `IMMOLATE_TICK_POWER_SCALE` below is derived from them and a literal repeated
## in two places is a literal that drifts.
const GRAPPLE_POWER_SCALE := 2.8
const GRAPPLE_WIND_UP := 8
const GRAPPLE_RECOVER := 10

## Issue 219: what one tick of `abomination_immolate` does to one enemy.
##
const IMMOLATE_TICK_POWER_SCALE := GRAPPLE_POWER_SCALE / float(GRAPPLE_WIND_UP + GRAPPLE_RECOVER)

static func actions() -> Array:
	return _core() + f1actions()

static func _core() -> Array:
	return [
		_action(&"warrior_strike", "Strike", "A reliable melee swing that costs nothing.", CG.DamageType.PHYSICAL, 40.0, 6, 8, 1.0, 0, 0),
		_targets_self(_action_status(&"warrior_guard", "Guard", "Raises a block that reduces damage taken by 25% for 6 seconds. Costs 20 Rage.", CG.DamageType.EARTH, 0.0, 4, 10, 0.0, 20, CG.Status.BLOCK, 90)),
		_action(&"warrior_execute", "Execute", "Retired from the Warrior on issue 592; kept only so an older test fixture referencing it by name still resolves.", CG.DamageType.PHYSICAL, 40.0, 8, 10, 2.0, 20, 40),
		_action_taunt(&"warrior_taunt", "Taunt", "Forces every enemy within 350 units to attack the caster for 16 seconds.", 6, 10, 350.0, 240),
		_covers(_action_status(&"warrior_block", "Directional Block", "Turns to face the nearest enemy to a chosen ally and raises a shield. It stops travelling shots crossing its front and soaks 40 damage before it breaks. It can be raised for any ally in the room.", CG.DamageType.EARTH, BLOCK_REACH, 6, 10, 0.0, 0, CG.Status.SHIELDING, BLOCK_BACKSTOP_TICKS), BLOCK_HEALTH),

		_action_self_heal(&"warrior_second_wind", "Second Wind", "Draws on a reserve of stamina to heal the Warrior for a moderate amount. Can only be done occasionally. Costs 15 Rage.", CG.DamageType.PHYSICAL, 15, 12, 2.2, 15, 450),

		_action_heal(&"priest_heal", "Heal", "Restores health to an ally within 220 units.", CG.DamageType.DIVINE, 220.0, 8, 10, 1.4, 25),
		_restores(_projectile(_action(&"priest_bolt", "Bolt", "A ranged bolt of divine light dealing damage at up to 220 units. Costs nothing and returns 3 Mana when it lands.", CG.DamageType.DIVINE, 220.0, 8, 10, 0.5, 0, 0, true), RANGED_PROJECTILE_SPEED), MAGIC_BASIC_ATTACK_MANA),
		_projectile(_action(&"priest_smite", "Smite", "A ranged bolt of divine light dealing damage at up to 220 units.", CG.DamageType.DIVINE, 220.0, 10, 10, 0.9, 15, 0, true), RANGED_PROJECTILE_SPEED),
		_action_ally_buff(&"priest_haste", "Haste", "Speeds up an ally's actions by 30% for 10 seconds. Costs 15 Mana.", CG.DamageType.DIVINE, 220.0, 8, 10, 15, CG.Status.HASTE, 150),
		_action_ally_buff(&"priest_ward", "Ward", "Reduces damage taken by an ally by 25% for 10 seconds. Costs 15 Mana.", CG.DamageType.DIVINE, 220.0, 8, 10, 15, CG.Status.SHIELD, 150),

		_restores(_projectile(_leaves_pool(_action(&"geyser_spout", "Spout", "A jet of scalding water dealing damage at up to 350 units. Leaves a small pool of water where it lands, which puts out any burning ground it touches. Costs nothing and returns 3 Mana when it lands.", CG.DamageType.WATER, CASTER_REACH, 8, 10, 0.5, 0, 0, true), SMALL_POOL_RADIUS), RANGED_PROJECTILE_SPEED), MAGIC_BASIC_ATTACK_MANA),
		_consumes(_projectile(_leaves_pool(_action_splash(&"geyser_blast", "Geyser Blast", "A splash of scalding water that damages every enemy within 50 units of the impact point, up to 350 units away. Against a burning target it snuffs the flames and hits far harder. Leaves a large pool of water where it lands, which puts out any burning ground it touches. Costs 20 Mana.", CG.DamageType.WATER, CASTER_REACH, 50.0, 12, 12, 0.8, 20, true), LARGE_POOL_RADIUS), RANGED_PROJECTILE_SPEED), CG.Status.BURN, BURN_CONSUME_POWER_SCALE),
		_projectile(_action_status(&"geyser_scald", "Scald", "A focused burst of fire at a single target up to 350 units away, setting it alight for 6 seconds. Costs 15 Mana.", CG.DamageType.FIRE, CASTER_REACH, 8, 8, 1.0, 15, CG.Status.BURN, BURN_DURATION_TICKS, true), RANGED_PROJECTILE_SPEED),
		_action_channel(&"channel_mana", "Channel", "Spends 3 seconds drawing back 25 Mana. Costs nothing, and a stun breaks it.", CHANNEL_WIND_UP, CHANNEL_COOLDOWN, CHANNEL_MANA),

		_action_cleanse(&"geyser_cleanse", "Scour", "Boils every harmful effect off an ally within 350 units. Costs 10 Mana.", CASTER_REACH, 8, 10, 10, 60),

		_projectile(_action(&"siege_master_shot", "Shot", "A ranged shot dealing damage at up to 350 units. Costs nothing.", CG.DamageType.PHYSICAL, CASTER_REACH, 8, 10, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),
		_projectile(_action_status(&"spotter_mark", "Spotter's Mark", "Marks a target within 350 units, reducing its damage reduction by 25 percentage points for 10 seconds.", CG.DamageType.PHYSICAL, CASTER_REACH, 10, 10, 1.0, 15, CG.Status.MARKED, 150, true), RANGED_PROJECTILE_SPEED),
		_summon_cap(_action_summon(&"build_siege_engine", "Build Siege Engine", "Spends 6 seconds building a Siege Engine with 140 health. It cannot move and only fires at enemies you have marked. Two at most. Costs 20 Mana.", 90, 20, 20, &"siege_engine"), 2),

		# Issue 62: abomination_claw, restored. The player's own direction --
		_action_status(&"abomination_claw", "Claw", "A melee strike that poisons the target for 4.5% of its max health per second, for 6 seconds. Costs nothing.", CG.DamageType.PROFANE, 45.0, 7, 9, 1.0, 0, CG.Status.POISON, 90),
		_projectile(_pull(_action(&"abomination_hook", "Hook", "A profane tendril that deals damage and drags the target 100 units toward the caster, stunning it for the whole drag. Reaches 140 units. Costs 15 Rage.", CG.DamageType.PROFANE, 140.0, 10, 12, 1.4, 15, 0, true), 100.0), RANGED_PROJECTILE_SPEED),
		_action_status(&"abomination_grapple", "Grapple", "A crushing melee grip that deals damage and slows the target's movement by 50% for 10 seconds. Costs 20 Rage.", CG.DamageType.PROFANE, 45.0, GRAPPLE_WIND_UP, GRAPPLE_RECOVER, GRAPPLE_POWER_SCALE, 20, CG.Status.SLOWED, 150),
		_sustained(&"abomination_immolate", "Immolate", "Sets the Abomination alight. Every enemy within 90 units burns for as long as it is held, taking a Grapple's worth of damage each second. Costs 1 Rage to light and 15 Rage a second to hold.", CG.DamageType.FIRE, 15, IMMOLATE_TICK_POWER_SCALE, 1, 1, 90.0),

		_action(&"goblin_stab", "Stab", "A melee jab dealing damage at up to 40 units.", CG.DamageType.PHYSICAL, 40.0, 6, 6, 1.0, 0, 0),
		_projectile(_action(&"goblin_arrow", "Arrow", "A ranged shot dealing damage at up to 200 units.", CG.DamageType.PHYSICAL, 200.0, 8, 8, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),
		_action(&"ghoul_maul", "Maul", "A melee blow at up to 45 units, with a 0.5-second wind-up.", CG.DamageType.PHYSICAL, 45.0, 14, 14, 1.0, 0, 0),
		# Issue 23: the bestiary's status user. Profane -> POISON per README.md.
		_projectile(_action_status(&"cultist_bolt", "Dark Bolt", "A ranged bolt at up to 200 units that poisons the target for 4.5% of its max health per second, for 6 seconds.", CG.DamageType.PROFANE, 200.0, 10, 10, 0.7, 0, CG.Status.POISON, 90, true), RANGED_PROJECTILE_SPEED),

		_action(&"warden_axe", "Executioner's Axe", "A melee swing at up to 55 units, with a 0.7-second wind-up.", CG.DamageType.PHYSICAL, 55.0, 20, 22, 2.4, 0, 0),
		_projectile(_action(&"warden_chain_toss", "Chain Toss", "A ranged attack at up to 270 units.", CG.DamageType.PHYSICAL, 270.0, 16, 18, 1.0, 0, 0, true), RANGED_PROJECTILE_SPEED),

		_projectile(_marked_only(_action(&"siege_engine_bolt", "Engine Bolt", "A ranged attack that reaches anywhere in the arena, but only at an enemy the Siege Master has marked. Fires once every 2 seconds.", CG.DamageType.PHYSICAL, ARENA_SPAN, 22, 8, 1.0, 0, 0, true)), RANGED_PROJECTILE_SPEED),

		_action(&"grunt_smash", "Smash", "Retired from the bestiary; kept only so an older test fixture referencing it by name still resolves.", CG.DamageType.PHYSICAL, 40.0, 10, 10, 1.0, 0, 0),
		_action(&"archer_shot", "Arrow", "Retired from the bestiary; kept only so an older test fixture referencing it by name still resolves.", CG.DamageType.PHYSICAL, 220.0, 12, 10, 0.8, 0, 0),
	]

static func _action(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int, requires_los: bool = false) -> Dictionary:
	var a := _blank()
	a["id"] = id
	a["display_name"] = display_name
	a["description"] = description
	a["damage_type"] = damage_type
	a["range_units"] = range_units
	a["wind_up_ticks"] = wind_up
	a["recover_ticks"] = recover
	a["power_scale"] = power_scale
	a["resource_cost"] = resource_cost
	a["cooldown_ticks"] = cooldown_ticks
	a["requires_line_of_sight"] = requires_los
	return a

## Issue 99: a heal a unit casts on itself, with a real cooldown.
##
static func _action_self_heal(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int) -> Dictionary:
	var a := _action(id, display_name, description, damage_type, 0.0, wind_up, recover, power_scale, resource_cost, 0)
	a["heals"] = true
	a["targets_self"] = true
	a["cooldown_ticks"] = cooldown_ticks
	return a

static func _action_heal(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int) -> Dictionary:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0)
	a["heals"] = true
	return a

static func _action_splash(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, splash_radius: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, requires_los: bool = false) -> Dictionary:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0, requires_los)
	a["splash_radius"] = splash_radius
	return a

static func _action_splash_cd(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, splash_radius: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int, requires_los: bool = false) -> Dictionary:
	var a := _action_splash(id, display_name, description, damage_type, range_units, splash_radius, wind_up, recover, power_scale, resource_cost, requires_los)
	a["cooldown_ticks"] = cooldown_ticks
	return a

static func _action_status(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, status: CG.Status, duration_ticks: int, requires_los: bool = false) -> Dictionary:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0, requires_los)
	a["applies_status_enabled"] = true
	a["applies_status"] = status
	a["status_duration_ticks"] = duration_ticks
	return a

## Issue 30: self-targeted (range 0.0, no line-of-sight check, no damage --
## same "the status is the whole effect" shape _action_summon already uses)
## Issue 593: names an ally, shields the caster, and carries a pool of health.
static func _covers(a: Dictionary, health: float) -> Dictionary:
	a["covers_target"] = true
	a["status_magnitude"] = health
	a["cooldown_ticks"] = BLOCK_COOLDOWN
	return a

static func _targets_self(a: Dictionary) -> Dictionary:
	a["targets_self"] = true
	return a

static func _projectile(a: Dictionary, speed: float) -> Dictionary:
	a["projectile_speed"] = speed
	return a

## Issue 121: how long `geyser_scald`'s BURN lasts. **Paired with
## `Balance.BURN_FRACTION_OF_HIT_PER_TICK` and the two must move together** --
const BURN_DURATION_TICKS := 90

## Issue 121: what `geyser_blast` gets for eating a BURN, as a multiple of the
## burn's own stored magnitude -- the mitigated damage of the hit that lit it.
const BURN_CONSUME_POWER_SCALE := 1.0

## Issue 132: the mana a magic class's default attack returns when it lands.
## Same inert-by-default shape as `_projectile` and `_marked_only` -- the field
## is 0 on every other action.
static func _restores(a: Dictionary, amount: int) -> Dictionary:
	a["restores_resource"] = amount
	return a

## Issue 166: an ability the caster has to sit idle for. The wind-up IS the
## idling -- a winding-up unit is never offered an intent, so it stands still
## for the whole of it and the wind-up bar says what it is standing still for.
static func _action_channel(id: StringName, display_name: String, description: String, wind_up: int, cooldown_ticks: int, restores: int) -> Dictionary:
	var a := _action_self_heal(id, display_name, description, CG.DamageType.RAW, wind_up, 0, 0.0, 0, cooldown_ticks)
	return _restores(a, restores)

## Issue 121: strips a status off the target and adds `scale` times its stored
## magnitude to this hit. The first consume in the game; every other action
## leaves `consumes_status_enabled` false and is untouched.
static func _consumes(a: Dictionary, status: CG.Status, scale: float) -> Dictionary:
	a["consumes_status_enabled"] = true
	a["consumes_status"] = status
	a["consumed_power_scale"] = scale
	return a

static func _marked_only(a: Dictionary) -> Dictionary:
	a["requires_marked_target"] = true
	return a

## Issue 93: caps how many live summons this action may have on the field at
## once. Built as a property of the summoning action rather than a special case
## for the Siege Master, because `summons_unit_id` is generic on either team and
## the next summoner will want the same thing -- there was no cap mechanism
## anywhere before this (`grep max_summon|summon_limit` returned nothing).
static func _summon_cap(a: Dictionary, cap: int) -> Dictionary:
	a["max_active_summons"] = cap
	return a

static func _sustained(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, wind_up: int, tick_power_scale: float, resource_cost: int, sustain_cost_per_tick: int, sustain_radius: float) -> Dictionary:
	var a := _action(id, display_name, description, damage_type, 0.0, wind_up, 0, tick_power_scale, resource_cost, 0)
	a["targets_self"] = true
	a["sustain_cost_per_tick"] = sustain_cost_per_tick
	a["sustain_radius"] = sustain_radius
	return a

## Issue 492: the two pool sizes, and there is no third. Half-widths, so the
## large pool is the splash it comes from and the small one is a quarter of it.
const SMALL_POOL_RADIUS := 25.0
const LARGE_POOL_RADIUS := 50.0

static func _leaves_pool(a: Dictionary, half_width: float) -> Dictionary:
	a["leaves_pool_radius"] = half_width
	return a

## Issue 52/14: wraps an ActionDef with a real pull, same "the mechanism was
## always inert-by-default, content decides who uses it" pattern _projectile
## established for issue 18. `distance` is how far the target is dragged
## toward the caster, in world units -- see ActionDef.pull_distance's own
## doc comment for the duration and the stun that come with it.
static func _pull(a: Dictionary, distance: float) -> Dictionary:
	a["pull_distance"] = distance
	return a

## Issue 52: a self-targeted status application whose cooldown genuinely
## matches its own duration, the same shape `_action_taunt` already uses --
static func _action_self_buff(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, wind_up: int, recover: int, status: CG.Status, duration_ticks: int) -> Dictionary:
	var a := _action(id, display_name, description, damage_type, 0.0, wind_up, recover, 0.0, 0, duration_ticks)
	a["targets_self"] = true
	a["applies_status_enabled"] = true
	a["applies_status"] = status
	a["status_duration_ticks"] = duration_ticks
	return a

static func _action_ally_buff(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, resource_cost: int, status: CG.Status, duration_ticks: int) -> Dictionary:
	var a := _action(id, display_name, description, damage_type, range_units, wind_up, recover, 0.0, resource_cost, duration_ticks)
	a["applies_status_enabled"] = true
	a["applies_status"] = status
	a["status_duration_ticks"] = duration_ticks
	return a

static func _action_cleanse(id: StringName, display_name: String, description: String, range_units: float, wind_up: int, recover: int, resource_cost: int, cooldown_ticks: int) -> Dictionary:
	var a := _action(id, display_name, description, CG.DamageType.WATER, range_units, wind_up, recover, 0.0, resource_cost, cooldown_ticks)
	a["heals"] = true
	a["cleanses_harmful"] = true
	return a

static func _action_taunt(id: StringName, display_name: String, description: String, wind_up: int, recover: int, taunt_radius: float, duration_ticks: int) -> Dictionary:
	var a := _action(id, display_name, description, CG.DamageType.PHYSICAL, 0.0, wind_up, recover, 0.0, 0, duration_ticks)
	a["targets_self"] = true
	a["applies_status_enabled"] = true
	a["applies_status"] = CG.Status.TAUNTING
	a["status_duration_ticks"] = duration_ticks
	a["taunt_radius"] = taunt_radius
	return a

## Issue 12: self-targeted (range 0.0, no line-of-sight check), deals no
## damage of its own (power_scale 0.0) -- summons_unit_id is the entire
## effect. `_action` already covers everything else this needs.
static func _action_summon(id: StringName, display_name: String, description: String, wind_up: int, recover: int, resource_cost: int, summons_unit_id: StringName) -> Dictionary:
	var a := _action(id, display_name, description, CG.DamageType.PHYSICAL, 0.0, wind_up, recover, 0.0, resource_cost, 0)
	a["targets_self"] = true
	a["summons_unit_id"] = summons_unit_id
	return a

## Issue 542: multiples of `MonsterProfile`, not absolutes. `damage_type` is the
## one type this monster's attack power is expressed in; `radius` stays absolute
## because it is collision geometry rather than a stat.

static func _blank() -> Dictionary:
	return {
		"id": &"", "display_name": "", "description": "",
		"wind_up_ticks": 0, "recover_ticks": 0, "cooldown_ticks": 0, "resource_cost": 0,
		"range_units": 0.0, "splash_radius": 0.0, "leaves_pool_radius": 0.0,
		"requires_line_of_sight": false,
		"damage_type": CG.DamageType.PHYSICAL, "power_scale": 1.0, "heals": false,
		"applies_status": CG.Status.SHIELD, "applies_status_enabled": false,
		"status_duration_ticks": 0, "status_magnitude": 0.0, "covers_target": false,
		"consumes_status": CG.Status.SHIELD, "consumes_status_enabled": false,
		"consumed_power_scale": 0.0,
		"summons_unit_id": &"", "max_active_summons": 0,
		"requires_marked_target": false, "restores_resource": 0,
		"pull_distance": 0.0, "cleanses_harmful": false, "projectile_speed": 0.0,
		"taunt_radius": 0.0, "targets_self": false,
		"sustain_cost_per_tick": 0, "sustain_radius": 0.0,
	}

const F1_RANGED_PROJECTILE_SPEED := 32.5

static func f1actions() -> Array:
	return [
		f1_action_taunt(&"brute_roar", "Roar", "Forces every enemy within 200 units to attack the Brute for 8 seconds. It cannot roar again for another 16 seconds.", 8, 9, 200.0, 120, 240),
		f1_action_status(&"brute_slam", "Slam", "A heavy melee blow at up to 50 units that stuns for 0.5 seconds, cancelling whatever the target was casting.", CG.DamageType.PHYSICAL, 50.0, 16, 18, 2.0, 0, CG.Status.STUN, 8),

		f1_projectile(f1_action_status_cd(&"stalker_mark", "Mark", "Marks a target within 220 units for 6 seconds, stripping its natural armour.", CG.DamageType.PHYSICAL, 220.0, 4, 5, 1.0, 0, CG.Status.MARKED, 90, 60, true), F1_RANGED_PROJECTILE_SPEED),

		f1_projectile(f1_action(&"stalker_dart", "Dart", "A light ranged dart at up to 200 units.", CG.DamageType.PHYSICAL, 200.0, 6, 8, 1.0, 0, 0, true), F1_RANGED_PROJECTILE_SPEED),

		f1_action_status(&"rat_bite", "Bite", "A fast melee bite at up to 40 units that adds a stack of Bleed.", CG.DamageType.PHYSICAL, 40.0, 3, 4, 1.0, 0, CG.Status.BLEED, 45),

		f1_summons(f1_action(&"rat_king_lash", "Tail Lash", "A ranged strike at up to 200 units that leaves a rat behind.", CG.DamageType.PHYSICAL, 200.0, 20, 22, 1.0, 0, 0, true), &"rat"),
	]

static func f1_action(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, cooldown_ticks: int, requires_los: bool = false) -> Dictionary:
	var a := _blank()
	a["id"] = id
	a["display_name"] = display_name
	a["description"] = description
	a["damage_type"] = damage_type
	a["range_units"] = range_units
	a["wind_up_ticks"] = wind_up
	a["recover_ticks"] = recover
	a["power_scale"] = power_scale
	a["resource_cost"] = resource_cost
	a["cooldown_ticks"] = cooldown_ticks
	a["requires_line_of_sight"] = requires_los
	return a

static func f1_action_status(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, status: CG.Status, duration_ticks: int, requires_los: bool = false) -> Dictionary:
	var a := f1_action(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, 0, requires_los)
	a["applies_status_enabled"] = true
	a["applies_status"] = status
	a["status_duration_ticks"] = duration_ticks
	return a

## `_action_status` with a real cooldown. `core_actions.gd`'s version hardcodes
## `cooldown_ticks` to 0 and its own comment says so twice, which is right for
## every caller it has -- a damage-dealing status application whose rate is
## already limited by its wind-up. It is wrong for an action whose entire
## effect is a status that already lasts 90 ticks.
static func f1_action_status_cd(id: StringName, display_name: String, description: String, damage_type: CG.DamageType, range_units: float, wind_up: int, recover: int, power_scale: float, resource_cost: int, status: CG.Status, duration_ticks: int, cooldown_ticks: int, requires_los: bool = false) -> Dictionary:
	var a := f1_action_status(id, display_name, description, damage_type, range_units, wind_up, recover, power_scale, resource_cost, status, duration_ticks, requires_los)
	a["cooldown_ticks"] = cooldown_ticks
	return a

## Issue 150: an enemy's taunt. Self-targeted, no damage of its own -- the
## status is the whole effect, the shape `core_actions._action_taunt` already
## uses for the Warrior's.
static func f1_action_taunt(id: StringName, display_name: String, description: String, wind_up: int, recover: int, taunt_radius: float, duration_ticks: int, cooldown_ticks: int) -> Dictionary:
	var a := f1_action(id, display_name, description, CG.DamageType.PHYSICAL, 0.0, wind_up, recover, 0.0, 0, cooldown_ticks)
	a["targets_self"] = true
	a["applies_status_enabled"] = true
	a["applies_status"] = CG.Status.TAUNTING
	a["status_duration_ticks"] = duration_ticks
	a["taunt_radius"] = taunt_radius
	return a

## An action that spawns a unit as well as doing whatever else it does.
static func f1_summons(a: Dictionary, unit_id: StringName) -> Dictionary:
	a["summons_unit_id"] = unit_id
	return a

static func f1_projectile(a: Dictionary, speed: float) -> Dictionary:
	a["projectile_speed"] = speed
	return a

## Issue 542: multiples of `MonsterProfile`, not absolutes. `damage_type` is the
## one type this monster's attack power is expressed in; `radius` stays absolute
## because it is collision geometry rather than a stat.
