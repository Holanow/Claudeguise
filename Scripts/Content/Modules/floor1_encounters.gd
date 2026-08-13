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
	return [_the_room(), _the_horde(), _the_ghoul_den(), _the_cover_room(), _the_hazard_room(), _the_chokepoint()]

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
static func _the_chokepoint() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_chokepoint"
	e.display_name = "Floor 1, The Narrows"
	e.enemy_spawns = _ROOM1_ENEMY_SPAWNS
	e.party_spawns = _PARTY_SPAWNS
	e.terrain = [
		Terrain.make(Terrain.Kind.WALL, Rect2(-20.0, -270.0, 40.0, 170.0)),
		Terrain.make(Terrain.Kind.WALL, Rect2(-20.0, 100.0, 40.0, 170.0)),
	]
	return e

## Issue 13b criterion 1's other half, and rook's finding from issue 24: ranged
## units are never threatened because nothing in a room breaks their line of
## sight. Fewer, weaker enemies than `floor1_room1` on purpose -- this room
## exists to test one lever in isolation, not to be a harder fight. Two
## pillars sit between the party's approach and the back rank, so a party that
## stands at range loses its shot the moment anything steps behind one, and an
## enemy that wants to fire back has to step out from behind cover to do it.
static func _the_cover_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_cover"
	e.display_name = "Floor 1, Broken Colonnade"
	e.enemy_spawns = [
		{"enemy_id": &"goblin_archer", "position": Vector2(220.0, -120.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(220.0, 120.0)},
		{"enemy_id": &"cultist", "position": Vector2(240.0, 0.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	e.terrain = [
		Terrain.make(Terrain.Kind.PILLAR, Rect2(40.0, -160.0, 50.0, 90.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(40.0, 70.0, 50.0, 90.0)),
	]
	return e

## Issue 13b's hazard criterion: a hazard worth walking around, not one that
## simply blocks the straight line the way a wall would. Ghouls anchor the far
## side, so the shortest path to them cuts straight through the burn patch --
## profane/undead ghouls being immune to their own room's fire would read as a
## bug, so this deliberately is not that pairing.
static func _the_hazard_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_hazard"
	e.display_name = "Floor 1, The Burn Pit"
	e.enemy_spawns = [
		{"enemy_id": &"ghoul", "position": Vector2(260.0, -100.0)},
		{"enemy_id": &"ghoul", "position": Vector2(260.0, 100.0)},
		{"enemy_id": &"goblin", "position": Vector2(200.0, 0.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	e.terrain = [
		Terrain.hazard(Rect2(0.0, -60.0, 160.0, 120.0), 6, CG.DamageType.FIRE),
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
