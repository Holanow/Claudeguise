extends RefCounted
class_name FloorRun


## Tracks one traversal of a generated FloorPlan: where the party is, which
## rooms have been visited, and what carried over from the last room each
## pawn fought in.

var plan: FloorPlan
var current_room_id: int = -1
var visited: Array[int] = []

## Keyed by pawn id (StringName). No entry means "not yet fought a room" and
## every reader here treats that as full health / alive, matching a pawn
## that has not been touched yet.
var carry: Dictionary = {}

## What the party has picked up this run, in the order rooms dropped it.
var loot: Array[EquipmentDef] = []

## Issue 919: the picked-up pieces nobody is wearing. The equip screen offers
## these beside the registry, so a chest that pays out into full slots is still
## something the player can use rather than a line in a log.
var bag: Array[EquipmentDef] = []

## Called when a room resolves and something drops. Records it; does not
## touch any pawn, same as record_result does not touch CombatSim.
func add_loot(item: EquipmentDef) -> void:
	loot.append(item)

## Issue 811: pickups awarded since the last arrival, drained by `carry_into`
## into LOOT_AWARDED events. A drop happens between rooms, where there is no
## live fight to emit into, so the announcement waits for the next one.
var pending_pickups: Array[Dictionary] = []

## Which PawnData property holds each equipment slot.
const SLOT_PROPERTY := {
	EquipmentDef.Slot.MAIN_HAND: &"main_hand",
	EquipmentDef.Slot.OFF_HAND: &"off_hand",
	EquipmentDef.Slot.HEAD: &"head",
	EquipmentDef.Slot.BODY: &"body",
	EquipmentDef.Slot.ACCESSORY: &"accessory",
}

## Issue 919: the 1-based floor this run is on. Never `room.difficulty` -- a
## difficulty-2 room on floor 1 would open the verb tier (#916).
var floor_index: int = 1

## Issue 919: how many chests in a row have put nothing on a pawn. README asks
## for a pity counter, and this is what it counts.
var unworn_chests: int = 0

## What a cleared room's chest holds, rolled the moment the room resolves.
## Seeded from the floor and the room rather than from the fight, so the
## contents are deterministic and do not perturb a single tick of combat.
static func roll_room_loot(run: FloorRun, room: FloorRoom, party: Array[PawnData],
		floor_seed: int) -> Array[EquipmentDef]:
	if room.type == FloorRoom.Type.CAMP:
		return [] as Array[EquipmentDef]
	var living := _living(run, party)
	if living.is_empty():
		return [] as Array[EquipmentDef]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([floor_seed, room.content_id, "loot"])
	var batch := LootTables.roll_batch(living, run.floor_index, rng)
	if run.unworn_chests >= LootTables.PITY_LIMIT:
		_apply_pity(run, living, batch, rng)
	return batch

## Issue 919: after PITY_LIMIT chests that dressed nobody, one piece of the next
## chest is replaced by something a living pawn has an empty legal slot for.
static func _apply_pity(run: FloorRun, living: Array[PawnData],
		batch: Array[EquipmentDef], rng: RandomNumberGenerator) -> void:
	if batch.is_empty():
		return
	var fits := LootTables.wearable_ids(living, func(p: PawnData, item: EquipmentDef) -> bool:
		return _slot_is_free(p, item))
	if fits.is_empty():
		return
	batch[0] = ItemRoller.roll(
		ItemLibrary.get_equipment(fits[rng.randi_range(0, fits.size() - 1)]),
		run.floor_index, rng)

## The player has opened the chest. Everything in it joins the run's bag, and
## whatever fits an empty slot on a living pawn is put on. Returns how many
## pieces were actually worn, which is what the pity counter reads.
static func take_chest(run: FloorRun, party: Array[PawnData], batch: Array[EquipmentDef]) -> int:
	var worn := 0
	for item in batch:
		run.add_loot(item)
		var taker := _taker_for(run, party, item)
		if taker == null:
			run.bag.append(item)
			continue
		taker.set(SLOT_PROPERTY[item.slot], item)
		run.pending_pickups.append({"pawn_id": taker.id, "item_id": item.id})
		worn += 1
	run.unworn_chests = 0 if worn > 0 else run.unworn_chests + 1
	return worn

## Roll and open in one call, for a headless sweep that has no chest to click.
## The live floor splits the two: the chest is filled when the room resolves
## and emptied when the player clicks it.
static func award_room_loot(run: FloorRun, room: FloorRoom, party: Array[PawnData],
		floor_seed: int) -> Array[EquipmentDef]:
	var batch := roll_room_loot(run, room, party, floor_seed)
	take_chest(run, party, batch)
	return batch

static func _living(run: FloorRun, party: Array[PawnData]) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for p in party:
		if run.is_alive(p.id):
			out.append(p)
	return out

## Party order, living pawns, first empty slot this class is allowed to fill.
## **Empty slots only, never an upgrade** -- deciding one item is better than
## the one already worn is a balance judgement and this is not the place for it.
static func _taker_for(run: FloorRun, party: Array[PawnData], item: EquipmentDef) -> PawnData:
	for p in party:
		if not run.is_alive(p.id):
			continue
		if not item.allows_class(p.pawn_class):
			continue
		if _slot_is_free(p, item):
			return p
	return null

## Whether this piece has a free slot on this pawn, gates aside. The two-hand
## rules are the whole of it: an off hand is not free when a two-hander fills
## it, and a two-hander cannot land on a pawn already carrying an off hand.
static func _slot_is_free(pawn: PawnData, item: EquipmentDef) -> bool:
	if item.slot == EquipmentDef.Slot.OFF_HAND and pawn.off_hand_blocked():
		return false
	if item.two_handed and pawn.off_hand != null:
		return false
	return pawn.get(SLOT_PROPERTY[item.slot]) == null

## `floor_plan` is optional: issue 729's linear floor sequence has no graph,
## only order, and needs the `carry` bookkeeping below without one.
func _init(floor_plan: FloorPlan = null) -> void:
	plan = floor_plan
	current_room_id = floor_plan.entrance_id if floor_plan != null else -1
	if current_room_id != -1:
		visited.append(current_room_id)

func enter(room_id: int) -> void:
	current_room_id = room_id
	if not visited.has(room_id):
		visited.append(room_id)

## Called once a room's fight is over, to carry a pawn's state into the next
## room. `alive == false` sticks until a revive, which on the live floor is the
## camp.
func record_result(pawn_id: StringName, hp: int, resource: int, alive: bool) -> void:
	carry[pawn_id] = {"hp": hp, "resource": resource, "alive": alive}

func hp_for(pawn_id: StringName, full_hp: int) -> int:
	if carry.has(pawn_id):
		return int(carry[pawn_id]["hp"])
	return full_hp

func resource_for(pawn_id: StringName, full_resource: int) -> int:
	if carry.has(pawn_id):
		return int(carry[pawn_id]["resource"])
	return full_resource

func is_alive(pawn_id: StringName) -> bool:
	if carry.has(pawn_id):
		return bool(carry[pawn_id]["alive"])
	return true

## Issue 796: a fraction of MISSING HP, healed on arrival in the next room,
## living pawns only, no revive. Never reaches full, so no room is free.
const BETWEEN_ROOM_HEAL_MISSING_FRACTION := 0.5

## Issue 868: the same share of MISSING RESOURCE, restored on arrival beside the
## heal -- the 0.50 `Balance.between_room_resource_recover` was authored with and
## which nothing ever called.
const BETWEEN_ROOM_RESOURCE_MISSING_FRACTION := 0.5

## Issue 802: what share of max hp a revived pawn comes back at. `static var`
## rather than `const` so one build can sweep several settings from the command
## line; nothing but Tools/ ever assigns it.
static var REVIVE_AT_HP_FRACTION := 0.5

## Set when the camp's one revive is spent. Still false at the end of a floor
## means the run never got two pawns down and never used it.
var revive_used: bool = false

## True on arrival at 0-based `room_index` under a cadence of `every` rooms.
## Room 0 is never a revive room: nobody has died yet.
static func revives_on_arrival(room_index: int, every: int = 0) -> bool:
	if every <= 0:
		return false
	return room_index > 0 and room_index % every == 0

## The whole decision for one arrival: the camp when the caller says where the
## party is standing, otherwise #802's cadence or its two-down proxy. Only the
## camp branch is the shipped floor; `walk == null` is a measurement path, and
## `proxy_revive` and `revive_every` are the arms `Tools/ReviveArgs.gd` swings
## (issues 908 and 924).
static func should_revive(run: FloorRun, party: Array[PawnData], room_index: int,
		walk: FloorWalk = null, proxy_revive: bool = true, revive_every: int = 0) -> bool:
	if walk != null:
		return camp_revives(run, party, walk)
	if not proxy_revive:
		return revives_on_arrival(room_index, revive_every)
	if run.revive_used or room_index < 1:
		return false
	return run.down_count(party) >= 2

## Issue 803: the camp is spent by standing in it with anybody down, whether
## one pawn or four come back. Deciding when to walk there is the player's,
## and headless it is `Tools/FloorRuns.gd`'s routing policy.
static func camp_revives(run: FloorRun, party: Array[PawnData], walk: FloorWalk) -> bool:
	if run.revive_used or walk.plan.camp_id < 0:
		return false
	return walk.current_id == walk.plan.camp_id and run.down_count(party) > 0

func down_count(party: Array[PawnData]) -> int:
	var n := 0
	for p in party:
		if not is_alive(p.id):
			n += 1
	return n

## Overwrites `state`'s party units (index i is party[i], the order
## `CombatSim.build` always places them in) with what this run carried from
## the last room, then applies the arrival heal above. Shared by BattleView's
## live floor and Tools/FloorRuns.gd's headless sweep so the carry rule and
## the heal have exactly one implementation.
##
## Issue 805: `heal` is false when the party walks back into a room they have
## already cleared. Without it, pacing between two cleared rooms pays the
## arrival heal every time and the floor has free healing in it.
static func carry_into(run: FloorRun, state: CombatState, party: Array[PawnData],
		room_index: int = 0, walk: FloorWalk = null, heal: bool = true,
		proxy_revive: bool = true, revive_every: int = 0) -> void:
	var revive := should_revive(run, party, room_index, walk, proxy_revive, revive_every)
	if revive:
		run.revive_used = true
	for i in party.size():
		var unit := state.unit(i)
		var pawn_id: StringName = party[i].id
		_commit_staged_plan(party[i])
		if not run.is_alive(pawn_id):
			if not revive:
				unit.alive = false
				unit.hp = 0
				continue
			_revive(state, run, unit, pawn_id)
			continue
		unit.hp = clampi(run.hp_for(pawn_id, unit.hp_max), 0, unit.hp_max)
		unit.resource = clampi(run.resource_for(pawn_id, unit.resource_max), 0, unit.resource_max)
		if heal:
			_apply_arrival_heal(state, unit)
			_apply_arrival_recovery(state, unit)
	_announce_pickups(state, run, party)

## Issue 811: the drop the last room paid out, said out loud in the room it is
## first worn in. Same precedent `_revive` sets -- a between-room fact reaches
## the player as an event in the arriving fight, because that is where the log is.
static func _announce_pickups(state: CombatState, run: FloorRun, party: Array[PawnData]) -> void:
	for pickup in run.pending_pickups:
		for i in party.size():
			if party[i].id != pickup["pawn_id"]:
				continue
			var e := CombatEvent.make(CG.EventKind.LOOT_AWARDED, state.tick)
			e.target_id = state.unit(i).id
			e.item_id = pickup["item_id"]
			state.emit(e)
	run.pending_pickups.clear()

## Issue 741: a plan edited while its owner's fight was running lands in
## `staged_plans` rather than `plans`, so the fight it started in stays
## reproducible. This is the commit point -- room arrival, the same moment hp
## and resource already carry across. A dead pawn's edits commit too: `plans`
## is what the next fight it joins will read, regardless of this one's result.
static func _commit_staged_plan(pawn: PawnData) -> void:
	if not pawn.plans_staged:
		return
	pawn.plans = pawn.staged_plans
	pawn.staged_plans = []
	pawn.plans_staged = false
	pawn.plans_edited = false

## Issue 802: a fallen pawn returns at REVIVE_AT_HP_FRACTION of max, with no
## resource, and does NOT also take the arrival heal in the same room. At
## least 1 hp, so a small pool rounding to zero cannot arrive dead.
static func _revive(state: CombatState, run: FloorRun, unit: CombatUnit, pawn_id: StringName) -> void:
	unit.alive = true
	unit.hp = maxi(1, int(round(float(unit.hp_max) * REVIVE_AT_HP_FRACTION)))
	unit.resource = 0
	run.record_result(pawn_id, unit.hp, 0, true)
	var e := CombatEvent.make(CG.EventKind.HEAL, state.tick)
	e.target_id = unit.id
	e.amount = unit.hp
	state.emit(e)

## Issue 868: the heal's twin for the resource pool, and it takes the same
## `heal` gate above -- #805's pacing exploit refills a caster for free
## otherwise, exactly as it healed one for free.
## Rage is exempt: it is earned by swinging, never handed over. Issue 948.
static func _apply_arrival_recovery(state: CombatState, unit: CombatUnit) -> void:
	if unit.resource_kind == CG.ResourceKind.RAGE:
		return
	var amount := int(round(float(unit.resource_max - unit.resource) * BETWEEN_ROOM_RESOURCE_MISSING_FRACTION))
	var before := unit.resource
	unit.resource = mini(unit.resource_max, unit.resource + amount)
	var applied := unit.resource - before
	if applied <= 0:
		return
	var e := CombatEvent.make(CG.EventKind.RESOURCE_GAINED, state.tick)
	e.target_id = unit.id
	e.amount = applied
	state.emit(e)

## Living pawn only, no revive: `carry_into` already set dead units aside
## above and this never runs on one. A pawn already at max hp emits nothing,
## same "no event for no change" rule `CombatSim._apply_heal` uses.
static func _apply_arrival_heal(state: CombatState, unit: CombatUnit) -> void:
	var amount := int(round(float(unit.hp_max - unit.hp) * BETWEEN_ROOM_HEAL_MISSING_FRACTION))
	var before := unit.hp
	unit.hp = mini(unit.hp_max, unit.hp + amount)
	var applied := unit.hp - before
	if applied <= 0:
		return
	var e := CombatEvent.make(CG.EventKind.HEAL, state.tick)
	e.target_id = unit.id
	e.amount = applied
	state.emit(e)
