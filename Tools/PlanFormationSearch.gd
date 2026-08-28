extends SceneTree

## Issue 736: does anything a player could author clear the ten-room floor?
## Two axes -- plan sets and starting formations -- searched in sequence, not
## multiplied: plans first at the room's authored formation, then formations
## against only the best two or three plan sets. Nothing in the game changes;
## this tool only builds parties and places them.

const SEEDS := 40

## Generic rows, usable on any class without a class-specific action id:
## "focus fire" reads as finishing whatever is already hurt, "aggression" as
## always hitting whatever is closest. Both use UseBestAttackBlock, so they
## never name an action the class does not have.
static func _aggro_row() -> Plan:
	return _row(&"aggro_nearest", "Attack the nearest enemy, always",
		null, [TargetNearestEnemyBlock.new(), UseBestAttackBlock.new()])

static func _focus_row() -> Plan:
	return _row(&"focus_lowest", "Focus the weakest enemy",
		null, [TargetLowestHpEnemyBlock.new(), UseBestAttackBlock.new()])

static func _row(id: StringName, name: String, condition: ConditionBlock, blocks: Array[PlanBlock]) -> Plan:
	var p := Plan.new()
	p.id = id
	p.display_name = name
	p.condition = condition
	p.blocks = blocks
	return p

## Existing preset rows for a class, keyed by id, so an archetype can pick a
## subset and reorder it without re-authoring the row itself.
static func _library(class_id: StringName) -> Dictionary:
	var out := {}
	for p in PresetPlans.for_class(class_id):
		out[p.id] = p
	return out

static func _pick(lib: Dictionary, ids: Array) -> Array[Plan]:
	var out: Array[Plan] = []
	for id in ids:
		if lib.has(id):
			out.append(lib[id])
	return out

## Five archetypes per class, built from that class's own rows plus the two
## generic rows above. Where a class's library has no defensive or support
## vocabulary at all (siege_master, abomination), the archetype falls back to
## the closest thing the library expresses and that gap is reported, not
## papered over with an invented mechanic.
static func archetypes(class_id: StringName) -> Dictionary:
	var lib := _library(class_id)
	match class_id:
		&"warrior":
			return {
				"aggression": [_aggro_row()],
				"focus_fire": [_focus_row()],
				"defensive": _pick(lib, [&"warrior_taunt_when_they_close", &"warrior_guard_when_hurt", &"warrior_block_default"]),
				"support_first": _pick(lib, [&"warrior_block_default", &"warrior_taunt_when_they_close"]),
				"resource_discipline": _pick(lib, [&"warrior_guard_when_hurt"]),
			}
		&"priest":
			return {
				"aggression": [_aggro_row()],
				"focus_fire": [_focus_row()],
				"defensive": _pick(lib, [&"priest_ward_default", &"priest_heal_hurt_ally"]),
				"support_first": _pick(lib, [&"priest_heal_hurt_ally", &"priest_ward_default", &"priest_haste_default", &"priest_smite_nearest"]),
				"resource_discipline": _pick(lib, [&"priest_channel_when_dry", &"priest_heal_hurt_ally"]),
			}
		&"geysermancer":
			return {
				"aggression": [_aggro_row()],
				"focus_fire": _pick(lib, [&"geyser_scald_finisher", &"geyser_blast_the_burning"]),
				"defensive": _pick(lib, [&"geyser_scour_afflicted", &"geyser_channel_when_dry"]),
				"support_first": _pick(lib, [&"geyser_scour_afflicted", &"geyser_channel_when_dry", &"geyser_blast_the_burning", &"geyser_scald_finisher"]),
				"resource_discipline": _pick(lib, [&"geyser_channel_when_dry", &"geyser_blast_the_burning", &"geyser_scald_finisher"]),
			}
		&"siege_master":
			return {
				"aggression": [_aggro_row()],
				"focus_fire": [_focus_row()],
				"defensive": [],
				"support_first": _pick(lib, [&"siege_master_mark_default"]),
				"resource_discipline": _pick(lib, [&"siege_master_build_when_ready", &"siege_master_mark_default"]),
			}
		&"abomination":
			return {
				"aggression": _pick(lib, [&"abomination_grapple_close", &"abomination_claw_the_unpoisoned", &"abomination_hook_far"]),
				"focus_fire": [_focus_row()],
				"defensive": [],
				"support_first": [],
				"resource_discipline": _pick(lib, [&"abomination_hook_far", &"abomination_claw_the_unpoisoned"]),
			}
	return {"aggression": [], "focus_fire": [], "defensive": [], "support_first": [], "resource_discipline": []}

## Party-level plan sets: deliberate combinations, not a 5^5 cross product.
## Each maps class_id -> archetype name. "preset" is the shipped library
## (issue 730/734's arm B) and doubles as the control the other sets are
## measured against.
static func plan_sets() -> Dictionary:
	return {
		"preset (shipped library)": {},
		"all aggression": {"_all": "aggression"},
		"all focus fire": {"_all": "focus_fire"},
		"all defensive": {"_all": "defensive"},
		"all resource discipline": {"_all": "resource_discipline"},
		"support-led (priest supports, rest aggro)": {
			&"priest": "support_first", &"warrior": "aggression", &"geysermancer": "aggression",
			&"siege_master": "aggression", &"abomination": "aggression"},
		"tank front, focus fire behind": {
			&"warrior": "defensive", &"priest": "support_first", &"geysermancer": "focus_fire",
			&"siege_master": "focus_fire", &"abomination": "focus_fire"},
		"defensive warrior, rest aggro": {
			&"warrior": "defensive", &"priest": "aggression", &"geysermancer": "aggression",
			&"siege_master": "aggression", &"abomination": "aggression"},
	}

## FORMATIONS. Party order stays `CLASS_ORDER`; a formation only changes which
## authored spawn slot each class lands in, or nudges that slot within the
## room's own deploy zone. Never an absolute coordinate.
const TANK_CLASS := &"warrior"
const BACK_SHIFT := 60.0
const SPLIT_LATERAL := 90.0
const MIN_ENEMY_GAP := 420.0

static func _authored(encounter: RoomData, n: int) -> Array[Vector2]:
	return DeployView.authored_positions(encounter, n)

static func _forward_axis(encounter: RoomData, positions: Array[Vector2]) -> Vector2:
	if encounter.enemy_spawns.is_empty() or positions.is_empty():
		return Vector2(1, 0)
	var ec := Vector2.ZERO
	for s in encounter.enemy_spawns:
		ec += (s.get("position", Vector2.ZERO) as Vector2)
	ec /= encounter.enemy_spawns.size()
	var pc := Vector2.ZERO
	for p in positions:
		pc += p
	pc /= positions.size()
	var f := ec - pc
	return f.normalized() if f.length() > 0.0001 else Vector2(1, 0)

## True if `pos` stays at least MIN_ENEMY_GAP from every enemy spawn. The one
## guard every nudge below is checked against before it is used.
static func _safe(encounter: RoomData, pos: Vector2) -> bool:
	for s in encounter.enemy_spawns:
		if pos.distance_to(s.get("position", Vector2.ZERO)) < MIN_ENEMY_GAP:
			return false
	return true

static func _clamp_zone(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, -CG.ARENA_HALF_WIDTH + 20.0, CG.party_deploy_max_x() - 20.0),
		clampf(pos.y, -CG.ARENA_HALF_HEIGHT + 20.0, CG.ARENA_HALF_HEIGHT - 20.0))

## Reorders `class_order` so `TANK_CLASS` lands on whichever authored slot is
## closest to the enemy, keeping everyone else in their original relative
## order. Coordinates never move -- only who stands where.
static func _tank_forward_order(class_order: Array, positions: Array[Vector2], forward: Vector2) -> Array:
	var tank_idx := class_order.find(TANK_CLASS)
	if tank_idx == -1:
		return class_order
	var best_slot := 0
	var best_proj := -INF
	for i in positions.size():
		var proj := positions[i].dot(forward)
		if proj > best_proj:
			best_proj = proj
			best_slot = i
	var out := class_order.duplicate()
	out.remove_at(tank_idx)
	out.insert(mini(best_slot, out.size()), TANK_CLASS)
	return out

## positions[i] is where `class_order[i]` stands. `class_order` defaults to
## `CLASS_ORDER` (the room's authored assignment); only "tank_forward" and
## "wedge" reorder it.
static func formation(shape: String, encounter: RoomData, class_order: Array) -> Dictionary:
	var base := _authored(encounter, class_order.size())
	var forward := _forward_axis(encounter, base)
	var lateral := forward.rotated(PI / 2.0)
	match shape:
		"line":
			return {"order": class_order, "positions": base}
		"tank_forward":
			return {"order": _tank_forward_order(class_order, base, forward), "positions": base}
		"back_heavy":
			var out: Array[Vector2] = []
			for p in base:
				var moved := _clamp_zone(p - forward * BACK_SHIFT)
				out.append(moved if _safe(encounter, moved) else p)
			return {"order": class_order, "positions": out}
		"split":
			var out2: Array[Vector2] = []
			for i in base.size():
				var side := 1.0 if i % 2 == 0 else -1.0
				var moved := _clamp_zone(base[i] + lateral * SPLIT_LATERAL * side)
				out2.append(moved if _safe(encounter, moved) else base[i])
			return {"order": class_order, "positions": out2}
		"wedge":
			var wedge_order := _tank_forward_order(class_order, base, forward)
			var out3: Array[Vector2] = []
			for i in base.size():
				if i == 0:
					out3.append(base[i])
					continue
				var side3 := 1.0 if i % 2 == 0 else -1.0
				var fan := float((i + 1) / 2)
				var moved := _clamp_zone(base[i] - forward * (BACK_SHIFT * 0.5) + lateral * SPLIT_LATERAL * side3 * fan)
				out3.append(moved if _safe(encounter, moved) else base[i])
			return {"order": wedge_order, "positions": out3}
	return {"order": class_order, "positions": base}

var CLASS_ORDER: Array = []

func _init() -> void:
	CLASS_ORDER = ClassLibrary.all_ids()
	if CLASS_ORDER.is_empty():
		printerr("no classes registered")
		quit(1)
		return
	print("Plan/formation search, issue 736: %d seeds, 10 rooms, authored formation first.\n" % SEEDS)

	var plan_results := {}
	for set_name in plan_sets():
		plan_results[set_name] = _run(plan_sets()[set_name], "line")
		_report("plans: %s (formation: line)" % set_name, plan_results[set_name])

	var ranked := plan_sets().keys()
	ranked.sort_custom(func(a, b): return _score(plan_results[a]) > _score(plan_results[b]))
	var finalists := ranked.slice(0, 3)
	print("Best plan sets by median depth: %s\n" % str(finalists))

	for set_name in finalists:
		for shape in ["tank_forward", "back_heavy", "split", "wedge"]:
			var r := _run(plan_sets()[set_name], shape)
			_report("plans: %s (formation: %s)" % [set_name, shape], r)

	quit(0)

static func _score(r: Dictionary) -> float:
	var depths: Array = r.depths
	var sorted := depths.duplicate()
	sorted.sort()
	var n := sorted.size()
	return float(sorted[n / 2]) if n % 2 == 1 else (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0

func _run(assignment: Dictionary, shape: String) -> Dictionary:
	var cleared := 0
	var died_at := {}
	var depths: Array[int] = []
	for s in range(SEEDS):
		var room_ids := FloorSequence.build(s)
		var party := _make_party(assignment)
		var run := FloorRun.new()
		var wiped := false
		for i in room_ids.size():
			var room_id: StringName = room_ids[i]
			var room := RoomLibrary.get_room(room_id)
			var f := formation(shape, room, CLASS_ORDER)
			var ordered_party: Array[PawnData] = []
			for cid in f.order:
				ordered_party.append(_pawn_for(party, cid))
			var placed: RoomData = DeployView.encounter_with_placement(room, f.positions)
			var state := CombatSim.build(ordered_party, placed, hash([s, room_id, i, shape]))
			FloorRun.carry_into(run, state, ordered_party)
			CombatSim.run(state)
			for j in ordered_party.size():
				var unit := state.unit(j)
				run.record_result(ordered_party[j].id, unit.hp, unit.resource, unit.alive)
			if state.outcome != CombatState.Outcome.PLAYER_WIN:
				wiped = true
				died_at[room_id] = int(died_at.get(room_id, 0)) + 1
				depths.append(i + 1)
				break
		if not wiped:
			cleared += 1
			depths.append(room_ids.size())
	return {"cleared": cleared, "died_at": died_at, "depths": depths}

func _pawn_for(party: Array[PawnData], class_id: StringName) -> PawnData:
	for p in party:
		if p.id == class_id:
			return p
	return null

func _make_party(assignment: Dictionary) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for cid in CLASS_ORDER:
		var c := StringName(cid)
		var display := ClassLibrary.get_class_def(c).display_name
		var pawn := PawnFactory.make_starter_pawn(c, c, display)
		var archetype_name: String = ""
		if assignment.has("_all"):
			archetype_name = assignment["_all"]
		elif assignment.has(c):
			archetype_name = assignment[c]
		if archetype_name != "":
			var chosen: Array[Plan] = []
			chosen.assign(archetypes(c)[archetype_name])
			pawn.plans = chosen
		elif assignment.is_empty():
			pawn.plans = PresetPlans.for_class(c)
		party.append(pawn)
	return party

func _report(label: String, r: Dictionary) -> void:
	print(label)
	print("  cleared the floor: %d of %d (%d%%)" % [r.cleared, SEEDS, int(round(100.0 * r.cleared / SEEDS))])
	_report_depth(r.depths)
	print("")

func _report_depth(depths: Array) -> void:
	var sorted: Array = depths.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0
	for d in sorted:
		total += int(d)
	var mean := float(total) / n
	var median: float = float(sorted[n / 2]) if n % 2 == 1 \
		else (int(sorted[n / 2 - 1]) + int(sorted[n / 2])) / 2.0
	print("  depth reached: min %d, median %.1f, mean %.1f, max %d" % [int(sorted[0]), median, mean, int(sorted[n - 1])])
	var histogram := {}
	for d in sorted:
		histogram[d] = int(histogram.get(d, 0)) + 1
	var line := "    "
	for depth in range(1, 11):
		line += "%d:%d  " % [depth, int(histogram.get(depth, 0))]
	print(line)
