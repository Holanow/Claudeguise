extends RefCounted
class_name FloorPlan


## One generated floor: its rooms and the connections between them. Named
## "FloorPlan" rather than "Floor" to keep the built-in `floor()` function
## unshadowed by any local `var floor := ...`.
##
## OWNER: wren, issue 5. Generated once by FloorGenerator and then reused for
## the whole trip â€” descent and ascent read the same instance rather than
## regenerating, which is what makes "the layout is preserved on the way
## back up" true by construction rather than by a rule someone has to
## remember.

var seed: int = 0
var rooms: Array[FloorRoom] = []
var entrance_id: int = -1
var miniboss_id: int = -1
var boss_id: int = -1

func room(id: int) -> FloorRoom:
	if id < 0 or id >= rooms.size():
		return null
	return rooms[id]

## Every room id reachable from the entrance, walking `connections`.
func reachable_from_entrance() -> Array[int]:
	return _reachable_from(entrance_id, {})

## Every room id reachable from the entrance if `excluded_id` were removed
## from the graph entirely (its own connections included). Used to prove the
## boss sits behind the miniboss rather than assuming it.
func reachable_excluding(excluded_id: int) -> Array[int]:
	if entrance_id == excluded_id:
		return []
	return _reachable_from(entrance_id, {excluded_id: true})

func _reachable_from(start_id: int, blocked: Dictionary) -> Array[int]:
	var seen: Dictionary = {}
	var queue: Array[int] = [start_id]
	while not queue.is_empty():
		var current: int = queue.pop_back()
		if seen.has(current) or blocked.has(current):
			continue
		seen[current] = true
		var r := room(current)
		if r == null:
			continue
		for next_id in r.connections:
			if not seen.has(next_id) and not blocked.has(next_id):
				queue.append(next_id)
	var out: Array[int] = []
	for id in seen.keys():
		out.append(id)
	out.sort()
	return out
