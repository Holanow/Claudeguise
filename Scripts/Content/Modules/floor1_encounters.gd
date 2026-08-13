extends RefCounted

const ClassDef := preload("res://Scripts/Core/ClassDef.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")

## The single hand authored encounter the slice ships: two melee grunts up
## front and two ranged casters (an archer and a cultist) held back, against a
## four-pawn party. See Registry.gd for the module contract. OWNER: teal.
##
## Tuning notes (see Tests/test_content_encounter.gd for the measured seed
## sweep): this is a room, not a single stat block, so "winnable and losable"
## is a property of the whole spawn list, not any one enemy.

static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	return []

static func enemies() -> Array[EnemyDef]:
	return []

static func encounters() -> Array[Encounter]:
	return [_the_room()]

static func _the_room() -> Encounter:
	var e := Encounter.new()
	e.id = &"floor1_room1"
	e.display_name = "Floor 1, Room 1"
	e.enemy_spawns = [
		{"enemy_id": &"dungeon_grunt", "position": Vector2(150.0, -60.0)},
		{"enemy_id": &"dungeon_grunt", "position": Vector2(150.0, 60.0)},
		{"enemy_id": &"dungeon_archer", "position": Vector2(380.0, 0.0)},
		{"enemy_id": &"dungeon_cultist", "position": Vector2(300.0, -150.0)},
	]
	## Vertical spacing here used to be 60 units, fine when a unit's draw
	## radius was 12. pike raised the radius to 22 for phone legibility, which
	## left barely 16 units of gap between two adjacent bodies and put every
	## label on top of the pawn above it. Roughly doubled.
	e.party_spawns = [
		Vector2(-350.0, -195.0),
		Vector2(-350.0, -65.0),
		Vector2(-350.0, 65.0),
		Vector2(-350.0, 195.0),
	]
	return e
