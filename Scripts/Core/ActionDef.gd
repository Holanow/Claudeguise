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
