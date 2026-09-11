extends RefCounted

## Issue 805: what an unattended tool clicks when a room's doors open. The
## floor is the player's choice now, so a tool that watches a whole floor has
## to make one, and this is the only place any of them decides it.

## The neighbour to walk into: the camp when `FloorWalk.wants_camp` says the
## party would turn round, otherwise the next fight, otherwise any door.
static func next_door(battle) -> int:
	var walk: FloorWalk = battle._floor_walk
	if walk == null:
		return -1
	var route: Array[int] = walk.route_to_camp() \
		if walk.wants_camp(battle._floor_run, battle._floor_party) \
		else walk.route_to_next_fight()
	if not route.is_empty():
		return route[0]
	var exits := walk.exits()
	return int(exits[0]["room_id"]) if not exits.is_empty() else -1

## The door's centre in viewport coordinates, for a tool pushing a real click
## rather than calling `take_door`.
static func door_point(battle, room_id: int) -> Vector2:
	for e in battle.open_exits():
		if int(e["room_id"]) == room_id:
			return battle._arena.get_global_transform() * FloorDoors.rect_for(e["dir"]).get_center()
	return Vector2.ZERO

## Issue 935: the boss room's chest holds the floor open, so an unattended tool
## has to click that too.
static func chest_point(battle) -> Vector2:
	return battle._arena.get_global_transform() * FloorChest.rect().get_center()
