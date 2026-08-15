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
##   floor1_cover       five pillars, sight broken   archers, cultists, a Stalker, rats
##   floor1_hazard      three burn bands, two lanes  ghouls, goblins, a Brute
##   floor1_chokepoint  pits, one land bridge, tar    room1's exact roster
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

## A HAZARD whose whole effect is a status. `Terrain.hazard()` takes a damage
## number and no status, and I did not ask rook for a second constructor:
## `Feature`'s fields are public and content already builds every other part of
## an `Encounter` by assignment, so a constructor here would be one more thing
## to keep in step for no reader's benefit.
##
## `damage_per_tick` stays 0, deliberately. A tar pit that also hurt would be a
## burn pit with extra steps, and the burn pit already exists two rooms over.
static func _status_hazard(rect: Rect2, status: CG.Status, ticks: int) -> Terrain.Feature:
	var f := Terrain.make(Terrain.Kind.HAZARD, rect)
	f.applies_status_enabled = true
	f.applies_status = status
	f.status_duration_ticks = ticks
	return f

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
	## **No pillars at the bridge mouth, and a 120-unit bridge.** Both were
	## measured at 40 seeds x 5 buildable parties, 200 fights per variant.
	##
	## The first version put two sight-blocking pillars in the gap, on the
	## reasoning that a chokepoint should choke shooting as well as walking.
	## It reintroduced the colonnade's limit cycle -- 3 stalls in 200 -- for
	## the same reason and with none of the pits involved. **Pits alone: zero
	## stalls in 200, at all three bridge widths tried.** The pillars were a
	## nice idea that cost the room the property it was rebuilt to have.
	##
	## Bridge width, pits only, 200 fights each:
	##
	##   120  no stalls, cost 32-69 across the five parties, losses in 3 of 5
	##   180  no stalls, cost 61-66 -- barely distinguishable from open ground
	##   240  no stalls, cost 41-75, and hardly a funnel at 44% of the arena
	##
	## 120 wins on every count: it is the narrowest, so it is most obviously
	## the room its name describes, and it is the one that asks different
	## parties for different amounts.
	e.terrain = [
		Terrain.make(Terrain.Kind.PIT, Rect2(-20.0, -270.0, 60.0, 210.0)),
		Terrain.make(Terrain.Kind.PIT, Rect2(-20.0, 60.0, 60.0, 210.0)),
		## **Issue #121 item 7, the player's tar pit: terrain that slows
		## instead of hurting.** `damage_per_tick` is 0 and the whole effect is
		## SLOWED, which is the first feature in the game to have no damage at
		## all -- and it is why `CombatSim._tick_hazards`' `damage_per_tick <= 0`
		## early-out has to move before this does anything. Noted here because
		## a reader of this line will otherwise assume it works.
		##
		## **In the gap and nowhere else, and that is the whole design.** The
		## two pits leave one 120-unit land bridge at y = -60..60, and every
		## unit on either side funnels through it -- that is what makes this
		## room a chokepoint rather than a wall. A hazard laid over the bridge
		## is therefore the one piece of terrain in the game that **every**
		## unit in the fight must cross, which is what makes it worth watching
		## rather than a patch to walk around. It also costs the room nothing
		## in reachability: SLOWED is a movement multiplier, so a slow crossing
		## is still a crossing, where damage on the bridge would have made the
		## room a toll gate that kills whoever is poorest.
		##
		## 45 ticks, three seconds, refreshed every tick a unit stands in it.
		## Longer than the crossing takes, so it is felt on the far side rather
		## than only inside the pit -- a slow you have already finished paying
		## by the time you arrive is a slow nobody can see. Shorter than a
		## fight, so it is a cost and not a state.
		##
		## This does not touch `_ROOM1_ENEMY_SPAWNS`. The chokepoint and
		## `floor1_room1` deliberately share a roster so terrain is the only
		## variable between them (13b criterion 1), and a terrain-only addition
		## is exactly what that comparison is built to measure.
		_status_hazard(Rect2(-20.0, -60.0, 60.0, 120.0), CG.Status.SLOWED, 45),
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
## goblins; this one is a shooting gallery -- one archer, a Stalker and
## three cultists behind three goblins and two rats. **The fourth archer became the Stalker
## in issue #121**; every measurement in the table below was taken with four
## archers, and the after-column is in that PR rather than rewritten in here,
## because a tuning table is a record of what was tried and not a description
## of the current roster. The cultist is the only POISON source in the game and
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
		## **Four rosters were measured at 20 seeds x 5 buildable parties,
		## each one both with the colonnade and with the terrain stripped, and
		## the second column is the one that decided it.** Comparing rosters
		## against each other only says which is harder. Comparing a roster
		## against itself on bare ground says whether this is a cover room at
		## all.
		##
		## Ranged density is the whole lever: an archer or a cultist can only
		## fire down a lane the pillars leave open, and a goblin does not care
		## where the pillars are because it is walking at you regardless.
		##
		##   roster                          wins (pillars / bare)   cost effect
		##   2 gob + ghoul, 4 arch, 3 cult   3/20 vs 1/20            huge, but
		##                                                           a wall
		##   2 gob + ghoul, 3 arch, 2 cult   19-20 vs 19-20          **none.**
		##                                                           39/39,
		##                                                           73/73 --
		##                                                           decoration
		##   3 gob, 4 arch, 2 cult + gob     20 vs 20                +0..+16
		## **3 gob, 4 arch, 3 cult           20 vs 19-20             +0..+18**
		##
		## The rejected middle row is the instructive one and it nearly
		## shipped: it had the best cost spread of the four and its pillars did
		## **nothing at all**, bit-identical tick counts on 20 of 20 seeds.
		## Enough goblins rush the party that the fight resolves near the party
		## spawns, a long way from the colonnade, and a pillar behind the
		## fighting is scenery. Judging it on its win table alone would have
		## shipped a cover room with no cover in it, which is this project's
		## single most repeated failure.
		##
		## Three cultists rather than two, for the same reason: the cultist is
		## the game's only POISON source and the player has almost never met
		## one, and it is also a 200-range attacker, so it is both the thing
		## worth showing and the thing the pillars act on.
		##
		## Direction of the effect, which is the opposite of the room's own
		## original premise: the pillars **help the party**, by +12 to +18
		## points of finishing health for three of the five parties. A
		## colonnade is cover for whoever is walking through it.
		## **Issue #130: two of the three archers are rats. Headcount stays at
		## ten (#94), so this is a swap.**
		##
		## **Two placements were measured and rejected before this one, and both
		## failures are the interesting part.**
		##
		## `floor1_hazard`'s two clear lanes, on the argument that the fastest
		## enemy in the game takes the gap the fire leaves. **It does not.**
		## `DefaultBehavior` has no hazard avoidance, so a rat walks the straight
		## line like everything else. Both rats died on tick 48 and tick 68 of
		## every seed, one to the fire with no action id on its death event, and
		## `rat_bite` fired **once in twenty fights**. 20 hp against 2 damage a
		## tick is ten ticks of standing in it -- which I had written down as the
		## reason for the lanes without checking that anything routes around fire.
		## The burn room cannot hold a 20 hp enemy at all.
		##
		## Then this room's goblin rank, which **stalled it**: `no_abomination`
		## ended unresolved at the 3600-tick cap on 2 of 6 seeds. The three
		## goblins are load-bearing for more than their damage -- the roster table
		## below chose them to stop the fight settling back at the colonnade,
		## where `DefaultBehavior`'s hysteresis-free approach/kite pair cycles
		## forever. Rats die too fast to replace that pressure.
		##
		## So the goblin rank is untouched and the rats take two of the three
		## archers. Zero stalls in 120 fights across all four pickable rooms.
		##
		## **The cost, stated rather than buried: this weakens what the colonnade
		## is for.** The pillars act on ranged enemies, and this removes two of
		## them. `test_the_colonnades_pillars_are_not_decoration` measures the
		## total pillar effect across the five buildable parties at **35 points,
		## down from 56**, and the largest single effect at 18, down from 22.
		## Still well clear of a room of paint, which measures 0, and still the
		## invariant that test guards -- but a room cannot be both the shooting
		## gallery and the swarm, and I would rather rook ruled on that than have
		## me quietly spend the room's identity on a bleed source. **Balance is
		## frozen: this is reported, not tuned.**
		{"enemy_id": &"goblin", "position": Vector2(110.0, -170.0)},
		{"enemy_id": &"goblin", "position": Vector2(120.0, 0.0)},
		{"enemy_id": &"goblin", "position": Vector2(110.0, 170.0)},
		{"enemy_id": &"rat", "position": Vector2(250.0, -225.0)},
		{"enemy_id": &"rat", "position": Vector2(260.0, -85.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(260.0, 85.0)},
		## **Issue #121: the Stalker takes the fourth archer's place, and the
		## headcount rule is why it is a swap rather than an addition.** Ten
		## enemies per pickable room is what makes the four rooms comparable
		## to each other (#94), and the retrospective's worst measurement was
		## a three-enemy room compared against a ten-enemy one.
		##
		## The fourth archer rather than a cultist or a goblin: the roster
		## table above chose three cultists deliberately (the game's only
		## POISON source, and the 200-range attacker the pillars act on) and
		## three goblins are what stop the fight resolving back at the party
		## spawns where a pillar is scenery. The archers are the one rank with
		## a spare, and the Stalker is a 220-range shooter itself, so ranged
		## density is unchanged at seven.
		##
		## And this is the room the mark is *for*. A marker is worthless
		## unless something exploits it, and this room has six other ranged
		## enemies to do the exploiting the day
		## `DefaultBehavior._choose_target` learns to prefer a marked target.
		## Until then the mark strips natural armour and nothing else --
		## measured effect in the pull request, and it is small.
		{"enemy_id": &"stalker", "position": Vector2(250.0, 225.0)},
		{"enemy_id": &"cultist", "position": Vector2(350.0, -155.0)},
		{"enemy_id": &"cultist", "position": Vector2(360.0, 0.0)},
		{"enemy_id": &"cultist", "position": Vector2(350.0, 155.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	## **The two x offsets below are swept, not chosen.** They are the one
	## number in this file that could not be reasoned about, because the
	## colonnade has two failure modes pulling in opposite directions and the
	## band between them is narrow.
	##
	## Too near where the fight settles and the fight **hangs**. The first
	## version put a rank at x = -40 and drew 4 of 20 for `no_abomination`;
	## x = -60 drew 8 of 20. Nothing is blocked -- a pillar stops sight and
	## not movement -- it is a **two-tick limit cycle** in `DefaultBehavior`.
	## The blocked-line-of-sight branch approaches, the kite branch retreats
	## when a ranged unit is inside `KITE_RANGE_FRACTION` of its own range, and
	## neither has hysteresis. A unit at rest on a pillar's edge alternates: it
	## steps 3 units, the line clears, it is now too close, it steps back, the
	## line breaks. Dumped at ticks 2000/2001/2002 the positions are exactly
	## period-2 and **not one shot is fired for 2400 ticks**. Reported to rook
	## for whoever owns `Scripts/Plans`; this file cannot fix it.
	##
	## Too far into the enemy half and the pillars are **decoration**. At
	## x = 60/200 the room measured byte-identical to the same roster on bare
	## ground for one party -- same wins, same median cost, same median tick
	## count -- which is the thing `test_content_encounter.gd` has an assertion
	## against for good reason.
	##
	## Swept at 20 seeds x 5 buildable parties per offset pair, 500 fights,
	## with the class order pinned (see `test_content_rooms.gd` on why an
	## unpinned one silently changes which class stands where):
	##
	##   -120/-20   4 draws, and the party hides: 84-93% health left, no price
	##    -60/40    1 draw,  86-91% health left
	##    -20/100   1 draw,  42-84%
	##  **20/160    zero draws in 100 fights, 47-72%, every party differs**
	##     60/200   zero draws, but byte-identical to bare ground for one
	##              party -- same wins, same cost, same tick count. Decoration.
	##
	## 20/160 is the only pair that is neither a hang nor a decoration, and it
	## carries a 25-point cost spread across the five parties on top.
	##
	## Worth writing down because it is the opposite of the intuition the room
	## was built on: **the pillars help the party more than they help the
	## shooters.** The same ten-enemy roster on bare ground wins 14-20 of 20;
	## with the colonnade it wins 19-20. A colonnade is cover for whoever is
	## walking through it.
	## **Square, and that is a correctness fix rather than taste.**
	## `ArenaFloor._draw_feature` draws a PILLAR as "a circle inscribed in its
	## rect", with `radius = min(width, height) * 0.5`. That reads truthfully
	## only for a square rect. These were 50 x 100, so the player saw a circle
	## of radius 25 while the simulation blocked sight across the full 50 x 100
	## footprint -- **half the drawn area, and a fight you cannot reason about
	## from the screen.** Caught by looking at the screenshot, not by any test.
	## 100 x 100 makes the drawn circle and the blocking footprint agree
	## everywhere except the four corners.
	##
	## The general problem is still there for the next author who writes a
	## non-square PILLAR, and `Scripts/UI/ArenaFloor.gd` is not mine. Reported.
	e.terrain = [
		Terrain.make(Terrain.Kind.PILLAR, Rect2(20.0, -250.0, 100.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(20.0, -50.0, 100.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(20.0, 150.0, 100.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(160.0, -150.0, 100.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(160.0, 50.0, 100.0, 100.0)),
	]
	return e

## THE HAZARD ROOM. Issue #94's third of four pickable rooms.
##
## Issue 13b's hazard criterion: a hazard worth walking around, not one that
## simply blocks the straight line the way a wall would. Two ghouls and, since
## issue #121, a Brute anchor the far side, so the shortest path to them cuts
## straight through the burn patch --
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
		## **Issue #121: the Brute takes the third ghoul's place.** Same
		## headcount rule as the colonnade -- ten, so an addition is a swap.
		##
		## This room rather than another, because the burn pit is the one
		## place in the game where a pawn is already paying for every tick it
		## spends deciding. A stun that cancels a committed wind-up costs its
		## victim the ticks it had already spent, and standing in fire while
		## that happens is a cost the player can watch land.
		##
		## The deep ghoul rather than one of the pair at the front: the room's
		## premise is "ghouls anchor the far side so the shortest path cuts
		## through the fire", and two of them still do. Ghoul to Brute is also
		## the smallest swap in the bestiary -- both slow, tough, melee -- so
		## what changes is the stun and not the shape of the room.
		{"enemy_id": &"brute", "position": Vector2(260.0, 0.0)},
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
