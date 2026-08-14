extends RefCounted

const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const EquipmentDef := preload("res://Scripts/Core/EquipmentDef.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const CG := preload("res://Scripts/Core/CG.gd")

## Floor 1's rooms. Issue 12: numbers and placement are levers independent of
## any single monster's stats. See Registry.gd for the module contract.
## OWNER: teal.
##
## Tuning notes (see Tests/test_content_encounter.gd for the measured seed
## sweep): a room is a property of the whole spawn list, not any one enemy.
##
## ISSUE #94 -- FOUR PICKABLE ROOMS. The player picks one of these four before
## the fight, and they are meant to play differently rather than to look
## different:
##
##   floor1_room1       open ground, no terrain      the baseline
##   floor1_cover       five pillars, sight broken   archers and cultists
##   floor1_hazard      three burn bands, two lanes  ghouls and goblins
##   floor1_chokepoint  pits, one land bridge        room1's exact roster
##
## **All four field exactly ten enemies.** That is a rule, not a coincidence.
## The retrospective records a terrain conclusion that was wrong because it
## compared a three-enemy room against a ten-enemy one and credited the
## geometry for the difference; holding headcount fixed is what makes the
## layout question answerable at all. Rosters differ freely, headcount does
## not.
##
## `floor1_horde`, `floor1_ghoul_den` and `floor1_warden` stay registered and
## are **not** picker options -- the picker lists the four ids above, not
## every encounter, or it offers the player the boss room.

## Vertical spacing between party spawns. Used to be 60 units, fine when a
## unit's draw radius was 12; pike raised the radius to 22 for phone
## legibility and nobody revisited the gap, so labels sat on top of the pawn
## above. Roughly doubled, shared by every encounter below.
const _PARTY_SPAWNS: Array[Vector2] = [
	Vector2(-350.0, -195.0),
	Vector2(-350.0, -65.0),
	Vector2(-350.0, 65.0),
	Vector2(-350.0, 195.0),
]

static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	return []

## Same spawn list as `_the_room()`'s, shared so `_the_chokepoint()` fights the
## identical roster with only the wall added -- issue 13b criterion 1 asks for
## two rooms that differ in terrain and nothing else, to isolate what terrain
## alone changes.
const _ROOM1_ENEMY_SPAWNS: Array[Dictionary] = [
	{"enemy_id": &"goblin", "position": Vector2(150.0, -150.0)},
	{"enemy_id": &"goblin", "position": Vector2(150.0, -50.0)},
	{"enemy_id": &"goblin", "position": Vector2(150.0, 50.0)},
	{"enemy_id": &"goblin", "position": Vector2(150.0, 150.0)},
	{"enemy_id": &"goblin_archer", "position": Vector2(230.0, -60.0)},
	{"enemy_id": &"goblin_archer", "position": Vector2(230.0, 60.0)},
	{"enemy_id": &"goblin_archer", "position": Vector2(230.0, 200.0)},
	{"enemy_id": &"cultist", "position": Vector2(210.0, -200.0)},
	{"enemy_id": &"ghoul", "position": Vector2(190.0, 0.0)},
	{"enemy_id": &"ghoul", "position": Vector2(190.0, -220.0)},
]

static func encounters() -> Array[Encounter]:
	return [_the_room(), _the_horde(), _the_ghoul_den(), _the_cover_room(), _the_hazard_room(), _the_chokepoint(), _the_warden_room()]

## Issue 44: floor 1's real boss room, replacing `floor1_chokepoint` as
## `FloorFightRunner`'s BOSS placeholder. The wall was a wall built to test a
## terrain mechanic, not a fight built to test a party -- it favoured
## whichever comp could stand at range outside it (19/20 at 86% health) and
## punished the balanced party for closing (1/20). One enemy, no terrain: the
## Warden's own two actions (melee axe, matching-reach chain) are what asks
## something of every composition instead of the room's geometry doing it
## unevenly.
static func _the_warden_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_warden"
	e.display_name = "Floor 1, The Warden's Chamber"
	e.enemy_spawns = [
		{"enemy_id": &"the_warden", "position": Vector2(200.0, 0.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	return e

static func items() -> Array[EquipmentDef]:
	return []

## The standard room: two goblins up front, a goblin archer and a cultist
## held back. Same shape the original three-mirrored-pawn roster had, now
## built from actual monsters.
static func _the_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_room1"
	e.display_name = "Floor 1, Room 1"
	## Four goblins (numerous), a pair of archers, a cultist, and a ghoul
	## anchoring the back — the tough/slow piece regen alone cannot make
	## trivial the way it did the pure-numbers version of this room.
	##
	## Issue 24: the back rank (archers, cultist, ghouls) used to sit at
	## x=380/300/250, 130-230 units behind the goblin front line. A party with
	## a long-range action (siege_shot, 260) could close to just outside the
	## goblins' own reach and never come within the back rank's, so it won a
	## clean sweep it never fought for. Pulled the whole back rank forward to
	## x=190-230 -- still behind the goblins, but close enough that closing on
	## the front line also brings the back rank's own range into play. Moves
	## the "party wins for free" cost from 98% party hp to 77% (SampleFights),
	## not a full fix -- terrain (issue 13b) is the next lever if that isn't
	## enough on its own.
	e.enemy_spawns = _ROOM1_ENEMY_SPAWNS
	e.party_spawns = _PARTY_SPAWNS
	return e

## Issue 13b criterion 1: `floor1_room1`'s exact roster, with a wall down the
## middle of the room and one gap in it. Every enemy that used to be reachable
## the instant the party closed to range is now reachable only through the
## gap, so a party that spreads out to alpha-strike the back rank instead has
## to fight through a single point -- the "four attackers cannot all reach one
## target" case from the issue text, and its mirror: one defender cannot be
## swarmed by four either.
##
## RE-REGISTERED (issue 34). Was pulled after wren's `_resolve_move` corner
## bug (issue 30, fixed in `8c21094`) made every fight against it stall to a
## 3600-tick draw. Fixed for real once `PlanInterpreter._target_in_los` and
## `DefaultBehavior`'s matching approach branch came back (issue 34: the
## corner-creep fix alone was not enough, a unit still needed a reason to
## walk toward a target it could see was blocked instead of firing at it
## forever). Verified with `Tools/TerrainAB.gd` and a direct probe:
## `siege_master x4` now resolves in 19/20 seeds (1 draw) instead of 20/20,
## and a full single-seed fight fires 58 shots at a 10% miss rate rather
## than the 94% issue 34 measured before the fix.
## **Issue #94: the two WALLs are now PITs, and that is a fix for #78 rather
## than a style change. The stalls were traced, not guessed at.**
##
## #78 measured three fights in 700 never resolving here and reporting as
## ordinary losses, and guessed the cause was "a party that cannot reach the
## enemy and an enemy that will not leave its position". Re-measured with
## `Tools/SampleFights.gd` on the trunk at `bea8f6c`, it is far worse than
## three in 700 for the parties that hit it: `no_warrior` draws **7 of 20**
## here, `no_priest` 3 of 20, `no_geysermancer` 1 of 20.
##
## Traced tick by tick on a stalled seed. `CombatSim._resolve_move` has no
## pathfinding and slides one axis at a time when the direct step is blocked
## (its own comment says so, and says a unit that genuinely cannot route
## around an obstacle is a finding to report). The slide is what kills it:
## two units on opposite sides of a wall each slide **toward the other's y**,
## converge on the same y, and at that moment `to_dest.y` is zero -- so the
## y-slide is a zero-length step, the x-slide is into the wall, and both sides
## freeze permanently, facing each other through 40 units of stone. The dump
## is unambiguous: party units parked at x = -44 and enemies at x = +32, every
## one of them reporting `moved 0` from tick 900 to the 3600-tick cap.
##
## **So the sliding rule does not merely fail to route around a wall, it
## actively drives units into the one configuration it cannot escape.** That
## is a simulation finding for whoever owns `Scripts/Combat`, reported rather
## than worked around in silence -- but it also means no amount of moving the
## gap fixes this room. Any WALL long enough to separate two clusters
## deadlocks eventually, because the sliding converges on the deadlock.
##
## A PIT blocks movement and **not sight**, which breaks the deadlock without
## a pathfinder: units that cannot walk to each other can still see and shoot
## each other, so the fight resolves through damage even when the pathing
## jams. The room keeps its whole point -- a narrow land bridge that melee has
## to funnel through, so four attackers cannot all reach one target -- and
## loses only the property that made it hang.
##
## The roster is deliberately `floor1_room1`'s, unchanged and shared through
## `_ROOM1_ENEMY_SPAWNS`. These two rooms are the project's one clean terrain
## A/B: identical enemies in identical positions, terrain the only variable.
## The other two pickable rooms carry different rosters at the same headcount.
static func _the_chokepoint() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_chokepoint"
	e.display_name = "Floor 1, The Narrows"
	e.enemy_spawns = _ROOM1_ENEMY_SPAWNS
	e.party_spawns = _PARTY_SPAWNS
	e.terrain = [
		Terrain.make(Terrain.Kind.PIT, Rect2(-20.0, -270.0, 60.0, 180.0)),
		Terrain.make(Terrain.Kind.PIT, Rect2(-20.0, 90.0, 60.0, 180.0)),
		## The bridge mouth. Sight-blocking only, so the funnel is a real
		## chokepoint for shooting as well as walking without adding back a
		## surface anything can deadlock against.
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-20.0, -70.0, 60.0, 50.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-20.0, 20.0, 60.0, 50.0)),
	]
	return e

## THE COVER ROOM. Issue #94's second of four pickable rooms.
##
## Issue 13b criterion 1's other half, and rook's finding from issue 24: ranged
## units are never threatened because nothing in a room breaks their line of
## sight.
##
## **Rebuilt for issue #94 from three enemies to ten.** The old three-enemy
## version was a single-lever probe, not a room a player would pick, and it
## measured 20/20 for every one of the five buildable parties at 88-100% of
## their own health -- a fight nobody can lose and nobody pays for. Worse, it
## made the room unusable for the one comparison #94 actually asks for: the
## retrospective records a terrain conclusion that was wrong because it put a
## three-enemy room against a ten-enemy one and credited the geometry. **All
## four pickable rooms now field exactly ten enemies**, so layout and roster
## are the only things that vary and neither is confounded by headcount.
##
## The roster is the room's other half. Nearly every fight in the game is
## goblins; this one is a shooting gallery -- four archers and three cultists
## behind three goblins. The cultist is the only POISON source in the game and
## the player has almost never met one, so three of them put a status the
## bestiary owns in front of the player for the first time.
##
## Five pillars in two staggered ranks, not two side by side. A pillar blocks
## sight and not movement, so a colonnade costs a standing-off party its shot
## without ever costing it a step: whoever closes gets to keep firing, whoever
## holds range loses the line every time anything shuffles. That is the same
## lever the two-pillar version tested and it now applies to a roster that can
## punish losing a turn.
static func _the_cover_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_cover"
	e.display_name = "Floor 1, Broken Colonnade"
	e.enemy_spawns = [
		## Two ghouls rather than three goblins in front. Measured: with three
		## goblins the colonnade cost every buildable party only 8-20% of its
		## health, which is a room with no price at all. A ghoul does not care
		## whether it can see you -- it walks at whatever is nearest and mauls
		## it -- so it is the piece that keeps pressure on a party that has
		## just spent the fight winning the sight-line game.
		{"enemy_id": &"ghoul", "position": Vector2(110.0, -170.0)},
		{"enemy_id": &"goblin", "position": Vector2(120.0, 0.0)},
		{"enemy_id": &"ghoul", "position": Vector2(110.0, 170.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(250.0, -225.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(260.0, -85.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(260.0, 85.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(250.0, 225.0)},
		{"enemy_id": &"cultist", "position": Vector2(350.0, -155.0)},
		{"enemy_id": &"cultist", "position": Vector2(360.0, 0.0)},
		{"enemy_id": &"cultist", "position": Vector2(350.0, 155.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	e.terrain = [
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-40.0, -250.0, 50.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-40.0, -50.0, 50.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-40.0, 150.0, 50.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(150.0, -150.0, 50.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(150.0, 50.0, 50.0, 100.0)),
	]
	return e

## THE HAZARD ROOM. Issue #94's third of four pickable rooms.
##
## Issue 13b's hazard criterion: a hazard worth walking around, not one that
## simply blocks the straight line the way a wall would. Ghouls anchor the far
## side, so the shortest path to them cuts straight through the burn patch --
## profane/undead ghouls being immune to their own room's fire would read as a
## bug, so this deliberately is not that pairing.
##
## **Rebuilt for issue #94, same headcount rule as the colonnade: ten.** The
## three-enemy version measured 20/20 for every buildable party at 77-96%
## health, and its single 160x120 burn patch sat off the shortest path, so the
## measured cost of the hazard was very nearly nothing.
##
## The geometry now is the point. Three burn bands leave two clear lanes about
## 50 units wide at y = -160..-110 and y = 110..160. The straight line from
## every party spawn to the enemy back rank crosses fire; the two lanes do not,
## and they are narrow and off-axis, so taking them costs distance and breaks
## the party's formation. That is "the shortest path is not always the right
## one" made structural rather than decorative.
##
## `damage_per_tick` is 2, not the 6 the old patch carried. 6 was survivable
## only because nothing ever stood in it: at `CG.TICKS_PER_SECOND` 15 it is 90
## damage a second, and a pawn with 98-214 hp crossing 200 units of it takes
## more than its whole health bar. 2 is 30 a second, so a full crossing costs
## roughly a third of a pawn -- a real decision rather than a death sentence.
## Measured, not reasoned: see the win-rate table in the pull request.
static func _the_hazard_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_hazard"
	e.display_name = "Floor 1, The Burn Pit"
	e.enemy_spawns = [
		{"enemy_id": &"ghoul", "position": Vector2(180.0, -60.0)},
		{"enemy_id": &"ghoul", "position": Vector2(190.0, 60.0)},
		{"enemy_id": &"ghoul", "position": Vector2(260.0, 0.0)},
		{"enemy_id": &"goblin", "position": Vector2(230.0, -215.0)},
		{"enemy_id": &"goblin", "position": Vector2(240.0, -135.0)},
		{"enemy_id": &"goblin", "position": Vector2(240.0, 135.0)},
		{"enemy_id": &"goblin", "position": Vector2(230.0, 215.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(370.0, -120.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(380.0, 0.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(370.0, 120.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	e.terrain = [
		Terrain.hazard(Rect2(-80.0, -110.0, 200.0, 220.0), 2, CG.DamageType.FIRE),
		Terrain.hazard(Rect2(-80.0, -270.0, 200.0, 110.0), 2, CG.DamageType.FIRE),
		Terrain.hazard(Rect2(-80.0, 160.0, 200.0, 110.0), 2, CG.DamageType.FIRE),
	]
	return e

## Issue 12 criterion 2, the "more enemies than pawns" half: eight goblins,
## individually weak, spread so the party cannot reach them all at once.
static func _the_horde() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_horde"
	e.display_name = "Floor 1, Goblin Horde"
	e.enemy_spawns = [
		{"enemy_id": &"goblin", "position": Vector2(120.0, -220.0)},
		{"enemy_id": &"goblin", "position": Vector2(120.0, -120.0)},
		{"enemy_id": &"goblin", "position": Vector2(120.0, -20.0)},
		{"enemy_id": &"goblin", "position": Vector2(120.0, 80.0)},
		{"enemy_id": &"goblin", "position": Vector2(120.0, 180.0)},
		{"enemy_id": &"goblin", "position": Vector2(260.0, -100.0)},
		{"enemy_id": &"goblin", "position": Vector2(260.0, 0.0)},
		{"enemy_id": &"goblin", "position": Vector2(260.0, 100.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	return e

## Issue 12 criterion 2, the "fewer and tougher" half: two ghouls. Slow,
## hard to kill, hit hard — a wall rather than a swarm.
static func _the_ghoul_den() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_ghoul_den"
	e.display_name = "Floor 1, Ghoul Den"
	e.enemy_spawns = [
		{"enemy_id": &"ghoul", "position": Vector2(200.0, -80.0)},
		{"enemy_id": &"ghoul", "position": Vector2(200.0, 80.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	return e
