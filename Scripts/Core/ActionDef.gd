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

## Whether this action needs an unobstructed line to its target. A wall or a
## pillar between the two stops it; a pit does not, since a pit blocks feet
## rather than sight.
##
## **Defaults to false, which means "behaves exactly as it does today", and that
## default is a liability rather than a resting place.** As of the commit that
## added this, `Terrain.line_is_blocked` was written, tested and called by
## nothing at all: walls stopped movement and every ranged attack fired straight
## through them. teal's own honesty check on issue 13b caught it —
## `test_the_wall_changes_the_fight_from_the_open_room`, which they wrote to fail
## if terrain turned out to be decoration, and which failed.
##
## That is why a party at 200+ units cannot be threatened by a wall today, and
## therefore why the whole cost of every fight still falls on whoever closes to
## melee. Setting this on the ranged actions is the point of the field.
##
## Two halves, filed as issue 28 the same minute this landed rather than left in
## a comment: the simulation has to consult it when resolving targets (wren), and
## the content has to declare which actions need it (teal).
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

## An `EnemyDef` id this action builds, on the caster's own team. Empty means
## the action summons nothing, which is every action that exists today, so
## adding this changes no behaviour and invalidates no measurement.
##
## The Siege Master is a SUMMONER and has never summoned anything -- the tag was
## on the class card while the class played as artillery. This is the field that
## makes the tag true.
##
## **`EnemyDef` rather than a new summon type, deliberately.** It already
## describes exactly what a siege engine is: a unit that is not a pawn, with hp,
## damage, actions, move speed and a shape. The only thing that made it "enemy"
## was which team spawned it. A second near-identical shape beside it is how two
## definitions of the same thing drift apart, and this project already has one
## rule about that -- reuse the vocabulary the game has.
##
## **Build time is `wind_up_ticks`**, which already exists and already works.
## An engine that takes a long time to raise is a long wind-up, not a new
## mechanism. The player asked for building to take a while; that is a number,
## not a feature.
##
## What does NOT exist yet: `CombatSim` builds its unit list once in `build()`
## and nothing ever appends to it mid-fight. That is the real work here and it
## is the simulation's, not content's.
@export var summons_unit_id: StringName = &""

## The most summons from this action that may be alive at once. Zero means no
## limit, which is every action that existed before the Siege Engine.
##
## A property of the action rather than a special case for one class, because
## the summon mechanism above is generic and the next summoner will want it.
##
## **This does more than cap a number, and the reason is worth keeping.** The
## player asked for a cap because engines were "getting built really fast" --
## 2.69 per fight, peaking at 7. (I first wrote 3.18 here. That came from my
## own probe running one hardcoded party; finch's runs every buildable party
## carrying a Siege Master, and theirs is the figure the PR reports. Neither
## measurement is wrong, but a Core comment disagreeing with the PR beside it
## is what costs somebody twenty minutes in a month.) But `build_siege_engine`
## and `spotter_mark`
## draw on one Mana pool with build ordered first, so building was starving
## marking, and engines that only fire at marked targets had nothing to shoot.
## Capping hands every capped-out tick back to the mark plan: marking went 8%
## of engine-alive ticks to 22% **with no change to `spotter_mark` at all**.
##
## That only works because the cap gates where the action is *chosen*, in
## `PlanInterpreter` beside the affordability check, rather than at spawn. A
## cap applied at spawn would have wasted the cast and starved marking exactly
## as before. Do not move it.
@export var max_active_summons: int = 0

## This action may only be used against a target carrying `CG.Status.MARKED`.
## False for every action that existed before the Siege Engine.
##
## The player's design: a Siege Engine reaches anywhere, fires slowly, cannot
## move, and **cannot choose its own targets** -- the Siege Master designates
## them. That turns `spotter_mark` from a damage-amp side ability into the
## engine's targeting system, and makes the class one thing instead of two
## unrelated halves.
##
## The risk this creates is measurable and was measured: an action gated this
## way is exactly as useful as marking is frequent. See `max_active_summons`
## above for why the cap, not the mark action, is what made it viable.
@export var requires_marked_target: bool = false

## How far this action drags its target toward the caster, in arena units. Zero
## means it does not pull, which is every action that exists today.
##
## The Abomination is a TANK and an ANTI_SUPPORT that has never had a way to be
## either: 12 CON with no way to make anything attack it, and no way to reach a
## healer standing behind a line. A hook is what makes both tags true -- drag an
## attacker off your casters, or drag their support out of position.
##
## **Nothing in the simulation moves another unit today.** Effects touch hp,
## resource and status only, so this is genuinely new and it is the simulation's
## work rather than content's.
##
## Two things it must not quietly become: a pull that puts a unit inside a wall
## (Terrain.point_is_blocked already exists and must be respected, same as
## ordinary movement), and a pull that fires after the target is dead.
@export var pull_distance: float = 0.0

## Strips every harmful status from this action's targets, per `CG.is_harmful`.
## False for every action that exists today.
##
## The Geysermancer is tagged SUPPORT and has two actions, both of which are
## pure damage. It has never done anything for an ally. This is the field that
## makes the tag true, and it is the counterplay to POISON, BURN, SLOWED and
## MARKED all arriving at once.
@export var cleanses_harmful: bool = false

## World units per tick a shot from this action travels before its effect
## lands. 0.0 means instant -- every action that exists today, unchanged --
## same inert-by-default pattern as pull_distance and summons_unit_id before
## it. Same unit system as CombatUnit.move_speed.
##
## Issue 18, the player's decision: most shots should be real projectiles.
## Distance currently costs a shooter nothing -- a 260-unit shot and a 40-unit
## stab both land the instant the wind-up ends -- which is a large part of why
## out-ranging the room was so dominant. Travel makes reach cost time, lets a
## target move out of the way, and gives the Warrior's guard something real to
## intercept.
##
## Which actions travel, and how fast, is content's decision rather than the
## simulation's. The mechanism lands with every action still at 0.0 so the
## balance re-measurement stays a separate, attributable step.
@export var projectile_speed: float = 0.0

## How far this action's TAUNTING status reaches, in world units. 0.0 means the
## action does not taunt, which is every action today.
##
## Read onto `CombatUnit.taunt_radius` at the moment the status is applied,
## rather than re-derived from the unit's action list each tick -- same as every
## other derived-at-apply-time number here.
##
## This is what finally makes TANK mean something. The Warrior has 9 CON and has
## never had any way to make a thing attack it, so "tank" has meant "survives"
## rather than "protects" for the whole project. dace found the same hole from
## the other side on issue 12: an 80-hp siege engine never draws fire because
## nothing prefers a summon over the nearest pawn, which makes a summoner just a
## fragile damage dealer. One mechanism, two classes.
@export var taunt_radius: float = 0.0

## Issue 61. Resource charged to the caster on every tick this action is held.
## 0 means the action is not sustained, which is every action that exists today,
## so adding this changes no behaviour and invalidates no measurement -- the same
## inert-by-default pattern as pull_distance, summons_unit_id and
## projectile_speed before it.
##
## **This is the first action in the game that is not a point in time.**
## Everything else resolves as wind-up, fire, recover. A sustained action fires
## once and is then *held*: it deals its effect and charges this cost on every
## tick, for as long as the pawn's plan keeps choosing it.
##
## The player's direction for the Abomination's Immolate: "damage to enemies
## nearby that costs rage per tick". Immolate is retired from the game entirely
## today because this mechanism did not exist.
##
## `resource_cost` is unchanged and still charged once, at commit. The two are
## different things: what it costs to light, and what it costs to keep burning.
@export var sustain_cost_per_tick: int = 0

## World units around the caster a held effect reaches on each tick. Every
## living enemy inside it takes the action's effect, the same
## membership-per-tick shape `_tick_hazards` already uses for standing in fire.
##
## A nonzero `sustain_cost_per_tick` with this left at 0 is a channel that
## charges the caster and reaches nothing. `Tests/test_combat_sustain.gd`
## asserts content never authors that pair.
@export var sustain_radius: float = 0.0
