extends RefCounted

const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

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

static func encounters() -> Array[Encounter]:
	return [_the_room(), _the_horde(), _the_ghoul_den()]

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
	e.enemy_spawns = [
		{"enemy_id": &"goblin", "position": Vector2(150.0, -150.0)},
		{"enemy_id": &"goblin", "position": Vector2(150.0, -50.0)},
		{"enemy_id": &"goblin", "position": Vector2(150.0, 50.0)},
		{"enemy_id": &"goblin", "position": Vector2(150.0, 150.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(380.0, -60.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(380.0, 60.0)},
		{"enemy_id": &"goblin_archer", "position": Vector2(380.0, 200.0)},
		{"enemy_id": &"cultist", "position": Vector2(300.0, -200.0)},
		{"enemy_id": &"ghoul", "position": Vector2(250.0, 0.0)},
		{"enemy_id": &"ghoul", "position": Vector2(250.0, -220.0)},
	]
	e.party_spawns = _PARTY_SPAWNS
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
