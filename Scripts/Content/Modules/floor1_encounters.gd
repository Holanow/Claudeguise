extends RefCounted


## Floor 1's rooms. Issue 12: numbers and placement are levers independent of
## any single monster's stats. See Registry.gd for the module contract.
## OWNER: teal.

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

## **This order is player-visible.** `Registry.pickable_encounter_ids()` keeps
## registration order, so the rooms whose `pickable` is set appear in the picker
## in the order they are listed here. The Rat King moved ahead of the Warden in
## this list for exactly that reason: it is the order `ROOM_ORDER` showed before
## #180 deleted it, and the set and order a player sees are unchanged.
static func encounters() -> Array[Encounter]:
	return [_the_room(), _the_horde(), _the_ghoul_den(), _the_cover_room(), _the_hazard_room(), _the_chokepoint(), _the_rat_king_room(), _the_warden_room()]

static func _the_warden_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_warden"
	e.display_name = "Floor 1, The Warden's Chamber"
	e.pickable = true
	e.enemy_spawns = [
		{"enemy_id": &"the_warden", "position": Vector2(200.0, 0.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	return e

static func _the_rat_king_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_rat_king"
	e.display_name = "Floor 1, The Nest"
	e.pickable = true
	e.enemy_spawns = [
		{"enemy_id": &"rat_king", "position": Vector2(330.0, 0.0)},
		{"enemy_id": &"rat", "position": Vector2(150.0, -140.0)},
		{"enemy_id": &"rat", "position": Vector2(160.0, -50.0)},
		{"enemy_id": &"rat", "position": Vector2(160.0, 50.0)},
		{"enemy_id": &"rat", "position": Vector2(150.0, 140.0)},
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
	e.pickable = true
	e.enemy_spawns = _ROOM1_ENEMY_SPAWNS
	e.party_spawns = _PARTY_SPAWNS
	return e

static func _the_chokepoint() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_chokepoint"
	e.display_name = "Floor 1, The Narrows"
	e.pickable = true
	e.enemy_spawns = _ROOM1_ENEMY_SPAWNS
	e.party_spawns = _PARTY_SPAWNS
	## **No pillars at the bridge mouth, and a 120-unit bridge.** Both were
	## measured at 40 seeds x 5 buildable parties, 200 fights per variant.
	e.terrain = [
		Terrain.make(Terrain.Kind.PIT, Rect2(-20.0, -270.0, 60.0, 210.0)),
		Terrain.make(Terrain.Kind.PIT, Rect2(-20.0, 60.0, 60.0, 210.0)),
		_status_hazard(Rect2(-20.0, -60.0, 60.0, 120.0), CG.Status.SLOWED, 45),
	]
	return e

## THE COVER ROOM. Issue #94's second of four pickable rooms.
##
static func _the_cover_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_cover"
	e.display_name = "Floor 1, Broken Colonnade"
	e.pickable = true
	e.enemy_spawns = [
		{"enemy_id": &"goblin", "position": Vector2(110.0, -170.0)},
		{"enemy_id": &"goblin", "position": Vector2(120.0, 0.0)},
		{"enemy_id": &"goblin", "position": Vector2(110.0, 170.0)},
		{"enemy_id": &"rat", "position": Vector2(250.0, -225.0)},
		{"enemy_id": &"rat", "position": Vector2(260.0, -85.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(260.0, 85.0)},
		{"enemy_id": &"stalker", "position": Vector2(250.0, 225.0)},
		{"enemy_id": &"cultist", "position": Vector2(350.0, -155.0)},
		{"enemy_id": &"cultist", "position": Vector2(360.0, 0.0)},
		{"enemy_id": &"cultist", "position": Vector2(350.0, 155.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
	## Issue #330: the colonnade stands where the fight is, x -300 and -120.
	## At x 20 and 160 it sat about 200 units east of the battle line, and
	## `Tools/ColonnadeLanes.gd` prints the arena cells that say so.
	e.terrain = [
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-300.0, -250.0, 100.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-300.0, -50.0, 100.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-300.0, 150.0, 100.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-120.0, -150.0, 100.0, 100.0)),
		Terrain.make(Terrain.Kind.PILLAR, Rect2(-120.0, 50.0, 100.0, 100.0)),
	]
	return e

## THE HAZARD ROOM. Issue #94's third of four pickable rooms.
##
static func _the_hazard_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_hazard"
	e.display_name = "Floor 1, The Burn Pit"
	e.pickable = true
	e.enemy_spawns = [
		{"enemy_id": &"ghoul", "position": Vector2(180.0, -60.0)},
		{"enemy_id": &"ghoul", "position": Vector2(190.0, 60.0)},
		## **Issue #121: the Brute takes the third ghoul's place.** Same
		## headcount rule as the colonnade -- ten, so an addition is a swap.
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
## hard to kill, hit hard Ã¢â‚¬-- a wall rather than a swarm.
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
