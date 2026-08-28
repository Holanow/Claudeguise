extends RefCounted
class_name FloorSequence


## Issue 729: the order of one floor's ten rooms, deterministic from a seed.
## Eight ordinary/elite rooms shuffled, the Rat King at slot 5 or 6 of 10, the
## Warden always last. Order only -- nothing here builds a fight or a view.

const SHUFFLED_IDS: Array[StringName] = [
	&"floor1_room1", &"floor1_horde", &"floor1_ghoul_den", &"floor1_cover",
	&"floor1_hazard", &"floor1_chokepoint", &"floor1_sellsword", &"floor1_narrows_elite",
]
const MINIBOSS_ID: StringName = &"floor1_rat_king"
const BOSS_ID: StringName = &"floor1_warden"

## 0-indexed slot for the miniboss -- 4 or 5, i.e. position 5 or 6 of 10.
const MINIBOSS_SLOTS := [4, 5]

static func build(floor_seed: int) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed
	var pool := SHUFFLED_IDS.duplicate()
	_shuffle(rng, pool)
	var slot: int = MINIBOSS_SLOTS[rng.randi_range(0, MINIBOSS_SLOTS.size() - 1)]
	pool.insert(slot, MINIBOSS_ID)
	pool.append(BOSS_ID)
	var out: Array[StringName] = []
	out.assign(pool)
	return out

## Fisher-Yates, same pattern as FloorFightRunner._shuffle: draw without
## replacement so no room can be picked twice.
static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
